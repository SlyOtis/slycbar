import Foundation

enum Warp {
	static func lines(_ files: [String], _ budget: Int) -> [Json] {
		var found: [Json] = []
		var used = 0
		let newline = UInt8(ascii: "\n")
		for file in files {
			guard let data = try? Data(contentsOf: URL(fileURLWithPath: file), options: .mappedIfSafe) else { continue }
			var from = data.startIndex
			while from < data.endIndex, used < budget {
				let to = data[from...].firstIndex(of: newline) ?? data.endIndex
				let line = data[from..<to]
				from = to < data.endIndex ? to + 1 : to
				guard let raw = String(data: line, encoding: .utf8) else { continue }
				guard raw.contains("\"type\":\"user\"") || raw.contains("\"type\":\"assistant\"") else { continue }
				if raw.contains("\"type\":\"tool_result\"") || raw.contains("\"type\":\"tool_use\"") || raw.contains("\"type\":\"thinking\"") { continue }
				guard let entry = Base.parse(raw), let role = entry["type"] as? String, role == "user" || role == "assistant" else { continue }
				let content = (entry["message"] as? Json)?["content"]
				var text = content as? String ?? (content as? [Json] ?? []).filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: " ")
				if text.isEmpty || text.hasPrefix("<") || text.hasPrefix("[Request interrupted") || text.contains("hit your session limit")
					|| text.hasPrefix("Base directory for this skill") || text.hasPrefix("Stop hook feedback") { continue }
				text = text.replacingOccurrences(of: "\\[Image[^\\]]*\\]", with: "", options: .regularExpression)
					.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
				if text.hasPrefix(" ") {
					text.removeFirst()
				}
				guard text.count > 1 else { continue }
				if used + text.count <= budget {
					found.append(["role": role, "text": text])
					used += text.count
				} else {
					found.append(["role": role, "text": String(text.prefix(budget - used)) + "… to be continued"])
					used = budget
				}
			}
			if used >= budget {
				break
			}
		}
		return found
	}

	static func warp(_ mail: String, _ display: String) -> Int32 {
		let fm = FileManager.default
		let email = mail.isEmpty ? Accounts.active() : mail
		let desktop = Base.tray + "/desktop.jpg"
		try? fm.removeItem(atPath: desktop)
		Base.run("/usr/sbin/screencapture", ["-x", "-D", display, "-t", "jpg", desktop])
		let audio = ["mp3", "m4a", "aac", "wav"].map { Base.tray + "/warp." + $0 }.first { fm.fileExists(atPath: $0) } ?? ""
		var cap = 328.0
		if !audio.isEmpty {
			for line in Base.run("/usr/bin/afinfo", [audio]).out.split(separator: "\n") where line.hasPrefix("estimated duration: ") {
				cap = Double(Int(Double(line.dropFirst(20).split(separator: " ").first ?? "") ?? 328))
			}
		}
		var groups: [(at: Double, weight: Double, files: [String], cwd: String)] = []
		let root = Base.claude + "/projects"
		for name in ((try? fm.contentsOfDirectory(atPath: root)) ?? []).sorted() {
			let dir = root + "/" + name
			var files: [(born: Double, size: Double, path: String)] = []
			for file in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where file.hasSuffix(".jsonl") {
				let attributes = try? fm.attributesOfItem(atPath: dir + "/" + file)
				files.append(((attributes?[.creationDate] as? Date)?.timeIntervalSince1970 ?? 0, (attributes?[.size] as? NSNumber)?.doubleValue ?? 0, dir + "/" + file))
			}
			files.sort { $0.born < $1.born }
			guard !files.isEmpty else { continue }
			var cwd = ""
			for file in files where cwd.isEmpty {
				guard let handle = FileHandle(forReadingAtPath: file.path) else { continue }
				let head = String(decoding: handle.readData(ofLength: 262144), as: UTF8.self)
				handle.closeFile()
				if let from = head.range(of: "\"cwd\":\""), let to = head[from.upperBound...].firstIndex(of: "\"") {
					cwd = String(head[from.upperBound..<to])
				}
			}
			let size = files.reduce(0) { $0 + $1.size }
			let weight = Double(Int(min(90, max(12, 6 + 9 * log(1 + size / 1048576))) * 100))
			groups.append((files[0].born, weight, files.map { $0.path }, cwd))
		}
		var kept: [(at: Double, weight: Double, files: [String], cwd: String)] = []
		var sum = 0.0
		for group in groups.sorted(by: { $0.weight > $1.weight }) {
			if cap * group.weight / (sum + group.weight) < 20 {
				break
			}
			sum += group.weight
			kept.append(group)
		}
		var projects: [Json] = []
		for group in kept.sorted(by: { $0.at < $1.at }) {
			let budget = max(40, Int((cap * group.weight / sum - 6) * 14))
			let top = Base.run("/usr/bin/git", ["-C", group.cwd, "rev-parse", "--show-toplevel"])
			let title = ((top.code == 0 ? top.out.trimmingCharacters(in: .whitespacesAndNewlines) : group.cwd) as NSString).lastPathComponent
			let found = lines(group.files, budget)
			guard !found.isEmpty else { continue }
			let length = found.reduce(0) { $0 + (($1["text"] as? String)?.count ?? 0) }
			projects.append(["title": title, "dir": group.cwd, "at": Int(group.at), "lines": found, "seconds": Int(Double(length) / 14 + 6)])
		}
		let estimate = audio.isEmpty ? projects.reduce(0) { $0 + ($1["seconds"] as? Int ?? 0) } : Int(cap)
		Base.say(Base.text(["email": email, "name": Accounts.name(email), "audio": audio, "cap": Int(cap), "estimate": estimate,
			"desktop": fm.fileExists(atPath: desktop) ? desktop : "", "projects": projects] as Json))
		return 0
	}

	static func impact(_ display: String) -> Int32 {
		let fm = FileManager.default
		let desktop = Base.tray + "/desktop.jpg"
		let fill = display == "fill"
		let busy = Base.cache + "/impact.lock"
		if fill {
			if Base.now - Base.modified(busy) > 900 {
				try? fm.removeItem(atPath: busy)
			}
			guard (try? fm.createDirectory(atPath: busy, withIntermediateDirectories: false)) != nil else { return 0 }
		} else if display != "live" {
			try? fm.removeItem(atPath: desktop)
			Base.run("/usr/sbin/screencapture", ["-x", "-D", display, "-t", "jpg", desktop])
		}
		let store = Base.cache + "/impact.json"
		var known = Base.json(store)
		let root = Base.claude + "/projects"
		var files: [(changed: Double, size: Int, path: String)] = []
		var since = Base.now
		if let walk = fm.enumerator(atPath: root) {
			for case let name as String in walk where name.hasSuffix(".jsonl") {
				let attributes = try? fm.attributesOfItem(atPath: root + "/" + name)
				since = min(since, (attributes?[.creationDate] as? Date)?.timeIntervalSince1970 ?? since)
				files.append(((attributes?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0, (attributes?[.size] as? NSNumber)?.intValue ?? 0, root + "/" + name))
			}
		}
		files.sort { $0.changed > $1.changed }
		let keys = ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"]
		let counted = try? NSRegularExpression(pattern: "\"(" + keys.joined(separator: "|") + ")\":(\\d+)")
		let named = try? NSRegularExpression(pattern: "\"id\":\"(msg_[^\"]+)\"")
		let needle = Data("\"output_tokens\"".utf8)
		let newline = UInt8(ascii: "\n")
		let end = fill ? Double.infinity : Base.now + 6
		var left = 0
		var sum = [String: Double]()
		for file in files {
			let stamp = "\(file.size) \(Int(file.changed))"
			var entry = known[file.path] as? Json ?? [:]
			if entry["stamp"] as? String != stamp {
				guard Base.now < end, let data = try? Data(contentsOf: URL(fileURLWithPath: file.path), options: .mappedIfSafe) else {
					left += 1
					continue
				}
				var seen = Set<String>()
				var found = [String: Double]()
				var from = data.startIndex
				while from < data.endIndex {
					let to = data[from...].firstIndex(of: newline) ?? data.endIndex
					let line = data[from..<to]
					from = to < data.endIndex ? to + 1 : to
					guard line.range(of: needle) != nil, let raw = String(data: line, encoding: .utf8), raw.contains("\"type\":\"assistant\"") else { continue }
					let whole = NSRange(raw.startIndex..., in: raw)
					if let hit = named?.firstMatch(in: raw, range: whole), let range = Range(hit.range(at: 1), in: raw), !seen.insert(String(raw[range])).inserted { continue }
					var taken = Set<String>()
					for hit in counted?.matches(in: raw, range: whole) ?? [] {
						guard let key = Range(hit.range(at: 1), in: raw), let value = Range(hit.range(at: 2), in: raw), taken.insert(String(raw[key])).inserted else { continue }
						found[String(raw[key]), default: 0] += Double(raw[value]) ?? 0
					}
				}
				entry = ["stamp": stamp]
				for key in keys {
					entry[key] = found[key] ?? 0
				}
				known[file.path] = entry
			}
			for key in keys {
				sum[key, default: 0] += (entry[key] as? NSNumber)?.doubleValue ?? 0
			}
		}
		let live = Set(files.map { $0.path })
		Base.write(store, Base.text(known.filter { live.contains($0.key) }))
		if fill {
			try? fm.removeItem(atPath: busy)
			return 0
		}
		if left > 0 {
			let rest = Process()
			rest.executableURL = URL(fileURLWithPath: Bundle.main.executablePath ?? CommandLine.arguments[0])
			rest.arguments = ["impact", "fill"]
			rest.standardOutput = FileHandle.nullDevice
			rest.standardError = FileHandle.nullDevice
			try? rest.run()
		}
		let audio = ["mp3", "m4a", "aac", "wav"].map { Base.tray + "/impact." + $0 }.first { fm.fileExists(atPath: $0) } ?? ""
		Base.say(Base.text(["name": Accounts.name(Accounts.active()), "desktop": fm.fileExists(atPath: desktop) ? desktop : "", "audio": audio, "faces": ((try? fm.contentsOfDirectory(atPath: Base.tray + "/faces")) ?? []).filter { $0.hasSuffix(".jpg") || $0.hasSuffix(".png") }.sorted().map { Base.tray + "/faces/" + $0 }, "since": Int(since), "logs": files.count, "left": left,
			"input": sum["input_tokens"] ?? 0, "write": sum["cache_creation_input_tokens"] ?? 0, "read": sum["cache_read_input_tokens"] ?? 0, "output": sum["output_tokens"] ?? 0] as Json))
		return 0
	}

	static func changes(_ target: String, _ display: String) -> Int32 {
		let fm = FileManager.default
		var isDir: ObjCBool = false
		guard fm.fileExists(atPath: target, isDirectory: &isDir) else { return Base.fail("no file at \(target)") }
		let dir = isDir.boolValue ? target : (target as NSString).deletingLastPathComponent
		let found = Base.run("/usr/bin/git", ["-C", dir, "rev-parse", "--show-toplevel"])
		guard found.code == 0 else { return Base.fail("\(target) is in no git repository") }
		let top = found.out.trimmingCharacters(in: .whitespacesAndNewlines)
		let scope = isDir.boolValue ? [] : ["--follow", "--", target]
		let me = Base.run("/usr/bin/git", ["-C", top, "config", "user.email"]).out.trimmingCharacters(in: .whitespacesAndNewlines)
		let desktop = Base.tray + "/desktop.jpg"
		try? fm.removeItem(atPath: desktop)
		Base.run("/usr/sbin/screencapture", ["-x", "-D", display, "-t", "jpg", desktop])
		let audio = ["mp3", "m4a", "aac", "wav"].map { Base.tray + "/warp." + $0 }.first { fm.fileExists(atPath: $0) } ?? ""
		var projects: [Json] = []
		func episode(_ title: String, _ lines: [Json]) {
			guard !lines.isEmpty else { return }
			let length = lines.reduce(0) { $0 + (($1["text"] as? String)?.count ?? 0) }
			projects.append(["title": title, "dir": top, "at": Int(Base.now), "lines": lines, "seconds": Int(Double(length) / 14 + 6)])
		}
		var day = ""
		var lines: [Json] = []
		let log = Base.run("/usr/bin/git", ["-C", top, "log", "-n", "40", "--reverse", "--shortstat", "--format=%x01%ad%x09%an%x09%ae%x09%s%x09%(trailers:key=Co-Authored-By,valueonly,separator=%x2C )", "--date=format:%A %e %B"] + scope).out
		for entry in log.split(separator: "\u{01}") {
			let rows = entry.split(separator: "\n", omittingEmptySubsequences: true).map(String.init)
			guard let head = rows.first else { continue }
			let f = head.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
			guard f.count >= 4 else { continue }
			if f[0] != day {
				episode(day, lines)
				day = f[0]
				lines = []
			}
			let with = f.count > 4 && !f[4].isEmpty ? " with " + f[4].replacingOccurrences(of: " <[^>]*>", with: "", options: .regularExpression) : ""
			let stat = rows.dropFirst().first { $0.contains("changed") }?.trimmingCharacters(in: .whitespaces) ?? ""
			lines.append(["role": f[2] == me && with.isEmpty ? "user" : "assistant", "text": f[1] + with + ": " + f[3] + (stat.isEmpty ? "" : " · " + stat)])
		}
		episode(day, lines)
		var open: [Json] = []
		for line in Base.run("/usr/bin/git", ["-C", top, "diff", "--numstat", "HEAD"] + (isDir.boolValue ? [] : ["--", target])).out.split(separator: "\n").prefix(12) {
			let f = line.split(separator: "\t", maxSplits: 2).map(String.init)
			guard f.count == 3 else { continue }
			open.append(["role": "user", "text": (f[2] as NSString).lastPathComponent + ": " + f[0] + " lines added, " + f[1] + " removed, not committed yet"])
		}
		episode("Still on the bench", open)
		guard !projects.isEmpty else { return Base.fail("no history for \(target)") }
		let estimate = projects.reduce(0) { $0 + ($1["seconds"] as? Int ?? 0) }
		Base.say(Base.text(["email": me, "name": (top as NSString).lastPathComponent, "audio": audio, "cap": estimate, "estimate": estimate,
			"desktop": fm.fileExists(atPath: desktop) ? desktop : "", "projects": projects] as Json))
		return 0
	}
}
