import Foundation



public final class ASAPExecution<R> {
	
	@discardableResult
	public static func when(_ condition: @autoclosure @escaping () -> Bool, do block: @escaping (_ isAsyncCall: Bool) -> R, endHandler: ((_ result: R?) -> Void)? = nil, retryDelay: TimeInterval? = nil, runLoop: RunLoop = .current, runLoopModes: [RunLoop.Mode] = [.default], maxTryCount: Int? = nil, skipSyncTry: Bool = false) -> ASAPExecution<R>? {
		return when(
			condition(), doThrowing: block,
			endHandler: { endHandler?($0?.success /* success will never be nil, but not unwrapping because $0 might. */) },
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
			condition: condition, block: block, endHandler: endHandler,
			retryDelay: retryDelay,
			runLoop: runLoop, runLoopModes: runLoopModes,
			currentTry: skipSyncTry ? 1 : 2, maxTryCount: maxTryCount
		)
	}
	
	/* Async implementation disabled because I’m not convinced they can actually be useful.*/
	
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
	
	internal var condition: () -> Bool
	internal var block: (_ isAsyncCall: Bool) throws -> R
	internal var endHandler: ((_ result: Result<R, Error>?) -> Void)?
	
	internal var retryDelay: TimeInterval?
	
	internal var runLoop: RunLoop
	internal var runLoopModes: [RunLoop.Mode]
	
	internal var currentTry: Int
	internal var maxTryCount: Int?
	
	internal init(
		condition: @escaping () -> Bool, block: @escaping (_ isAsyncCall: Bool) throws -> R, endHandler: ((Result<R, Error>?) -> Void)?,
		retryDelay: TimeInterval?,
		runLoop: RunLoop, runLoopModes: [RunLoop.Mode],
		currentTry: Int, maxTryCount: Int?)
	{
		self.condition = condition
		self.block = block
		self.endHandler = endHandler
		self.retryDelay = retryDelay
		self.runLoop = runLoop
		self.runLoopModes = runLoopModes
		self.currentTry = currentTry
		self.maxTryCount = maxTryCount
		
		/* --- Variables are all init’d here --- */
		
		self.usingItself = self
		scheduleNextTry()
	}
	
	deinit {
		NSLog("Deinit happened for an ASAPExecution")
	}
	
	private var usingItself: ASAPExecution<R>?
	
	private func scheduleNextTry() {
		if let retryDelay = retryDelay {
			let timer = Timer(timeInterval: retryDelay, repeats: false, block: { t in t.invalidate() /* Probably unneeded */; self.runNextTry() })
			for mode in runLoopModes {runLoop.add(timer, forMode: mode)}
		} else {
			/* We schedule immediately. */
			runLoop.perform(inModes: runLoopModes, block: runNextTry)
		}
	}
	
	private func runNextTry() {
		guard currentTry <= maxTryCount ?? .max else {
			endHandler?(nil)
			return
		}
		
		currentTry += 1
		if condition() {
			do    {let ret = try block(true); endHandler?(.success(ret))}
			catch {                           endHandler?(.failure(error))}
			usingItself = nil
		} else {
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
