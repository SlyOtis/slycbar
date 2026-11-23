import Foundation

extension Work {
	func record(_ a: [String]) -> Int32 {
		guard a.count == 4 else {
			err("""
			slybar space log <event> <tool> <session id> <folder>

			Called by the space_guard hook. Appends to ~/.claude/space-n-resources.log (SPACE_LOG) one tab separated row
			per process of the calling claude session that is not logged yet: epoch, session id, claude pid, origin, tool,
			pid, start time, folder, command. On SessionStart, and when the log passes SPACE_LOG_ROWS (2000) rows, the
			rows of processes that no longer run are dropped first.

			""")
			return 2
		}
		let event = a[0], sid = a[2], dir = a[3]
		let fm = FileManager.default
		try? fm.createDirectory(atPath: dirname(log), withIntermediateDirectories: true)
		if !exists(log) { fm.createFile(atPath: log, contents: nil) }
		guard let h = FileHandle(forWritingAtPath: log) else {
			err("slybar space log: cannot write \(log)\n")
			return 1
		}
		try? h.close()

		var text = String(decoding: fm.contents(atPath: log) ?? Data(), as: UTF8.self)
		let most = Int(env("SPACE_LOG_ROWS", "2000")) ?? 2000
		if !text.isEmpty, event == "SessionStart" || text.utf8.filter({ $0 == 10 }).count > most {
			var live: Set<String> = []
			for l in lines(sh("ps", ["-axo", "pid=,lstart="]).out) {
				let w = words(l)
				live.insert(at(w, 0) + "\t" + w.dropFirst().joined(separator: " "))
			}
			text = lines(text).enumerated().filter {
				let v = $0.offset == 0 ? words($0.element) : tabs($0.element)
				return live.contains(at(v, 5) + "\t" + at(v, 6))
			}.map { $0.element + "\n" }.joined()
			if fm.createFile(atPath: log + ".tmp", contents: Data(text.utf8)) { rename(log + ".tmp", log) }
		}

		let label = event == "PostToolUse" ? a[1] : "session"
		var carried = Tab()
		for l in lines(sh("ps", ["-E", "-ww", "-axo", "pid=,command="]).out) {
			let w = words(l)
			if w.dropFirst(2).contains("CLAUDE_CODE_SESSION_ID=" + sid) { carried.add(w[0]) }
		}

		var known: Set<String> = []
		for l in lines(text) {
			let v = tabs(l)
			if at(v, 1) == sid { known.insert(at(v, 5) + "\t" + at(v, 6)) }
		}
		var par: [String: String] = [:]
		var start: [String: String] = [:]
		var cmd: [String: String] = [:]
		var all = Tab()
		for l in lines(sh("ps", ["-axo", "pid=,ppid=,lstart=,command="]).out) {
			let w = words(l)
			guard !w.isEmpty else { continue }
			par[w[0]] = at(w, 1)
			start[w[0]] = (2...6).map { at(w, $0) }.joined(separator: " ")
			cmd[w[0]] = w.dropFirst(7).joined(separator: " ")
			all.add(w[0])
		}
		func name(_ c: String) -> String {
			var c = c
			if let r = c.range(of: ".app/", options: .literal) { c = String(c[..<r.lowerBound]) } else if let r = c.range(of: " ", options: .literal) { c = String(c[..<r.lowerBound]) }
			if let r = c.range(of: "/", options: [.literal, .backwards]) { c = String(c[r.upperBound...]) }
			return c
		}

		var q = "\(getpid())"
		var under = q
		var n = 0
		while num(q) > 1, n < 64 {
			n += 1
			if name(cmd[q] ?? "") == "claude" { break }
			under = q
			q = par[q] ?? ""
		}
		guard num(q) > 1, name(cmd[q] ?? "") == "claude" else { return 0 }
		let claude = q

		var origin = ""
		var top = claude
		q = par[claude] ?? ""
		n = 0
		while num(q) > 1, n < 64 {
			n += 1
			if (cmd[q] ?? "").lowercased().contains("ghostty") { origin = "ghostty" }
			top = q
			q = par[q] ?? ""
		}
		if origin.isEmpty { origin = top == claude ? "launchd" : name(cmd[top] ?? "") }

		let order = all.keys
		var tree = Tab([claude])
		var grew = true
		while grew {
			grew = false
			for i in order where tree.has(par[i] ?? "") && !tree.has(i) {
				tree.add(i)
				grew = true
			}
		}
		var hooks: Set<String> = [under]
		for i in order where par[i] == claude && (cmd[i] ?? "").contains("/hooks/") { hooks.insert(i) }
		hooks = below(Array(hooks), par)
		for i in carried.keys where par[i] != nil { tree.add(i) }

		var out = ""
		for p in tree.keys {
			let c = cmd[p] ?? ""
			if hooks.contains(p) && p != claude || c.hasPrefix("(") { continue }
			if known.contains(p + "\t" + (start[p] ?? "")) { continue }
			out += "\(now)\t\(sid)\t\(claude)\t\(origin)\t\(p == claude ? "session" : label)\t\(p)\t\(start[p] ?? "")\t\(dir)\t\(clip(c, 200))\n"
		}
		guard let end = FileHandle(forWritingAtPath: log) else { return 1 }
		end.seekToEndOfFile()
		end.write(Data(out.utf8))
		try? end.close()
		return 0
	}
}
