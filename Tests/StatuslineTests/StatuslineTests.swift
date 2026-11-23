import Foundation
import Testing
@testable import Statusline

func check(_ name: String, _ got: String, _ want: String, at: SourceLocation = #_sourceLocation) {
	#expect(got.contains(want), "\(name)\nwant: \(want)\ngot:  \(got)", sourceLocation: at)
}

func refute(_ name: String, _ got: String, _ unwanted: String, at: SourceLocation = #_sourceLocation) {
	#expect(!got.contains(unwanted), "\(name)\nunwanted: \(unwanted)\ngot:      \(got)", sourceLocation: at)
}

func equal(_ name: String, _ got: String, _ want: String, at: SourceLocation = #_sourceLocation) {
	#expect(got == want, "\(name)\nwant: \(want)\ngot:  \(got)", sourceLocation: at)
}

func strip(_ raw: String) -> String {
	var out = ""
	for c in Table.plain(Array(raw.utf8)).text where !(c == " " && out.hasSuffix(" ")) {
		out.append(c)
	}
	return out
}

func widths(_ raw: String) -> String {
	var all = Set<String>()
	for line in raw.split(separator: "\n", omittingEmptySubsequences: false) {
		var w = 0
		for cp in Table.plain(Array(line.utf8)).text.unicodeScalars.map({ Int($0.value) }) {
			let wide = (cp >= 4352 && cp <= 4447) || (cp >= 11904 && cp <= 42191) || (cp >= 44032 && cp <= 55203) || (cp >= 63744 && cp <= 64255) ||
				(cp >= 65280 && cp <= 65376) || (cp >= 65504 && cp <= 65510) || (cp >= 127744 && cp <= 129791) || (cp >= 131072 && cp <= 262141)
			w += wide ? 2 : 1
		}
		all.insert("\(w)")
	}
	return all.sorted().map { $0 + " " }.joined()
}

final class Fixture {
	let fx = "/tmp/slycbar-test-\(getpid())-\(UInt32.random(in: 0..<100000))"
	let now = Int(Date().timeIntervalSince1970)
	var env = ProcessInfo.processInfo.environment
	var repo: String { fx + "/widgets" }
	var tp: String { fx + "/proj/s1.jsonl" }
	var sub: String { fx + "/proj/s1/subagents" }
	var cache: String { fx + "/cache" }

	init() {
		env["SLYCBAR_CACHE"] = cache
		env["SLYCBAR_SESSIONS"] = fx + "/sessions"
		env["COLUMNS"] = "204"
		for key in ["CLAUDE_PID", "SLYCBAR_MARGIN", "SLYCBAR_SCAN_LIMIT", "SLYCBAR_NOW"] {
			env[key] = nil
		}
		for dir in [sub, fx + "/sessions"] {
			try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
		}
	}

	func git(_ args: String...) {
		let task = Process()
		task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		task.arguments = ["git"] + args
		task.standardOutput = FileHandle.nullDevice
		task.standardError = FileHandle.nullDevice
		try? task.run()
		task.waitUntilExit()
	}

	func iso(_ at: Int) -> String {
		let f = DateFormatter()
		f.locale = Locale(identifier: "en_US_POSIX")
		f.timeZone = TimeZone(identifier: "UTC")
		f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'.000Z'"
		return f.string(from: Date(timeIntervalSince1970: Double(at)))
	}

	func touch(_ path: String, _ at: Int) {
		try? FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: Double(at))], ofItemAtPath: path)
	}

	func asst(_ id: String, _ a: Int, _ b: Int, _ c: Int, _ d: Int) -> String {
		"{\"type\":\"assistant\",\"message\":{\"id\":\"\(id)\",\"usage\":{\"input_tokens\":\(a),\"cache_creation_input_tokens\":\(b),\"cache_read_input_tokens\":\(c),\"output_tokens\":\(d)}}}\n"
	}

	func put(_ path: String, _ text: String) {
		FileManager.default.createFile(atPath: path, contents: Data(text.utf8))
	}

	func add(_ path: String, _ text: String) {
		let old = FileManager.default.contents(atPath: path) ?? Data()
		FileManager.default.createFile(atPath: path, contents: old + Data(text.utf8))
	}

	func agent(_ id: String, _ type: String, _ about: String, _ line: String) {
		put(sub + "/agent-\(id).meta.json", "{\"agentType\":\"\(type)\",\"description\":\"\(about)\"}\n")
		put(sub + "/agent-\(id).jsonl", line + "\n")
	}

	func stdin(_ cwd: String, _ sid: String, _ tp: String, _ top: String = "", _ workspace: String = "") -> String {
		"{\"cwd\":\"\(cwd)\",\"session_id\":\"\(sid)\",\"transcript_path\":\"\(tp)\"," +
			"\"workspace\":{\"current_dir\":\"\(cwd)\",\"project_dir\":\"\(cwd)\"\(workspace)}," +
			"\"model\":{\"id\":\"claude-opus-5-5\",\"display_name\":\"Opus 5.5\"}," +
			"\"cost\":{\"total_cost_usd\":1.234,\"total_duration_ms\":3723000,\"total_lines_added\":10,\"total_lines_removed\":2}," +
			"\"context_window\":{\"used_percentage\":12.6,\"context_window_size\":200000}," +
			"\"prompt_cache\":{\"warm\":true,\"hit_ratio\":0.912}," +
			"\"rate_limits\":{\"five_hour\":{\"used_percentage\":23.5,\"resets_at\":\(Int(Date().timeIntervalSince1970) + 8010)},\"seven_day\":{\"used_percentage\":41.2,\"resets_at\":\(Int(Date().timeIntervalSince1970) + 273630)}}\(top)}"
	}

	func run(_ cwd: String, _ sid: String, _ tp: String, top: String = "", workspace: String = "", with: [String: String] = [:]) -> String {
		let vars = env.merging(with) { $1 }
		let bar = Bar(vars, Array(stdin(cwd, sid, tp, top, workspace).utf8))
		bar.launch = { tp, base in
			Thread.detachNewThread {
				Bar(vars, []).count(tp, base)
			}
		}
		return Sys.trim(bar.table())
	}
}

@Test func statusline() throws {
	let x = Fixture()
	let fx = x.fx
	let now = x.now
	let repo = x.repo
	let tp = x.tp
	let me = getpid()
	x.git("init", "-q", "-b", "feat/42-widget-thing", repo)
	x.git("-C", repo, "remote", "add", "origin", "git@github.com:acme/widgets.git")

	func result(_ text: String, _ at: Int) -> String {
		"{\"type\":\"user\",\"timestamp\":\"\(x.iso(at))\",\"message\":{\"content\":[{\"type\":\"tool_result\",\"content\":\"\(text)\"}]}}\n"
	}
	x.put(tp, "{\"type\":\"user\",\"message\":{\"role\":\"user\",\"content\":\"hi\"}}\n" +
		x.asst("msg_a", 10, 100, 1000, 5) +
		x.asst("msg_a", 10, 100, 1000, 50) +
		x.asst("msg_b", 1, 0, 2000, 7) +
		"{\"type\":\"permission-mode\",\"permissionMode\":\"plan\",\"sessionId\":\"s1\"}\n" +
		"{\"type\":\"permission-mode\",\"permissionMode\":\"auto\",\"sessionId\":\"s1\"}\n" +
		result("Command running in background with ID: bsh1. Output is being written to: x", now - 600) +
		result("Command running in background with ID: bsh2.", now - 590) +
		result("Successfully stopped task: bsh2", now - 580) +
		result("Command running in background with ID: bsh3.", now - 570) +
		"{\"type\":\"queue-operation\",\"operation\":\"enqueue\",\"timestamp\":\"\(x.iso(now - 560))\",\"content\":\"<task-notification>\\n<task-id>bsh3</task-id>\\n<status>completed</status>\\n</task-notification>\"}\n" +
		result("Command running in background with ID: bold1.", now - 7200))

	let reading = "{\"type\":\"assistant\",\"message\":{\"id\":\"msg_c\",\"stop_reason\":null,\"content\":[{\"type\":\"tool_use\",\"name\":\"Read\",\"input\":{\"file_path\":\"/x/y/slycbar.sh\"}}],\"usage\":{\"input_tokens\":100,\"cache_creation_input_tokens\":0,\"cache_read_input_tokens\":200000,\"output_tokens\":50}}}"
	let sleeping = "\"stop_reason\":\"tool_use\",\"content\":[{\"type\":\"tool_use\",\"name\":\"Bash\",\"input\":{\"command\":\"sleep 100\"}}],\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}}"
	x.agent("aaa", "general-purpose", "Draft the bar", reading)
	x.agent("bbb", "Explore", "Finished one", "{\"type\":\"assistant\",\"message\":{\"id\":\"msg_d\",\"stop_reason\":\"end_turn\",\"content\":[{\"type\":\"text\",\"text\":\"done\"}],\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}}")
	x.agent("ccc", "fork", "Handed back", "{\"type\":\"assistant\",\"message\":{\"id\":\"msg_e\",\"stop_reason\":\"tool_use\",\"content\":[{\"type\":\"tool_use\",\"name\":\"SubagentHandback\",\"input\":{\"message\":\"report\"}}],\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}}")
	x.agent("ddd", "fork", "Killed one", "{\"type\":\"assistant\",\"message\":{\"id\":\"msg_f\"," + sleeping)
	x.agent("eee", "fork", "Before restart", "{\"type\":\"assistant\",\"message\":{\"id\":\"msg_g\"," + sleeping)
	x.agent("fff", "fork", "Just launched", "")
	x.add(x.sub + "/agent-aaa.jsonl", x.asst("msg_a", 10, 100, 1000, 50) + x.asst("msg_c2", 3, 0, 0, 3) + reading + "\n")
	x.touch(x.sub + "/agent-ddd.jsonl", now - 900)
	x.touch(x.sub + "/agent-eee.meta.json", now - 7200)
	x.add(tp, "{\"type\":\"queue-operation\",\"operation\":\"enqueue\",\"timestamp\":\"\(x.iso(now - 300))\",\"content\":\"<task-notification><task-id>ddd</task-id><status>killed</status></task-notification>\"}\n")

	let shell = Process()
	shell.executableURL = URL(fileURLWithPath: "/bin/bash")
	shell.arguments = ["-c", "sleep 60; : shell-snapshots"]
	try shell.run()
	defer {
		if shell.isRunning {
			shell.terminate()
		}
	}

	x.put(fx + "/sessions/\(me).json", "{\"pid\":\(me),\"sessionId\":\"s1\",\"startedAt\":\(now - 3600)000,\"bridgeSessionId\":\"session_x\"}")

	let raw = x.run(repo, "s1", tp)
	var out = strip(raw)
	check("absolute current dir", out, "dir \(repo) │")
	check("branch", out, "│ branch feat/42-widget-thing │")
	check("issue from origin remote", out, "│ issue acme/widgets#42 │")
	check("dir links to the folder", raw, "\u{1b}]8;;file://\(repo)\u{1b}\\")
	check("branch links to the repo", raw, "\u{1b}]8;;https://github.com/acme/widgets\u{1b}\\")
	check("issue links to the issue", raw, "\u{1b}]8;;https://github.com/acme/widgets/issues/42\u{1b}\\")
	check("acct starts the tray when it is not running", out, "│ acct start ")
	check("acct links to the tray", raw, "\u{1b}]8;;slycbar://open\u{1b}\\")
	try FileManager.default.createDirectory(atPath: x.cache + "/tray", withIntermediateDirectories: true)
	x.put(x.cache + "/tray/pid", "\(me)")
	x.put(x.cache + "/tray/active", "Work Account\n")
	check("acct shows the active account while the tray runs", strip(x.run(repo, "s1", tp)), "│ acct Work Account ")
	try FileManager.default.removeItem(atPath: x.cache + "/tray")
	refute("no project dir", out, "project")
	refute("no board", out, "board")
	refute("no model row", out, "Opus")
	refute("no agents activity row", out, "Reading")
	check("usage cells in one row at 204", out, "mode auto │ context 12% of 200k │ tokens ↓203.2k ↑114 │ cache 91% warm │ cost $1.23 │ time 1h 2m 3s │ limits 23%/41% 76h │ lines +10 -2 │ remote on │ shells 1 │ agents 2 ")
	refute("no powerline glyph", raw, "\u{e0b0}")
	check("thin cell dividers", out, "┬")
	check("dim dividers", raw, "\u{1b}[2m─")
	check("dim labels and normal values", raw, "\u{1b}[2mdir \u{1b}[22m")

	equal("every line is COLUMNS minus the footer padding", widths(raw), "200 ")
	let raw160 = x.run(repo, "s1", tp, with: ["COLUMNS": "160"])
	equal("every line is 156 at 160 columns", widths(raw160), "156 ")
	check("short labels at 160", strip(raw160), "mode auto │ ctx 12% │ tok ↓203k ↑114 │ cache 91% │ cost $1 │ time 1h2m │ lim 23%/41% 76h │ lines +10 -2 │ rc on │ sh 1 │ ag 2 ")
	let raw100 = x.run(repo, "s1", tp, with: ["COLUMNS": "100"])
	equal("every line is 96 at 100 columns", widths(raw100), "96 ")
	check("usage cells wrap at 100", "\(strip(raw100).split(separator: "\n").filter { $0.hasPrefix("mode auto │") }.count)", "1")
	let raw40 = x.run(repo, "s1", tp, with: ["COLUMNS": "40"])
	equal("every line is 36 at 40 columns", widths(raw40), "36 ")
	check("long values cut with an ellipsis", strip(raw40), "…")
	equal("margin 0 fills COLUMNS", widths(x.run(repo, "s1", tp, with: ["SLYCBAR_MARGIN": "0"])), "204 ")

	let wide = fx + "/工具-🚀"
	x.git("init", "-q", "-b", "main", wide)
	let rawwide = x.run(wide, "s1", tp, with: ["COLUMNS": "120"])
	equal("wide glyphs counted as two columns", widths(rawwide), "116 ")
	check("wide glyphs kept", strip(rawwide), "工具-🚀")
	let rawwide40 = x.run(wide, "s1", tp, with: ["COLUMNS": "40"])
	equal("wide glyphs cut on a column boundary", widths(rawwide40), "36 ")

	out = strip(x.run(repo, "s1", tp, with: ["HOME": fx]))
	check("home shown as tilde", out, "dir ~/widgets │")

	out = strip(x.run(repo, "s1", tp, top: ",\"worktree\":{\"name\":\"wt1\"},\"pr\":{\"number\":7,\"review_state\":\"approved\"}"))
	check("worktree", out, "│ worktree wt1 │")
	check("pull request", out, "│ pr #7 approved │")

	x.add(tp, x.asst("msg_z", 1000000, 0, 0, 1000))
	out = strip(x.run(repo, "s1", tp))
	check("appended message counted", out, "tokens ↓1.2M ↑1.1k")

	let line = x.asst("msg_y", 0, 0, 0, 900)
	x.add(tp, String(line.prefix(40)))
	out = strip(x.run(repo, "s1", tp))
	check("partial line ignored", out, "tokens ↓1.2M ↑1.1k")
	x.add(tp, String(line.dropFirst(40)))
	out = strip(x.run(repo, "s1", tp))
	check("completed line counted once", out, "tokens ↓1.2M ↑2.0k")

	x.add(tp, "{\"type\":\"permission-mode\",\"permissionMode\":\"plan\",\"sessionId\":\"s1\"}\n")
	out = strip(x.run(repo, "s1", tp))
	check("mode follows the transcript", out, "mode plan │")

	out = strip(x.run(repo, "s1", tp, workspace: ",\"repo\":{\"owner\":\"octo\",\"name\":\"repo\"}"))
	check("issue repo from stdin workspace.repo", out, "│ issue octo/repo#42 │")

	let panel = "{\"session_id\":\"s1\",\"columns\":70,\"tasks\":[" +
		"{\"id\":\"t1\",\"type\":\"local_agent\",\"agentType\":\"Explore\",\"status\":\"running\",\"description\":\"Look\",\"label\":\"Reading running_tasks in slycbar.sh\",\"startTime\":\((now - 125) * 1000),\"model\":\"claude-opus-5-5\",\"effort\":\"max\",\"contextWindowSize\":1000000,\"tokenCount\":288200}," +
		"{\"id\":\"t2\",\"type\":\"local_agent\",\"agentType\":\"fork\",\"status\":\"completed\",\"description\":\"Old task\",\"startTime\":\((now - 30) * 1000),\"tokenCount\":5}]}"
	let rows = Bar(x.env.merging(["SLYCBAR_NOW": "\(now)"]) { $1 }, Array(panel.utf8)).agents().text
	var content: [String: String] = [:]
	for row in rows.split(separator: "\n") {
		let map = try #require(JSONSerialization.jsonObject(with: Data(row.utf8)) as? [String: String])
		content[map["id"] ?? ""] = map["content"]
	}
	equal("agent panel row with more information", strip(content["t1"] ?? ""), "Explore · Reading running_tasks in slycbar.sh · 2m 5s · 288.2k tok 28…")
	check("finished agent row says so", strip(content["t2"] ?? ""), "fork · Old task · 30s · 5 tok · completed")
	check("panel rows fit the panel width", widths((content["t1"] ?? "") + "\n" + (content["t2"] ?? "")), "41 70 ")
	out = strip(x.run(repo, "s1", tp))
	check("agents count from the panel feed", out, "│ agents 1 ")
	x.touch(x.cache + "/sessions/s1.agents.json", now - 120)
	out = strip(x.run(repo, "s1", tp))
	check("stale panel feed falls back to transcripts", out, "│ agents 2 ")

	shell.terminate()
	shell.waitUntilExit()
	out = strip(x.run(repo, "s1", tp))
	check("shell count capped by live shells", out, "│ shells 0 │")

	x.put(fx + "/sessions/\(me).json", "{\"pid\":\(me),\"sessionId\":\"s1\",\"startedAt\":\(now - 3600)000,\"bridgeSessionId\":null}")
	out = strip(x.run(repo, "s1", tp))
	check("remote control off", out, "│ remote off │")

	x.put(fx + "/sessions/999999.json", "{\"pid\":999999,\"sessionId\":\"s9\",\"bridgeSessionId\":\"session_y\"}")
	out = strip(x.run(repo, "s9", tp))
	check("dead process manifest is unknown", out, "│ remote ? ")
	refute("no live process, no shells or agents", out, "shells")

	out = strip(x.run(repo, "s2", fx + "/none.jsonl"))
	check("no manifest is unknown", out, "│ remote ? ")
	refute("no transcript shows no totals", out, "tokens")
	refute("no transcript shows no mode", out, "mode")

	let big = fx + "/big/s3.jsonl"
	try FileManager.default.createDirectory(atPath: fx + "/big", withIntermediateDirectories: true)
	x.put(big, (1...8).map { x.asst("msg_big\($0)", 1000, 0, 0, 10) }.joined())
	out = strip(x.run(repo, "s3", big, with: ["SLYCBAR_SCAN_LIMIT": "100"]))
	check("large backlog is counted in the background", out, "│ tokens counting… │")
	for _ in 1...10 where !FileManager.default.fileExists(atPath: x.cache + "/sessions/s3.sum") {
		Thread.sleep(forTimeInterval: 0.2)
	}
	out = strip(x.run(repo, "s3", big, with: ["SLYCBAR_SCAN_LIMIT": "100"]))
	check("background count shown when done", out, "│ tokens ↓8.0k ↑80 │")

	x.git("-C", repo, "checkout", "-q", "-b", "main")
	out = strip(x.run(repo, "s1", tp))
	check("plain branch", out, "│ branch main │")
	refute("no issue on plain branch", out, "issue")
	x.git("-C", repo, "remote", "remove", "origin")
	check("branch marked local without origin", strip(x.run(repo, "s1", tp)), "│ branch main (local) │")
	x.git("-C", repo, "remote", "add", "origin", "git@github.com:acme/widgets.git")

	out = strip(x.run(fx, "s1", tp))
	refute("no branch outside git", out, "branch")
}
