// swift-tools-version:5.9
import PackageDescription
let package = Package(name: "Blinq", platforms: [.macOS(.v14)],
  targets: [.executableTarget(name: "Blinq", path: "Sources/Blinq")])
