import Foundation

struct Halt: Error {
	let code: Int32
}

struct Ran {
	let out: String
	let code: Int32
}

struct Tab {
	var slots: [[String]] = Array(repeating: [], count: 50)
	var known: Set<[UInt8]> = []

	init(_ keys: [String] = []) {
		for k in keys { add(k) }
	}

	static func hash(_ key: String, _ size: Int) -> Int {
		var h: UInt32 = 0
		for b in key.utf8 { h = UInt32(bitPattern: Int32(Int8(bitPattern: b))) &+ 31 &* h }
		return Int(h % UInt32(size))
	}

	func has(_ key: String) -> Bool { known.contains(Array(key.utf8)) }

	mutating func add(_ key: String) {
		guard known.insert(Array(key.utf8)).inserted else { return }
		if known.count > 2 * slots.count {
			var next: [[String]] = Array(repeating: [], count: 4 * slots.count)
			for chain in slots {
				for k in chain { next[Tab.hash(k, next.count)].insert(k, at: 0) }
			}
			slots = next
		}
		slots[Tab.hash(key, slots.count)].insert(key, at: 0)
	}

	var keys: [String] { slots.flatMap { $0 } }
}

func env(_ key: String, _ fallback: String) -> String {
	let v = ProcessInfo.processInfo.environment[key] ?? ""
	return v.isEmpty ? fallback : v
}

func put(_ s: String) { FileHandle.standardOutput.write(Data(s.utf8)) }

func err(_ s: String) { FileHandle.standardError.write(Data(s.utf8)) }

func which(_ tool: String) -> String? {
	let fm = FileManager.default
	if tool.contains("/") { return fm.isExecutableFile(atPath: tool) ? tool : nil }
	for d in cut(env("PATH", "/usr/bin:/bin:/usr/sbin:/sbin"), by: 58) {
		let p = (d.isEmpty ? "." : d) + "/" + tool
		if fm.isExecutableFile(atPath: p) && !folder(p) { return p }
	}
	return nil
}

@discardableResult
func sh(_ tool: String, _ args: [String], limit: Double? = nil, out: FileHandle? = nil) -> Ran {
	guard let path = which(tool) else { return Ran(out: "", code: 127) }
	let p = Process()
	let pipe = Pipe()
	p.executableURL = URL(fileURLWithPath: path)
	p.arguments = args
	p.standardInput = FileHandle.nullDevice
	p.standardError = FileHandle.nullDevice
	p.standardOutput = out ?? pipe
	do { try p.run() } catch { return Ran(out: "", code: 127) }
	var stop: DispatchWorkItem?
	if let limit {
		let w = DispatchWorkItem { p.terminate() }
		DispatchQueue.global().asyncAfter(deadline: .now() + limit, execute: w)
		stop = w
	}
	let data = out == nil ? pipe.fileHandleForReading.readDataToEndOfFile() : Data()
	p.waitUntilExit()
	stop?.cancel()
	return Ran(out: String(decoding: data, as: UTF8.self), code: p.terminationReason == .exit ? p.terminationStatus : 128 + p.terminationStatus)
}

func cut(_ s: String, by byte: UInt8, keep: Bool = true) -> [String] {
	s.utf8.split(separator: byte, omittingEmptySubsequences: !keep).map { String(decoding: $0, as: UTF8.self) }
}

func lines(_ s: String) -> [String] {
	var r = cut(s, by: 10)
	if r.last == "" { r.removeLast() }
	return r
}

func words(_ s: String) -> [String] {
	s.utf8.split(omittingEmptySubsequences: true) { $0 == 32 || $0 == 9 }.map { String(decoding: $0, as: UTF8.self) }
}

func tabs(_ s: String) -> [String] { cut(s, by: 9) }

func at(_ a: [String], _ i: Int) -> String { i < a.count ? a[i] : "" }

func fields(_ s: String, _ n: Int) -> [String] {
	let b = Array(s.utf8)
	var r: [String] = []
	var i = 0
	while r.count < n {
		while i < b.count, b[i] == 32 || b[i] == 9 { i += 1 }
		var j = i
		while j < b.count, b[j] != 32, b[j] != 9 { j += 1 }
		r.append(String(decoding: b[i..<j], as: UTF8.self))
		i = j
	}
	while i < b.count, b[i] == 32 || b[i] == 9 { i += 1 }
	var e = b.count
	while e > i, b[e - 1] == 32 || b[e - 1] == 9 { e -= 1 }
	r.append(String(decoding: b[i..<e], as: UTF8.self))
	return r
}

func num(_ s: String) -> Double { strtod(s, nil) }

func whole(_ s: String) -> Int {
	let d = num(s)
	return d.isFinite ? Int(d) : 0
}

func secs(_ e: String) -> Int {
	var d = 0.0
	var t = e
	if let i = e.firstIndex(of: "-") {
		d = num(String(e[..<i]))
		t = String(e[e.index(after: i)...])
	}
	let p = cut(t, by: 58)
	let s = p.count == 3 ? num(p[0]) * 3600 + num(p[1]) * 60 + num(p[2]) : num(p[0]) * 60 + num(at(p, 1))
	return Int(d * 86400 + s)
}

func up(_ s: Int) -> String {
	s >= 86400 ? "\(s / 86400)d" : s >= 3600 ? "\(s / 3600)h" : "\(s / 60)m"
}

func f(_ format: String, _ a: CVarArg...) -> String { String(format: format, arguments: a) }

func left(_ s: String, _ n: Int) -> String { s + String(repeating: " ", count: max(0, n - s.utf8.count)) }

func right(_ s: String, _ n: Int) -> String { String(repeating: " ", count: max(0, n - s.utf8.count)) + s }

func clip(_ s: String, _ n: Int) -> String { String(decoding: s.utf8.prefix(n), as: UTF8.self) }

func head(_ s: String, _ n: Int) -> String { String(String.UnicodeScalarView(s.unicodeScalars.prefix(n))) }

func starts(_ s: String, _ p: String) -> Bool { s.utf8.starts(with: p.utf8) }

let collation = newlocale(LC_COLLATE_MASK, "", nil)

func before(_ a: String, _ b: String) -> Bool {
	let c = strcoll_l(a, b, collation)
	return c != 0 ? c < 0 : a.utf8.lexicographicallyPrecedes(b.utf8)
}

func lead(_ s: String) -> Double {
	var t = ""
	var dot = false
	for c in s.utf8.drop(while: { $0 == 32 || $0 == 9 }) {
		if c == 45, t.isEmpty { t = "-" } else if c >= 48, c <= 57 { t.append(Character(UnicodeScalar(c))) } else if c == 46, !dot {
			dot = true
			t.append(".")
		} else { break }
	}
	return Double(t) ?? 0
}

func third(_ s: String) -> Double { lead(at(words(s), 2)) }

func ranked(_ l: [String], down: Bool = false, by key: (String) -> Double = lead) -> [String] {
	let s = l.map { (key($0), $0) }.sorted { $0.0 != $1.0 ? $0.0 < $1.0 : before($0.1, $1.1) }.map { $0.1 }
	return down ? s.reversed() : s
}

func re(_ p: String) -> NSRegularExpression? { try? NSRegularExpression(pattern: p) }

func hit(_ r: NSRegularExpression?, _ s: String) -> Bool {
	guard let r else { return false }
	return r.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
}

func stamp(_ path: String, read: Bool = false) -> Int? {
	var s = stat()
	guard lstat(path, &s) == 0 else { return nil }
	return read ? s.st_atimespec.tv_sec : s.st_mtimespec.tv_sec
}

func folder(_ path: String) -> Bool {
	var d: ObjCBool = false
	return FileManager.default.fileExists(atPath: path, isDirectory: &d) && d.boolValue
}

func exists(_ path: String) -> Bool { FileManager.default.fileExists(atPath: path) }

func glob(_ dir: String, _ suffix: String) -> [String] {
	let names = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
	return names.filter { !$0.hasPrefix(".") && $0.utf8.count >= suffix.utf8.count && $0.utf8.suffix(suffix.utf8.count).elementsEqual(suffix.utf8) }
		.sorted(by: before).map { dir + "/" + $0 }
}

func dirname(_ p: String) -> String {
	let d = (p as NSString).deletingLastPathComponent
	return d.isEmpty ? "." : d
}

func basename(_ p: String, _ suffix: String = "") -> String {
	let n = (p as NSString).lastPathComponent
	return !suffix.isEmpty && n != suffix && n.hasSuffix(suffix) ? String(n.dropLast(suffix.count)) : n
}

func mark(_ back: DateComponents) -> String {
	let d = Calendar.current.date(byAdding: back, to: Date()) ?? Date()
	let t = (d.timeIntervalSince1970 / 60).rounded(.down) * 60
	let path = NSTemporaryDirectory() + "space-n-resources." + UUID().uuidString
	FileManager.default.createFile(atPath: path, contents: nil)
	try? FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSince1970: t)], ofItemAtPath: path)
	return path
}

func drop(_ path: String) { try? FileManager.default.removeItem(atPath: path) }

func below(_ roots: [String], _ par: [String: String]) -> Set<String> {
	var kids: [String: [String]] = [:]
	for (p, q) in par { kids[q, default: []].append(p) }
	var seen = Set(roots)
	var todo = roots
	while let x = todo.popLast() {
		for k in kids[x] ?? [] where seen.insert(k).inserted { todo.append(k) }
	}
	return seen
}
