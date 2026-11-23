import Foundation

public enum Statusline {
	public static func run(_ args: [String]) -> Int32 {
		let env = ProcessInfo.processInfo.environment
		if args.first == "--scan" {
			guard args.count > 2 else {
				return 1
			}
			Bar(env, []).count(args[1], args[2])
			return 0
		}
		let bar = Bar(env, [UInt8](FileHandle.standardInput.readDataToEndOfFile()))
		FileHandle.standardOutput.write(Data(args.first == "--agents" ? bar.agents() : bar.table()))
		return 0
	}
}

final class Bar {
	static let fields: [(String, [[String]])] = [
		("cwd", [["workspace", "current_dir"], ["cwd"]]),
		("sid", [["session_id"]]),
		("tp", [["transcript_path"]]),
		("owner", [["workspace", "repo", "owner"]]),
		("name", [["workspace", "repo", "name"]]),
		("wt", [["worktree", "name"], ["workspace", "git_worktree"]]),
		("pr", [["pr", "number"]]),
		("prstate", [["pr", "review_state"]]),
		("cost", [["cost", "total_cost_usd"]]),
		("dur", [["cost", "total_duration_ms"]]),
		("added", [["cost", "total_lines_added"]]),
		("removed", [["cost", "total_lines_removed"]]),
		("pct", [["context_window", "used_percentage"]]),
		("ctxsize", [["context_window", "context_window_size"]]),
		("hit", [["prompt_cache", "hit_ratio"]]),
		("warm", [["prompt_cache", "warm"]]),
		("rl5", [["rate_limits", "five_hour", "used_percentage"]]),
		("rl7", [["rate_limits", "seven_day", "used_percentage"]]),
		("rs5", [["rate_limits", "five_hour", "resets_at"]]),
		("rs7", [["rate_limits", "seven_day", "resets_at"]]),
	]

	let env: [String: String]
	let input: [UInt8]
	let home: String
	let cache: String
	let sessions: String
	let width: Int
	let limit: Int
	let tag = "\(getpid())"
	var rows = ""
	var launch: ((String, String) -> Void)?

	init(_ env: [String: String], _ input: [UInt8]) {
		func get(_ key: String, _ or: String) -> String {
			let v = env[key] ?? ""
			return v.isEmpty ? or : v
		}
		var end = input.count
		while end > 0 && input[end - 1] == 10 {
			end -= 1
		}
		self.env = env
		self.input = Array(input[0..<end])
		home = env["HOME"] ?? NSHomeDirectory()
		cache = get("SLYCBAR_CACHE", get("XDG_CACHE_HOME", home + "/.cache") + "/slycbar")
		sessions = get("SLYCBAR_SESSIONS", get("CLAUDE_CONFIG_DIR", home + "/.claude") + "/sessions")
		let cols = Int(get("COLUMNS", "0")) ?? 0
		width = cols > 0 ? cols - (Int(get("SLYCBAR_MARGIN", "4")) ?? 0) : 120
		limit = Int(get("SLYCBAR_SCAN_LIMIT", "4000000")) ?? 0
	}

	func get(_ key: String, _ or: String = "") -> String {
		let v = env[key] ?? ""
		return v.isEmpty ? or : v
	}

	func row() {
		rows += "R\n"
	}

	func cell(_ label: String, _ value: String, _ colour: Int, _ side: String = "R", _ short: String = "", _ less: String = "", _ link: String = "") {
		if !value.isEmpty {
			rows += "C\t\(label)\t\(value)\t\(colour)\t\(side)\t\(short.isEmpty ? label : short)\t\(less.isEmpty ? value : less)\t\(link)\n"
		}
	}

	func human(_ raw: String, _ short: Bool = false) -> String {
		var s = Sys.chop(raw)
		if s.isEmpty {
			s = "0"
		}
		guard let n = Int(s) else {
			return s
		}
		if short {
			if n >= 1_000_000_000 {
				return "\(n / 1_000_000_000).\(n % 1_000_000_000 / 100_000_000)G"
			}
			if n >= 10_000_000 {
				return "\(n / 1_000_000)M"
			}
			if n >= 1_000_000 {
				return "\(n / 1_000_000).\(n % 1_000_000 / 100_000)M"
			}
			return n >= 1000 ? "\(n / 1000)k" : s
		}
		if n >= 1_000_000_000 {
			return String(format: "%d.%02dG", n / 1_000_000_000, n % 1_000_000_000 / 10_000_000)
		}
		if n >= 1_000_000 {
			return "\(n / 1_000_000).\(n % 1_000_000 / 100_000)M"
		}
		return n >= 1000 ? "\(n / 1000).\(n % 1000 / 100)k" : s
	}

	func duration(_ secs: Int, _ short: Bool = false) -> String {
		let all = max(secs, 0)
		let h = all / 3600
		let m = all % 3600 / 60
		let s = all % 60
		if short {
			return h > 0 ? "\(h)h\(m)m" : m > 0 ? "\(m)m" : "\(s)s"
		}
		return h > 0 ? "\(h)h \(m)m \(s)s" : m > 0 ? "\(m)m \(s)s" : "\(s)s"
	}

	func epoch(_ s: [UInt8]) -> Double {
		if s.isEmpty {
			return 0
		}
		func n(_ at: Int, _ len: Int) -> Double {
			at - 1 < s.count ? strtod(s[(at - 1)..<min(at - 1 + len, s.count)].text, nil) : 0
		}
		var y = n(1, 4)
		var m = n(6, 2)
		if m <= 2 {
			y -= 1
			m += 12
		}
		let days = 365 * y + (y / 4).rounded(.towardZero) - (y / 100).rounded(.towardZero) + (y / 400).rounded(.towardZero) + ((153 * (m - 3) + 2) / 5).rounded(.towardZero) + n(9, 2) - 719469
		return days * 86400 + n(12, 2) * 3600 + n(15, 2) * 60 + n(18, 2)
	}

	func after(_ hay: [UInt8], _ key: String) -> [Int] {
		let key = Array(key.utf8)
		var out: [Int] = []
		var at = 0
		while let i = hay.find(key, at) {
			var j = i + key.count
			while j < hay.count && hay[j] == 32 {
				j += 1
			}
			out.append(j)
			at = i + 1
		}
		return out
	}

	func manifest(_ sid: String) -> String {
		if sid.isEmpty {
			return ""
		}
		let want = Array("\"\(sid)\"".utf8)
		var all = Sys.names(sessions, "", ".json").map { sessions + "/" + $0 }
		if !get("CLAUDE_PID").isEmpty {
			all.insert(sessions + "/" + get("CLAUDE_PID") + ".json", at: 0)
		}
		for path in all where Sys.file(path) && Sys.alive(String(Sys.leaf(path).dropLast(5))) {
			let body = Sys.read(path) ?? []
			if after(body, "\"sessionId\":").contains(where: { body[$0...].starts(with: want) }) {
				return path
			}
		}
		return ""
	}

	func bridged(_ body: [UInt8]) -> Bool {
		after(body, "\"bridgeSessionId\":").contains { at in
			guard at < body.count, body[at] == 34 else {
				return false
			}
			var j = at + 1
			while j < body.count && body[j] != 34 && body[j] != 10 {
				j += 1
			}
			return j > at + 1 && j < body.count && body[j] == 34
		}
	}

	func started(_ body: [UInt8]) -> Int {
		var value = 0
		for at in after(body, "\"startedAt\":") {
			var j = at
			while j < body.count && body[j] >= 48 && body[j] <= 57 {
				j += 1
			}
			if j > at {
				value = Int(body[at..<j].text) ?? 0
			}
		}
		return value / 1000
	}

	func fresh() -> [String: String] {
		guard let root = Jq.parse(input) else {
			return [:]
		}
		var f: [String: String] = [:]
		do {
			for (name, paths) in Bar.fields {
				var v: Any?
				for path in paths {
					v = try Jq.at(root, path)
					if Jq.truthy(v) {
						break
					}
				}
				f[name] = v == nil || v is NSNull ? "" : Jq.text(v)
			}
		} catch {
			return [:]
		}
		return f
	}

	func here() -> String {
		let set = get("PWD")
		var a = stat()
		var b = stat()
		if set.hasPrefix("/") && stat(set, &a) == 0 && stat(".", &b) == 0 && a.st_dev == b.st_dev && a.st_ino == b.st_ino {
			return set
		}
		return FileManager.default.currentDirectoryPath
	}

	func fable(_ mail: String) -> (pct: String, reset: String) {
		guard !mail.isEmpty, let body = Sys.read(cache + "/tray/usage.json"), let root = Jq.parse(body),
			let v = try? Jq.at(root, [mail, "fable"]), Jq.truthy(v), let map = v as? NSDictionary else {
			return ("", "")
		}
		let out = Array("\(Jq.text(map["pct"])) \(Jq.truthy(map["reset"]) ? Jq.text(map["reset"]) : "")".utf8)
		var at = 0
		let line = Sys.line(out, &at).text
		guard let cut = line.firstIndex(where: { $0 == " " || $0 == "\t" }) else {
			return (line, "")
		}
		return (String(line[..<cut]), String(line[cut...].drop { $0 == " " || $0 == "\t" }))
	}

	func background(_ tp: String, _ base: String) {
		if let launch {
			launch(tp, base)
		} else {
			_ = Sys.spawn(Bundle.main.executablePath ?? CommandLine.arguments[0], ["slybar", "statusline", "--scan", tp, base], env, nil)
		}
	}

	func running(_ dir: String, _ base: String, _ since: Int, _ notes: [String: Double]) -> Int {
		let panel = base + ".agents.json"
		if let st = Sys.info(panel), st.file, time(nil) - st.time < 30 {
			guard let root = Jq.parse(Sys.read(panel) ?? []) as? NSDictionary else {
				return 0
			}
			let tasks = root["tasks"]
			var n = 0
			for item in (tasks as? [Any]) ?? (tasks as? NSDictionary)?.allValues ?? [] where !(item is NSNull) {
				guard let task = item as? NSDictionary else {
					return 0
				}
				if task["status"] as? String == "running" {
					n += 1
				}
			}
			return n
		}
		var n = 0
		let sub = dir + "/subagents/"
		let mark = Array("\"type\":\"assistant\"".utf8)
		for name in Sys.names(sub, "agent-", ".meta.json") {
			let log = sub + name.dropLast(10) + ".jsonl"
			guard let meta = Sys.info(sub + name), meta.time >= since, let st = Sys.info(log), st.file else {
				continue
			}
			if let note = notes[String(name.dropFirst(6).dropLast(10))], note >= Double(st.time - 2) {
				continue
			}
			var last: [UInt8] = []
			let fd = open(log, O_RDONLY)
			if fd >= 0 {
				var buf = [UInt8](repeating: 0, count: 65536)
				let got = pread(fd, &buf, buf.count, off_t(max(st.size - 65536, 0)))
				close(fd)
				for line in buf[0..<max(got, 0)].split(separator: 10) where Array(line).find(mark) != nil {
					last = Array(line)
				}
			}
			if last.find(Array("\"stop_reason\":\"end_turn\"".utf8)) != nil || last.find(Array("\"name\":\"SubagentHandback\"".utf8)) != nil {
				continue
			}
			n += 1
		}
		return n
	}

	func table() -> [UInt8] {
		if Sys.info(cache + "/sessions") == nil {
			try? FileManager.default.createDirectory(atPath: cache + "/sessions", withIntermediateDirectories: true)
		}
		_ = Sys.put(cache + "/last-stdin.json", input + [10])
		let load = Sys.start("ps", ["-A", "-o", "%cpu="], env)
		let f = fresh()
		func v(_ key: String) -> String {
			f[key] ?? ""
		}
		let cwd = v("cwd").isEmpty ? here() : v("cwd")
		let sid = v("sid")
		let tp = v("tp")
		var owner = v("owner")
		var name = v("name")
		let base = cache + "/sessions/" + (sid.isEmpty ? "none" : sid)
		let dir = tp.hasSuffix(".jsonl") ? String(tp.dropLast(6)) : tp

		let git = ["-C", cwd, "--no-optional-locks"]
		let head = Sys.start("git", git + ["symbolic-ref", "--short", "-q", "HEAD"], env)
		let url = Sys.start("git", git + ["remote", "get-url", "origin"], env)
		let ref = Sys.finish(head)
		var branch = Sys.trim(ref.out)
		if ref.code != 0 {
			let rev = Sys.finish(Sys.start("git", git + ["rev-parse", "--short", "HEAD"], env))
			branch = (rev.code == 0 ? "@" : "") + Sys.trim(rev.out)
		}
		let origin = Sys.finish(url)
		var issue = ""
		for lead in ["feat/", "fix/"] where branch.hasPrefix(lead) {
			let rest = branch.utf8.dropFirst(lead.utf8.count)
			let digits = rest.prefix { $0 >= 48 && $0 <= 57 }
			if !digits.isEmpty && rest.dropFirst(digits.count).first == 45 {
				issue = String(decoding: digits, as: UTF8.self)
			}
		}
		var web = ""
		var unpushed = ""
		if !branch.isEmpty && origin.code == 0 {
			web = Sys.trim(origin.out)
			for (find, with) in [("^[^@/:]+@([^:]+):", "https://$1/"), ("^ssh://([^@/]+@)?([^/:]+)(:[0-9]+)?/", "https://$2/"), ("^https?://([^@/]+@)?", "https://"), ("\\.git$", "")] {
				web = web.replacingOccurrences(of: find, with: with, options: .regularExpression)
			}
			if !web.hasPrefix("https://") || web.dropFirst(8).filter({ $0 == "/" }).count < 2 {
				web = ""
			}
		} else if !branch.isEmpty {
			unpushed = " (local)"
		}
		if !issue.isEmpty && !web.isEmpty && (owner.isEmpty || name.isEmpty) {
			var slug = web
			if let cut = web.dropFirst(8).firstIndex(of: "/") {
				slug = String(web[web.index(after: cut)...])
			}
			owner = slug.lastIndex(of: "/").map { String(slug[..<$0]) } ?? slug
			name = Sys.leaf(slug)
		}
		row()
		let tilde = cwd == home ? "~" : cwd.hasPrefix(home + "/") ? "~" + cwd.dropFirst(home.count) : cwd
		cell("dir", tilde, 33, "L", "", "", "file://" + cwd.replacingOccurrences(of: " ", with: "%20"))
		cell("branch", branch + unpushed, 135, "R", "", "", web)
		let rest = web.hasPrefix("https://") ? String(web.dropFirst(8)) : web
		let host = String(rest.prefix { $0 != "/" })
		if !issue.isEmpty {
			cell("issue", (owner.isEmpty ? "" : owner + "/" + name) + "#" + issue, 172, "R", "", "", owner.isEmpty ? "" : "https://\(host.isEmpty ? "github.com" : host)/\(owner)/\(name)/issues/\(issue)")
		}
		cell("worktree", v("wt"), 135)
		cell("pr", v("pr").isEmpty ? "" : "#" + v("pr") + (v("prstate").isEmpty ? "" : " " + v("prstate")), 172)
		var acct = "start"
		var mail = ""
		if Sys.file(cache + "/tray/pid") && Sys.alive(Sys.text(cache + "/tray/pid")) {
			if let body = Sys.read(cache + "/tray/active") {
				var at = 0
				let one = Sys.line(body, &at)
				let two = Sys.line(body, &at)
				acct = one.whole ? one.text : "on"
				mail = two.whole ? two.text : ""
			} else {
				acct = "on"
			}
		}
		cell("acct", acct, 135, "R", "acct", acct, "slycbar://open")
		var sum = 0.0
		for line in Sys.finish(load).out.split(separator: 10) {
			sum += strtod(Array(line).text, nil)
		}
		var p = Int(sum / Double(Sys.ctl("hw.ncpu") ?? 1))
		cell("cpu", "\(p)%", p >= 80 ? 160 : p >= 50 ? 136 : 34)
		if let level = Sys.ctl("kern.memorystatus_level") {
			p = 100 - level
			cell("mem", "\(p)%", p >= 85 ? 160 : p >= 70 ? 136 : 34)
		}
		var fs = statfs()
		if statfs(home, &fs) == 0 {
			let size = UInt64(fs.f_bsize)
			let blocks = size != 0 && size < 1024 ? fs.f_bavail / (1024 / size) : fs.f_bavail * (size / 1024)
			let free = Int(blocks / 1048576)
			cell("disk", "\(free)G", free < 5 ? 160 : free < 20 ? 136 : 34)
		}

		var scanned = ""
		let live = Sys.file(tp)
		if live {
			let got = scan(tp, base, limit)
			scanned = got.sum
			if got.code == 2 {
				let scanner = Sys.file(base + ".lock") ? Sys.text(base + ".lock") : ""
				if scanner.isEmpty || !Sys.alive(scanner) {
					background(tp, base)
				}
				scanned = Sys.file(base + ".sum") ? Sys.text(base + ".sum") + " …" : ""
			}
		}

		var mode = ""
		if Sys.file(base + ".mode") {
			var at = 0
			mode = Sys.line(Sys.read(base + ".mode") ?? [], &at).text
		}

		row()
		switch mode {
		case "auto": cell("mode", "auto", 172)
		case "plan": cell("mode", "plan", 37)
		case "acceptEdits": cell("mode", "accept edits", 135, "R", "mode", "edits")
		case "bypassPermissions": cell("mode", "bypass", 160)
		default: cell("mode", mode, 246)
		}
		if !v("pct").isEmpty {
			let pct = Sys.chop(v("pct"))
			let n = Int(pct) ?? 0
			var size = ""
			if !v("ctxsize").isEmpty {
				let all = human(v("ctxsize"))
				size = " of " + (all.range(of: ".0").map { all.replacingCharacters(in: $0, with: "") } ?? all)
			}
			cell("context", pct + "%" + size, n >= 80 ? 160 : n >= 50 ? 136 : 34, "R", "ctx", pct + "%")
		}
		if live {
			let part = scanned.split(separator: " ", maxSplits: 2).map { String($0) }
			if part.isEmpty {
				cell("tokens", "counting…", 246, "R", "tok")
			} else {
				let tin = part[0]
				let tout = part.count > 1 ? part[1] : ""
				let more = part.count > 2 ? " " + part[2] : ""
				cell("tokens", "↓\(human(tin)) ↑\(human(tout))\(more)", 67, "R", "tok", "↓\(human(tin, true)) ↑\(human(tout, true))\(more)")
			}
		}
		if !v("hit").isEmpty {
			let h = String(format: "%.2f", strtod(v("hit"), nil))
			if let n = Int(h.range(of: ".").map { h.replacingCharacters(in: $0, with: "") } ?? h), n >= 0 {
				let warm = v("warm").isEmpty ? "" : v("warm") == "true" ? " warm" : " cold"
				cell("cache", "\(n)%\(warm)", 67, "R", "cache", "\(n)%")
			}
		}
		if !v("cost").isEmpty {
			let cost = strtod(v("cost"), nil)
			cell("cost", String(format: "$%.2f", cost), 136, "R", "cost", String(format: "$%.0f", cost))
		}
		if !v("dur").isEmpty, let ms = Int(Sys.chop(v("dur"))) {
			cell("time", duration(ms / 1000), 37, "R", "time", duration(ms / 1000, true))
		}
		let now = Int(get("SLYCBAR_NOW")) ?? time(nil)
		let extra = fable(mail)
		var a = ""
		p = 0
		for one in [v("rl5"), v("rl7"), extra.pct].map({ Sys.chop($0) }) where !one.isEmpty {
			a += (a.isEmpty ? "" : "/") + one + "%"
			if let n = Int(one), n > p {
				p = n
			}
		}
		let b = !v("rs7").isEmpty ? v("rs7") : !extra.reset.isEmpty ? extra.reset : v("rs5")
		if !a.isEmpty && !b.isEmpty, let at = Int(Sys.chop(b)) {
			a += " \(max(at - now, 0) / 3600)h"
		}
		cell("limits", a, p >= 90 ? 160 : p >= 70 ? 136 : 34, "R", "lim")
		if !(v("added") + v("removed")).isEmpty {
			cell("lines", "+\(v("added").isEmpty ? "0" : v("added")) -\(v("removed").isEmpty ? "0" : v("removed"))", 34)
		}

		let m = manifest(sid)
		if m.isEmpty {
			cell("remote", "?", 246, "R", "rc")
		} else {
			let body = Sys.read(m) ?? []
			cell("remote", bridged(body) ? "on" : "off", bridged(body) ? 34 : 246, "R", "rc")
			let pid = Int(Sys.leaf(m).dropLast(5)) ?? -1
			let since = started(body)
			var shells = 0
			var notes: [String: Double] = [:]
			for line in (Sys.read(base + ".tasks") ?? []).split(10) where !line.isEmpty {
				let c = line.split(9) + [[], [], [], []]
				if c[1].text == "shell" && c[3].isEmpty && epoch(c[2]) >= Double(since) {
					shells += 1
				}
				if !c[3].isEmpty {
					notes[c[0].text] = epoch(c[4])
				}
			}
			if shells > 0 {
				var open = 0
				let mark = Array("shell-snapshots".utf8)
				for line in Sys.finish(Sys.start("ps", ["-o", "ppid=,command=", "-ax"], env)).out.split(separator: 10) {
					let one = Array(line)
					if Int(one.split(separator: 32).first.map { Array($0).text } ?? "") == pid && one.find(mark) != nil {
						open += 1
					}
				}
				shells = min(shells, open)
			}
			cell("shells", "\(shells)", 37, "R", "sh")
			cell("agents", "\(running(dir, base, since, notes))", 37, "R", "ag")
		}
		return Table.render(Array(rows.utf8), width)
	}
}
