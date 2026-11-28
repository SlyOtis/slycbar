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
	dependencies: [
		.package(url: "https://github.com/ChimeHQ/SwiftTreeSitter", from: "0.25.0"),
		.package(url: "https://github.com/tree-sitter/tree-sitter-json", from: "0.24.8"),
		.package(url: "https://github.com/tree-sitter/tree-sitter-javascript", exact: "0.23.1"),
		.package(url: "https://github.com/tree-sitter/tree-sitter-typescript", from: "0.23.2"),
		.package(url: "https://github.com/tree-sitter/tree-sitter-go", from: "0.25.0"),
		.package(url: "https://github.com/tree-sitter/tree-sitter-python", exact: "0.23.6"),
		.package(url: "https://github.com/tree-sitter/tree-sitter-rust", from: "0.24.2"),
		.package(url: "https://github.com/tree-sitter/tree-sitter-bash", from: "0.25.1"),
		.package(url: "https://github.com/tree-sitter/tree-sitter-html", from: "0.23.2"),
		.package(url: "https://github.com/tree-sitter/tree-sitter-css", exact: "0.23.2"),
		.package(url: "https://github.com/alex-pinkus/tree-sitter-swift", exact: "0.7.4-with-generated-files"),
	],
	targets: [
		.target(name: "Statusline"),
		.target(name: "Space"),
		.target(name: "Core", dependencies: ["Space"]),
		.executableTarget(name: "slybar", dependencies: ["Statusline", "Space", "Core"]),
		.target(name: "tray"),
		.executableTarget(name: "slyed", dependencies: ["tray", "SwiftTreeSitter",
			.product(name: "TreeSitterJSON", package: "tree-sitter-json"), .product(name: "TreeSitterJavaScript", package: "tree-sitter-javascript"),
			.product(name: "TreeSitterTypeScript", package: "tree-sitter-typescript"), .product(name: "TreeSitterGo", package: "tree-sitter-go"),
			.product(name: "TreeSitterPython", package: "tree-sitter-python"), .product(name: "TreeSitterRust", package: "tree-sitter-rust"),
			.product(name: "TreeSitterBash", package: "tree-sitter-bash"), .product(name: "TreeSitterHTML", package: "tree-sitter-html"),
			.product(name: "TreeSitterCSS", package: "tree-sitter-css"), .product(name: "TreeSitterSwift", package: "tree-sitter-swift")]),
		.executableTarget(name: "widget", swiftSettings: [.unsafeFlags(["-application-extension"])], linkerSettings: [.unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])]),
		.testTarget(name: "StatuslineTests", dependencies: ["Statusline", "Space"]),
	],
	swiftLanguageModes: [.v5]
)
