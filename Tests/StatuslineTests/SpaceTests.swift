import Foundation
import Testing
@testable import Space

@Test func nimonAndMarkers() throws {
	let fm = FileManager.default
	let fx = "/tmp/slycbar-space-\(getpid())-\(UInt32.random(in: 0..<100000))"
	defer { try? fm.removeItem(atPath: fx) }
	let big = Data(count: 55 * 1024 * 1024)
	func file(_ path: String, _ data: Data = Data("x".utf8)) {
		try? fm.createDirectory(atPath: (path as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
		fm.createFile(atPath: path, contents: data)
	}
	let tag = Data((Work.signature + "\n# cache\n").utf8)
	let proj = fx + "/Projects/acme/app"
	file(fx + "/.nimon/profiles/p1/Default/Cache/blob", big)
	file(fx + "/.nimon/profiles/p1/Default/Cookies")
	file(fx + "/.nimon/profiles/p1/Default/Login Data")
	file(fx + "/.nimon/run/old.log")
	file(fx + "/.nimon/run/new.log")
	try fm.setAttributes([.modificationDate: Date(timeIntervalSinceNow: -20 * 86400)], ofItemAtPath: fx + "/.nimon/run/old.log")
	file(proj + "/.nimon/localhost-1/bugs/a", big)
	file(proj + "/.nimon/localhost-1/shots/a", big)
	file(proj + "/.nimon/localhost-1/recordings/r1/frames/a", big)
	file(proj + "/.nimon/localhost-1/recordings/r2/frames/a", big)
	file(proj + "/.nimon/localhost-1/recordings/r2/r2.mp4")
	file(fx + "/.cargo/tagged/CACHEDIR.TAG", tag)
	file(fx + "/.cargo/tagged/blob", Data(count: 105 * 1024 * 1024))
	file(fx + "/.cargo/plain/blob", Data(count: 105 * 1024 * 1024))
	file(fx + "/.cargo/forged/CACHEDIR.TAG", Data("Signature: nope\n".utf8))
	file(fx + "/.cargo/forged/blob", Data(count: 105 * 1024 * 1024))
	file(fx + "/.cargo/small/CACHEDIR.TAG", tag)
	file(fx + "/.cargo/small/blob")

	setenv("HOME", fx, 1)
	let w = Work()
	var rows: [Space.Row] = []
	let covered = w.nimon([], { _ in false }) { rows.append($0) }
	w.markers([], [], covered, { _ in false }) { rows.append($0) }
	let targets = rows.map { $0.target }

	#expect(targets.contains { $0.contains("\"\(fx)/.nimon/profiles/p1/Default/Cache\"") || $0 == fx + "/.nimon/profiles/p1/Default/Cache" })
	#expect(!targets.contains { $0.contains("Cookies") || $0.contains("Login Data") })
	#expect(targets.contains { $0.contains("find \"\(fx)/.nimon/run\"") && $0.contains("-mtime +14") })
	let host = targets.first { $0.contains("localhost-1/bugs") } ?? ""
	#expect(host.contains("\"\(proj)/.nimon/localhost-1/bugs\""))
	#expect(host.contains("recordings/r2/frames"))
	#expect(!host.contains("recordings/r1/frames"))
	#expect(!host.contains("shots"))
	#expect(targets.contains(fx + "/.cargo/tagged"))
	#expect(!targets.contains(fx + "/.cargo/plain"))
	#expect(!targets.contains(fx + "/.cargo/forged"))
	#expect(!targets.contains(fx + "/.cargo/small"))
	#expect(rows.allSatisfy { $0.kind == "cache" || $0.kind == "stale" })
}
