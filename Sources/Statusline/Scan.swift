import Foundation

struct Tally {
	static let first = ["\"output_tokens\"", "\"type\":\"permission-mode\"", "<task-notification>", "running in background with ID: ", "moved to the background (ID: ", "Successfully stopped task: "].map { Array($0.utf8) }
	static let second = ["\"type\":\"assistant\"", "\"type\":\"user\"", "\"type\":\"queue-operation\"", "\"type\":\"permission-mode\""].map { Array($0.utf8) }

	let main: String
	var ids: [String] = []
	var tin: [String: Double] = [:]
	var tout: [String: Double] = [:]
	var order: [String] = []
	var kind: [String: String] = [:]
	var lts: [String: String] = [:]
	var st: [String: String] = [:]
	var sts: [String: String] = [:]
	var file = ""
	var mode = ""
	var carry: [UInt8] = []

	init(_ base: String, _ main: String) {
		self.main = main
		for line in (Sys.read(base + ".ids") ?? []).split(10) where !line.isEmpty {
			let c = line.split(9).map { $0.text }
			ids.append(c[0])
			tin[c[0]] = c.count > 1 ? strtod(c[1], nil) : 0
			tout[c[0]] = c.count > 2 ? strtod(c[2], nil) : 0
		}
		for line in (Sys.read(base + ".tasks") ?? []).split(10) where !line.isEmpty {
			let c = line.split(9).map { $0.text } + ["", "", "", ""]
			order.append(c[0])
			kind[c[0]] = c[1]
			lts[c[0]] = c[2]
			st[c[0]] = c[3]
			sts[c[0]] = c[4]
		}
	}

	static func less(_ a: String, _ b: String) -> Bool {
		a.utf8.lexicographicallyPrecedes(b.utf8)
	}

	static func word(_ b: UInt8) -> Bool {
		(b >= 97 && b <= 122) || (b >= 48 && b <= 57)
	}

	static func named(_ b: [UInt8], _ lead: String, _ tail: String) -> [String] {
		let lead = Array(lead.utf8)
		let tail = Array(tail.utf8)
		var out: [String] = []
		var at = 0
		while let i = b.find(lead, at) {
			var j = i + lead.count
			while j < b.count && word(b[j]) {
				j += 1
			}
			if j > i + lead.count && b[j...].starts(with: tail) {
				out.append(b[(i + lead.count)..<j].text)
				at = j + tail.count
			} else {
				at = i + 1
			}
		}
		return out
	}

	static func noted(_ b: [UInt8]) -> [(id: String, status: String)] {
		let a = Array("<task-id>".utf8)
		let z = Array("</task-id>".utf8)
		let s = Array("<status>".utf8)
		let e = Array("</status>".utf8)
		var out: [(id: String, status: String)] = []
		var at = 0
		while let i = b.find(a, at) {
			at = i + 1
			let from = i + a.count
			var j = from
			while j < b.count && b[j] != 60 {
				j += 1
			}
			guard j > from, b[j...].starts(with: z) else {
				continue
			}
			var k = j + z.count
			while let m = b.find(s, k) {
				let open = m + s.count
				var n = open
				while n < b.count && b[n] != 60 {
					n += 1
				}
				if n > open && b[n...].starts(with: e) {
					out.append((b[from..<j].text, b[open..<n].text))
					at = n + e.count
					break
				}
				k = m + 1
			}
		}
		return out
	}

	mutating func feed(_ p: UnsafeRawBufferPointer) {
		guard let base = p.baseAddress else {
			return
		}
		var at = 0
		while at < p.count {
			guard let hit = memchr(base + at, 10, p.count - at) else {
				carry.append(contentsOf: UnsafeRawBufferPointer(rebasing: p[at...]))
				return
			}
			let end = base.distance(to: UnsafeRawPointer(hit))
			if carry.isEmpty {
				line(UnsafeRawBufferPointer(rebasing: p[at..<end]))
			} else {
				carry.append(contentsOf: UnsafeRawBufferPointer(rebasing: p[at..<end]))
				flush()
			}
			at = end + 1
		}
	}

	mutating func flush() {
		let whole = carry
		carry = []
		whole.withUnsafeBytes { line($0) }
	}

	mutating func line(_ p: UnsafeRawBufferPointer) {
		guard Tally.first.contains(where: { p.find($0) != nil }), Tally.second.contains(where: { p.find($0) != nil }) else {
			return
		}
		if let o = Jq.parse([UInt8](p)) as? NSDictionary {
			take(o)
		}
	}

	mutating func take(_ o: NSDictionary) {
		if Jq.truthy(o["slycbar_file"]) {
			file = Jq.text(o["slycbar_file"])
			return
		}
		let type = o["type"] as? String
		if type == "permission-mode" {
			let m = Jq.truthy(o["permissionMode"]) ? Jq.text(o["permissionMode"]) : ""
			if file == main && !m.isEmpty {
				mode = m
			}
			return
		}
		if type == "assistant" {
			guard let m = o["message"] as? NSDictionary, Jq.truthy(m["id"]), let u = m["usage"] as? NSDictionary else {
				return
			}
			var all: [Double] = []
			for key in ["input_tokens", "cache_creation_input_tokens", "cache_read_input_tokens", "output_tokens"] {
				if !Jq.truthy(u[key]) {
					all.append(0)
				} else if let n = Jq.number(u[key]) {
					all.append(n)
				} else {
					return
				}
			}
			let id = Jq.text(m["id"])
			if let was = tout[id] {
				if all[3] > was {
					tout[id] = all[3]
				}
			} else {
				ids.append(id)
				tin[id] = all[0] + all[1] + all[2]
				tout[id] = all[3]
			}
			return
		}
		let ts = Jq.truthy(o["timestamp"]) ? Jq.text(o["timestamp"]) : ""
		var c = ""
		if type == "user" {
			if let m = o["message"], !(m is NSNull) {
				guard let m = m as? NSDictionary else {
					return
				}
				c = Jq.text(m["content"])
			} else {
				c = "null"
			}
		} else if o["operation"] as? String == "enqueue" {
			c = Jq.truthy(o["content"]) ? Jq.text(o["content"]) : ""
		}
		let b = Array(c.utf8)
		for id in Tally.named(b, "running in background with ID: ", "") + Tally.named(b, "moved to the background (ID: ", ")") {
			if kind[id] == nil {
				order.append(id)
				kind[id] = "shell"
				lts[id] = ts
			} else if kind[id] == "" || Tally.less(ts, lts[id] ?? "") {
				kind[id] = "shell"
				lts[id] = ts
			}
		}
		let stopped = Tally.named(b, "Successfully stopped task: ", "").map { (id: $0, status: "stopped") }
		for note in stopped + Tally.noted(b) {
			if kind[note.id] == nil {
				order.append(note.id)
				kind[note.id] = ""
			}
			if !Tally.less(ts, sts[note.id] ?? "") {
				st[note.id] = note.status
				sts[note.id] = ts
			}
		}
	}

	func write(_ base: String, _ tag: String) -> String {
		if !mode.isEmpty {
			Sys.swap(base + ".mode", mode, tag)
		}
		var a = 0.0
		var b = 0.0
		for id in ids {
			a += tin[id] ?? 0
			b += tout[id] ?? 0
		}
		if !ids.isEmpty {
			Sys.swap(base + ".ids", ids.map { "\($0)\t\(Jq.num(tin[$0] ?? 0))\t\(Jq.num(tout[$0] ?? 0))\n" }.joined(), tag)
		}
		if !order.isEmpty {
			Sys.swap(base + ".tasks", order.map { "\($0)\t\(kind[$0] ?? "")\t\(lts[$0] ?? "")\t\(st[$0] ?? "")\t\(sts[$0] ?? "")\n" }.joined(), tag)
		}
		return String(format: "%.0f %.0f", a, b)
	}
}

extension Bar {
	func count(_ tp: String, _ base: String) {
		_ = Sys.put(base + ".lock", Array(tag.utf8))
		_ = scan(tp, base, 0)
	}

	func ended(_ path: String, _ size: Int) -> Bool {
		let fd = open(path, O_RDONLY)
		guard fd >= 0 else {
			return true
		}
		defer { close(fd) }
		var byte: UInt8 = 0
		return pread(fd, &byte, 1, off_t(max(size - 1, 0))) != 1 || byte == 10 || byte == 0
	}

	func scan(_ tp: String, _ base: String, _ limit: Int) -> (code: Int32, sum: String) {
		let dir = (tp.hasSuffix(".jsonl") ? String(tp.dropLast(6)) : tp) + "/subagents/"
		let files = [tp] + Sys.names(dir, "", ".jsonl").map { dir + $0 }.filter { Sys.file($0) }
		var old: [String: Int] = [:]
		for line in (Sys.read(base + ".tsv") ?? []).split(10) where !line.isEmpty {
			let c = line.split(9).map { $0.text }
			old[c[0]] = c.count > 1 ? Int(c[1]) ?? 0 : 0
		}
		var todo: [(path: String, off: Int)] = []
		var saved = ""
		var pending = 0
		for path in files {
			guard var size = Sys.info(path)?.size else {
				continue
			}
			var off = old[path] ?? 0
			if off > size {
				off = 0
			}
			if off != size {
				todo.append((path, off))
				pending += size - off
				if !ended(path, size) {
					size = off
				}
			}
			saved += "\(path)\t\(size)\n"
		}
		if todo.isEmpty && Sys.file(base + ".sum") {
			return (0, Sys.text(base + ".sum"))
		}
		if limit > 0 && pending > limit {
			return (2, "")
		}
		var tally = Tally(base, Sys.leaf(tp))
		var buf = [UInt8](repeating: 0, count: 1 << 20)
		for item in todo {
			Array("{\"type\":\"permission-mode\",\"slycbar_file\":\"\(Sys.leaf(item.path))\"}\n".utf8).withUnsafeBytes { tally.feed($0) }
			let fd = open(item.path, O_RDONLY)
			guard fd >= 0 else {
				continue
			}
			lseek(fd, off_t(item.off), SEEK_SET)
			while true {
				let n = read(fd, &buf, buf.count)
				if n <= 0 {
					break
				}
				buf.withUnsafeBytes { tally.feed(UnsafeRawBufferPointer(rebasing: $0[0..<n])) }
			}
			close(fd)
		}
		if !tally.carry.isEmpty {
			tally.flush()
		}
		let sum = tally.write(base, tag)
		Sys.swap(base + ".sum", sum, tag)
		Sys.swap(base + ".tsv", saved, tag)
		return (0, sum)
	}
}
