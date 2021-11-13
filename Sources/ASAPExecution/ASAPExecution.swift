import Foundation



public final class ASAPExecution<R> {
	
	@discardableResult
	public static func when(_ condition: @autoclosure @escaping () -> Bool, do block: @escaping () -> R, endHandler: ((_ result: R?) -> Void)?, retryDelay: TimeInterval? = nil, runLoop: RunLoop = .current, runLoopModes: [RunLoop.Mode] = [.default], maxTryCount: Int? = nil, skipSyncTry: Bool = false) -> ASAPExecution<R>? {
		return when(
			condition(), doThrowing: block,
			endHandler: { endHandler?($0?.success /* success will never be nil, but not unwrapping because $0 might. */) },
			retryDelay: retryDelay, runLoop: runLoop, runLoopModes: runLoopModes,
			maxTryCount: maxTryCount, skipSyncTry: skipSyncTry
		)
	}
	
	@discardableResult
	public static func when(_ condition: @autoclosure @escaping () -> Bool, doThrowing block: @escaping () throws -> R, endHandler: ((_ result: Result<R, Error>?) -> Void)?, retryDelay: TimeInterval? = nil, runLoop: RunLoop = .current, runLoopModes: [RunLoop.Mode] = [.default], maxTryCount: Int? = nil, skipSyncTry: Bool = false) -> ASAPExecution<R>? {
		/* We avoid an allocation if condition is already true (happy and probably most common path). */
		if !skipSyncTry, condition() {
			do    {let ret = try block(); endHandler?(.success(ret))}
			catch {                       endHandler?(.failure(error))}
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
	
	var condition: () -> Bool
	var block: () throws -> R
	var endHandler: ((_ result: Result<R, Error>?) -> Void)?
	
	var retryDelay: TimeInterval?
	
	var runLoop: RunLoop
	var runLoopModes: [RunLoop.Mode]
	
	var currentTry: Int
	var maxTryCount: Int?
	
	init(
		condition: @escaping () -> Bool, block: @escaping () throws -> R, endHandler: ((Result<R, Error>?) -> Void)?,
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
		if condition() {
			do    {let ret = try block(); endHandler?(.success(ret))}
			catch {                       endHandler?(.failure(error))}
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
