import Foundation
import XCTest

import RunLoopThread

@testable import ASAPExecution



final class ASAPExecutionTests : XCTestCase {
	
	func testBasicUsage() throws {
		let t = RunLoopThread(name: "me.frizlab.asap-execution.test-basic-usage")
		t.start()
		
		let exitExpectation = XCTNSNotificationExpectation(name: .NSThreadWillExit, object: t)
		
		var nTries = 0
		var cond = false
		var witness = false
		t.sync{
			ASAPExecution.when({ nTries += 1; return cond }(), do: { _ in witness = true }, endHandler: { _ in t.cancel() })
		}
		
		XCTAssertFalse(witness)
		
		Thread.sleep(forTimeInterval: 0.25)
		XCTAssertFalse(witness)
		
		cond = true
		
		Thread.sleep(forTimeInterval: 0.250)
		XCTAssertTrue(witness)
		XCTAssertGreaterThan(nTries, 5/* In 250ms 5 tries have to have been tried at least! Said he, licking his finger… */)
		
		let r = XCTWaiter().wait(for: [exitExpectation], timeout: 0.25)
		XCTAssertEqual(r, .completed)
	}
	
	func testMaxTryCount() throws {
		let t = RunLoopThread(name: "me.frizlab.asap-execution.test-max-try-count")
		
		let exitExpectation = XCTNSNotificationExpectation(name: .NSThreadWillExit, object: t)
		
		var nTries = 0
		t.start()
		t.sync{
			ASAPExecution.when({ nTries += 1; return false }(), do: { _ in }, endHandler: { _ in t.cancel() }, maxTryCount: 3)
		}
		
		let r = XCTWaiter().wait(for: [exitExpectation], timeout: 0.25)
		XCTAssertEqual(r, .completed)
		XCTAssertEqual(nTries, 3)
	}
	
	@objc
	private class Witness : NSObject {
		@objc dynamic var value: NSNumber = 0
		func wentThere() {value = NSNumber(value: value.intValue + 1)}
	}
	
}
