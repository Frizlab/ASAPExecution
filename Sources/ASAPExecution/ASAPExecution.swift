import Foundation



/* Note: A fun thing to do later (when Swift allows it) would be to try and reimplement this as an actor using a custom executor. */
public final class ASAPExecution<R> {
	
	@discardableResult
	public static func when(_ condition: @autoclosure @escaping () -> Bool, do block: @escaping (_ isAsyncCall: Bool) -> R, endHandler: ((_ result: R?) -> Void)? = nil, retryDelay: TimeInterval? = nil, runLoop: RunLoop = .current, runLoopModes: [RunLoop.Mode] = [.default], maxTryCount: Int? = nil, skipSyncTry: Bool = false) -> ASAPExecution<R>? {
		return when(
			condition(), doThrowing: block,
			endHandler: { endHandler?($0?.success /* success will never be nil, but not force-unwrapping because $0 might. */) },
			retryDelay: retryDelay, runLoop: runLoop, runLoopModes: runLoopModes,
			maxTryCount: maxTryCount, skipSyncTry: skipSyncTry
		)
	}
	
	@discardableResult
	public static func when(_ condition: @autoclosure @escaping () -> Bool, doThrowing block: @escaping (_ isAsyncCall: Bool) throws -> R, endHandler: ((_ result: Result<R, Error>?) -> Void)? = nil, retryDelay: TimeInterval? = nil, runLoop: RunLoop = .current, runLoopModes: [RunLoop.Mode] = [.default], maxTryCount: Int? = nil, skipSyncTry: Bool = false) -> ASAPExecution<R>? {
		/* We avoid an allocation if condition is already true (happy and probably most common path). */
		if !skipSyncTry, condition() {
			do    {let ret = try block(false); endHandler?(.success(ret))}
			catch {                            endHandler?(.failure(error))}
			return nil
		}
		
		/* The ASAPExecution holds a strong reference to itself; no need to keep a hold of it. */
		return ASAPExecution(
			stopCondition: condition,
			untilConditionBlock: { _ in },
			whenConditionBlock: block,
			endHandler: endHandler,
			retryDelay: retryDelay,
			runLoop: runLoop, runLoopModes: runLoopModes,
			currentTry: skipSyncTry ? 1 : 2, maxTryCount: maxTryCount
		)
	}
	
	@discardableResult
	public static func until(_ condition: @autoclosure @escaping () -> Bool, do block: @escaping (_ isAsyncCall: Bool) -> Void, endHandler: ((_ cancelledOrReachedMaxRunCount: Bool) -> Void)? = nil, delay: TimeInterval? = nil, runLoop: RunLoop = .current, runLoopModes: [RunLoop.Mode] = [.default], maxRunCount: Int? = nil, skipSyncRun: Bool = false) -> ASAPExecution<R>? where R == Void {
		/* We avoid an allocation if condition is already true. */
		if !skipSyncRun {
			guard !condition() else {
				endHandler?(false)
				return nil
			}
			block(false)
		}
		
		/* The ASAPExecution holds a strong reference to itself; no need to keep a hold of it. */
		return ASAPExecution(
			stopCondition: condition,
			untilConditionBlock: block,
			whenConditionBlock: { _ in },
			endHandler: { v in endHandler?(v == nil) },
			retryDelay: delay,
			runLoop: runLoop, runLoopModes: runLoopModes,
			currentTry: skipSyncRun ? 1 : 2, maxTryCount: maxRunCount
		)
	}
	
	/* Async implementations disabled because I’m not convinced they can actually be useful.*/
	
//	@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
//	public static func when(_ condition: @autoclosure @escaping () -> Bool, do block: @escaping (_ isAsyncCall: Bool) -> R, retryDelay: TimeInterval? = nil, runLoop: RunLoop = .current, runLoopModes: [RunLoop.Mode] = [.default], maxTryCount: Int? = nil, skipSyncTry: Bool = false) async -> R? {
//		await withCheckedContinuation{ continuation in
//			when(
//				condition(), do: block, endHandler: { continuation.resume(returning: $0) },
//				retryDelay: retryDelay,
//				runLoop: runLoop, runLoopModes: runLoopModes,
//				maxTryCount: maxTryCount, skipSyncTry: skipSyncTry
//			)
//		}
//	}
//
//	@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
//	public static func when(_ condition: @autoclosure @escaping () -> Bool, doThrowing block: @escaping (_ isAsyncCall: Bool) -> R, retryDelay: TimeInterval? = nil, runLoop: RunLoop = .current, runLoopModes: [RunLoop.Mode] = [.default], maxTryCount: Int? = nil, skipSyncTry: Bool = false) async throws -> R? {
//		try await withCheckedThrowingContinuation{ continuation in
//			when(
//				condition(), doThrowing: block, endHandler: { continuation.resume(with: $0?.map{ $0 as R? } ?? .success(nil)) },
//				retryDelay: retryDelay,
//				runLoop: runLoop, runLoopModes: runLoopModes,
//				maxTryCount: maxTryCount, skipSyncTry: skipSyncTry
//			)
//		}
//	}
	
	internal var stopCondition: () -> Bool
	internal var untilConditionBlock: (_ isAsyncCall: Bool) -> Void
	internal var whenConditionBlock: (_ isAsyncCall: Bool) throws -> R
	internal var endHandler: ((_ result: Result<R, Error>?) -> Void)?
	
	internal var retryDelay: TimeInterval?
	
	internal var runLoop: RunLoop
	internal var runLoopModes: [RunLoop.Mode]
	
	internal var currentTry: Int
	internal var maxTryCount: Int?
	
	internal init(
		stopCondition: @escaping () -> Bool,
		untilConditionBlock: @escaping (_ isAsyncCall: Bool) -> Void,
		whenConditionBlock: @escaping (_ isAsyncCall: Bool) throws -> R,
		endHandler: ((Result<R, Error>?) -> Void)?,
		retryDelay: TimeInterval?,
		runLoop: RunLoop, runLoopModes: [RunLoop.Mode],
		currentTry: Int, maxTryCount: Int?)
	{
		self.stopCondition = stopCondition
		self.untilConditionBlock = untilConditionBlock
		self.whenConditionBlock = whenConditionBlock
		self.endHandler = endHandler
		self.retryDelay = retryDelay
		self.runLoop = runLoop
		self.runLoopModes = runLoopModes
		self.currentTry = currentTry
		self.maxTryCount = maxTryCount
		
		/* --- Variables are all init’d here --- */
		
		usingMe = self
		scheduleNextTry()
	}
	
	deinit {
//		NSLog("Deinit happened for an ASAPExecution")
	}
	
	public func cancel() {
		runLoop.perform(inModes: runLoopModes, block: {
			/* If we’re already cancelled, we have nothing to do. */
			guard !self.isCancelled else {
				return
			}
			
			/* Mark execution as cancelled. */
			self.isCancelled = true
			
			/* Invalidate next try timer if any. */
			self.timer?.invalidate()
			self.timer = nil
			
			/* We force run the next try so that the handler is called and the cleanup is done. */
			self.runNextTry()
		})
	}
	
	private var usingMe: ASAPExecution<R>?
	
	private var timer: Timer?
	private var isCancelled: Bool = false
	
	/* This method is called:
	 *    - At init time, on any runloop, thread, whatever;
	 *    - Once the ASAPExecution has been init, always on the execution runloop.
	 * Thanks to this, we know we can modify the timer variable w/o any locks as it is always modified on the runloop. */
	private func scheduleNextTry() {
		if let retryDelay = retryDelay {
			let t = Timer(timeInterval: retryDelay, repeats: false, block: { t in
				assert(t === self.timer)
				self.timer = nil
				t.invalidate() /* Probably unneeded */
				
				self.runNextTry()
			})
			assert(timer == nil)
			timer = t
			for mode in runLoopModes {runLoop.add(t, forMode: mode)}
		} else {
			/* We schedule immediately… on next run loop. */
			runLoop.perform(inModes: runLoopModes, block: runNextTry)
		}
	}
	
	private func runNextTry() {
		guard !isCancelled, currentTry <= maxTryCount ?? .max else {
			/* If the ASAPExecution has no retry delay and is cancelled,
			 * the run next try function might be called more than once with isCancelled set to true.
			 * To prevent calling the end handler more than once, we verify usingMe is not nil before calling it. */
			if usingMe != nil {
				assert(usingMe === self)
				endHandler?(nil)
				usingMe = nil
			}
			return
		}
		
		currentTry += 1
		if stopCondition() {
			do    {let ret = try whenConditionBlock(true); endHandler?(.success(ret))}
			catch {                                        endHandler?(.failure(error))}
			assert(usingMe === self)
			usingMe = nil
		} else {
			untilConditionBlock(true)
			scheduleNextTry()
		}
	}
	
}


private extension Result {
	
	var success: Success? {
		switch self {
			case .failure:        return nil
			case .success(let s): return s
		}
	}
	
}
