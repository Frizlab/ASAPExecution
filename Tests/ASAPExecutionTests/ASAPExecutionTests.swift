import Foundation
import XCTest

import RunLoopThread

@testable import ASAPExecution



@available(macOS 12.0, iOS 15.0, tvOS 15.0, watchOS 8.0, *)
final class ASAPExecutionTests : XCTestCase {
	
	func testBasicUsage() async throws {
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
		
		await Task.sleep(250 * 1_000_000)
		XCTAssertFalse(witness)
		
		cond = true
		
		await Task.sleep(250 * 1_000_000)
		XCTAssertTrue(witness)
		XCTAssertGreaterThan(nTries, 5/* In 250ms 5 tries have to have been tried at least! Said he, licking his finger… */)
		
		let r = XCTWaiter().wait(for: [exitExpectation], timeout: 0.25)
		XCTAssertEqual(r, .completed)
	}
	
	func testMaxTryCount() async throws {
		let t = RunLoopThread(name: "me.frizlab.asap-execution.test-basic-usage")
		
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
