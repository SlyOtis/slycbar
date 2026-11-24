import Foundation

extension Space {
	static func level(_ name: String) -> Int? {
		var v: Int32 = 0
		var n = MemoryLayout<Int32>.size
		return sysctlbyname(name, &v, &n, nil, 0) == 0 ? Int(v) : nil
	}

	static func probe(_ path: String, _ bytes: Int) -> [Check]? {
		var dir = path
		while !folder(dir), dir != "/" { dir = dirname(dir) }
		var s = statfs()
		guard statfs(dir, &s) == 0, let ncpu = level("hw.ncpu"), let used = level("kern.memorystatus_level") else { return nil }
		let load = lines(sh("ps", ["-A", "-o", "%cpu="]).out)
		guard ncpu > 0, !load.isEmpty else { return nil }
		let free = Int(s.f_bavail) * Int(s.f_bsize) / 1024
		let disk = (free - bytes / 1024) / 1024
		let mem = 100 - used
		let cpu = Int(load.reduce(0.0) { $0 + num(at(words($1), 0)) } / Double(ncpu))
		let least = Int(env("SPACE_MIN_FREE_MB", "2048")) ?? 2048
		let most = Int(env("SPACE_MAX_MEM", "90")) ?? 90
		let busy = Int(env("SPACE_MAX_CPU", "90")) ?? 90
		return [
			Check(name: "disk", value: disk, limit: least, over: disk < least),
			Check(name: "mem", value: mem, limit: most, over: mem > most),
			Check(name: "cpu", value: cpu, limit: busy, over: cpu > busy),
		]
	}

	static func check(_ a: [String]) -> Int32 {
		if at(a, 0) == "-h" || at(a, 0) == "--help" {
			err("""
			slybar space check [path] [bytes]

			Reads free disk, memory used and cpu used once and prints one tab separated row each: name, value, limit and
			ok or over. disk is the megabytes free on the volume of path (home when none is given) after bytes are written
			there, over when under SPACE_MIN_FREE_MB (2048); mem is the percent of memory used, over when above
			SPACE_MAX_MEM (90); cpu is the percent of all cores used, over when above SPACE_MAX_CPU (90). Exits 0 when all
			three are ok, 1 when any is over and 2 when a source cannot be read.

			""")
			return 2
		}
		guard let rows = probe(at(a, 0).isEmpty ? env("HOME", NSHomeDirectory()) : a[0], Int(at(a, 1)) ?? 0) else {
			err("slybar space check: df, sysctl or ps read nothing\n")
			return 2
		}
		for r in rows { put("\(r.name)\t\(r.value)\t\(r.limit)\t\(r.over ? "over" : "ok")\n") }
		return rows.contains { $0.over } ? 1 : 0
	}

	static func free(_ a: [String]) -> Int32 {
		var kinds = "orphan,stale,cache,redundant,data,running,rogue"
		var i = 0
		var bad = false
		while i < a.count {
			if a[i] == "--kind" {
				kinds = at(a, i + 1)
				i += 2
			} else {
				bad = true
				break
			}
		}
		if bad || isatty(0) == 1 {
			err("""
			slybar space candidates | slybar space free [--kind orphan,stale,cache,redundant,data,running,rogue]

			Reads the rows slybar space candidates prints, kind, kb, action, target, why and group, and prints one block per
			group of things that belong together, the easiest to remove first and what loses the most last: the group and
			what removing it costs on a line, a blank line, then each reason with its size, equal reasons counted as one,
			directly followed by its own commands, one kill for every process, one rm for every path and each command of a
			tool, every command on its own line, and a blank line. Nothing else is printed.

			""")
			return 2
		}
		let groups = [
			("processes", "nothing is lost, each starts again when it is needed"),
			("servers", "the server stops, it is started again with its recipe"),
			("containers", "the container stops, its volumes and data stay"),
			("open applications", "the application quits, it opens again when it is asked for"),
			("sessions", "the session ends, its transcript stays and claude --continue resumes it"),
			("rogue sessions", "the session ends, its transcript stays and claude --continue resumes it from ghostty"),
			("trash", "already thrown away"),
			("package caches", "downloaded again on the next install or build"),
			("browser caches", "downloaded again on the next run"),
			("tool caches", "rebuilt by the tool on its next run"),
			("app caches", "rebuilt by the application when it runs next, it starts slower once"),
			("docker", "images and layers are pulled or built again"),
			("worktrees", "the branch keeps every commit"),
			("build folders", "built again on the next build"),
			("toolchains and images", "downloaded again when something asks for them"),
			("applications", "installed again from its source, settings under Library stay"),
			("browser profiles", "the logins in them are gone"),
			("transcripts", "the session can no longer be resumed"),
			("projects", "cloned again from the remote"),
			("installers", "downloaded again if the source still has them"),
			("emulators", "the saved state is gone"),
			("docker volumes", "the data in them is gone"),
			("files", "gone for good"),
			("folders", "gone for good"),
			("unpushed projects", "work that is on no remote is gone for good"),
			("", ""),
		]
		var rank: [String: Int] = [:]
		var cost: [String: String] = [:]
		for (n, g) in groups.enumerated() {
			rank[g.0] = n + 1
			cost[g.0] = g.1
		}
		let want = Set(kinds.isEmpty ? [] : cut(kinds, by: 44))
		var sorted: [(rank: Int, size: String, line: String)] = []
		for l in lines(String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)) {
			let v = l.isEmpty ? [] : tabs(l)
			guard v.count >= 5, want.contains(v[0]) else { continue }
			let g = v.count >= 6 && !v[5].isEmpty ? v[5] : v[0]
			let kb = num(v[1])
			let r = rank[g] ?? 999
			let inverse = f("%012ld", Int(999999999999 - kb))
			sorted.append((r, inverse, "\(r)\t\(inverse)\t\(v[2])\t\(v[3])\t\(g)\t\(Int(kb))\t\(v[4])\t\(cost[g] ?? "")"))
		}
		sorted.sort { $0.rank != $1.rank ? $0.rank < $1.rank : $0.size != $1.size ? before($0.size, $1.size) : before($0.line, $1.line) }

		var group = ""
		var note = ""
		var order: [String] = []
		var kb: [String: Double] = [:]
		var count: [String: Int] = [:]
		var mem: [String: Bool] = [:]
		var cmds: [String: String] = [:]
		var seen: Set<String> = []
		func flush() {
			if order.isEmpty { return }
			var s = "== \(group)\(note.isEmpty ? "" : ": \(note)")\n\n"
			for w in order {
				let k = kb[w] ?? 0
				var size = k >= 1048576 ? f(", %.1fG", k / 1048576) : k >= 1024 ? f(", %.0fM", k / 1024) : ""
				if !size.isEmpty, mem[w] == true { size += " of memory" }
				let n = count[w] ?? 0
				s += "  \(n > 1 ? "\(n) × " : "")\(w)\(size)\n\(cmds[w] ?? "")\n"
			}
			put(s)
			order = []
			kb = [:]
			count = [:]
			mem = [:]
			cmds = [:]
		}
		for e in sorted {
			let v = tabs(e.line)
			let action = at(v, 2)
			if at(v, 4) != group {
				flush()
				group = at(v, 4)
				note = at(v, 7)
			}
			guard action == "kill" || action == "rm" || action == "run" else { continue }
			guard seen.insert(action + "\t" + at(v, 3)).inserted else { continue }
			var t = at(v, 3)
			let w = at(v, 6)
			if action == "kill" {
				while t.hasSuffix(" ") { t.removeLast() }
				t = "kill " + t
			}
			if action == "rm" { t = "rm -rf \"" + t.replacingOccurrences(of: "\"", with: "\\\"") + "\"" }
			if count[w] == nil { order.append(w) }
			count[w, default: 0] += 1
			kb[w, default: 0] += num(at(v, 5))
			mem[w] = action == "kill" || at(v, 4) == "containers" || at(v, 4) == "open applications"
			cmds[w, default: ""] += t + "\n"
		}
		flush()
		return 0
	}
}
