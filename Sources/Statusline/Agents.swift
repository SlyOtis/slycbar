import Foundation

extension Bar {
	func clock(_ secs: Double) -> String {
		let s = secs.rounded(.down)
		if s >= 3600 {
			return "\(Jq.num((s / 3600).rounded(.down)))h \(Jq.num((Double(Int64(s) % 3600) / 60).rounded(.down)))m"
		}
		if s >= 60 {
			return "\(Jq.num((s / 60).rounded(.down)))m \(Int64(s) % 60)s"
		}
		return "\(Jq.num(s))s"
	}

	func tokens(_ v: Any?, _ n: Double) -> String {
		if n >= 1e9 {
			return Jq.num((n / 1e8).rounded(.down) / 10) + "G"
		}
		if n >= 1e6 {
			return Jq.num((n / 1e5).rounded(.down) / 10) + "M"
		}
		if n >= 1e3 {
			return Jq.num((n / 1e2).rounded(.down) / 10) + "k"
		}
		return Jq.json(v)
	}

	func parts(_ task: NSDictionary, _ now: Double?) throws -> [Any?] {
		var parts: [Any?] = []
		parts.append(Jq.truthy(task["agentType"]) ? task["agentType"] : Jq.truthy(task["name"]) ? task["name"] : "agent")
		let label = task["label"]
		let about = task["description"]
		let same = (label as? NSObject)?.isEqual(about) ?? false
		let pick = Jq.truthy(label) && !same ? label : about
		parts.append(Jq.truthy(pick) ? pick : "")
		if Jq.truthy(task["startTime"]) {
			guard let now, let at = Jq.number(task["startTime"]) else {
				throw Jq.Bad()
			}
			parts.append(clock(now - at / 1000))
		}
		if Jq.truthy(task["tokenCount"]) {
			guard let n = Jq.number(task["tokenCount"]) else {
				throw Jq.Bad()
			}
			var text = tokens(task["tokenCount"], n) + " tok"
			if Jq.truthy(task["contextWindowSize"]) {
				guard let size = Jq.number(task["contextWindowSize"]), size != 0 else {
					throw Jq.Bad()
				}
				text += " \(Jq.num((n * 100 / size).rounded(.down)))%"
			}
			parts.append(text)
		}
		if Jq.truthy(task["model"]) {
			guard let model = task["model"] as? String else {
				throw Jq.Bad()
			}
			parts.append(model.hasPrefix("claude-") ? String(model.dropFirst(7)) : model)
		}
		if Jq.truthy(task["effort"]) {
			parts.append(Jq.text(task["effort"]))
		}
		if task["status"] as? String != "running" {
			parts.append(task["status"])
		}
		return parts
	}

	func agents() -> [UInt8] {
		let root = Jq.parse(input)
		let map = root as? NSDictionary
		let sid = Jq.truthy(map?["session_id"]) ? Jq.text(map?["session_id"]) : ""
		if !sid.isEmpty && (try? FileManager.default.createDirectory(atPath: cache + "/sessions", withIntermediateDirectories: true)) != nil {
			let path = cache + "/sessions/" + sid + ".agents.json"
			if Sys.put(path + "." + tag, input + [10]) {
				rename(path + "." + tag, path)
			}
		}
		guard let map else {
			return []
		}
		var now: Double? = Date().timeIntervalSince1970
		if !get("SLYCBAR_NOW").isEmpty {
			guard let set = Jq.parse(Array(get("SLYCBAR_NOW").utf8)) else {
				return []
			}
			if Jq.truthy(set) {
				now = Jq.number(set)
			}
		}
		let cols = Jq.truthy(map["columns"]) ? Jq.number(map["columns"]) : 120
		let esc = "\u{1b}"
		let dot = " · "
		let dim = esc + "[2m" + dot + esc + "[22m"
		var out = ""
		let tasks = map["tasks"]
		for item in (tasks as? [Any]) ?? (tasks as? NSDictionary)?.allValues ?? [] {
			guard let task = item is NSNull ? NSDictionary() : item as? NSDictionary, let parts = try? parts(task, now) else {
				break
			}
			var text: [String] = []
			for part in parts {
				if part is [Any] || part is NSDictionary {
					return Array(out.utf8)
				}
				text.append(part == nil || part is NSNull ? "" : Jq.text(part))
			}
			var all = Array(text.joined(separator: dot).unicodeScalars)
			if let cols, Double(all.count) > cols {
				var end = Int((cols - 1).rounded(.up))
				if end < 0 {
					end += all.count
				}
				all = Array(all[0..<min(max(end, 0), all.count)]) + Array("…".unicodeScalars)
			}
			var fit = String.UnicodeScalarView()
			fit.append(contentsOf: all)
			var pieces: [String] = []
			let bytes = Array(String(fit).utf8)
			let mark = Array(dot.utf8)
			var at = 0
			while let hit = bytes.find(mark, at) {
				pieces.append(bytes[at..<hit].text)
				at = hit + mark.count
			}
			if !bytes.isEmpty {
				pieces.append(bytes[at...].text)
			}
			var content = esc + "[1m" + (pieces.first ?? "") + esc + "[22m"
			if pieces.count > 1 {
				content += dim + pieces[1...].joined(separator: dim)
			}
			out += "{\"id\":\(Jq.json(task["id"])),\"content\":\(Jq.quote(content))}\n"
		}
		return Array(out.utf8)
	}
}
