import Foundation



/* I don’t think this should be public, except maybe if we want to be able to cancel an ASAP execution… */
class ASAPExecution<R> {
	
	var condition: () -> Bool
	var block: () throws -> R
	var completion: ((_ result: Result<R, Error>?) -> Void)?
	
	var retryDelay: TimeInterval?
	
	var runLoop: RunLoop
	var runLoopModes: [RunLoop.Mode]
	
	var currentTry: Int
	var maxTryCount: Int?
	
	init(
		condition: @escaping () -> Bool, block: @escaping () throws -> R, completion: ((Result<R, Error>?) -> Void)?,
		retryDelay: TimeInterval?,
		runLoop: RunLoop, runLoopModes: [RunLoop.Mode],
		currentTry: Int, maxTryCount: Int?)
	{
		self.condition = condition
		self.block = block
		self.completion = completion
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
			do    {let ret = try block(); completion?(.success(ret))}
			catch {                       completion?(.failure(error))}
			usingItself = nil
		} else {
			scheduleNextTry()
		}
	}
	
}
