import Foundation

public enum Space {
	public struct Row {
		public let kind: String
		public let kb: Int
		public let action: String
		public let target: String
		public let why: String
		public let group: String

		public init(kind: String, kb: Int, action: String, target: String, why: String, group: String? = nil) {
			self.kind = kind
			self.kb = kb
			self.action = action
			self.target = target
			self.why = why
			self.group = group ?? kind
		}

		var line: String { "\(kind)\t\(kb)\t\(action)\t\(target)\t\(why)\t\(group)\n" }
	}

	public struct Check {
		public let name: String
		public let value: Int
		public let limit: Int
		public let over: Bool

		public init(name: String, value: Int, limit: Int, over: Bool) {
			self.name = name
			self.value = value
			self.limit = limit
			self.over = over
		}
	}

	public static func run(_ args: [String]) -> Int32 {
		do { return try route(args) } catch let h as Halt { return h.code } catch { return 1 }
	}

	public static func check(path: String, bytes: Int) -> [Check]? { probe(path, bytes) }

	public static func running() -> [Row] {
		let w = Work()
		w.quiet = true
		var rows: [Row] = []
		try? w.running { rows.append($0) }
		return rows
	}

	public static func candidates(days: Int?) -> [Row] {
		let w = Work()
		w.quiet = true
		var rows: [Row] = []
		try? w.candidates(days.map { "\($0)" } ?? "") { rows.append($0) }
		return rows
	}

	static func usage() -> Halt {
		err("""
		slybar space all                 disk, then memory and cpu, one pass
		slybar space disk                free space, home, library, the usual suspects, docker, models, simulators, trash, installers
		slybar space build [days]        build artifacts under ~/Projects, largest first, stale when the project is untouched for days (60)
		slybar space mem                 swap, pressure, load, the heaviest processes, dev servers, orphans, claude sessions with their tree
		slybar space candidates [days]   one tab separated row per thing that can go: kind (orphan, stale, cache, redundant, data), kb, action, target, why; pipe it to slybar space free
		slybar space running             what runs now, read without a disk walk and without starting orbstack: idle and rogue claude sessions, listening servers, lost processes, what closed sessions left by the space_guard log, duplicates, processes over 150M, headless browsers, open applications, containers, orbstack; pipe it to slybar space free
		slybar space pause               stop every claude session and its process tree except the one asking, with kill -STOP
		slybar space resume              continue what pause stopped

		""")
		return Halt(code: 2)
	}

	static func route(_ a: [String]) throws -> Int32 {
		let days = at(a, 1)
		switch at(a, 0) {
		case "running":
			try Work().running { put($0.line) }
		case "pause":
			return try Work().pause()
		case "resume":
			return Work().resume()
		case "all":
			let w = Work()
			try w.disk()
			w.mem()
		case "disk":
			try Work().disk()
		case "build":
			guard days.isEmpty || Int(days) != nil else { throw usage() }
			_ = Work().build(days, show: true)
		case "mem":
			Work().mem()
		case "candidates":
			guard days.isEmpty || Int(days) != nil else { throw usage() }
			let w = Work()
			w.quiet = true
			try w.candidates(days) { put($0.line) }
		case "check":
			return check(Array(a.dropFirst()))
		case "free":
			return free(Array(a.dropFirst()))
		case "log":
			return Work().record(Array(a.dropFirst()))
		default:
			throw usage()
		}
		return 0
	}
}

final class Work {
	static let artifacts = "node_modules|target|\\.svelte-kit|dist|build|\\.gradle|\\.next|\\.nuxt|\\.turbo|\\.vite|DerivedData|\\.parcel-cache|vendor"
	static let dev = "vite|esbuild|air$|go-build|go run|cargo run|rust-analyzer|gopls|tsserver|playwright|chrome-headless|remote-debugging-port|pnpm dlx|npm exec|mcp|pagecast|nimpress dev|storybook|webpack|tailwindcss|ollama|whisper"
	static let system = re("^(/Applications/|/System/|/Library/|/usr/libexec/|/usr/sbin/|/usr/bin/|/sbin/|/bin/|<defunct>|[(]|-?(/bin/)?(zsh|bash|sh|login)( |$))")

	let home = env("HOME", NSHomeDirectory())
	let projects: String
	let limit: Double
	let rss: Int
	let stale: Int
	let orphan: Int
	let idle: Int
	let unused: Int
	let log: String
	let cache: String
	let fresh: String
	let paused: String
	let now = Int(Date().timeIntervalSince1970)
	var quiet = false
	var read = false
	var sizes: [(kb: String, path: String)] = []
	var known: [String: String] = [:]
	var active: [String] = []
	var guarded: Set<String> = []

	init() {
		projects = env("SPACE_PROJECTS", home + "/Projects")
		limit = Double(env("SPACE_DU_TIMEOUT", "60")) ?? 60
		rss = Int(env("SPACE_RSS_MB", "150")) ?? 150
		stale = Int(env("SPACE_STALE_DAYS", "60")) ?? 60
		orphan = Int(env("SPACE_ORPHAN_MIN", "30")) ?? 30
		idle = Int(env("SPACE_IDLE_HOURS", "6")) ?? 6
		unused = Int(env("SPACE_UNUSED_DAYS", "14")) ?? 14
		log = env("SPACE_LOG", home + "/.claude/space-n-resources.log")
		cache = env("SPACE_CACHE", env("TMPDIR", "/tmp") + "/space-n-resources.du")
		fresh = env("SPACE_CACHE_MIN", "30")
		paused = env("TMPDIR", "/tmp") + "/space-n-resources.paused"
	}

	func note(_ s: String) {
		if !quiet { err(s + "\n") }
	}

	func section(_ s: String) { put("\n== \(s)\n") }

	func size(_ path: String) -> String { sh("du", ["-sk", path], limit: limit).out }

	func human(_ l: [String]) -> String {
		l.map {
			let w = words($0)
			let k = num(at(w, 0))
			let rest = w.dropFirst().joined(separator: " ")
			return (k >= 1048576 ? f("%6.1fG  ", k / 1048576) : f("%6.0fM  ", k / 1024)) + rest + "\n"
		}.joined()
	}

	func cwd(_ pid: String) -> String {
		lines(sh("lsof", ["-a", "-p", pid, "-d", "cwd", "-Fn"]).out).filter { $0.hasPrefix("n") }.map { String($0.dropFirst()) }.joined(separator: "\n")
	}

	func moved(_ dir: String) -> Int? {
		let name = String(String.UnicodeScalarView(dir.unicodeScalars.map { s in
			s.isASCII && (CharacterSet.alphanumerics.contains(s)) ? s : "-"
		}))
		return glob(home + "/.claude/projects/" + name, ".jsonl").compactMap { stamp($0) }.max()
	}
}
