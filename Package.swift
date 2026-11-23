// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "slybar",
	platforms: [.macOS(.v14)],
	products: [
		.executable(name: "slybar", targets: ["slybar"]),
		.executable(name: "tray", targets: ["tray"]),
		.executable(name: "editor", targets: ["editor"]),
		.executable(name: "app", targets: ["app"]),
		.executable(name: "widget", targets: ["widget"]),
	],
	targets: [
		.target(name: "Statusline"),
		.target(name: "Space"),
		.target(name: "Core", dependencies: ["Space"]),
		.executableTarget(name: "slybar", dependencies: ["Statusline", "Space", "Core"]),
		.executableTarget(name: "tray"),
		.executableTarget(name: "editor"),
		.executableTarget(name: "app"),
		.executableTarget(name: "widget", swiftSettings: [.unsafeFlags(["-application-extension"])], linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]),
		.testTarget(name: "StatuslineTests", dependencies: ["Statusline"]),
	],
	swiftLanguageModes: [.v5]
)
