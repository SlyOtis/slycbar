import Foundation

typealias Json = [String: Any]

enum Base {
	static let env = ProcessInfo.processInfo.environment
	static let home = NSHomeDirectory()
	static let cache = env["SLYCBAR_CACHE"] ?? (env["XDG_CACHE_HOME"] ?? home + "/.cache") + "/slycbar"
	static let tray = cache + "/tray"
	static let claude = env["CLAUDE_CONFIG_DIR"] ?? home + "/.claude"
	static let config = (env["CLAUDE_CONFIG_DIR"] ?? home) + "/.claude.json"
	static let sessions = env["SLYCBAR_SESSIONS"] ?? claude + "/sessions"
	static let main = "Claude Code-credentials"
	static let store = "slycbar"
	static let api = "https://api.anthropic.com/api/oauth"
	static let token = "https://platform.claude.com/v1/oauth/token"
	static let client = "9d1c250a-e61b-44d9-88ed-5944d1962f5e"
	static let editApp = home + "/Applications/Slyed.app"
	static let plugin = home + "/.slycbar/plugin"
	static let settings = home + "/.slycbar/settings.json"
	static let agent = "no.slytech.slycbar"
	static let plist = home + "/Library/LaunchAgents/no.slytech.slycbar.plist"
	static let bin = home + "/.local/bin/slybar"

	static let here: String = {
		if let set = env["SLYBAR_HOME"] {
			return set
		}
		let real = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0]).resolvingSymlinksInPath().path
		var at = (real as NSString).deletingLastPathComponent
		while at.count > 1 {
			if FileManager.default.fileExists(atPath: at + "/Package.swift") {
				return at
			}
			at = (at as NSString).deletingLastPathComponent
		}
		return (try? String(contentsOfFile: home + "/.slycbar/home", encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? FileManager.default.currentDirectoryPath
	}()

	static var now: Double { Date().timeIntervalSince1970 }

	static func fail(_ message: String, _ code: Int32 = 1) -> Int32 {
		FileHandle.standardError.write(Data((message + "\n").utf8))
		return code
	}

	static func say(_ text: String) {
		FileHandle.standardOutput.write(Data((text + "\n").utf8))
	}

	static func tools() -> [String: String] {
		var all = env
		all["PATH"] = ["/opt/homebrew/bin", home + "/Library/pnpm", home + "/.cargo/bin", home + "/go/bin", home + "/.local/bin", "/usr/local/bin", env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin"].joined(separator: ":")
		all["S"] = cache + "/editor/servers"
		return all
	}

	@discardableResult
	static func run(_ tool: String, _ args: [String], input: String? = nil, dir: String? = nil, quiet: Bool = true, env: [String: String]? = nil) -> (code: Int32, out: String) {
		let task = Process()
		let out = Pipe()
		let feed = Pipe()
		task.executableURL = URL(fileURLWithPath: tool.hasPrefix("/") ? tool : "/usr/bin/env")
		task.arguments = tool.hasPrefix("/") ? args : [tool] + args
		task.environment = env ?? tools()
		task.standardOutput = out
		task.standardError = quiet ? FileHandle.nullDevice : FileHandle.standardError
		if input != nil {
			task.standardInput = feed
		}
		if let dir {
			task.currentDirectoryURL = URL(fileURLWithPath: dir)
		}
		do {
			try task.run()
		} catch {
			return (127, "")
		}
		if let input {
			feed.fileHandleForWriting.write(Data(input.utf8))
			feed.fileHandleForWriting.closeFile()
		}
		let data = out.fileHandleForReading.readDataToEndOfFile()
		task.waitUntilExit()
		return (task.terminationStatus, String(decoding: data, as: UTF8.self))
	}

	static func shell(_ command: String, quiet: Bool = true) -> Int32 {
		run("/bin/sh", ["-c", command], quiet: quiet).code
	}

	static func read(_ path: String) -> String {
		(try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
	}

	static func write(_ path: String, _ text: String) {
		let mode = (try? FileManager.default.attributesOfItem(atPath: path)[.posixPermissions]) as? NSNumber
		try? text.write(toFile: path, atomically: true, encoding: .utf8)
		if let mode {
			try? FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: path)
		}
	}

	static func json(_ path: String) -> Json {
		parse(read(path)) ?? [:]
	}

	static func parse(_ text: String) -> Json? {
		(try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? Json
	}

	static func text(_ value: Any, pretty: Bool = false) -> String {
		guard JSONSerialization.isValidJSONObject(value), let data = try? JSONSerialization.data(withJSONObject: value, options: pretty ? [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes] : [.withoutEscapingSlashes]) else { return "null" }
		return String(decoding: data, as: UTF8.self)
	}

	static func edit(_ path: String, _ change: (inout Json) -> Void) {
		var all = json(path)
		change(&all)
		write(path, text(all))
	}

	static func modified(_ path: String) -> Double {
		((try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate]) as? Date)?.timeIntervalSince1970 ?? 0
	}

	static func alive(_ pid: Int) -> Bool {
		pid > 0 && kill(pid_t(pid), 0) == 0
	}

	static func prepare() {
		try? FileManager.default.createDirectory(atPath: tray, withIntermediateDirectories: true)
		for name in ["accounts.json", "usage.json"] where !FileManager.default.fileExists(atPath: tray + "/" + name) {
			write(tray + "/" + name, "{}")
		}
		for name in ["resources.tsv", "space.tsv"] where !FileManager.default.fileExists(atPath: tray + "/" + name) {
			write(tray + "/" + name, "")
		}
	}

	static func lock(wait: Bool) -> Bool {
		let path = tray + "/lock"
		while true {
			if (try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)) != nil {
				return true
			}
			if !wait {
				return false
			}
			if now - modified(path) > 60 {
				try? FileManager.default.removeItem(atPath: path)
			}
			Thread.sleep(forTimeInterval: 0.2)
		}
	}

	static func unlock() {
		try? FileManager.default.removeItem(atPath: tray + "/lock")
	}

	static func get(_ url: String, headers: [String: String] = [:], body: Data? = nil) -> (code: Int, text: String) {
		guard let target = URL(string: url) else { return (0, "") }
		var request = URLRequest(url: target, timeoutInterval: 15)
		for (name, value) in headers {
			request.setValue(value, forHTTPHeaderField: name)
		}
		if let body {
			request.httpMethod = "POST"
			request.httpBody = body
		}
		let done = DispatchSemaphore(value: 0)
		var result = (0, "")
		URLSession.shared.dataTask(with: request) { data, response, _ in
			result = ((response as? HTTPURLResponse)?.statusCode ?? 0, String(decoding: data ?? Data(), as: UTF8.self))
			done.signal()
		}.resume()
		done.wait()
		return result
	}
}
