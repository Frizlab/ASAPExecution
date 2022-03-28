import Foundation
import XCTest

import RunLoopThread

@testable import ASAPExecution



final class ASAPExecutionUntilTests : XCTestCase {
	
	func testBasicUsage() throws {
		let t = RunLoopThread(name: "me.frizlab.asap-execution-until.test-basic-usage")
		t.start()
		
		let exitExpectation = XCTNSNotificationExpectation(name: .NSThreadWillExit, object: t)
		
		var nTries = 0
		var cond = false
		_ = t.sync{
			ASAPExecution.until(cond, do: { _ in nTries += 1; XCTAssertFalse(cond) }, endHandler: { _ in t.cancel() })
		}
		
		/* The runloop goes *fast*.
		 * In real life testing, some tries have already been done when we get here. */
		XCTAssertGreaterThanOrEqual(nTries, 0)
		
		Thread.sleep(forTimeInterval: 0.25)
		XCTAssertGreaterThan(nTries, 0)
		
		cond = true
		
		Thread.sleep(forTimeInterval: 0.250)
		XCTAssertGreaterThan(nTries, 5/* In 250ms 5 tries have to have been tried at least! Said he, licking his finger… */)
		
		let r = XCTWaiter().wait(for: [exitExpectation], timeout: 0.25)
		XCTAssertEqual(r, .completed)
	}
	
}
