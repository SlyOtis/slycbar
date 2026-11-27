import Foundation

enum Review {
	static let usage = "usage: slybar review <plan.json|-> [status|wait [seconds]|put]"
	static let index = Base.cache + "/plans.json"

	static func parent(_ pid: Int32) -> Int32 {
		var info = kinfo_proc()
		var size = MemoryLayout<kinfo_proc>.stride
		var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
		guard sysctl(&mib, 4, &info, &size, nil, 0) == 0, size > 0 else { return 0 }
		return info.kp_eproc.e_ppid
	}

	static func session() -> Json {
		var pid = getpid()
		for _ in 0..<8 where pid > 1 {
			let found = Base.json(Base.sessions + "/\(pid).json")
			if found["sessionId"] is String {
				return found
			}
			pid = parent(pid)
		}
		return [:]
	}

	static func absolute(_ path: String) -> String {
		path.hasPrefix("/") ? path : FileManager.default.currentDirectoryPath + "/" + path
	}

	static func check(_ plan: Json) -> String? {
		let changes = plan["changes"] as? [Json] ?? []
		guard !changes.isEmpty else { return "the plan has no changes" }
		for (at, change) in changes.enumerated() {
			let n = at + 1
			guard let target = change["path"] as? String, target.hasPrefix("/") else { return "change \(n) needs an absolute path" }
			guard let proposed = change["proposed"] as? String, proposed.hasPrefix("/") else { return "change \(n) needs an absolute proposed path or its contents" }
			guard FileManager.default.fileExists(atPath: proposed) else { return "change \(n): no proposed file at \(proposed)" }
			if let base = change["base"] as? String, !base.isEmpty, !FileManager.default.fileExists(atPath: base) { return "change \(n): no base file at \(base)" }
		}
		return nil
	}

	static func place(_ given: Json, _ path: String) -> String? {
		let fm = FileManager.default
		let dir = (path as NSString).deletingLastPathComponent
		try? fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
		let old = Base.json(path)
		let before = old["changes"] as? [Json] ?? []
		var plan = given
		var changes = plan["changes"] as? [Json] ?? []
		for at in changes.indices {
			var change = changes[at]
			let target = change["path"] as? String ?? ""
			let prior = before.first { $0["path"] as? String == target && !target.isEmpty }
			let was = prior.flatMap { $0["proposed"] as? String }.map { Base.read($0) }
			if let contents = change["contents"] as? String {
				var proposed = change["proposed"] as? String ?? ""
				if !proposed.hasPrefix("/") {
					proposed = dir + "/proposed/\(at + 1)-" + (target.isEmpty ? "change" : (target as NSString).lastPathComponent)
				}
				try? fm.createDirectory(atPath: (proposed as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
				guard (try? contents.write(toFile: proposed, atomically: true, encoding: .utf8)) != nil else { return "change \(at + 1): the proposed file \(proposed) was not written" }
				change["proposed"] = proposed
				change["contents"] = nil
			}
			let same = was.map { $0 == Base.read(change["proposed"] as? String ?? "") } ?? false
			if change["status"] == nil {
				change["status"] = same ? prior?["status"] ?? "pending" : "pending"
			}
			if change["comments"] == nil {
				change["comments"] = prior?["comments"] ?? []
			}
			if !same {
				change["status"] = "pending"
				change["comments"] = (change["comments"] as? [Json] ?? []).filter { $0["status"] == nil || !($0["text"] as? String ?? "").isEmpty }.map { entry -> Json in
					var kept = entry
					kept["status"] = nil
					return kept
				}
			}
			changes[at] = change
		}
		plan["changes"] = changes
		if plan["comments"] == nil {
			plan["comments"] = old["comments"] ?? []
		}
		if plan["title"] == nil, let title = old["title"] {
			plan["title"] = title
		}
		plan["round"] = before.isEmpty ? plan["round"] ?? 1 : (old["round"] as? Int ?? 1) + 1
		plan["state"] = "open"
		plan["run"] = nil
		Base.write(path, Base.text(plan, pretty: true))
		return nil
	}

	static func own(_ path: String) {
		var plan = Base.json(path)
		let found = session()
		var changed = false
		if (plan["session"] as? String ?? "").isEmpty, let sid = found["sessionId"] as? String {
			plan["session"] = sid
			changed = true
		}
		if (plan["dir"] as? String ?? "").isEmpty {
			plan["dir"] = found["cwd"] as? String ?? FileManager.default.currentDirectoryPath
			changed = true
		}
		if plan["state"] == nil {
			plan["state"] = "open"
			changed = true
		}
		if changed {
			Base.write(path, Base.text(plan, pretty: true))
		}
		guard let sid = found["sessionId"] as? String ?? plan["session"] as? String, !sid.isEmpty else { return }
		Base.edit(index) { $0[sid] = path }
		try? FileManager.default.removeItem(atPath: told(sid))
	}

	static func record(_ path: String) {
		var plan = Base.json(path)
		guard let sid = plan["session"] as? String, !sid.isEmpty, var changes = plan["changes"] as? [Json] else { return }
		let fm = FileManager.default
		let ref = "refs/slyed/" + sid + ".plan"
		var tips: [String: String] = [:]
		for at in changes.indices {
			let target = changes[at]["path"] as? String ?? ""
			let proposed = changes[at]["proposed"] as? String ?? ""
			var dir = (target as NSString).deletingLastPathComponent
			while dir.count > 1, !fm.fileExists(atPath: dir) {
				dir = (dir as NSString).deletingLastPathComponent
			}
			var env = Base.tools()
			func git(_ args: [String]) -> (code: Int32, out: String) {
				let found = Base.run("/usr/bin/git", ["-C", dir] + args, env: env)
				return (found.code, found.out.trimmingCharacters(in: .whitespacesAndNewlines))
			}
			let top = git(["rev-parse", "--show-toplevel"])
			let store = git(["rev-parse", "--absolute-git-dir"])
			guard top.code == 0, store.code == 0, target.hasPrefix(top.out + "/"), fm.fileExists(atPath: proposed) else { continue }
			let index = store.out + "/slyed/" + sid + ".plan.index"
			try? fm.createDirectory(atPath: store.out + "/slyed", withIntermediateDirectories: true)
			env["GIT_INDEX_FILE"] = index
			var parent = tips[top.out] ?? ""
			if parent.isEmpty {
				parent = git(["rev-parse", "-q", "--verify", "HEAD^{commit}"]).out
				try? fm.removeItem(atPath: index)
				guard !parent.isEmpty, git(["read-tree", parent]).code == 0 else { continue }
			}
			let blob = git(["hash-object", "-w", "--", proposed])
			guard blob.code == 0, git(["update-index", "--add", "--cacheinfo", "100644," + blob.out + "," + String(target.dropFirst(top.out.count + 1))]).code == 0 else { continue }
			let tree = git(["write-tree"])
			let said = [changes[at]["title"] as? String ?? "", changes[at]["why"] as? String ?? ""].filter { !$0.isEmpty }.joined(separator: "\n\n")
			let made = git(["commit-tree", tree.out, "-p", parent, "-m", said.isEmpty ? (target as NSString).lastPathComponent : said])
			guard tree.code == 0, made.code == 0 else { continue }
			tips[top.out] = made.out
			changes[at]["commit"] = made.out
			_ = git(["update-ref", ref, made.out])
		}
		guard !tips.isEmpty else { return }
		plan["changes"] = changes
		Base.write(path, Base.text(plan, pretty: true))
	}

	static func told(_ sid: String) -> String {
		(Base.env["TMPDIR"] ?? "/tmp") + "/slycbar.plan." + sid
	}

	static func status(_ path: String) -> Json {
		let plan = Base.json(path)
		let changes = plan["changes"] as? [Json] ?? []
		let rows: [Json] = changes.enumerated().map { at, change in
			["change": at + 1, "title": change["title"] ?? "", "path": change["path"] ?? "", "proposed": change["proposed"] ?? "", "status": change["status"] ?? "pending", "comments": change["comments"] ?? []]
		}
		let decided = rows.filter { ($0["status"] as? String ?? "pending") != "pending" }.count
		return ["plan": path, "title": plan["title"] ?? "", "state": plan["state"] ?? "open", "round": plan["round"] ?? 1, "session": plan["session"] ?? "", "decided": decided, "pending": rows.count - decided,
			"comments": plan["comments"] ?? [], "run": plan["run"] ?? NSNull(), "changes": rows]
	}

	static func wait(_ path: String, _ seconds: Int) -> Json {
		let end = Base.now + Double(max(1, min(seconds, 3600)))
		while Base.now < end {
			let state = Base.json(path)["state"] as? String ?? "open"
			if state == "sent" || state == "approved" {
				return status(path)
			}
			Thread.sleep(forTimeInterval: 1)
		}
		var found = status(path)
		found["waited"] = seconds
		return found
	}

	static func show(_ path: String) -> Int32 {
		guard FileManager.default.fileExists(atPath: Base.editApp) else { return Base.fail("Slyed is not installed, run slybar install") }
		var allowed = CharacterSet.alphanumerics
		allowed.insert(charactersIn: "-_.~")
		return Base.run("/usr/bin/open", ["slyed://review?plan=" + (path.addingPercentEncoding(withAllowedCharacters: allowed) ?? path)]).code
	}

	static func fresh() -> String {
		let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "")
		return Base.cache + "/plans/" + stamp + "-" + String(getpid()) + "/plan.json"
	}

	static func open(_ given: Json?, _ target: String) -> (Json?, String?) {
		let path = target.isEmpty ? fresh() : absolute(target)
		if let given {
			if let failed = place(given, path) { return (nil, failed) }
		} else {
			guard FileManager.default.fileExists(atPath: path) else { return (nil, "no plan at \(path)") }
			let plan = Base.json(path)
			guard !plan.isEmpty else { return (nil, "the plan at \(path) is not a json object") }
			if (plan["changes"] as? [Json] ?? []).contains(where: { $0["contents"] is String }), let failed = place(plan, path) { return (nil, failed) }
		}
		if let failed = check(Base.json(path)) { return (nil, failed) }
		own(path)
		record(path)
		let code = show(path)
		var found = status(path)
		if code != 0 {
			found["editor"] = "not opened"
		}
		return (found, nil)
	}

	static func review(_ args: [String]) -> Int32 {
		guard let first = args.first else { return Base.fail(usage, 2) }
		let verb = args.count > 1 ? args[1] : ""
		if first == "-" || verb == "put" {
			guard args.count <= 2 else { return Base.fail(usage, 2) }
			guard let given = Base.parse(String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)) else { return Base.fail("the plan on stdin is not a json object") }
			let (found, failed) = open(given, first == "-" ? "" : first)
			if let failed { return Base.fail(failed) }
			Base.say(Base.text(found ?? [:], pretty: true))
			return 0
		}
		let path = absolute(first)
		switch verb {
		case "":
			let (found, failed) = open(nil, path)
			if let failed { return Base.fail(failed) }
			return found?["editor"] == nil ? 0 : Base.fail("Slyed did not open the plan")
		case "status":
			guard FileManager.default.fileExists(atPath: path) else { return Base.fail("no plan at \(path)") }
			Base.say(Base.text(status(path), pretty: true))
			return 0
		case "wait":
			guard FileManager.default.fileExists(atPath: path) else { return Base.fail("no plan at \(path)") }
			Base.say(Base.text(wait(path, args.count > 2 ? Int(args[2]) ?? 600 : 600), pretty: true))
			return 0
		default:
			return Base.fail(usage, 2)
		}
	}

	static func why(_ log: String, _ id: String, _ path: String) -> String {
		guard let handle = FileHandle(forReadingAtPath: log) else { return "" }
		let size = handle.seekToEndOfFile()
		handle.seek(toFileOffset: size > 400000 ? size - 400000 : 0)
		let lines = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n")
		handle.closeFile()
		var seen = false
		for line in lines.reversed() {
			guard let entry = Base.parse(String(line)), let role = entry["type"] as? String else { continue }
			let content = (entry["message"] as? Json)?["content"]
			let blocks = content as? [Json] ?? []
			if role == "user" {
				if seen, content is String || blocks.contains(where: { $0["type"] as? String == "text" }) { return "" }
				continue
			}
			guard role == "assistant" else { continue }
			if !seen {
				seen = blocks.contains { $0["type"] as? String == "tool_use" && (id.isEmpty ? ($0["input"] as? Json)?["file_path"] as? String == path : $0["id"] as? String == id) }
				guard seen else { continue }
			}
			let said = (blocks.last(where: { $0["type"] as? String == "text" })?["text"] as? String ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
			if !said.isEmpty {
				return String(said.suffix(1000))
			}
		}
		return ""
	}

	static func snap(_ sid: String, _ path: String, _ why: String?) {
		guard !sid.isEmpty, path.hasPrefix("/") else { return }
		let fm = FileManager.default
		var dir = (path as NSString).deletingLastPathComponent
		while dir.count > 1, !fm.fileExists(atPath: dir) {
			dir = (dir as NSString).deletingLastPathComponent
		}
		var env = Base.tools()
		func git(_ args: [String]) -> (code: Int32, out: String) {
			let found = Base.run("/usr/bin/git", ["-C", dir] + args, env: env)
			return (found.code, found.out.trimmingCharacters(in: .whitespacesAndNewlines))
		}
		let store = git(["rev-parse", "--absolute-git-dir"])
		guard store.code == 0 else { return }
		let ref = "refs/slyed/" + sid
		var parent = git(["rev-parse", "-q", "--verify", ref + "^{commit}"])
		if parent.code != 0 {
			parent = git(["rev-parse", "-q", "--verify", "HEAD^{commit}"])
		}
		let index = store.out + "/slyed/" + sid + ".index"
		try? fm.createDirectory(atPath: store.out + "/slyed", withIntermediateDirectories: true)
		env["GIT_INDEX_FILE"] = index
		if !fm.fileExists(atPath: index), parent.code == 0 {
			guard git(["read-tree", parent.out]).code == 0 else { return }
		}
		_ = git(["add", "-A", "--", path])
		let tree = git(["write-tree"])
		guard tree.code == 0 else { return }
		if parent.code == 0, git(["rev-parse", parent.out + "^{tree}"]).out == tree.out { return }
		let said = why.map { $0.isEmpty ? (path as NSString).lastPathComponent : $0 } ?? "base"
		let made = git(["commit-tree", tree.out] + (parent.code == 0 ? ["-p", parent.out] : []) + ["-m", said])
		guard made.code == 0 else {
			_ = Base.fail("slybar guard: no snapshot of \(path) on \(ref), git commit-tree failed, the repository may have no user.name and user.email")
			return
		}
		_ = git(["update-ref", ref, made.out])
	}

	static func off() -> Bool {
		if let set = Base.env["SLYCBAR_PLAN"] {
			return set == "off"
		}
		return Base.read(Base.here + "/.env").split(separator: "\n").contains { $0.trimmingCharacters(in: .whitespaces) == "SLYCBAR_PLAN=off" }
	}

	static func gate(_ sid: String) -> String? {
		guard !sid.isEmpty, !off() else { return nil }
		let fm = FileManager.default
		let path = Base.json(index)[sid] as? String ?? ""
		let plan = path.isEmpty ? [:] : Base.json(path)
		let changes = plan["changes"] as? [Json] ?? []
		guard !changes.isEmpty else {
			if fm.fileExists(atPath: told(sid)) {
				try? fm.removeItem(atPath: told(sid))
				return nil
			}
			Base.write(told(sid), "")
			return "slycbar: this plan was not put up for review. Present the intended changes as their proposed file contents with the slycbar review_open tool, or slybar review - with the plan on stdin, then wait with review_wait or slybar review <plan> wait, revise on the feedback, and call ExitPlanMode once every change is accepted. A plan that changes no file calls ExitPlanMode again."
		}
		let marks = changes.map { $0["status"] as? String ?? "pending" }
		let state = plan["state"] as? String ?? "open"
		if state == "approved" || marks.allSatisfy({ $0 == "accepted" }) {
			Base.edit(index) { $0[sid] = nil }
			return nil
		}
		let accepted = marks.filter { $0 == "accepted" }.count
		let rejected = marks.filter { $0 == "rejected" }.count
		return "slycbar: the review of \(plan["title"] as? String ?? "the plan") at \(path) is \(state), round \(plan["round"] as? Int ?? 1): \(accepted) accepted, \(rejected) rejected, \(marks.count - accepted - rejected) pending. Wait for it with review_wait or slybar review \(path) wait, read the feedback with review_status, revise with review_open and this plan path, and call ExitPlanMode once every change is accepted."
	}

	static let guide = "slycbar puts a plan of real file changes before the user in Slyed, the slycbar editor. In plan mode, present the intended changes as their full proposed file contents with review_open, never as prose alone: one change per file, in the order the work is done, with title, why, the absolute target path and the contents. Slyed numbers the changes 1, 2, 3 and splits each into its diff hunks, numbered 2.1, 2.2 within change 2; write the why of a change as a numbered list with one line per hunk in file order, and use these numbers whenever you refer to a change. Slyed shows every hunk of every file in one diff, and the user accepts or rejects each hunk, with or without a comment. Call review_wait right after review_open, in the same turn, and call it again when it returns with waited set: nothing comes back until the user has decided every hunk. The result holds, in each change's comments, one entry per hunk in file order with side, line, end, status accepted or rejected, and text when the user commented. When the state is sent, revise the plan as a whole on those entries and call review_open again with the same plan path and every change; a change whose contents did not change keeps its verdicts. When the state is approved, every hunk is accepted: apply exactly that and do not open the review again. Call ExitPlanMode only then; a hook refuses it before."

	static let tools: [Json] = [
		["name": "review_open", "description": "Put a plan of proposed file changes up for review in Slyed, or revise one. Each change carries the full proposed file contents; slycbar writes them beside the plan file and never touches the target. With plan and no changes it opens that plan again. Returns the plan path and its status.",
			"inputSchema": ["type": "object", "properties": [
				"plan": ["type": "string", "description": "Absolute path of the plan file. Omit for a new plan; pass it to revise a plan."],
				"title": ["type": "string", "description": "What the plan does, one line."],
				"changes": ["type": "array", "description": "One entry per file, in the order the work is done. Slyed numbers them from 1 and their hunks 1.1, 1.2.", "items": ["type": "object", "properties": [
					"title": ["type": "string"], "why": ["type": "string", "description": "A numbered list, one line per hunk of this file in file order."], "path": ["type": "string", "description": "Absolute path of the target file."],
					"contents": ["type": "string", "description": "The full proposed contents of the file."], "proposed": ["type": "string", "description": "Absolute path of a file that already holds the proposed contents, instead of contents."],
					"base": ["type": "string", "description": "Absolute path of the left side when it is not the target's current contents."],
					"comments": ["type": "array", "description": "The change's comments with an answer field filled for each question; omit to keep them."]] as Json, "required": ["path"]] as Json],
				"comments": ["type": "array", "description": "Plan wide comments with answers; omit to keep them."]] as Json] as Json],
		["name": "review_status", "description": "Read a review: state (open, sent, revising, approved), round, every change with its status and comments, and the plan wide comments. Questions carry question true.",
			"inputSchema": ["type": "object", "properties": ["plan": ["type": "string", "description": "Absolute path of the plan file."]] as Json, "required": ["plan"]] as Json,
			"annotations": ["readOnlyHint": true]],
		["name": "review_wait", "description": "Wait until the user has decided every hunk in Slyed, state sent or approved, then return the review: each change with its status and one comment entry per hunk carrying side, line, end, status and text. Returns after seconds with waited set when the user is not done; call it again.",
			"inputSchema": ["type": "object", "properties": ["plan": ["type": "string", "description": "Absolute path of the plan file."], "seconds": ["type": "integer", "description": "How long to wait, 600 by default, at most 3600."]] as Json, "required": ["plan"]] as Json,
			"annotations": ["readOnlyHint": true]],
	]

	static func call(_ name: String, _ args: Json) -> (String, Bool) {
		let plan = args["plan"] as? String ?? ""
		switch name {
		case "review_open":
			var given: Json?
			if let changes = args["changes"] as? [Json], !changes.isEmpty {
				var built: Json = ["changes": changes]
				for key in ["title", "comments"] where args[key] != nil {
					built[key] = args[key]
				}
				if !plan.isEmpty {
					var old = Base.json(absolute(plan))
					old["changes"] = nil
					old["comments"] = nil
					old["round"] = nil
					built.merge(old) { mine, _ in mine }
				}
				given = built
			} else if plan.isEmpty {
				return ("review_open needs changes, or the plan path of an existing plan", true)
			}
			let (found, failed) = open(given, plan)
			if let failed { return (failed, true) }
			return (Base.text(found ?? [:], pretty: true), false)
		case "review_status":
			guard FileManager.default.fileExists(atPath: absolute(plan)) else { return ("no plan at \(plan)", true) }
			return (Base.text(status(absolute(plan)), pretty: true), false)
		case "review_wait":
			guard FileManager.default.fileExists(atPath: absolute(plan)) else { return ("no plan at \(plan)", true) }
			return (Base.text(wait(absolute(plan), args["seconds"] as? Int ?? 600), pretty: true), false)
		default:
			return ("unknown tool \(name)", true)
		}
	}

	static func mcp() -> Int32 {
		let lock = NSLock()
		let send = { (message: Json) in
			var body = message
			body["jsonrpc"] = "2.0"
			lock.lock()
			FileHandle.standardOutput.write(Data((Base.text(body) + "\n").utf8))
			lock.unlock()
		}
		let group = DispatchGroup()
		while let line = readLine() {
			guard let message = Base.parse(line), let method = message["method"] as? String, let id = message["id"] else { continue }
			let params = message["params"] as? Json ?? [:]
			switch method {
			case "initialize":
				send(["id": id, "result": ["protocolVersion": params["protocolVersion"] as? String ?? "2025-06-18", "capabilities": ["tools": [:] as Json], "serverInfo": ["name": "slycbar", "version": Tools.version()], "instructions": guide] as Json])
			case "ping":
				send(["id": id, "result": [:] as Json])
			case "tools/list":
				send(["id": id, "result": ["tools": tools]])
			case "tools/call":
				group.enter()
				DispatchQueue.global().async {
					let (text, failed) = call(params["name"] as? String ?? "", params["arguments"] as? Json ?? [:])
					send(["id": id, "result": ["content": [["type": "text", "text": text]], "isError": failed] as Json])
					group.leave()
				}
			default:
				send(["id": id, "error": ["code": -32601, "message": "Method not found"] as Json])
			}
		}
		group.wait()
		return 0
	}

	static func compare(_ args: [String]) -> Int32 {
		guard args.count == 2 else { return Base.fail("usage: slybar compare <path> <path>", 2) }
		let paths = args.map { $0.hasPrefix("/") ? $0 : FileManager.default.currentDirectoryPath + "/" + $0 }
		for path in paths where !FileManager.default.fileExists(atPath: path) {
			return Base.fail("no file at \(path)")
		}
		guard FileManager.default.fileExists(atPath: Base.editApp) else { return Base.fail("Slyed is not installed, run slybar install") }
		var allowed = CharacterSet.alphanumerics
		allowed.insert(charactersIn: "-_.~")
		let a = paths[0].addingPercentEncoding(withAllowedCharacters: allowed) ?? paths[0]
		let b = paths[1].addingPercentEncoding(withAllowedCharacters: allowed) ?? paths[1]
		return Base.run("/usr/bin/open", ["slyed://compare?a=" + a + "&b=" + b]).code
	}
}
