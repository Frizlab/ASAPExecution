import Foundation



func frz_executeASAP<R>(_ condition: @autoclosure @escaping () -> Bool, _ block: @escaping () -> R, completion: ((_ result: R?) -> Void)?, retryDelay: TimeInterval? = nil, runLoop: RunLoop = .current, runLoopModes: [RunLoop.Mode] = [.default], maxTryCount: Int? = nil, skipSyncTry: Bool = false) {
	frz_executeASAPThrows(condition(), block, completion: { completion?($0?.success /* success will never be nil, but not unwrapping because $0 might. */) }, retryDelay: retryDelay, runLoop: runLoop, runLoopModes: runLoopModes, maxTryCount: maxTryCount, skipSyncTry: skipSyncTry)
}

func frz_executeASAPThrows<R>(_ condition: @autoclosure @escaping () -> Bool, _ block: @escaping () throws -> R, completion: ((_ result: Result<R, Error>?) -> Void)?, retryDelay: TimeInterval? = nil, runLoop: RunLoop = .current, runLoopModes: [RunLoop.Mode] = [.default], maxTryCount: Int? = nil, skipSyncTry: Bool = false) {
	/* We avoid an allocation if condition is already true (happy and probably most common path). */
	if !skipSyncTry, condition() {
		do    {let ret = try block(); completion?(.success(ret))}
		catch {                       completion?(.failure(error))}
		return
	}
	
	/* The ASAPExecution holds a strong reference to itself; no need to keep a hold of it. */
	_ = ASAPExecution(
		condition: condition, block: block, completion: completion,
		retryDelay: retryDelay,
		runLoop: runLoop, runLoopModes: runLoopModes,
		currentTry: skipSyncTry ? 0 : 1, maxTryCount: maxTryCount
	)
}


private extension Result {
	
	var success: Success? {
		switch self {
			case .failure:        return nil
			case .success(let s): return s
		}
	}
	
}
