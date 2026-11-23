import Foundation
import Space

enum State {
	static func rows(_ path: String) -> [[String]] {
		Base.read(path).split(separator: "\n").map { $0.split(separator: "\t", omittingEmptySubsequences: false).map(String.init) }
	}

	static func row(_ f: [String]) -> Json {
		func at(_ i: Int) -> Any { i < f.count ? f[i] as Any : NSNull() }
		var all: Json = [:]
		all["kind"] = at(1)
		all["kb"] = f.count > 2 ? Double(f[2]) ?? 0 : 0
		all["action"] = at(3)
		all["target"] = at(4)
		all["why"] = at(5)
		all["group"] = f.count > 6 ? at(6) : at(1)
		all["cpu"] = f.count > 7 ? Double(f[7]).map { $0 as Any } ?? NSNull() : NSNull()
		return all
	}

	static func state() -> Int32 {
		Accounts.sync()
		let fm = FileManager.default
		let manifests = ((try? fm.contentsOfDirectory(atPath: Base.sessions)) ?? []).filter { $0.hasSuffix(".json") }.sorted()
		let pids = manifests.map { String($0.dropLast(5)) }
		var live: [String: Json] = [:]
		if !pids.isEmpty {
			var env = Base.tools()
			env["LC_ALL"] = "C"
			for line in Base.run("/bin/ps", ["-o", "pid=,pcpu=,rss=,comm=", "-p", pids.joined(separator: ",")], env: env).out.split(separator: "\n") {
				let f = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
				guard f.count > 3, let last = f.last, last == "claude" || last.hasSuffix("/claude") else { continue }
				live[f[0]] = ["cpu": (Double(f[1]) ?? 0).rounded(), "kb": Double(f[2]) ?? 0]
			}
		}
		let stdin = Base.cache + "/last-stdin.json"
		var bar: Any = NSNull()
		if let input = Base.parse(Base.read(stdin)) {
			let limits = input["rate_limits"] as? Json ?? [:]
			let cost = input["cost"] as? Json ?? [:]
			bar = ["dir": (input["workspace"] as? Json)?["current_dir"] ?? input["cwd"] ?? NSNull(), "model": (input["model"] as? Json)?["display_name"] ?? NSNull(),
				"cost": cost["total_cost_usd"] ?? NSNull(), "ms": cost["total_duration_ms"] ?? NSNull(), "ctx": (input["context_window"] as? Json)?["used_percentage"] ?? NSNull(),
				"five": limits["five_hour"] ?? NSNull(), "seven": limits["seven_day"] ?? NSNull()] as Json
		}
		let barAt = Base.modified(stdin)
		let active = Accounts.active()
		let known = Base.json(Base.tray + "/accounts.json")
		let usage = Base.json(Base.tray + "/usage.json")
		let accounts: [Json] = known.keys.sorted().map { email in
			var all = known[email] as? Json ?? [:]
			all["email"] = email
			all["active"] = email == active
			for (key, value) in usage[email] as? Json ?? [:] {
				all[key] = value
			}
			if email == active, let from = bar as? Json, let five = from["five"] as? Json, barAt > (all["at"] as? Double ?? 0) {
				let seven = from["seven"] as? Json ?? [:]
				all["five"] = ["pct": five["used_percentage"] ?? NSNull(), "reset": five["resets_at"] ?? NSNull()] as Json
				all["seven"] = ["pct": seven["used_percentage"] ?? NSNull(), "reset": seven["resets_at"] ?? NSNull()] as Json
				all["at"] = Int(barAt)
			}
			return all
		}
		var sessions: [Json] = []
		for name in manifests {
			let all = Base.json(Base.sessions + "/" + name)
			guard let pid = all["pid"] as? Int, let seen = live[String(pid)] else { continue }
			let since = (all["statusUpdatedAt"] as? Double ?? all["startedAt"] as? Double ?? 0) / 1000
			var entry: Json = ["pid": pid, "name": all["name"] ?? NSNull(), "dir": all["cwd"] ?? NSNull(), "status": all["status"] ?? NSNull(), "since": Int(since)]
			for (key, value) in seen {
				entry[key] = value
			}
			sessions.append(entry)
		}
		let res = rows(Base.tray + "/resources.tsv")
		let checks: [Json] = res.filter { $0.first == "check" && $0.count > 4 }.map {
			["name": $0[1], "value": Double($0[2]) ?? 0, "limit": Double($0[3]) ?? 0, "over": $0[4] == "over"]
		}
		let agents = res.first { $0.first == "agents" && $0.count > 1 }.flatMap { Double($0[1]) } ?? 0
		let pid = Int(Base.read(Base.tray + "/space.pid").trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
		let all: Json = ["accounts": accounts, "active": active, "bar": bar, "sessions": sessions,
			"resources": ["at": Int(Base.modified(Base.tray + "/resources.tsv")), "check": checks, "agents": agents, "rows": res.filter { $0.first == "row" }.map(row)] as Json,
			"space": ["at": Int(Base.modified(Base.tray + "/space.tsv")), "scanning": Base.alive(pid), "rows": rows(Base.tray + "/space.tsv").map(row)] as Json]
		Base.say(Base.text(all, pretty: true))
		return 0
	}

	static func resources() -> Int32 {
		guard let checks = Space.check(path: Base.home, bytes: 0) else { return Base.fail("slybar: df, sysctl or ps read nothing") }
		let tray = Base.read(Base.tray + "/pid").trimmingCharacters(in: .whitespacesAndNewlines)
		var env = Base.tools()
		env["LC_ALL"] = "C"
		var cpu: [String: Double] = [:]
		var procs: [(pid: String, cpu: Double, rss: String, comm: String)] = []
		var agents = 0
		for line in Base.run("/bin/ps", ["-axo", "pid=,pcpu=,rss=,comm=", "-r"], env: env).out.split(separator: "\n") {
			let f = line.split(separator: " ", maxSplits: 3, omittingEmptySubsequences: true).map(String.init)
			guard f.count == 4 else { continue }
			cpu[f[0]] = Double(f[1]) ?? 0
			procs.append((f[0], Double(f[1]) ?? 0, f[2], f[3]))
			if f[3] == "claude" || f[3].hasSuffix("/claude") {
				agents += 1
			}
		}
		var out = checks.map { "check\t\($0.name)\t\($0.value)\t\($0.limit)\t\($0.over ? "over" : "ok")" }
		out.append("agents\t\(agents)")
		for row in Space.running() {
			var used = 0.0
			if row.action == "kill" {
				used = row.target.split(separator: " ").reduce(0) { $0 + (cpu[String($1)] ?? 0) }
			} else if let from = row.target.range(of: "quit app \""), let to = row.target[from.upperBound...].firstIndex(of: "\"") {
				let name = "/" + row.target[from.upperBound..<to] + ".app/"
				used = procs.filter { $0.comm.contains(name) }.reduce(0) { $0 + $1.cpu }
			}
			out.append(["row", row.kind, String(row.kb), row.action, row.target, row.why, row.group.isEmpty ? row.kind : row.group, String(Int(used))].joined(separator: "\t"))
		}
		var heavy = 0
		for proc in procs where proc.cpu >= 10 && proc.pid != tray && heavy < 6 {
			out.append(["row", "running", proc.rss, "kill", proc.pid, (proc.comm as NSString).lastPathComponent, "cpu", String(Int(proc.cpu))].joined(separator: "\t"))
			heavy += 1
		}
		Base.write(Base.tray + "/resources.tsv", out.joined(separator: "\n") + "\n")
		return 0
	}

	static func space() -> Int32 {
		Base.write(Base.tray + "/space.pid", String(ProcessInfo.processInfo.processIdentifier))
		let out = Space.candidates(days: nil).map { ["row", $0.kind, String($0.kb), $0.action, $0.target, $0.why, $0.group.isEmpty ? $0.kind : $0.group].joined(separator: "\t") }
		Base.write(Base.tray + "/space.tsv", out.isEmpty ? "" : out.joined(separator: "\n") + "\n")
		try? FileManager.default.removeItem(atPath: Base.tray + "/space.pid")
		return 0
	}

	static func tree(_ pid: String) -> [String] {
		Base.run("/usr/bin/pgrep", ["-P", pid]).out.split(separator: "\n").flatMap { tree(String($0)) } + [pid]
	}

	static func free(_ targets: [String]) -> Int32 {
		let files = [Base.tray + "/resources.tsv", Base.tray + "/space.tsv"]
		for target in targets {
			var action = ""
			for file in files where action.isEmpty {
				action = rows(file).first { $0.count > 4 && $0[0] == "row" && $0[4] == target }?[3] ?? ""
			}
			switch action {
			case "kill":
				for pid in target.split(separator: " ") {
					for each in tree(String(pid)) {
						if let number = pid_t(each) {
							kill(number, SIGKILL)
						}
					}
				}
			case "rm":
				try? FileManager.default.removeItem(atPath: target)
			case "run":
				_ = Base.shell(target)
			default:
				return Base.fail("no row for \(target)")
			}
			for file in files {
				let kept = rows(file).filter { !($0.count > 4 && $0[0] == "row" && $0[4] == target) }.map { $0.joined(separator: "\t") }
				Base.write(file, kept.isEmpty ? "" : kept.joined(separator: "\n") + "\n")
			}
		}
		return 0
	}
}
