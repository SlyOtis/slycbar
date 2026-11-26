import Foundation

enum Tools {
	static func running() -> Bool {
		Base.alive(Int(Base.read(Base.tray + "/pid").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0)
	}

	static func open() -> Int32 {
		if running() {
			Base.write(Base.tray + "/show", String(Int(Base.now)))
			return 0
		}
		let task = Process()
		task.executableURL = URL(fileURLWithPath: Base.editApp + "/Contents/MacOS/slyed")
		task.arguments = ["tray", "show"]
		task.environment = Base.env.filter { !$0.key.hasPrefix("CLAUDE") || $0.key == "CLAUDE_CONFIG_DIR" }
		task.standardInput = FileHandle.nullDevice
		task.standardOutput = FileHandle.nullDevice
		task.standardError = FileHandle.nullDevice
		do {
			try task.run()
		} catch {
			return Base.fail("Slyed is not installed, run slybar install")
		}
		return 0
	}

	static let defaults: Json = ["font": "Liga Roboto Mono", "ligatures": true, "smoothing": true, "traces": true, "accent": "#b4632f", "read": "#56a8f5", "edited": "#ef8221", "wrote": "#6aab73",
		"agents": true, "meters": true, "stats": true, "warp": true, "width": 214.0, "scale": 1.1, "zoom": 1.2]

	static func settings(_ args: [String]) -> Int32 {
		var stored = Base.json(Base.settings)
		guard let key = args.first else {
			Base.say(Base.text(defaults.merging(stored) { _, set in set }, pretty: true))
			return 0
		}
		guard let standard = defaults[key] ?? (key.hasPrefix("zoom.code.") || key.hasPrefix("zoom.preview.") ? 1.0 : nil) else { return Base.fail("unknown setting \(key), one of " + defaults.keys.sorted().joined(separator: ", ")) }
		guard args.count > 1 else {
			Base.say(Base.text(["value": stored[key] ?? standard]))
			return 0
		}
		if standard is Bool {
			guard args[1] == "true" || args[1] == "false" else { return Base.fail("\(key) is true or false") }
			stored[key] = args[1] == "true"
		} else if standard is Double {
			guard let number = Double(args[1]) else { return Base.fail("\(key) is a number") }
			stored[key] = number
		} else if (standard as? String)?.hasPrefix("#") == true {
			guard args[1].range(of: "^#[0-9a-fA-F]{6}$", options: .regularExpression) != nil else { return Base.fail("\(key) is a colour as #rrggbb") }
			stored[key] = args[1].lowercased()
		} else {
			stored[key] = args[1...].joined(separator: " ")
		}
		Base.write(Base.settings, Base.text(stored, pretty: true))
		Base.say(Base.text(defaults.merging(stored) { _, set in set }, pretty: true))
		return 0
	}

	static func widget() -> Int32 {
		if FileManager.default.fileExists(atPath: Base.editApp) {
			Base.run("/usr/bin/open", ["-g", "slycbar://reload"])
		}
		return 0
	}

	static func edit(_ args: [String]) -> Int32 {
		guard var path = args.first else { return Base.fail("usage: slybar edit <path> [line] [end]", 2) }
		if !path.hasPrefix("/") {
			path = FileManager.default.currentDirectoryPath + "/" + path
		}
		guard FileManager.default.fileExists(atPath: path) else { return Base.fail("no file at \(path)") }
		guard FileManager.default.fileExists(atPath: Base.editApp) else { return Base.fail("Slyed is not installed, run slybar install") }
		var allowed = CharacterSet.alphanumerics
		allowed.insert(charactersIn: "-_.~")
		var url = "slyed://open?path=" + (path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path)
		if args.count > 1 {
			url += "&line=" + args[1]
		}
		if args.count > 2 {
			url += "&end=" + args[2]
		}
		return Base.run("/usr/bin/open", [url]).code
	}

	static func server(_ args: [String]) -> Int32 {
		guard let path = args.first else { return Base.fail("usage: slybar server <path> [install]", 2) }
		let name = (path as NSString).lastPathComponent.lowercased()
		let ext = name.contains(".") ? (name as NSString).pathExtension : name
		let all = (try? JSONSerialization.jsonObject(with: Data(Base.read(Base.here + "/editor/servers.json").utf8))) as? [Json] ?? []
		guard let entry = all.first(where: { ($0["languages"] as? Json)?[ext] != nil || ($0["languages"] as? Json)?[name] != nil }) else {
			guard Base.run("brew", ["--version"]).code == 0 else { return Base.fail("brew is missing") }
			let found = Base.run("brew", ["search", "/(^|-)\(ext)(-|_)?(language-server|lsp|ls)$/"]).out.split(separator: "\n").map(String.init).filter { !$0.isEmpty && !$0.hasPrefix("==>") }
			Base.say(Base.text(["server": NSNull(), "extension": ext, "brew": found] as Json, pretty: true))
			return 0
		}
		let check = entry["check"] as? String ?? "false"
		let install = entry["install"] as? String ?? "false"
		if args.count > 1, args[1] == "install", Base.shell(check) != 0 {
			_ = Base.shell(install + " >&2", quiet: false)
		}
		Base.say(Base.text(["server": entry["name"] ?? NSNull(), "installed": Base.shell(check) == 0, "install": install] as Json, pretty: true))
		return 0
	}

	static func version() -> String {
		var text = ""
		for skill in ((try? FileManager.default.contentsOfDirectory(atPath: Base.here + "/skills")) ?? []).sorted() {
			text += Base.read(Base.here + "/skills/" + skill + "/SKILL.md")
		}
		let sum = Base.run("/usr/bin/shasum", ["-a", "256"], input: text + "hooks: guard on SessionStart, PreToolUse, PostToolUse, ExitPlanMode; mcp: review_open, review_status, review_wait").out
		return "v1.0-" + sum.prefix(12)
	}

	static let hosts = ["claude", "codex", "gemini", "opencode", "desktop", "chatgpt", "antigravity"]
	static let about = "Statusline, tray, widget, code editor and machine resources for Claude Code"

	static func skills(_ dir: String) {
		let fm = FileManager.default
		for skill in (try? fm.contentsOfDirectory(atPath: Base.here + "/skills")) ?? [] {
			try? fm.removeItem(atPath: dir + "/skills/" + skill)
			try? fm.createDirectory(atPath: dir + "/skills/" + skill, withIntermediateDirectories: true)
			Base.write(dir + "/skills/" + skill + "/SKILL.md", Base.read(Base.here + "/skills/" + skill + "/SKILL.md"))
		}
	}

	static func hooks(_ host: String) -> Json {
		if host == "claude" {
			let hook: Json = ["type": "command", "command": Base.bin, "args": ["guard"], "timeout": 5]
			return ["SessionStart": [["hooks": [hook]]],
				"PreToolUse": [["matcher": "Edit|Write|MultiEdit|NotebookEdit", "hooks": [hook]], ["matcher": "Bash|mcp__.*|Agent|Task", "hooks": [hook]], ["matcher": "ExitPlanMode", "hooks": [hook]]],
				"PostToolUse": [["matcher": "Bash|mcp__.*|Agent|Task", "hooks": [hook]]]]
		}
		let gemini = host == "gemini"
		let hook: Json = ["type": "command", "command": Base.bin + " guard", "timeout": gemini ? 5000 : 5]
		let write = gemini ? "write_file|replace" : "Edit|Write|apply_patch"
		let run = gemini ? "run_shell_command|mcp_.*" : "Bash|mcp__.*|Agent"
		return ["SessionStart": [["hooks": [hook]]],
			(gemini ? "BeforeTool" : "PreToolUse"): [["matcher": write, "hooks": [hook]], ["matcher": run, "hooks": [hook]]],
			(gemini ? "AfterTool" : "PostToolUse"): [["matcher": run, "hooks": [hook]]]]
	}

	static func found(_ host: String) -> Bool {
		let fm = FileManager.default
		switch host {
		case "desktop": return fm.fileExists(atPath: Base.home + "/Library/Application Support/Claude")
		case "chatgpt": return fm.fileExists(atPath: "/Applications/ChatGPT.app") || fm.fileExists(atPath: Base.home + "/Applications/ChatGPT.app")
		case "antigravity": return Base.shell("command -v agy") == 0 || fm.fileExists(atPath: Base.home + "/.gemini/config")
		default: return Base.shell("command -v " + host) == 0
		}
	}

	static func table(_ path: String) {
		var kept: [String] = []
		var skip = false
		for line in Base.read(path).split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
			let trimmed = line.trimmingCharacters(in: .whitespaces)
			if trimmed.hasPrefix("[") {
				skip = trimmed == "[mcp_servers.slycbar]" || trimmed.hasPrefix("[mcp_servers.slycbar.")
			}
			if !skip {
				kept.append(line)
			}
		}
		var body = kept.joined(separator: "\n").trimmingCharacters(in: .newlines)
		if !body.isEmpty {
			body += "\n\n"
		}
		body += "[mcp_servers.slycbar]\ncommand = " + Base.text([Base.bin]).dropFirst().dropLast() + "\nargs = [\"mcp\"]\n"
		try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
		Base.write(path, body)
	}

	static func merge(_ path: String, _ change: (inout Json) -> Void) -> Bool {
		let text = Base.read(path)
		var all: Json = [:]
		if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
			guard let read = Base.parse(text) else { return false }
			all = read
		}
		change(&all)
		try? FileManager.default.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
		Base.write(path, Base.text(all, pretty: true) + "\n")
		return true
	}

	static func install(_ host: String, _ carried: String) -> Int32 {
		let fm = FileManager.default
		let server: Json = ["command": Base.bin, "args": ["mcp"]]
		switch host {
		case "claude":
			guard Base.run("claude", ["--version"]).code == 0 else { return Base.fail("claude is missing") }
			try? fm.createDirectory(atPath: Base.plugin + "/.claude-plugin", withIntermediateDirectories: true)
			try? fm.removeItem(atPath: Base.plugin + "/skills")
			skills(Base.plugin)
			try? fm.createDirectory(atPath: Base.plugin + "/hooks", withIntermediateDirectories: true)
			Base.write(Base.plugin + "/hooks/hooks.json", Base.text(["hooks": hooks(host)] as Json, pretty: true))
			Base.write(Base.plugin + "/.mcp.json", Base.text(["mcpServers": ["slycbar": server]] as Json, pretty: true))
			Base.write(Base.plugin + "/.claude-plugin/plugin.json", Base.text(["name": "slycbar", "version": carried, "description": about, "author": ["name": "Slytech"], "skills": "./skills/"] as Json, pretty: true))
			Base.write(Base.plugin + "/.claude-plugin/marketplace.json", Base.text(["name": "slycbar", "description": "The slycbar plugin this checkout carries.", "owner": ["name": "Slytech"],
				"plugins": [["name": "slycbar", "description": about, "source": "./", "version": carried]]] as Json, pretty: true))
			if Base.run("claude", ["plugin", "marketplace", "add", Base.plugin]).code != 0 {
				Base.run("claude", ["plugin", "marketplace", "update", "slycbar"])
			}
			if Base.run("claude", ["plugin", "install", "slycbar@slycbar"]).code != 0 {
				Base.run("claude", ["plugin", "update", "slycbar@slycbar"])
			}
			Base.say("installed the slycbar plugin \(carried) from \(Base.plugin)")
			return 0
		case "codex", "chatgpt":
			skills(Base.home + "/.agents")
			table(Base.home + "/.codex/config.toml")
			let path = Base.home + "/.codex/hooks.json"
			let merged = merge(path) { all in
				var events = all["hooks"] as? Json ?? [:]
				for (event, groups) in hooks(host) {
					let kept = (events[event] as? [Json] ?? []).filter { group in
						!(group["hooks"] as? [Json] ?? []).contains { ($0["command"] as? String ?? "").hasPrefix(Base.bin + " ") }
					}
					events[event] = kept + (groups as? [Json] ?? [])
				}
				all["hooks"] = events
			}
			guard merged else { return Base.fail("\(path) is not json and is left as it is") }
		case "gemini":
			guard Base.shell("command -v gemini") == 0 else { return Base.fail("gemini is missing") }
			let dir = Base.home + "/.slycbar/gemini"
			try? fm.createDirectory(atPath: dir + "/hooks", withIntermediateDirectories: true)
			skills(dir)
			Base.write(dir + "/hooks/hooks.json", Base.text(["hooks": hooks(host)] as Json, pretty: true))
			Base.write(dir + "/gemini-extension.json", Base.text(["name": "slycbar", "version": String(carried.dropFirst()), "description": about, "mcpServers": ["slycbar": server]] as Json, pretty: true))
			Base.run("gemini", ["extensions", "uninstall", "slycbar"])
			guard Base.run("gemini", ["extensions", "install", dir, "--consent"]).code == 0 else { return Base.fail("gemini extensions install \(dir) failed") }
		case "opencode":
			let dir = Base.home + "/.config/opencode"
			skills(dir)
			let path = dir + (fm.fileExists(atPath: dir + "/opencode.json") || !fm.fileExists(atPath: dir + "/opencode.jsonc") ? "/opencode.json" : "/opencode.jsonc")
			let merged = merge(path) { all in
				var mcp = all["mcp"] as? Json ?? [:]
				var servers = mcp["servers"] as? Json ?? [:]
				servers["slycbar"] = ["type": "local", "command": [Base.bin, "mcp"]] as Json
				mcp["servers"] = servers
				all["mcp"] = mcp
			}
			guard merged else { return Base.fail("\(path) is not plain json and is left as it is, add mcp.servers.slycbar there by hand") }
		case "desktop":
			let path = Base.home + "/Library/Application Support/Claude/claude_desktop_config.json"
			let merged = merge(path) { all in
				var servers = all["mcpServers"] as? Json ?? [:]
				servers["slycbar"] = server
				all["mcpServers"] = servers
			}
			guard merged else { return Base.fail("\(path) is not json and is left as it is") }
		case "antigravity":
			let dir = Base.home + "/.gemini/config"
			skills(dir)
			let path = dir + "/mcp_config.json"
			let merged = merge(path) { all in
				var servers = all["mcpServers"] as? Json ?? [:]
				servers["slycbar"] = server
				all["mcpServers"] = servers
			}
			guard merged else { return Base.fail("\(path) is not json and is left as it is") }
		default:
			return Base.fail("no host is \(host)", 2)
		}
		_ = merge(Base.home + "/.slycbar/hosts.json") { $0[host] = carried }
		Base.say("installed slycbar \(carried) for \(host)")
		return 0
	}

	static func plugin(_ args: [String]) -> Int32 {
		let carried = version()
		let usage = "usage: slybar plugin install [" + hosts.map { "--" + $0 }.joined(separator: "] [") + "]|status"
		switch args.first ?? "status" {
		case "install":
			var picked = args.dropFirst().map { String($0.dropFirst(2)) }
			guard args.dropFirst().allSatisfy({ $0.hasPrefix("--") }), picked.allSatisfy(hosts.contains) else { return Base.fail(usage, 2) }
			if picked.isEmpty {
				let found = hosts.filter(Tools.found)
				let flags = "pass " + hosts.map { "--" + $0 }.joined(separator: ", ") + " to pick"
				guard !found.isEmpty else { return Base.fail("none of \(hosts.joined(separator: ", ")) is found on this machine, \(flags)") }
				picked = found
				if found.count > 1 {
					guard isatty(0) != 0, isatty(2) != 0 else { return Base.fail("\(found.joined(separator: ", ")) are installed, \(flags)", 2) }
					for (at, host) in found.enumerated() {
						FileHandle.standardError.write(Data("\(at + 1)  \(host)\n".utf8))
					}
					FileHandle.standardError.write(Data("install for which, numbers separated by spaces, or all: ".utf8))
					let words = (readLine() ?? "").replacingOccurrences(of: ",", with: " ").split(separator: " ").map(String.init)
					if !words.contains("all") {
						picked = words.compactMap { Int($0) }.filter { $0 >= 1 && $0 <= found.count }.map { found[$0 - 1] }
						guard !picked.isEmpty, picked.count == words.count else { return Base.fail("no host was picked, \(flags)", 2) }
					}
				}
			}
			for host in picked {
				let code = install(host, carried)
				if code != 0 { return code }
			}
			return 0
		case "status":
			var installed = Base.json(Base.home + "/.slycbar/hosts.json")
			if let version = Base.json(Base.plugin + "/.claude-plugin/plugin.json")["version"] as? String {
				installed["claude"] = version
			}
			guard !installed.isEmpty else { return Base.fail("the slycbar plugin is not installed, run slybar plugin install") }
			for host in hosts {
				guard let version = installed[host] as? String else { continue }
				guard version == carried else { return Base.fail("the plugin installed for \(host) is \(version), this checkout carries \(carried), run slybar plugin install --\(host)") }
				Base.say("the slycbar plugin \(carried) is current for \(host)")
			}
			return 0
		default:
			return Base.fail(usage, 2)
		}
	}
}
