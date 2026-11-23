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
		task.executableURL = URL(fileURLWithPath: Base.trayApp + "/Contents/MacOS/tray")
		task.arguments = [Base.bin, Base.tray, "show"]
		task.environment = Base.env.filter { !$0.key.hasPrefix("CLAUDE") || $0.key == "CLAUDE_CONFIG_DIR" }
		task.standardInput = FileHandle.nullDevice
		task.standardOutput = FileHandle.nullDevice
		task.standardError = FileHandle.nullDevice
		do {
			try task.run()
		} catch {
			return Base.fail("the tray is not installed, run slybar install")
		}
		return 0
	}

	static func widget() -> Int32 {
		if FileManager.default.fileExists(atPath: Base.app) {
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
		guard FileManager.default.fileExists(atPath: Base.editApp) else { return Base.fail("the editor is not installed, run slybar install") }
		var allowed = CharacterSet.alphanumerics
		allowed.insert(charactersIn: "-_.~")
		var url = "slycbar-editor://open?path=" + (path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path)
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
		let sum = Base.run("/usr/bin/shasum", ["-a", "256"], input: text + "hooks: guard on SessionStart, PreToolUse, PostToolUse").out
		return "v1.0-" + sum.prefix(12)
	}

	static func plugin(_ action: String) -> Int32 {
		let fm = FileManager.default
		let carried = version()
		switch action {
		case "install":
			guard Base.run("claude", ["--version"]).code == 0 else { return Base.fail("claude is missing") }
			try? fm.removeItem(atPath: Base.plugin + "/skills")
			try? fm.createDirectory(atPath: Base.plugin + "/.claude-plugin", withIntermediateDirectories: true)
			for skill in (try? fm.contentsOfDirectory(atPath: Base.here + "/skills")) ?? [] {
				try? fm.createDirectory(atPath: Base.plugin + "/skills/" + skill, withIntermediateDirectories: true)
				Base.write(Base.plugin + "/skills/" + skill + "/SKILL.md", Base.read(Base.here + "/skills/" + skill + "/SKILL.md"))
			}
			let hook: Json = ["type": "command", "command": Base.bin, "args": ["guard"], "timeout": 5]
			try? fm.createDirectory(atPath: Base.plugin + "/hooks", withIntermediateDirectories: true)
			Base.write(Base.plugin + "/hooks/hooks.json", Base.text(["hooks": ["SessionStart": [["hooks": [hook]]],
				"PreToolUse": [["matcher": "Edit|Write|MultiEdit|NotebookEdit", "hooks": [hook]], ["matcher": "Bash|mcp__.*|Agent|Task", "hooks": [hook]]],
				"PostToolUse": [["matcher": "Bash|mcp__.*|Agent|Task", "hooks": [hook]]]]] as Json, pretty: true))
			let about = "Statusline, tray, widget, code editor and machine resources for Claude Code"
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
		case "status":
			guard let installed = Base.json(Base.plugin + "/.claude-plugin/plugin.json")["version"] as? String else { return Base.fail("the slycbar plugin is not installed, run slybar plugin install") }
			guard installed == carried else { return Base.fail("the installed plugin is \(installed), this checkout carries \(carried), run slybar plugin install") }
			Base.say("the slycbar plugin \(carried) is current")
			return 0
		default:
			return Base.fail("usage: slybar plugin install|status", 2)
		}
	}
}
