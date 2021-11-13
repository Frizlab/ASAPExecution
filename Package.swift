// swift-tools-version:5.5
import PackageDescription


let package = Package(
	name: "ASAPExecution",
	platforms: [.macOS(.v10_12), .iOS(.v15), .tvOS(.v15), .watchOS(.v8)],
	products: [.library(name: "ASAPExecution", targets: ["ASAPExecution"])],
	dependencies: [.package(url: "https://github.com/happn-tech/RunLoopThread.git", from: "1.0.0")],
	targets: [
		.target(name: "ASAPExecution"),
		.testTarget(name: "ASAPExecutionTests", dependencies: [
			"ASAPExecution",
			.product(name: "RunLoopThread", package: "RunLoopThread")
		])
	]
)
