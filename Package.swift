// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "slybar",
	platforms: [.macOS(.v14)],
	products: [
		.executable(name: "slybar", targets: ["slybar"]),
		.executable(name: "slyed", targets: ["slyed"]),
		.executable(name: "widget", targets: ["widget"]),
	],
	targets: [
		.target(name: "Statusline"),
		.target(name: "Space"),
		.target(name: "Core", dependencies: ["Space"]),
		.executableTarget(name: "slybar", dependencies: ["Statusline", "Space", "Core"]),
		.target(name: "tray"),
		.executableTarget(name: "slyed", dependencies: ["tray"]),
		.executableTarget(name: "widget", swiftSettings: [.unsafeFlags(["-application-extension"])], linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]),
		.testTarget(name: "StatuslineTests", dependencies: ["Statusline", "Space"]),
	],
	swiftLanguageModes: [.v5]
)
