import Foundation

struct Proc {
	let pid: String
	let par: String
	let rss: String
	let age: Int
	let own: String
	let cwd: String
	let cmd: String
	let uid: String
}

extension Work {
	static let bundle = re("^(/Applications|/Users/[^/]+/Applications)/[^/]+\\.app/")

	func asker() -> String {
		var par: [String: String] = [:]
		var name: [String: String] = [:]
		for l in lines(sh("ps", ["-axco", "pid=,ppid=,comm="]).out) {
			let v = fields(l, 2)
			par[v[0]] = v[1]
			name[v[0]] = v[2]
		}
		var p = "\(getpid())"
		var top = "0"
		var n = 0
		while (Int(p) ?? 0) > 1, n < 1024 {
			if name[p] == "claude" { top = p }
			p = par[p] ?? ""
			n += 1
		}
		return top
	}

	func table() throws -> [Proc] {
		var dirs: [String: String] = [:]
		var p = ""
		for l in lines(sh("lsof", ["-d", "cwd", "-Fpn"]).out) {
			if l.hasPrefix("p") { p = String(l.dropFirst()) }
			if l.hasPrefix("n") { dirs[p] = String(l.dropFirst()) }
		}
		var claude: Set<String> = []
		for l in lines(sh("ps", ["-axco", "pid=,comm="]).out) {
			let w = words(l)
			if at(w, 1) == "claude" { claude.insert(at(w, 0)) }
		}
		var raw: [String: [String]] = [:]
		var order = Tab()
		for l in lines(sh("ps", ["-axo", "pid=,ppid=,rss=,etime=,uid=,command="]).out) {
			let w = words(l)
			guard !w.isEmpty else { continue }
			raw[w[0]] = w
			order.add(w[0])
		}
		var rows: [Proc] = []
		for pid in order.keys {
			guard let w = raw[pid] else { continue }
			var own = "0"
			var q = pid
			var n = 0
			while num(q) > 1, n < 64 {
				n += 1
				if claude.contains(q) { own = q }
				q = at(raw[q] ?? [], 1)
			}
			rows.append(Proc(pid: pid, par: at(w, 1), rss: at(w, 2), age: secs(at(w, 3)), own: own, cwd: dirs[pid] ?? "", cmd: w.dropFirst(5).joined(separator: " "), uid: at(w, 4)))
		}
		guard !rows.isEmpty else {
			err("slybar space: ps read no processes\n")
			throw Halt(code: 1)
		}
		return rows
	}

	func running(_ emit: Emit) throws {
		let asker = asker()
		let t = try table()
		var procs: [String: Proc] = [:]
		for x in t { procs[x.pid] = x }
		let order = Tab(t.map { $0.pid }).keys
		let uid = "\(getuid())"
		let big = rss * 1024
		var mins: [String: Int] = [:]

		func who(_ o: String) -> String {
			o == "0" ? "started by no claude session" : o == asker ? "started by this session" : "started by the session in " + (procs[o]?.cwd ?? "")
		}
		func via(_ tool: String) -> String { tool == "session" ? "started with" : "started by \(tool) in" }
		func claude(_ pid: String) -> Bool {
			var c = procs[pid]?.cmd ?? ""
			if let r = c.range(of: " ", options: .literal) { c = String(c[..<r.lowerBound]) }
			if let r = c.range(of: "/", options: [.literal, .backwards]) { c = String(c[r.upperBound...]) }
			return c == "claude"
		}

		for p in order {
			guard let x = procs[p], x.own == p else { continue }
			var o = ""
			var top = p
			var q = x.par
			var n = 0
			while num(q) > 1, n < 64 {
				n += 1
				if (procs[q]?.cmd ?? "").lowercased().contains("ghostty") { o = "ghostty" }
				top = q
				q = procs[q]?.par ?? ""
			}
			if o.isEmpty {
				o = top == p ? "launchd" : procs[top]?.cmd ?? ""
				if let r = o.range(of: ".app/", options: .literal) { o = String(o[..<r.lowerBound]) } else if let r = o.range(of: " ", options: .literal) { o = String(o[..<r.lowerBound]) }
				if let r = o.range(of: "/", options: [.literal, .backwards]) { o = String(o[r.upperBound...]) }
			}
			let v = cut("\(p)\t\(x.cwd)\t\(o)", by: 9, keep: false)
			let c = at(v, 0), dir = at(v, 1), from = v.dropFirst(2).joined(separator: "\t")
			var m = -1
			var moves = "its transcript has never moved"
			if let last = moved(dir) {
				m = (now - last) / 60
				moves = "its transcript moved \(m) minutes ago"
			}
			mins[c] = m
			if c == asker { continue }
			let same = t.filter { $0.pid == $0.own && $0.cwd == dir }.count
			let tree = t.filter { $0.own == c }
			let sum = Int(tree.reduce(0.0) { $0 + num($1.rss) })
			if from != "ghostty" {
				emit(Space.Row(kind: "rogue", kb: sum, action: "kill", target: c, why: "claude session in \(dir) started from \(from), not from ghostty, \(tree.count) processes, \(moves)", group: "rogue sessions"))
				continue
			}
			if m >= 0, m < orphan { continue }
			emit(Space.Row(kind: "running", kb: sum, action: "kill", target: c, why: "claude session in \(dir), \(tree.count) processes, \(moves)\(same > 1 ? ", one of \(same) sessions in that folder" : "")", group: "sessions"))
		}

		var headless: Set<String> = []
		var apps = Tab()
		for x in t {
			if x.cmd.contains("--headless") { headless.insert(x.pid) }
			if x.uid == uid, x.own == "0", hit(Work.bundle, x.cmd) { apps.add(x.pid) }
		}
		var names = Tab()
		var sum: [String: Double] = [:]
		var count: [String: Int] = [:]
		var oldest: [String: Int] = [:]
		for p in apps.keys {
			guard let x = procs[p], !headless.contains(p), !headless.contains(x.par), let r = x.cmd.range(of: ".app/", options: .literal) else { continue }
			var a = String(x.cmd[..<r.lowerBound])
			if let s = a.range(of: "/", options: [.literal, .backwards]) { a = String(a[s.upperBound...]) }
			if a == "Ghostty" || a == "OrbStack" { continue }
			names.add(a)
			sum[a, default: 0] += num(x.rss)
			count[a, default: 0] += 1
			if x.age > oldest[a] ?? 0 { oldest[a] = x.age }
		}
		for a in names.keys where (sum[a] ?? 0) > Double(big) {
			emit(Space.Row(kind: "running", kb: Int(sum[a] ?? 0), action: "run", target: "osascript -e 'quit app \"\(a)\"'", why: "\(a), \(count[a] ?? 0) processes, up \(up(oldest[a] ?? 0))", group: "open applications"))
		}

		var ports: [String: [String]] = [:]
		var p = ""
		for l in lines(sh("lsof", ["-nP", "-iTCP", "-sTCP:LISTEN", "-Fpn"]).out) {
			if l.hasPrefix("p") { p = String(l.dropFirst()) }
			if l.hasPrefix("n") {
				var a = String(l.dropFirst())
				if let r = a.range(of: ":", options: [.literal, .backwards]) { a = String(a[r.upperBound...]) }
				if !(ports[p] ?? []).contains(a) { ports[p, default: []].append(a) }
			}
		}
		let listen = ranked(ports.compactMap { e in procs[e.key].map { "\($0.age)\t\(e.key)\t\(e.value.joined(separator: ","))" } }).map { tabs($0) }
		var listening: Set<String> = []
		var shape: [String: Int] = [:]
		var servers: [(pid: String, port: String, key: String)] = []
		for v in listen {
			let pid = at(v, 1)
			listening.insert(pid)
			guard let x = procs[pid], !hit(Work.system, x.cmd), x.uid == uid, starts(x.cwd, home + "/") else { continue }
			let k = String(decoding: (x.cwd + "\t" + x.cmd).utf8.filter { $0 < 48 || $0 > 57 }, as: UTF8.self)
			shape[k, default: 0] += 1
			servers.append((pid, at(v, 2), k))
		}
		var seen: Set<String> = []
		for s in servers {
			guard let x = procs[s.pid] else { continue }
			if !seen.insert(s.key).inserted {
				emit(row("redundant", x.rss, "kill", s.pid, "one of \(shape[s.key] ?? 0) servers of the same command in \(x.cwd), older than the newest, port \(s.port), up \(up(x.age)), \(who(x.own))", "servers"))
			} else {
				emit(row("running", x.rss, "kill", s.pid, "server on port \(s.port) in \(x.cwd), up \(up(x.age)), \(who(x.own)): \(clip(x.cmd, 60))", "servers"))
			}
		}

		var jobs: Set<String> = []
		for l in lines(sh("launchctl", ["list"]).out) {
			let w = at(words(l), 0)
			if !w.isEmpty, w.utf8.allSatisfy({ $0 >= 48 && $0 <= 57 }) { jobs.insert(w) }
		}
		var sid: [String: String] = [:]
		for l in lines(sh("ps", ["-E", "-ww", "-axo", "pid=,command="]).out) {
			let w = words(l)
			if let e = w.dropFirst().first(where: { starts($0, "CLAUDE_CODE_SESSION_ID=") }) { sid[w[0]] = String(decoding: e.utf8.dropFirst(23), as: UTF8.self) }
		}
		var alive: Set<String> = []
		for l in lines(sh("ps", ["-axo", "pid=,lstart="]).out) {
			let w = words(l)
			alive.insert(at(w, 0) + "\t" + w.dropFirst().joined(separator: " "))
		}
		var tool: [String: String] = [:]
		var from: [String: String] = [:]
		var dir: [String: String] = [:]
		for l in lines(String(decoding: FileManager.default.contents(atPath: log) ?? Data(), as: UTF8.self)) {
			let v = tabs(l)
			let pid = at(v, 5), parent = at(v, 2)
			let equal = Double(pid) != nil && Double(parent) != nil ? Double(pid) == Double(parent) : pid == parent
			if !equal, alive.contains(pid + "\t" + at(v, 6)) {
				tool[pid] = at(v, 4)
				from[pid] = parent
				dir[pid] = at(v, 7)
			}
		}
		var live: Set<String> = []
		for x in t where x.own != "0" {
			if let s = sid[x.pid] { live.insert(s) }
		}

		var copies: [String: Int] = [:]
		var newest: [String: String] = [:]
		var key: [String: String] = [:]
		var keyed = Tab()
		for p in order {
			guard let x = procs[p] else { continue }
			let short = clip(x.cmd, 60)
			let age = up(x.age)
			if x.cmd.contains("--headless") || x.cmd.contains("\"headless\":true"), !x.cmd.contains("--type=") {
				emit(row("running", x.rss, "kill", p, "headless browser, up \(age), \(who(x.own)): \(short)", "processes"))
			}
			if p == x.own || x.uid != uid { continue }
			if let started = tool[p] {
				let parent = from[p] ?? ""
				if !claude(parent) {
					emit(row("orphan", x.rss, "kill", p, "\(via(started)) the claude session in \(dir[p] ?? "") that has closed, up \(age): \(short)", "processes"))
					continue
				}
				let m = mins[procs[parent]?.own ?? ""] ?? 0
				if m >= idle * 60 {
					emit(row("stale", x.rss, "kill", p, "\(via(started)) the claude session in \(dir[p] ?? ""), idle \(m / 60)h, up \(age): \(short)", "processes"))
					continue
				}
			}
			if hit(Work.system, x.cmd) || listening.contains(p) { continue }
			if x.own == "0", let s = sid[p], !live.contains(s) {
				emit(row("orphan", x.rss, "kill", p, "left by a claude session that has ended, up \(age): \(short)", "processes"))
			} else if x.own == "0", x.par == "1", !jobs.contains(p) {
				emit(row("orphan", x.rss, "kill", p, "parent gone and no launchd job owns it, up \(age): \(short)", "processes"))
			} else if num(x.rss) > Double(big) {
				emit(row("running", x.rss, "kill", p, "process over \(rss)M, up \(age), \(who(x.own))\(tool[p].map { ", \(via($0)) it" } ?? ""): \(short)", "processes"))
			}
			if !starts(x.cwd, home + "/") { continue }
			let k = x.own + "\t" + x.cwd + "\t" + x.cmd
			copies[k, default: 0] += 1
			if let o = newest[k].flatMap({ procs[$0] }), x.age >= o.age {} else { newest[k] = p }
			key[p] = k
			keyed.add(p)
		}
		for p in keyed.keys {
			guard let x = procs[p], let k = key[p], (copies[k] ?? 0) > 1, p != newest[k], x.age > 300 else { continue }
			emit(row("redundant", x.rss, "kill", p, "one of \(copies[k] ?? 0) instances of the same command in \(x.cwd), older than the newest, \(who(x.own)): \(clip(x.cmd, 60))", "processes"))
		}

		let orb = t.filter { $0.cmd.contains("/OrbStack.app/") }
		var n = 0
		if sh("docker", ["info"], out: .nullDevice).code == 0 {
			n = lines(sh("docker", ["ps", "-q"]).out).count
			let stats = lines(sh("docker", ["stats", "--no-stream", "--format", "{{.ID}}\\t{{.MemUsage}}"]).out)
			let boxes = lines(sh("docker", ["ps", "--format", "{{.ID}}\\t{{.Image}}\\t{{.Names}}\\t{{.RunningFor}}\\t{{.Label \"com.docker.compose.project.working_dir\"}}"]).out).map { tabs($0) }
			if !stats.isEmpty {
				var mem: [String: Int] = [:]
				for l in stats {
					let v = tabs(l)
					let s = at(cut(at(v, 1), by: 32), 0)
					mem[at(v, 0)] = s.contains("GiB") ? Int(num(s) * 1048576) : s.contains("MiB") ? Int(num(s) * 1024) : s.contains("KiB") ? Int(num(s)) : 0
				}
				var images: [String: Int] = [:]
				for b in boxes { images[at(b, 1), default: 0] += 1 }
				var met: Set<String> = []
				for b in boxes {
					let id = at(b, 0), image = at(b, 1), name = at(b, 2)
					var time = at(b, 3)
					if time.hasSuffix(" ago") { time.removeLast(4) }
					let spot = at(b, 4).isEmpty ? "" : ", compose project in \(at(b, 4))"
					if !met.insert(image).inserted {
						emit(Space.Row(kind: "redundant", kb: mem[id] ?? 0, action: "run", target: "docker stop \(id)", why: "container \(name), one of \(images[image] ?? 0) running containers of image \(image), older than the newest, up \(time)\(spot)", group: "containers"))
					} else {
						emit(Space.Row(kind: "running", kb: mem[id] ?? 0, action: "run", target: "docker stop \(id)", why: "container \(name) of image \(image), up \(time)\(spot)", group: "containers"))
					}
				}
			}
		} else if orb.isEmpty {
			note("slybar space: docker is down, orbstack was not started")
		}
		if !orb.isEmpty {
			emit(Space.Row(kind: "running", kb: Int(orb.reduce(0.0) { $0 + num($1.rss) }), action: "run", target: "orb stop", why: "orbstack with \(n) running containers, every container stops with it", group: "containers"))
		}
	}

	func pause() throws -> Int32 {
		if let d = FileManager.default.contents(atPath: paused), !d.isEmpty {
			err("slybar space: sessions are already paused, run slybar space resume first\n")
			return 1
		}
		let asker = asker()
		let t = try table()
		let stop = t.filter { $0.own != "0" && $0.own != asker }.map { $0.pid }
		if stop.isEmpty {
			drop(paused)
			put("no other claude session is running, nothing paused\n")
			return 0
		}
		guard FileManager.default.createFile(atPath: paused, contents: Data((stop.joined(separator: "\n") + "\n").utf8)) else { return 1 }
		for p in stop {
			if let n = Int32(p) { kill(n, SIGSTOP) }
		}
		for x in t where x.pid == x.own && x.pid != asker { put("paused the claude session in \(x.cwd), pid \(x.pid)\n") }
		put("\(stop.count) processes paused, slybar space resume continues them\n")
		return 0
	}

	func resume() -> Int32 {
		guard let d = FileManager.default.contents(atPath: paused), !d.isEmpty else {
			err("slybar space: nothing is paused\n")
			return 1
		}
		let text = String(decoding: d, as: UTF8.self)
		for p in words(text.replacingOccurrences(of: "\n", with: " ")) {
			if let n = Int32(p) { kill(n, SIGCONT) }
		}
		put("\(lines(text).count) processes continued, type fg in the terminal of each paused claude session\n")
		drop(paused)
		return 0
	}
}
