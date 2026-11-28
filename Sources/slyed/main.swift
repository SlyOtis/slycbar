import AppKit
import Combine
import Network
import SQLite3
import SwiftTreeSitter
import SwiftUI
import TreeSitterBash
import TreeSitterCSS
import TreeSitterGo
import TreeSitterHTML
import TreeSitterJSON
import TreeSitterJavaScript
import TreeSitterPython
import TreeSitterRust
import TreeSitterSwift
import TreeSitterTSX
import TreeSitterTypeScript
import UniformTypeIdentifiers
import AVKit
import PDFKit
import WebKit
import WidgetKit
import tray

let cache = (ProcessInfo.processInfo.environment["SLYCBAR_CACHE"] ?? NSHomeDirectory() + "/.cache/slycbar") + "/editor"
let pages = (Bundle.main.resourcePath ?? "") + "/editor"

let probing = #"""
(function () { if (window.top !== window) return; var arm = (function (root, send, own) {
  var doc = root.ownerDocument
  var ring = doc.createElement('div')
  var armed = false
  var over = null
  function trail(el) {
    var parts = []
    for (var at = el; at && at.nodeType === 1 && at !== root && parts.length < 6; at = at.parentElement) {
      var names = typeof at.className === 'string' ? at.className.trim() : (at.getAttribute('class') || '').trim()
      parts.unshift(at.localName + (at.id ? '#' + at.id : '') + (names ? '.' + names.split(/\s+/).slice(0, 3).join('.') : ''))
    }
    return parts.join(' > ')
  }
  function arm(on) {
    armed = on
    over = null
    ring.style.cssText = 'display:none'
    root.style.cursor = on ? 'crosshair' : ''
    if (on && !ring.parentNode) (doc.body || doc.documentElement).appendChild(ring)
    send({ armed: on })
  }
  root.addEventListener('mousemove', function (event) {
    var el = event.target
    if (!armed || el === over || el === root || el === ring || el.nodeType !== 1 || el.closest('.zoomer')) return
    over = el
    var box = el.getBoundingClientRect()
    ring.style.cssText = 'position:fixed;z-index:2147483647;pointer-events:none;box-sizing:border-box;border:2px solid #ef8221;border-radius:4px;background:rgba(239,130,33,0.14);left:' + box.left + 'px;top:' + box.top + 'px;width:' + box.width + 'px;height:' + box.height + 'px'
  }, true)
  root.addEventListener('click', function (event) {
    if (!armed || event.target.closest('.zoomer')) return
    event.preventDefault()
    event.stopPropagation()
    var el = over || event.target
    var files = []
    doc.querySelectorAll('link[href], script[src], img[src], source[src], iframe[src]').forEach(function (used) {
      var url = used.href || used.src
      if (url && files.indexOf(url) < 0) files.push(url)
    })
    var picked = { trail: trail(el), id: el.id || '', text: (el.textContent || '').trim().replace(/\s+/g, ' ').slice(0, 300), html: el.outerHTML.slice(0, 1200), files: files }
    arm(false)
    send({ picked: picked })
  }, true)
  doc.addEventListener('keydown', function (event) {
    if (event.key === 'Escape' && armed) arm(false)
    if (!own || armed || event.key !== 'c' || event.metaKey || event.ctrlKey || event.altKey) return
    if (event.target.isContentEditable || /^(input|textarea|select)$/.test(event.target.localName)) return
    event.preventDefault()
    arm(true)
  }, true)
  return arm
})(document.documentElement, function (said) { window.webkit.messageHandlers.editor.postMessage(said) }, true) })()
"""#


func tools() -> [String: String] {
	var env = ProcessInfo.processInfo.environment
	let home = NSHomeDirectory()
	env["PATH"] = ["/opt/homebrew/bin", home + "/Library/pnpm", home + "/.cargo/bin", home + "/go/bin", "/usr/local/bin", env["PATH"] ?? "/usr/bin:/bin"].joined(separator: ":")
	env["S"] = cache + "/servers"
	return env
}

func call(_ path: String, _ args: [String]) -> (code: Int32, out: Data) {
	let task = Process()
	let pipe = Pipe()
	task.executableURL = URL(fileURLWithPath: path)
	task.arguments = args
	task.environment = tools()
	task.standardOutput = pipe
	task.standardError = FileHandle.nullDevice
	do {
		try task.run()
	} catch {
		return (127, Data())
	}
	let data = pipe.fileHandleForReading.readDataToEndOfFile()
	task.waitUntilExit()
	return (task.terminationStatus, data)
}

func git(_ dir: String, _ args: [String]) -> (code: Int32, out: Data) {
	call("/usr/bin/git", ["-C", dir] + args)
}

func note(_ file: String, _ line: String) {
	try? FileManager.default.createDirectory(atPath: cache, withIntermediateDirectories: true)
	let path = cache + "/" + file
	if !FileManager.default.fileExists(atPath: path) {
		FileManager.default.createFile(atPath: path, contents: nil)
	}
	guard let handle = FileHandle(forWritingAtPath: path) else { return }
	handle.seekToEndOfFile()
	handle.write(Data((ISO8601DateFormatter().string(from: Date()) + " " + line + "\n").utf8))
	handle.closeFile()
}

struct Entry: Decodable {
	let name: String
	let languages: [String: String]
	let check: String
	let install: String
	let run: String
}

final class Server {
	let process = Process()
	let input = Pipe()
	let output = Pipe()
	var next = 1
	var waiting: [Int: (Any?) -> Void] = [:]
	var versions: [String: Int] = [:]
	var ready = false
	var held: [() -> Void] = []
	var diagnosed: (String, [[String: Any]]) -> Void = { _, _ in }

	init?(command: String, root: String) {
		process.executableURL = URL(fileURLWithPath: "/bin/bash")
		process.arguments = ["-c", command]
		process.environment = tools()
		process.currentDirectoryURL = URL(fileURLWithPath: root)
		process.standardInput = input
		process.standardOutput = output
		process.standardError = FileHandle.nullDevice
		do {
			try process.run()
		} catch {
			return nil
		}
		Thread.detachNewThread { [weak self] in self?.read() }
		let uri = URL(fileURLWithPath: root).absoluteString
		request("initialize", [
			"processId": ProcessInfo.processInfo.processIdentifier,
			"rootUri": uri,
			"workspaceFolders": [["uri": uri, "name": (root as NSString).lastPathComponent]],
			"capabilities": [
				"textDocument": [
					"synchronization": ["didSave": true],
					"completion": ["completionItem": ["snippetSupport": false, "documentationFormat": ["plaintext", "markdown"]]],
					"hover": ["contentFormat": ["plaintext", "markdown"]],
					"publishDiagnostics": [:] as [String: Any],
				],
				"workspace": ["configuration": true, "workspaceFolders": true],
			],
		]) { [weak self] _ in
			guard let self else { return }
			self.notify("initialized", [:])
			self.ready = true
			self.held.forEach { $0() }
			self.held = []
		}
	}

	func write(_ message: [String: Any]) {
		var body = message
		body["jsonrpc"] = "2.0"
		guard process.isRunning, let data = try? JSONSerialization.data(withJSONObject: body) else { return }
		let handle = input.fileHandleForWriting
		try? handle.write(contentsOf: Data("Content-Length: \(data.count)\r\n\r\n".utf8) + data)
	}

	func request(_ method: String, _ params: [String: Any], _ reply: @escaping (Any?) -> Void) {
		let id = next
		next += 1
		waiting[id] = reply
		write(["id": id, "method": method, "params": params])
	}

	func notify(_ method: String, _ params: [String: Any]) {
		write(["method": method, "params": params])
	}

	func when(_ work: @escaping () -> Void) {
		if ready {
			work()
		} else {
			held.append(work)
		}
	}

	func sync(_ path: String, _ language: String, _ text: String) {
		let uri = URL(fileURLWithPath: path).absoluteString
		if let version = versions[uri] {
			versions[uri] = version + 1
			notify("textDocument/didChange", ["textDocument": ["uri": uri, "version": version + 1], "contentChanges": [["text": text]]])
		} else {
			versions[uri] = 1
			notify("textDocument/didOpen", ["textDocument": ["uri": uri, "languageId": language, "version": 1, "text": text]])
		}
	}

	func take(_ message: [String: Any]) {
		let method = message["method"] as? String
		if let id = message["id"] as? Int, method == nil {
			let reply = waiting.removeValue(forKey: id)
			reply?(message["result"])
			return
		}
		if let id = message["id"], let method {
			let items = ((message["params"] as? [String: Any])?["items"] as? [Any])?.count ?? 0
			write(["id": id, "result": method == "workspace/configuration" ? Array(repeating: NSNull(), count: items) as Any : NSNull()])
			return
		}
		if method == "textDocument/publishDiagnostics", let params = message["params"] as? [String: Any],
			let uri = params["uri"] as? String, let url = URL(string: uri) {
			diagnosed(url.path, params["diagnostics"] as? [[String: Any]] ?? [])
		}
	}

	func read() {
		let handle = output.fileHandleForReading
		var buffer = Data()
		let mark = Data("Content-Length:".utf8)
		let gap = Data("\r\n\r\n".utf8)
		while true {
			let chunk = handle.availableData
			if chunk.isEmpty {
				return
			}
			buffer.append(chunk)
			while let start = buffer.range(of: mark), let end = buffer.range(of: gap, in: start.lowerBound..<buffer.endIndex) {
				let head = String(decoding: buffer[start.lowerBound..<end.lowerBound], as: UTF8.self)
				let first = head.split(separator: "\r\n").first ?? ""
				guard let length = Int(first.dropFirst(15).trimmingCharacters(in: .whitespaces)) else {
					buffer.removeSubrange(buffer.startIndex..<end.upperBound)
					continue
				}
				guard buffer.endIndex - end.upperBound >= length else { break }
				let body = buffer[end.upperBound..<end.upperBound + length]
				buffer = Data(buffer[(end.upperBound + length)...])
				if let message = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
					DispatchQueue.main.async { self.take(message) }
				}
			}
		}
	}
}

final class Servers {
	let entries: [Entry]
	var live: [String: Server] = [:]
	var waiting: [String: [(Server?) -> Void]] = [:]
	var failed: Set<String> = []
	var status: (String) -> Void = { _ in }
	var diagnosed: (String, [[String: Any]]) -> Void = { _, _ in }

	init() {
		let data = FileManager.default.contents(atPath: pages + "/servers.json") ?? Data("[]".utf8)
		let own = FileManager.default.contents(atPath: NSHomeDirectory() + "/.slycbar/servers.json").flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? []
		entries = own + ((try? JSONDecoder().decode([Entry].self, from: data)) ?? []).filter { entry in !own.contains { $0.name == entry.name } }
	}

	func entry(_ path: String) -> (Entry, String)? {
		let name = (path as NSString).lastPathComponent.lowercased()
		let ext = (name as NSString).pathExtension
		for entry in entries {
			if let language = entry.languages[ext] ?? entry.languages[name] {
				return (entry, language)
			}
		}
		return nil
	}

	func bash(_ command: String, _ done: @escaping (Bool) -> Void) {
		DispatchQueue.global().async {
			let code = call("/bin/bash", ["-c", command]).code
			DispatchQueue.main.async { done(code == 0) }
		}
	}

	func start(_ entry: Entry, _ root: String, _ key: String) {
		let server = Server(command: entry.run, root: root)
		server?.diagnosed = { [weak self] path, list in self?.diagnosed(path, list) }
		live[key] = server
		status(server == nil ? entry.name + " did not start" : entry.name)
		if server == nil {
			failed.insert(key)
		}
		waiting.removeValue(forKey: key)?.forEach { $0(server) }
	}

	func with(_ path: String, _ root: String, _ then: @escaping (Server?, String) -> Void) {
		guard let (entry, language) = entry(path) else {
			status("")
			then(nil, "")
			return
		}
		let key = entry.name + " " + root
		if let server = live[key], server.process.isRunning {
			status(entry.name)
			then(server, language)
			return
		}
		if failed.contains(key) {
			then(nil, language)
			return
		}
		let first = waiting[key] == nil
		waiting[key, default: []].append { then($0, language) }
		guard first else { return }
		bash(entry.check) { found in
			if found {
				self.start(entry, root, key)
				return
			}
			self.status("installing " + entry.name + "…")
			note("servers.log", "install " + entry.name)
			self.bash(entry.install) { ok in
				note("servers.log", (ok ? "installed " : "install failed ") + entry.name)
				if ok {
					self.start(entry, root, key)
				} else {
					self.failed.insert(key)
					self.status(entry.name + " did not install")
					self.waiting.removeValue(forKey: key)?.forEach { $0(nil) }
				}
			}
		}
	}
}

final class Index {
	var db: OpaquePointer?
	var filled: [String: Int] = [:]
	var scanning: Set<String> = []
	let queue = DispatchQueue(label: "no.slytech.slyed.index", qos: .userInitiated)
	let fleeting = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
	static let sources: Set<String> = ["swift", "go", "rs", "ts", "tsx", "mts", "js", "jsx", "mjs", "cjs", "vue", "svelte", "py", "rb", "java", "kt", "c", "h", "cpp", "hpp", "m", "mm", "cs", "php", "lua", "zig", "dart", "ex", "exs", "scala", "sh", "tengo"]
	static let loose: Set<String> = ["const", "let", "var", "val"]
	static let declared = try? NSRegularExpression(pattern: "^([ \\t]*)(?:(?:export|default|public|private|internal|fileprivate|open|static|final|async|pub|override|abstract|declare|unsafe|extern|inline|virtual|mutating|nonisolated)[ \\t]+)*(func|function|fn|def|class|struct|enum|protocol|interface|type|trait|extension|impl|module|const|let|var|val)[ \\t]+(?:\\([^)\\n]*\\)[ \\t]*)?([A-Za-z_$][\\w$]*)", options: [.anchorsMatchLines])

	init() {
		queue.async {
			try? FileManager.default.createDirectory(atPath: cache, withIntermediateDirectories: true)
			guard sqlite3_open(cache + "/index.sqlite", &self.db) == SQLITE_OK else {
				self.db = nil
				return
			}
			["PRAGMA journal_mode = WAL", "PRAGMA synchronous = NORMAL", "PRAGMA temp_store = MEMORY", "PRAGMA mmap_size = 268435456",
				"CREATE TABLE IF NOT EXISTS files (id INTEGER PRIMARY KEY, root TEXT NOT NULL, path TEXT NOT NULL, name TEXT NOT NULL, stamp REAL NOT NULL DEFAULT 0)",
				"CREATE UNIQUE INDEX IF NOT EXISTS files_path ON files (root, path)",
				"CREATE VIRTUAL TABLE IF NOT EXISTS names USING fts5(path, tokenize = 'trigram')",
				"CREATE TABLE IF NOT EXISTS symbols (id INTEGER PRIMARY KEY, file INTEGER NOT NULL, name TEXT NOT NULL, kind TEXT NOT NULL, line INTEGER NOT NULL)",
				"CREATE INDEX IF NOT EXISTS symbols_file ON symbols (file)",
				"CREATE VIRTUAL TABLE IF NOT EXISTS marks USING fts5(name, tokenize = 'trigram')"].forEach { self.ask($0) }
		}
	}

	func bind(_ statement: OpaquePointer?, _ args: [Any]) {
		for (at, arg) in args.enumerated() {
			if let number = arg as? Int {
				sqlite3_bind_int64(statement, Int32(at + 1), Int64(number))
			} else if let number = arg as? Double {
				sqlite3_bind_double(statement, Int32(at + 1), number)
			} else {
				sqlite3_bind_text(statement, Int32(at + 1), arg as? String ?? "", -1, fleeting)
			}
		}
	}

	@discardableResult
	func ask(_ sql: String, _ args: [Any] = []) -> [[String]] {
		var statement: OpaquePointer?
		guard db != nil, sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return [] }
		defer { sqlite3_finalize(statement) }
		bind(statement, args)
		var found: [[String]] = []
		let wide = sqlite3_column_count(statement)
		while sqlite3_step(statement) == SQLITE_ROW {
			found.append((0..<wide).map { sqlite3_column_text(statement, $0).map { String(cString: $0) } ?? "" })
		}
		return found
	}

	func each(_ sql: String, _ sets: [[Any]]) {
		var statement: OpaquePointer?
		guard db != nil, sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else { return }
		for args in sets {
			bind(statement, args)
			sqlite3_step(statement)
			sqlite3_reset(statement)
		}
		sqlite3_finalize(statement)
	}

	func put(_ root: String, _ paths: [String]) {
		queue.sync {
			var hasher = Hasher()
			hasher.combine(paths)
			let sum = hasher.finalize()
			guard db != nil, filled[root] != sum else { return }
			let had = Set(ask("SELECT path FROM files WHERE root = ?", [root]).map { $0[0] })
			let kept = Set(paths)
			let gone = had.subtracting(kept).map { [root, $0] as [Any] }
			ask("BEGIN")
			let owned = "(SELECT id FROM files WHERE root = ? AND path = ?)"
			each("DELETE FROM marks WHERE rowid IN (SELECT id FROM symbols WHERE file IN " + owned + ")", gone)
			each("DELETE FROM symbols WHERE file IN " + owned, gone)
			each("DELETE FROM names WHERE rowid IN " + owned, gone)
			each("DELETE FROM files WHERE root = ? AND path = ?", gone)
			var file: OpaquePointer?
			var name: OpaquePointer?
			if sqlite3_prepare_v2(db, "INSERT INTO files (root, path, name) VALUES (?, ?, ?)", -1, &file, nil) == SQLITE_OK,
				sqlite3_prepare_v2(db, "INSERT INTO names (rowid, path) VALUES (?, ?)", -1, &name, nil) == SQLITE_OK {
				for path in paths where !had.contains(path) {
					bind(file, [root, path, (path as NSString).lastPathComponent])
					sqlite3_step(file)
					sqlite3_reset(file)
					bind(name, [Int(sqlite3_last_insert_rowid(db)), path.hasPrefix(root + "/") ? String(path.dropFirst(root.count + 1)) : path])
					sqlite3_step(name)
					sqlite3_reset(name)
				}
			}
			sqlite3_finalize(file)
			sqlite3_finalize(name)
			ask("COMMIT")
			filled[root] = sum
		}
		scan(root)
	}

	static func symbols(_ text: String) -> [(String, String, Int)] {
		guard let declared else { return [] }
		let whole = text as NSString
		var found: [(String, String, Int)] = []
		var line = 1
		var at = 0
		for match in declared.matches(in: text, range: NSRange(location: 0, length: whole.length)) {
			var seek = NSRange(location: at, length: match.range.location - at)
			while seek.length > 0 {
				let hit = whole.range(of: "\n", options: .literal, range: seek)
				guard hit.location != NSNotFound else { break }
				line += 1
				seek = NSRange(location: hit.location + 1, length: match.range.location - hit.location - 1)
			}
			at = match.range.location
			let kind = whole.substring(with: match.range(at: 2))
			if loose.contains(kind), match.range(at: 1).length > 0 { continue }
			found.append((whole.substring(with: match.range(at: 3)), kind, line))
			if found.count >= 400 { break }
		}
		return found
	}

	func keep(_ batch: [(Int, Double, [(String, String, Int)])]) {
		guard db != nil, !batch.isEmpty else { return }
		ask("BEGIN")
		each("DELETE FROM marks WHERE rowid IN (SELECT id FROM symbols WHERE file = ?)", batch.map { [$0.0] })
		each("DELETE FROM symbols WHERE file = ?", batch.map { [$0.0] })
		var symbol: OpaquePointer?
		var mark: OpaquePointer?
		if sqlite3_prepare_v2(db, "INSERT INTO symbols (file, name, kind, line) VALUES (?, ?, ?, ?)", -1, &symbol, nil) == SQLITE_OK,
			sqlite3_prepare_v2(db, "INSERT INTO marks (rowid, name) VALUES (?, ?)", -1, &mark, nil) == SQLITE_OK {
			for (file, _, symbols) in batch {
				for (name, kind, line) in symbols {
					bind(symbol, [file, name, kind, line])
					sqlite3_step(symbol)
					sqlite3_reset(symbol)
					bind(mark, [Int(sqlite3_last_insert_rowid(db)), name])
					sqlite3_step(mark)
					sqlite3_reset(mark)
				}
			}
		}
		sqlite3_finalize(symbol)
		sqlite3_finalize(mark)
		each("UPDATE files SET stamp = ? WHERE id = ?", batch.map { [$0.1, $0.0] })
		ask("COMMIT")
	}

	func scan(_ root: String) {
		queue.async {
			guard self.db != nil, !self.scanning.contains(root) else { return }
			self.scanning.insert(root)
			let known = self.ask("SELECT id, path, stamp FROM files WHERE root = ?", [root])
			DispatchQueue.global(qos: .utility).async {
				let fm = FileManager.default
				var batch: [(Int, Double, [(String, String, Int)])] = []
				for row in known where Index.sources.contains((row[1] as NSString).pathExtension.lowercased()) {
					guard let id = Int(row[0]), let facts = try? fm.attributesOfItem(atPath: row[1]), let changed = facts[.modificationDate] as? Date, (facts[.size] as? NSNumber)?.intValue ?? 0 < 512000 else { continue }
					let stamp = changed.timeIntervalSince1970
					guard abs(stamp - (Double(row[2]) ?? 0)) > 0.01, let data = fm.contents(atPath: row[1]) else { continue }
					batch.append((id, stamp, Index.symbols(String(decoding: data, as: UTF8.self))))
					if batch.count >= 200 {
						let held = batch
						batch = []
						self.queue.async { self.keep(held) }
					}
				}
				let held = batch
				self.queue.async {
					self.keep(held)
					self.scanning.remove(root)
				}
			}
		}
	}

	func get(_ root: String, _ text: String, _ limit: Int) -> [String] {
		queue.sync {
			let q = text.lowercased()
			guard !q.isEmpty else {
				return ask("SELECT path FROM files WHERE root = ? ORDER BY path LIMIT ?", [root, limit]).map { $0[0] }
			}
			var found: [String] = []
			if q.count > 2 {
				found = ask("SELECT f.path FROM names JOIN files f ON f.id = names.rowid WHERE names MATCH ? AND f.root = ? LIMIT 400", ["\"" + q.replacingOccurrences(of: "\"", with: "\"\"") + "\"", root]).map { $0[0] }
			}
			if found.count < limit {
				let held = Set(found)
				let apart = "%" + q.map { "%_\\".contains($0) ? "\\" + String($0) : String($0) }.joined(separator: "%") + "%"
				found += ask("SELECT path FROM files WHERE root = ? AND substr(path, ?) LIKE ? ESCAPE '\\' LIMIT 400", [root, root.count + 2, apart]).map { $0[0] }.filter { !held.contains($0) }
			}
			var ranked: [(Int, String)] = []
			for path in found {
				let name = (path as NSString).lastPathComponent.lowercased()
				if let hit = name.range(of: q) {
					ranked.append((name.distance(from: name.startIndex, to: hit.lowerBound) * 10 + name.count, path))
				} else {
					ranked.append((10000 + path.count, path))
				}
			}
			ranked.sort { $0.0 < $1.0 }
			var best = ranked.prefix(limit).map { $0.1 }
			if best.count < limit, q.count > 3 {
				let letters = Array(q.filter { $0 != "\"" })
				let grams = Set((0..<max(0, letters.count - 2)).map { String(letters[$0..<$0 + 3]) })
				let near = ask("SELECT f.path FROM names JOIN files f ON f.id = names.rowid WHERE names MATCH ? AND f.root = ? ORDER BY bm25(names) LIMIT ?", [grams.sorted().map { "\"" + $0 + "\"" }.joined(separator: " OR "), root, limit * 2]).map { $0[0] }
				best += near.filter { !best.contains($0) }.prefix(limit - best.count)
			}
			return best
		}
	}

	func getSymbols(_ root: String, _ text: String, _ limit: Int) -> [[String]] {
		queue.sync {
			let q = text.lowercased()
			guard q.count > 2 else { return [] }
			let found = ask("SELECT s.name, s.kind, f.path, s.line FROM marks JOIN symbols s ON s.id = marks.rowid JOIN files f ON f.id = s.file WHERE marks MATCH ? AND f.root = ? LIMIT 300", ["\"" + q.replacingOccurrences(of: "\"", with: "\"\"") + "\"", root])
			return Array(found.map { row -> (Int, [String]) in
				let name = row[0].lowercased()
				return (name == q ? 0 : name.hasPrefix(q) ? name.count : 1000 + name.count, row)
			}.sorted { $0.0 < $1.0 }.prefix(limit).map { $0.1 })
		}
	}
}

struct Hit: Identifiable {
	let id: String
	let section: String
	let icon: String
	let title: String
	let detail: String
	let hint: String
	let run: () -> Void
}

struct Agent: Identifiable {
	let id: Int
	let name: String
	let dir: String
	let status: String
	let files: [String]
	let acts: [String: String]
	let socket: String
	let last: String
	let questions: [String]
	let sid: String
	let logs: [String]

	var color: Color {
		status == "busy" ? Color(red: 0.95, green: 0.65, blue: 0.42) : status == "idle" ? Color.white.opacity(0.4) : Color(red: 0.92, green: 0.74, blue: 0.33)
	}
}

struct Card: Identifiable, Equatable {
	let id: String
	let repo: String
	let number: String
	let title: String
	let kind: String
	let status: String
	let tree: String
	let session: String
	let updated: Date
	let questions: Int
}

struct Feed: Identifiable, Equatable {
	let id: String
	let group: String
	let name: String
	let detail: String
	let model: String
	let busy: Bool
	let lines: [String]
	let questions: [String]
	let trees: Set<String>
}

final class Live: ObservableObject {
	@Published var cards: [Card] = []
	@Published var feeds: [Feed] = []
}

final class Pulse: ObservableObject {
	@Published var draft = ""
	@Published var stats: [String] = []
	@Published var cursor = ""
	@Published var zoom = 0.95
	@Published var mark = ""
	@Published var focus = 0
}

struct Node: Identifiable {
	let path: String
	let depth: Int
	let dir: Bool
	var id: String { path }
}

final class Model: ObservableObject {
	@Published var root = "" {
		didSet {
			laid = nil
			if !stepping, oldValue != root, !oldValue.isEmpty {
				turned(oldValue)
			}
		}
	}
	var stepping = false
	var turned: (String) -> Void = { _ in }
	var back: () -> Void = {}
	var forward: () -> Void = {}
	@Published var hidden: Set<String> = []
	@Published var earlier = false
	@Published var later = false

	func label(_ path: String) -> String {
		path == NSHomeDirectory() ? "~" : path == "/" ? "/" : (path as NSString).lastPathComponent
	}
	@Published var roots: [String] = UserDefaults.standard.stringArray(forKey: "roots") ?? []

	@Published var icons: [String: NSImage] = [:]
	var sought: Set<String> = []

	func icon(_ folder: String) -> NSImage? {
		if let known = icons[folder] {
			return known
		}
		guard !sought.contains(folder) else { return nil }
		sought.insert(folder)
		DispatchQueue.global().async {
			let fm = FileManager.default
			let skip: Set<String> = ["node_modules", "target", "Pods", "vendor", "DerivedData"]
			var level = [folder]
			var found: String?
			var seen = 0
			for _ in 0..<5 where found == nil && !level.isEmpty {
				var next: [String] = []
				for dir in level where found == nil {
					for name in ((try? fm.contentsOfDirectory(atPath: dir)) ?? []).sorted() {
						seen += 1
						let path = dir + "/" + name
						if name == ".favicon" || name == "favicon.svg" {
							found = path
							break
						}
						var isDir: ObjCBool = false
						if !name.hasPrefix("."), !skip.contains(name), fm.fileExists(atPath: path, isDirectory: &isDir), isDir.boolValue {
							next.append(path)
						}
					}
					if seen > 20000 { break }
				}
				level = seen > 20000 ? [] : next
			}
			guard let found, let image = NSImage(contentsOfFile: found) else { return }
			DispatchQueue.main.async { self.icons[folder] = image }
		}
		return nil
	}

	func adopt(_ path: String) {
		if !roots.contains(path) {
			roots.append(path)
		}
		root = path
		UserDefaults.standard.set(roots, forKey: "roots")
	}

	func drop(_ path: String) {
		roots.removeAll { $0 == path }
		UserDefaults.standard.set(roots, forKey: "roots")
	}
	@Published var file = ""
	@Published var open: Set<String> = [] {
		didSet { laid = nil }
	}
	@Published var kids: [String: [(String, Bool)]] = [:] {
		didSet { laid = nil }
	}
	var laid: [Node]?
	@Published var dirty: Set<String> = []
	@Published var ignored: [String] = []
	@Published var marks: [String: String] = [:]
	@Published var diff = false
	@Published var sides = false
	@Published var gitOpen = false
	@Published var boardOpen = false
	@Published var setOpen = false
	@Published var set: [String: Any] = [:]
	var store: (String, String) -> Void = { _, _ in }
	let live = Live()
	var stream: () -> Void = {}
	@Published var branch = ""
	@Published var tracking = ""
	@Published var state = ""
	@Published var changes: [Change] = []
	@Published var branches: [String] = []
	@Published var commits: [Commit] = []
	@Published var stashes: [String] = []
	@Published var message = ""
	@Published var said = ""
	@Published var failed = false
	@Published var armedGit = ""
	@Published var base = "HEAD"
	var act: ([String]) -> Void = { _ in }
	var compare: (String) -> Void = { _ in }
	var disarmGit: Timer?

	func git(_ args: [String], _ sure: String) {
		if !sure.isEmpty && armedGit != sure {
			armedGit = sure
			disarmGit?.invalidate()
			disarmGit = Timer.scheduledTimer(withTimeInterval: 4, repeats: false) { [weak self] _ in self?.armedGit = "" }
			return
		}
		armedGit = ""
		act(args)
	}

	func commit(_ amend: Bool) {
		if amend {
			git(message.isEmpty ? ["commit", "--amend", "--no-edit"] : ["commit", "--amend", "-m", message], "amend the last commit")
		} else if !message.isEmpty {
			act(["commit", "-m", message])
		}
	}
	var openGit: () -> Void = {}
	var choose: () -> Void = {}
	var changed: () -> Void = {}

	func prompt(_ title: String, _ value: String) -> String? {
		let alert = NSAlert()
		alert.messageText = title
		alert.addButton(withTitle: "OK")
		alert.addButton(withTitle: "Cancel")
		let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
		field.stringValue = value
		alert.accessoryView = field
		alert.window.initialFirstResponder = field
		guard alert.runModal() == .alertFirstButtonReturn else { return nil }
		let name = field.stringValue.trimmingCharacters(in: .whitespaces)
		return name.isEmpty || name.contains("/") ? nil : name
	}

	func enter(_ path: String) {
		roots.removeAll { $0 == root }
		ask(path)
	}

	func make(_ folder: String, _ dir: Bool) {
		guard let name = prompt(dir ? "New folder in " + (folder as NSString).lastPathComponent : "New file in " + (folder as NSString).lastPathComponent, "") else { return }
		let path = folder + "/" + name
		guard !FileManager.default.fileExists(atPath: path) else {
			status = name + " already exists"
			return
		}
		if dir {
			try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
		} else {
			FileManager.default.createFile(atPath: path, contents: nil)
		}
		open.insert(folder)
		changed()
		if !dir {
			ask(path)
		}
	}

	func rename(_ path: String) {
		guard let name = prompt("Rename " + (path as NSString).lastPathComponent, (path as NSString).lastPathComponent) else { return }
		let next = (path as NSString).deletingLastPathComponent + "/" + name
		guard !FileManager.default.fileExists(atPath: next) else {
			status = name + " already exists"
			return
		}
		do {
			try FileManager.default.moveItem(atPath: path, toPath: next)
		} catch {
			status = "not renamed: " + error.localizedDescription
			return
		}
		changed()
		if file == path {
			ask(next)
		}
	}

	func duplicate(_ path: String) {
		let ext = (path as NSString).pathExtension
		let stem = (path as NSString).deletingPathExtension
		var next = stem + " copy" + (ext.isEmpty ? "" : "." + ext)
		var n = 2
		while FileManager.default.fileExists(atPath: next) {
			next = stem + " copy \(n)" + (ext.isEmpty ? "" : "." + ext)
			n += 1
		}
		try? FileManager.default.copyItem(atPath: path, toPath: next)
		changed()
	}

	func trash(_ path: String) {
		do {
			try FileManager.default.trashItem(at: URL(fileURLWithPath: path), resultingItemURL: nil)
			status = (path as NSString).lastPathComponent + " moved to the Trash"
		} catch {
			status = "not moved: " + error.localizedDescription
		}
		changed()
	}
	var warp: () -> Void = {}
	var impact: () -> Void = {}
	@Published var tracked = false
	@Published var status = "" {
		didSet {
			shown += 1
			let mine = shown
			guard !status.isEmpty else { return }
			DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
				if mine == self.shown {
					self.status = ""
				}
			}
		}
	}
	var shown = 0
	@Published var server = ""
	@Published var preview = false
	@Published var media = ""
	@Published var sheeted = false
	@Published var twinned = false
	@Published var inquiring = false
	@Published var noting = false
	@Published var mode = "both"
	var ask: (String) -> Void = { _ in }
	var up: () -> Void = {}
	var flip: () -> Void = {}
	var flipSides: () -> Void = {}
	var show: (String) -> Void = { _ in }
	@Published var side = true
	@Published var width = UserDefaults.standard.double(forKey: "width") == 0 ? 214 : UserDefaults.standard.double(forKey: "width")
	@Published var over = false
	@Published var scale = UserDefaults.standard.double(forKey: "scale") == 0 ? 1.1 : UserDefaults.standard.double(forKey: "scale")
	@Published var zoomed = UserDefaults.standard.double(forKey: "zoom") == 0 ? 1.2 : UserDefaults.standard.double(forKey: "zoom")
	@Published var palette = ""
	@Published var query = "" { didSet { search() } }
	@Published var results: [String] = []
	@Published var hits: [Hit] = []
	@Published var busy = false
	var actions: [Hit] = []
	var count: Int { palette == "search" ? hits.count : results.count }
	@Published var at = 0
	@Published var agents: [Agent] = []
	@Published var meters: [Meter] = []
	@Published var account = ""
	let pulse = Pulse()
	let sight = Sight()
	var format: () -> Void = {}
	@Published var high = UserDefaults.standard.double(forKey: "high")
	var grown = 160.0
	@Published var fitted = 160.0
	var resting = true

	func fit(_ tall: Double) {
		grown = tall
		if resting {
			fitted = tall
		}
	}
	var dragged = 0.0
	var comment: (String) -> Void = { _ in }
	var audit: (Agent) -> Void = { _ in }
	struct Talk {
		let agent: Agent?
		let title: String
		let detail: String
		let file: String
		var lines: [String]
	}

	struct Kit {
		var top = ""
		var file = ""
		var tasks: [(path: String, id: String, title: String, status: String)] = []
		var agents: [String] = []
		var skills: [String] = []
		var memory: [(line: Int, kind: String, asked: String, answer: String)] = []
	}

	@Published var talk: Talk?
	@Published var reply = ""
	@Published var kitOpen = false
	@Published var kit = Kit()
	var converse: (Agent?, String, String, String) -> Void = { _, _, _, _ in }
	var openKit: () -> Void = {}

	func tell() {
		let text = reply.trimmingCharacters(in: .whitespacesAndNewlines)
		guard let agent = talk?.agent, !text.isEmpty else { return }
		reply = ""
		answer(agent, text)
	}

	func board() {
		boardOpen.toggle()
		if boardOpen {
			stream()
		}
	}
	@Published var asking: Agent?
	var answer: (Agent, String) -> Void = { _, _ in }
	@Published var counts: [String: (Int, Int)] = [:]
	var review: (String) -> Void = { _ in }
	var get: (String, String, Int) -> [String] = { _, _, _ in [] }
	var getSymbols: (String, String, Int) -> [[String]] = { _, _, _ in [] }
	var recent: [String] = []
	var top = ""
	var line: (Int) -> Void = { _ in }
	var done: () -> Void = {}
	var jump: (String, Int?) -> Void = { _, _ in }
	@Published var proposal = ""
	@Published var claude = false
	var decide: (Bool) -> Void = { _ in }
	var asked = 0
	@Published var plan = ""
	@Published var heading = ""
	@Published var steps: [Step] = []
	@Published var step = -1
	@Published var hunks: [Hunk] = []
	@Published var hunk = -1
	@Published var region = ""
	@Published var comparing = ""
	@Published var remarks: [Note] = []
	@Published var phase = ""
	@Published var round = 1
	@Published var folder = ""
	@Published var deep = UserDefaults.standard.double(forKey: "deep")
	var depth = 0.0
	var visit: (Int) -> Void = { _ in }
	var judge: (Int, String) -> Void = { _, _ in }
	var walk: (Bool) -> Void = { _ in }
	var resume: () -> Void = {}
	var leave: () -> Void = {}

	@Published var view = "sides"
	var look: (String) -> Void = { _ in }
	var magnify: (Double) -> Void = { _ in }
	var remark: () -> Void = {}
	var inquire: (String) -> Void = { _ in }
	var unmark: () -> Void = {}

	var decided: Int { hunks.filter { $0.on && $0.status != "pending" }.count }
	var aimed: Int { hunks.filter { $0.on }.count }
	var reviewing: Bool { !plan.isEmpty && hunk >= 0 && hunk < hunks.count }

	func follow(_ url: URL) -> OpenURLAction.Result {
		let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
		guard url.scheme == "slyed", let path = items.first(where: { $0.name == "path" })?.value else { return .systemAction }
		jump(path, items.first(where: { $0.name == "line" })?.value.flatMap { Int($0) })
		return .handled
	}

	func trail() -> [String] {
		var list = [root]
		let home = NSHomeDirectory()
		var at = root
		while at.count > 1, at != home {
			at = (at as NSString).deletingLastPathComponent
			list.insert(at, at: 0)
		}
		return list
	}

	func climb(_ path: String) {
		roots.removeAll { $0 == root }
		open.insert(root)
		ask(path)
	}

	func above() -> [String] {
		var list: [String] = []
		var at = root
		while at.count > 1 {
			at = (at as NSString).deletingLastPathComponent
			list.append(at)
		}
		return list
	}

	func hint(_ agent: Agent, _ path: String) -> String {
		agent.name + " " + (agent.acts[path] ?? "") + " " + short(path)
	}

	func short(_ path: String) -> String {
		(path as NSString).abbreviatingWithTildeInPath
	}

	func relative(_ path: String) -> String {
		let base = top.isEmpty ? root : top
		return path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : path
	}

	func search() {
		let q = query.lowercased()
		at = 0
		if palette == "line" || palette == "comment" || palette == "answer" {
			results = []
			return
		}
		if palette == "search" {
			asked += 1
			let mine = asked
			let base = top.isEmpty ? root : top
			let text = query
			let q = text.lowercased()
			let commands = actions.filter { q.isEmpty || $0.title.lowercased().contains(q) }
			hits = Array(commands.prefix(q.isEmpty ? 12 : 5))
			guard text.count > 1 else {
				busy = false
				return
			}
			busy = true
			let get = self.get
			let getSymbols = self.getSymbols
			let jump = self.jump
			let short = self.short
			DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
				guard mine == self.asked else { return }
				var found: [Hit] = []
				for path in get(base, q, 5) {
					found.append(Hit(id: "file " + path, section: "Files", icon: "doc", title: (path as NSString).lastPathComponent, detail: short((path as NSString).deletingLastPathComponent), hint: "") { jump(path, nil) })
				}
				for row in getSymbols(base, q, 6) where row.count == 4 {
					found.append(Hit(id: "symbol " + row[2] + ":" + row[3] + " " + row[0], section: "Symbols", icon: "curlybraces", title: row[0], detail: (row[2] as NSString).lastPathComponent + ":" + row[3], hint: row[1]) { jump(row[2], Int(row[3])) })
				}
				let out = call("/usr/bin/env", ["rg", "--line-number", "--no-heading", "--color", "never", "--smart-case", "--max-count", "3", "--max-columns", "160", "--max-filesize", "1M", "--fixed-strings", "--", text, base]).out
				for line in String(decoding: out, as: UTF8.self).split(separator: "\n").prefix(8) {
					let parts = line.split(separator: ":", maxSplits: 2, omittingEmptySubsequences: false)
					guard parts.count == 3, let number = Int(parts[1]) else { continue }
					let path = String(parts[0])
					found.append(Hit(id: "text " + line, section: "In files", icon: "text.magnifyingglass", title: parts[2].trimmingCharacters(in: .whitespaces), detail: (path as NSString).lastPathComponent + ":" + parts[1], hint: "") { jump(path, number) })
				}
				if text.count > 2 {
					let mac = String(decoding: call("/usr/bin/mdfind", ["-name", text, "-onlyin", NSHomeDirectory()]).out, as: UTF8.self).split(separator: "\n")
					for line in mac.filter({ !$0.contains("/Library/") && !$0.contains("/node_modules/") && !$0.contains("/.") }).prefix(6) {
						let path = String(line)
						guard !found.contains(where: { $0.id == "file " + path }) else { continue }
						found.append(Hit(id: "mac " + path, section: "On this Mac", icon: "externaldrive", title: (path as NSString).lastPathComponent, detail: short((path as NSString).deletingLastPathComponent), hint: "") { jump(path, nil) })
					}
				}
				DispatchQueue.main.async {
					if mine == self.asked {
						self.hits = Array(commands.prefix(5)) + found
						self.busy = false
					}
				}
			}
			return
		}
		if palette == "files" && (query.hasPrefix("/") || query.hasPrefix("~")) {
			let full = (query as NSString).expandingTildeInPath
			let dir = query.hasSuffix("/") ? full : (full as NSString).deletingLastPathComponent
			let start = query.hasSuffix("/") ? "" : (full as NSString).lastPathComponent.lowercased()
			let names = ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { start.isEmpty || $0.lowercased().hasPrefix(start) }.sorted().prefix(14)
			results = names.map { name in
				let path = (dir as NSString).appendingPathComponent(name)
				var isDir: ObjCBool = false
				FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
				return isDir.boolValue ? path + "/" : path
			}
			return
		}
		if palette != "recent" {
			asked += 1
			let mine = asked
			let get = self.get
			let base = top.isEmpty ? root : top
			DispatchQueue.global(qos: .userInitiated).async {
				let found = get(base, q, 14)
				DispatchQueue.main.async {
					if mine == self.asked, self.palette == "files" {
						self.results = found
					}
				}
			}
			return
		}
		let from = recent
		if q.isEmpty {
			results = Array(from.prefix(14))
			return
		}
		var hits: [(Int, String)] = []
		for path in from {
			let name = (path as NSString).lastPathComponent.lowercased()
			if let found = name.range(of: q) {
				hits.append((name.distance(from: name.startIndex, to: found.lowerBound) * 10 + name.count, path))
				continue
			}
			var rest = Substring(q)
			for ch in path.lowercased() where ch == rest.first {
				rest = rest.dropFirst()
				if rest.isEmpty { break }
			}
			if rest.isEmpty {
				hits.append((10000 + path.count, path))
			}
		}
		hits.sort { $0.0 < $1.0 }
		results = hits.prefix(14).map { $0.1 }
	}

	func close() {
		palette = ""
		query = ""
		done()
	}

	func pick() {
		if palette == "search" {
			guard at < hits.count else { return }
			let hit = hits[at]
			close()
			hit.run()
			return
		}
		if palette == "answer" {
			let text = query
			let agent = asking
			close()
			if let agent, !text.trimmingCharacters(in: .whitespaces).isEmpty {
				answer(agent, text)
			}
			return
		}
		if palette == "comment" {
			let text = query
			close()
			if !text.trimmingCharacters(in: .whitespaces).isEmpty {
				comment(text)
			}
			return
		}
		if palette == "line" {
			let number = Int(query.trimmingCharacters(in: .whitespaces))
			close()
			if let number {
				line(number)
			}
			return
		}
		guard at < results.count else { return }
		let parts = results[at].components(separatedBy: "\t")
		if parts[0].hasSuffix("/") {
			ask(String(parts[0].dropLast()))
			query = (parts[0] as NSString).abbreviatingWithTildeInPath + "/"
			return
		}
		close()
		jump(parts[0], parts.count > 1 ? Int(parts[1]) : nil)
	}

	func list(_ dir: String) -> [(String, Bool)] {
		if let known = kids[dir] {
			return known
		}
		let urls = (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: dir), includingPropertiesForKeys: [.isDirectoryKey])) ?? []
		var found: [(String, Bool)] = []
		for url in urls where url.lastPathComponent != ".git" && url.lastPathComponent != ".DS_Store" {
			let values = try? url.resourceValues(forKeys: [.isDirectoryKey])
			found.append((url.path, values?.isDirectory ?? false))
		}
		found.sort { (a: (String, Bool), b: (String, Bool)) -> Bool in
			a.1 != b.1 ? a.1 : a.0.localizedStandardCompare(b.0) == .orderedAscending
		}
		DispatchQueue.main.async { self.kids[dir] = found }
		return found
	}

	func nodes() -> [Node] {
		if let laid {
			return laid
		}
		let found = rows(root, 0)
		laid = found
		return found
	}

	func rows(_ dir: String, _ depth: Int) -> [Node] {
		list(dir).flatMap { path, isDir in
			[Node(path: path, depth: depth, dir: isDir)] + (isDir && open.contains(path) ? rows(path, depth + 1) : [])
		}
	}

	func under(_ path: String, _ list: [String]) -> Bool {
		list.contains { path == $0 || path.hasPrefix($0 + "/") }
	}

	func mark(_ path: String, _ dir: Bool) -> String {
		if let own = marks[path] {
			return own
		}
		if let above = marks.first(where: { path.hasPrefix($0.key + "/") && $0.value == "?" }) {
			return above.value
		}
		return dir && marks.keys.contains(where: { $0.hasPrefix(path + "/") }) ? "·" : ""
	}
}

struct Ops: View {
	@ObservedObject var model: Model
	let path: String
	let dir: Bool
	var top = false

	var body: some View {
		let folder = dir ? path : (path as NSString).deletingLastPathComponent
		Button("New File…") { model.make(folder, false) }
		Button("New Folder…") { model.make(folder, true) }
		Divider()
		if top {
			Button("Go to Parent Folder") { model.up() }
			Menu("Go Up To") {
				ForEach(model.above(), id: \.self) { parent in
					Button(model.short(parent)) { model.climb(parent) }
				}
			}
			Button("Open Folder…") { model.choose() }
			if model.roots.count > 1 {
				Button("Close This Project") { model.drop(path) }
			}
		} else {
			if dir {
				Button("Go Into This Folder") { model.enter(path) }
				Button("Open as a Project") { model.ask(path) }
			}
			Button("Rename…") { model.rename(path) }
			Button("Duplicate") { model.duplicate(path) }
			Button("Move to Trash") { model.trash(path) }
		}
		Divider()
		Button("Copy Path") { copy(path) }
		Button("Copy Relative Path") { copy(model.relative(path)) }
		Button("Copy Name") { copy((path as NSString).lastPathComponent) }
		Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)]) }
	}
}

struct More: View {
	@ObservedObject var model: Model
	let path: String
	let dir: Bool
	var top = false

	var body: some View {
		Menu {
			Ops(model: model, path: path, dir: dir, top: top)
		} label: {
			Text("⋮").font(.system(size: 13 * model.scale, weight: .bold)).foregroundStyle(Ink.dim).frame(width: 14 * model.scale, height: 13 * model.scale)
		}
		.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 14 * model.scale, height: 13 * model.scale).fixedSize()
		.tip("File and folder actions")
	}
}

struct Row: View {
	@ObservedObject var model: Model
	let node: Node
	@State private var over = false

	var body: some View {
		let name = (node.path as NSString).lastPathComponent
		let hidden = model.under(node.path, model.ignored)
		let mark = model.mark(node.path, node.dir)
		let tint = mark == "?" ? Color(red: 0.42, green: 0.78, blue: 0.56) : mark.isEmpty ? Color.white.opacity(0.88) : Color(red: 0.92, green: 0.74, blue: 0.33)
		HStack(spacing: 5) {
			Text(node.dir ? (model.open.contains(node.path) ? "▾" : "▸") : "").font(.system(size: 9)).foregroundStyle(Color.white.opacity(0.5)).frame(width: 10)
			Image(systemName: node.dir ? "folder" : "doc").font(.system(size: 10)).foregroundStyle(Color.white.opacity(0.5)).frame(width: 14)
			Text(name).foregroundStyle(tint).italic(hidden).lineLimit(1).truncationMode(.middle).frame(maxWidth: .infinity, alignment: .leading).layoutPriority(1)
			if let count = model.counts[node.path] {
				Counts(added: count.0, removed: count.1)
			}
			if let agent = model.agents.first(where: { $0.files.contains(node.path) }) {
				Badge(text: agent.acts[node.path] ?? "open", color: agent.color, scale: model.scale).tip(agent.name + " " + (agent.acts[node.path] ?? "") + ", " + agent.status)
			}
			if model.dirty.contains(node.path) {
				Circle().fill(Color.white.opacity(0.7)).frame(width: 6, height: 6)
			} else if !mark.isEmpty && mark != "·" {
				Text(mark == "?" ? "U" : mark).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
			}
			More(model: model, path: node.path, dir: node.dir).opacity(over ? 1 : 0).allowsHitTesting(over).padding(.leading, -5)
		}
		.font(.system(size: 12 * model.scale))
		.opacity(hidden ? 0.4 : 1)
		.padding(.leading, 8 + Double(node.depth) * 12)
		.padding(.trailing, 8)
		.padding(.vertical, 3)
		.background(RoundedRectangle(cornerRadius: 8).fill(node.path == model.file ? Ink.hover : over ? Color.white.opacity(0.05) : Color.clear))
		.contentShape(Rectangle())
		.onHover { over = $0 }
		.onTapGesture(count: 2) {
			if node.dir {
				model.enter(node.path)
			}
		}
		.onTapGesture {
			if node.dir {
				if model.open.contains(node.path) {
					model.open.remove(node.path)
				} else {
					model.open.insert(node.path)
				}
			} else {
				model.ask(node.path)
			}
		}
		.tip(hidden ? node.path + " · ignored by git" : node.path)
		.contextMenu {
			Ops(model: model, path: node.path, dir: node.dir)
		}
	}
}

final class Scroller: NSScroller {
	override class var isCompatibleWithOverlayScrollers: Bool { true }

	override func drawKnobSlot(in slotRect: NSRect, highlight flag: Bool) {}

	var over = false {
		didSet { needsDisplay = true }
	}

	override func updateTrackingAreas() {
		super.updateTrackingAreas()
		trackingAreas.forEach { removeTrackingArea($0) }
		addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow], owner: self))
	}

	override func mouseEntered(with event: NSEvent) { over = true }
	override func mouseExited(with event: NSEvent) { over = false }

	override func drawKnob() {
		let knob = rect(for: .knob)
		let wide = over ? 6.0 : 2.5
		let bar = NSRect(x: bounds.maxX - wide - 1, y: knob.minY + 2, width: wide, height: max(10, knob.height - 4))
		let path = NSBezierPath(roundedRect: bar, xRadius: wide / 2, yRadius: wide / 2)
		if over {
			NSGradient(starting: NSColor(red: 0.94, green: 0.51, blue: 0.13, alpha: 0.95), ending: NSColor(red: 0.71, green: 0.39, blue: 0.18, alpha: 0.95))?.draw(in: path, angle: 90)
		} else {
			NSColor.white.withAlphaComponent(0.3).setFill()
			path.fill()
		}
	}
}

struct Thin: NSViewRepresentable {
	func makeNSView(context: Context) -> NSView {
		let view = NSView()
		DispatchQueue.main.async {
			guard let scroll = view.enclosingScrollView else { return }
			let bar = Scroller()
			bar.scrollerStyle = .overlay
			scroll.scrollerStyle = .overlay
			scroll.verticalScroller = bar
		}
		return view
	}

	func updateNSView(_ view: NSView, context: Context) {}
}

final class Sheet: NSView {
	struct Item {
		let section: Int
		let hunk: Int
		let top: CGFloat
		let tall: CGFloat
		let rows: Int
	}

	struct Section {
		let title: String
		let detail: String
		let added: Int
		let removed: Int
		let ids: [Int]
	}

	var hunks: [Hunk] = []
	var paths: [String] = []
	var current = -1
	var view = "sides"
	var dents: [Int: Int] = [:]
	var sections: [Section] = []
	var items: [Item] = []
	var spots: [Int: Int] = [:]
	var opened: Set<Int> = []
	var pairs: [Int: [(Int, Int)]] = [:]
	var cuts: [Int: [Int: NSRange]] = [:]
	let inked = NSCache<NSNumber, NSAttributedString>()
	var shift: CGFloat = 0
	var scale = 0.95
	var digits = 5
	var pick: (Int) -> Void = { _ in }
	var fog = false
	var chosen: (hunk: Int, from: Int, to: Int)? {
		didSet { marked() }
	}
	var marked: () -> Void = {}
	var build: (NSMenu) -> Void = { _ in }
	var others: [(hunk: Int, from: Int, to: Int)] = []
	var notes: [Int: [(row: Int, text: String)]] = [:]
	var shown: [Int: [(at: Int, lines: [String])]] = [:]
	var anchor: (Int, Int)?
	var fogging = false
	var font = NSFont.monospacedSystemFont(ofSize: 12, weight: .regular)
	var plain = NSFont.systemFont(ofSize: 11)
	var bold = NSFont.systemFont(ofSize: 11, weight: .semibold)
	var wide: CGFloat = 7
	var tall: CGFloat = 18
	var head: CGFloat = 22
	var band: CGFloat = 30
	var gap: CGFloat = 8
	static let words: Set<String> = ["func", "function", "fn", "def", "class", "struct", "enum", "protocol", "interface", "type", "trait", "extension", "impl", "module", "package", "import", "from", "export", "default", "const", "let", "var", "val", "static", "final", "public", "private", "internal", "return", "if", "else", "for", "while", "do", "switch", "case", "break", "continue", "guard", "defer", "try", "catch", "throw", "throws", "async", "await", "new", "in", "of", "as", "is", "where", "select", "insert", "update", "delete", "create", "table", "go", "chan", "range", "map", "self", "this", "super", "extends", "implements", "override", "use", "pub", "mut", "match", "end", "then", "elif", "lambda", "with", "yield", "and", "or", "not"]
	static let atoms: Set<String> = ["true", "false", "null", "nil", "None", "True", "False", "undefined"]
	static let keyed: Set<String> = ["json", "jsonc", "jsonl", "json5", "yaml", "yml", "toml", "lock", "map"]
	static let hashed: Set<String> = ["sh", "bash", "zsh", "py", "rb", "yaml", "yml", "toml", "conf", "cfg", "ini", "env", "tf", "just", "justfile", ".justfile", "mk"]
	static let recipes: Set<String> = ["just", "justfile", ".justfile"]

	override var isFlipped: Bool { true }
	override var isOpaque: Bool { true }

	static func tone(_ hex: Int, _ alpha: CGFloat = 1) -> NSColor {
		NSColor(srgbRed: CGFloat(hex >> 16 & 255) / 255, green: CGFloat(hex >> 8 & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
	}

	func measure() {
		let size = CGFloat(12 * scale)
		let family = "Liga Roboto Mono"
		if !NSFontManager.shared.availableFontFamilies.contains(family) {
			for name in (try? FileManager.default.contentsOfDirectory(atPath: pages + "/fonts")) ?? [] where name.hasPrefix("LigaRobotoMono") && name.hasSuffix(".ttf") {
				CTFontManagerRegisterFontsForURL(URL(fileURLWithPath: pages + "/fonts/" + name) as CFURL, .process, nil)
			}
		}
		font = NSFontManager.shared.availableFontFamilies.contains(family) ? NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: family]), size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular) : .monospacedSystemFont(ofSize: size, weight: .regular)
		plain = .systemFont(ofSize: size * 0.9)
		bold = .systemFont(ofSize: size * 0.9, weight: .semibold)
		wide = ("0" as NSString).size(withAttributes: [.font: font]).width
		tall = (size * 1.5).rounded(.up)
		head = (size * 1.9).rounded(.up)
		band = (size * 2.6).rounded(.up)
		gap = (size * 0.6).rounded(.up)
		inked.removeAllObjects()
	}

	func arrange() {
		let sides = view == "sides"
		items = []
		spots = [:]
		shown = [:]
		let across = enclosingScrollView?.contentSize.width ?? bounds.width
		var top: CGFloat = 0
		for (n, section) in sections.enumerated() {
			items.append(Item(section: n, hunk: -1, top: top, tall: band, rows: 0))
			top += band
			for id in section.ids where id < hunks.count {
				let hunk = hunks[id]
				let rows = hunk.on || opened.contains(id) ? (sides ? hunk.pairs : hunk.rows.count) : 0
				var extra: CGFloat = 0
				if rows > 0, let own = notes[id], !own.isEmpty {
					let matched = sides ? match(id, hunk.rows) : []
					let cols = max(24, Int((across - wide * 10) / (wide * 0.9)))
					let placed = own.map { note in (at: sides ? (matched.firstIndex { $0.0 == note.row || $0.1 == note.row } ?? 0) : note.row, lines: Sheet.fold(note.text, cols)) }.sorted { $0.at < $1.at }
					shown[id] = placed
					extra = placed.reduce(0) { $0 + CGFloat($1.lines.count) * tall + 8 }
				}
				let high = head + CGFloat(rows) * tall + extra
				spots[id] = items.count
				items.append(Item(section: n, hunk: id, top: top, tall: high, rows: rows))
				top += high + gap
			}
			top += gap * 2
		}
		let room = enclosingScrollView?.contentSize ?? .zero
		setFrameSize(NSSize(width: room.width, height: max(room.height, top + room.height * 0.4)))
		needsDisplay = true
	}

	func focus(_ id: Int) {
		opened.insert(id)
		current = id
		arrange()
		guard let at = spots[id], let scroll = enclosingScrollView else { return }
		let item = items[at]
		let room = scroll.contentSize.height
		scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, item.tall < room ? item.top - (room - item.tall) / 2 : item.top - band)))
		scroll.reflectScrolledClipView(scroll.contentView)
		needsDisplay = true
	}

	func first(_ edge: CGFloat) -> Int {
		var low = 0
		var high = items.count
		while low < high {
			let mid = (low + high) / 2
			if items[mid].top + items[mid].tall < edge {
				low = mid + 1
			} else {
				high = mid
			}
		}
		return low
	}

	func match(_ id: Int, _ rows: [[String: Any]]) -> [(Int, Int)] {
		if let known = pairs[id] {
			return known
		}
		if pairs.count > 600 {
			pairs = [:]
			cuts = [:]
			dents = [:]
		}
		var dent = Int.max
		var out: [(Int, Int)] = []
		var marks: [Int: NSRange] = [:]
		var minus: [Int] = []
		var plus: [Int] = []
		let flush = {
			for n in 0..<max(minus.count, plus.count) {
				let left = n < minus.count ? minus[n] : -1
				let right = n < plus.count ? plus[n] : -1
				if left >= 0, right >= 0 {
					let a = (rows[left]["s"] as? String ?? "") as NSString
					let b = (rows[right]["s"] as? String ?? "") as NSString
					let short = min(a.length, b.length)
					var lead = 0
					while lead < short, a.character(at: lead) == b.character(at: lead) { lead += 1 }
					var trail = 0
					while trail < short - lead, a.character(at: a.length - 1 - trail) == b.character(at: b.length - 1 - trail) { trail += 1 }
					if Double(lead + trail) >= Double(short) * 0.4 {
						marks[left] = NSRange(location: lead, length: a.length - trail - lead)
						marks[right] = NSRange(location: lead, length: b.length - trail - lead)
					}
				}
				out.append((left, right))
			}
			minus = []
			plus = []
		}
		for (n, row) in rows.enumerated() {
			let mark = row["t"] as? String
			let text = row["s"] as? String ?? ""
			if text.contains(where: { $0 != " " && $0 != "\t" }) {
				dent = min(dent, text.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) })
			}
			if mark == " " {
				flush()
				out.append((n, n))
			} else if mark == "-" {
				minus.append(n)
			} else {
				plus.append(n)
			}
		}
		flush()
		pairs[id] = out
		dents[id] = dent == Int.max ? 0 : dent
		cuts[id] = marks
		return out
	}

	func ink(_ id: Int, _ n: Int, _ row: [String: Any], _ ext: String) -> NSAttributedString {
		let key = NSNumber(value: id << 20 | n)
		if let known = inked.object(forKey: key) {
			return known
		}
		let mark = row["t"] as? String ?? " "
		let text = String((row["s"] as? String ?? "").prefix(4000)).replacingOccurrences(of: "\t", with: "    ")
		let whole = text as NSString
		let out = NSMutableAttributedString(string: text, attributes: [.font: font, .foregroundColor: mark == "+" ? Sheet.tone(0xa9d9b1) : mark == "-" ? Sheet.tone(0xf2a3ab) : NSColor.white.withAlphaComponent(0.8)])
		Sheet.tones(whole, NSRange(location: 0, length: whole.length), ext, false) { out.addAttribute(.foregroundColor, value: $1, range: $0) }
		let size = whole.length
		if let cut = cuts[id]?[n], cut.length > 0, cut.location + cut.length <= size {
			out.addAttribute(.backgroundColor, value: mark == "+" ? Sheet.tone(0x6aab73, 0.38) : Sheet.tone(0xf75464, 0.36), range: cut)
		}
		inked.setObject(out, forKey: key)
		return out
	}

	static let lingo: [String: Set<String>] = {
		let sets: [(String, String)] = [
			("swift", "func class struct enum protocol extension import let var static final public private internal fileprivate open return if else for while repeat switch case default break continue guard defer do try catch throw throws rethrows async await in as is where self Self super init deinit typealias associatedtype some any inout mutating nonisolated override lazy weak unowned actor"),
			("go", "func type struct interface package import const var return if else for range switch case default break continue go defer chan map select fallthrough goto"),
			("js jsx mjs cjs ts tsx mts cts vue svelte", "function class extends implements interface type enum import from export default const let var static public private protected readonly return if else for while do switch case break continue try catch finally throw new async await yield in of as is typeof instanceof this super delete void namespace declare abstract"),
			("py pyi", "def class import from as return if elif else for while break continue try except finally raise with yield lambda pass global nonlocal in is not and or async await assert del self"),
			("rs", "fn struct enum trait impl mod use pub crate self Self super let mut const static return if else for while loop match break continue in as where async await move dyn ref unsafe type"),
			("c h cpp hpp cc m mm java kt kts cs dart scala zig", "class struct enum interface union typedef namespace using import package public private protected static final const void return if else for while do switch case default break continue try catch finally throw throws new delete this super extends implements override virtual inline extern sizeof fun val var when object companion null"),
			("sql", "select from where insert into values update set delete create table alter drop index view join left right inner outer on group by order having limit offset as and or not null is in exists union all distinct primary key foreign references default constraint begin commit function returns language declare end if then else case when"),
			("sh bash zsh fish mk", "if then else elif fi for while do done case esac in function return export local readonly set unset source alias exit break continue"),
			("just justfile .justfile", "set export unexport alias import mod if else assert shell positional-arguments dotenv-load allow-duplicate-recipes fallback"),
		]
		var found: [String: Set<String>] = [:]
		for (kinds, words) in sets {
			let set = Set(words.split(separator: " ").map(String.init))
			kinds.split(separator: " ").forEach { found[String($0)] = set }
		}
		return found
	}()

	@discardableResult
	static func tones(_ whole: NSString, _ range: NSRange, _ ext: String, _ inside: Bool, _ each: (NSRange, NSColor) -> Void) -> Bool {
		var at = range.location
		let size = range.location + range.length
		let known = lingo[ext] ?? words
		var open = inside
		if recipes.contains(ext), at < size {
			var end = at
			while end < size, whole.character(at: end) == 64 { end += 1 }
			let from = end
			while end < size, let scalar = UnicodeScalar(whole.character(at: end)), CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "-" { end += 1 }
			let rest = whole.substring(with: NSRange(location: end, length: size - end))
			if end > from, let colon = rest.firstIndex(of: ":"), !rest[rest.index(after: colon)...].hasPrefix("="), !rest[..<colon].contains("=") {
				each(NSRange(location: from, length: end - from), tone(0x56a8f5))
				at = end
			}
		}
		while at < size {
			if open {
				let close = whole.range(of: "*/", options: .literal, range: NSRange(location: at, length: size - at))
				let end = close.location == NSNotFound ? size : close.location + 2
				each(NSRange(location: at, length: end - at), tone(0x7a7e85))
				open = close.location == NSNotFound
				at = end
				continue
			}
			if recipes.contains(ext), whole.character(at: at) == 123, at + 1 < size, whole.character(at: at + 1) == 123 {
				let close = whole.range(of: "}}", options: .literal, range: NSRange(location: at, length: size - at))
				let end = close.location == NSNotFound ? size : close.location + 2
				each(NSRange(location: at, length: end - at), tone(0x42c3d4))
				at = end
				continue
			}
			let c = whole.character(at: at)
			if c == 47, at + 1 < size, whole.character(at: at + 1) == 42 {
				open = true
			} else if c == 34 || c == 39 || c == 96 {
				var end = at + 1
				while end < size, whole.character(at: end) != c, whole.character(at: end) != 10 {
					end += whole.character(at: end) == 92 ? 2 : 1
				}
				end = min(size, end + 1)
				var next = end
				while next < size, whole.character(at: next) == 32 { next += 1 }
				let key = next < size && whole.character(at: next) == 58 && keyed.contains(ext)
				each(NSRange(location: at, length: end - at), tone(key ? 0x56a8f5 : 0x6aab73))
				at = end
			} else if (c == 47 && at + 1 < size && whole.character(at: at + 1) == 47) || (c == 35 && hashed.contains(ext) && (at == range.location || whole.character(at: at - 1) == 32 || whole.character(at: at - 1) == 10)) || (c == 45 && ext == "sql" && at + 1 < size && whole.character(at: at + 1) == 45) {
				var end = at
				while end < size, whole.character(at: end) != 10 { end += 1 }
				each(NSRange(location: at, length: end - at), tone(0x7a7e85))
				at = end
			} else if c >= 48 && c <= 57 {
				var end = at + 1
				while end < size, let scalar = UnicodeScalar(whole.character(at: end)), CharacterSet.alphanumerics.contains(scalar) || scalar == "." || scalar == "_" { end += 1 }
				each(NSRange(location: at, length: end - at), tone(0x2aacb8))
				at = end
			} else if (c >= 65 && c <= 90) || (c >= 97 && c <= 122) || c == 95 || c == 36 || c == 64 {
				var end = at + 1
				while end < size, let scalar = UnicodeScalar(whole.character(at: end)), CharacterSet.alphanumerics.contains(scalar) || scalar == "_" || scalar == "$" { end += 1 }
				let word = whole.substring(with: NSRange(location: at, length: end - at))
				if atoms.contains(word) {
					each(NSRange(location: at, length: end - at), tone(0xc77dbb))
				} else if known.contains(word) || (ext == "sql" && known.contains(word.lowercased())) {
					each(NSRange(location: at, length: end - at), tone(0xcf8e6d))
				} else if c == 64 {
					each(NSRange(location: at, length: end - at), tone(0xb3ae60))
				} else if end < size, whole.character(at: end) == 40 {
					each(NSRange(location: at, length: end - at), tone(0x56a8f5))
				} else if c >= 65 && c <= 90 {
					each(NSRange(location: at, length: end - at), tone(0x57c1c8))
				}
				at = end
			} else {
				at += 1
			}
		}
		return open
	}

	func number(_ value: Int, _ x: CGFloat, _ y: CGFloat) {
		guard value > 0 else { return }
		let text = String(value) as NSString
		let attributes: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.3)]
		text.draw(at: NSPoint(x: x + CGFloat(digits) * wide - text.size(withAttributes: attributes).width, y: y), withAttributes: attributes)
	}

	func line(_ id: Int, _ n: Int, _ row: [String: Any], _ ext: String, _ left: Bool?, _ x: CGFloat, _ width: CGFloat, _ y: CGFloat) {
		let mark = row["t"] as? String ?? " "
		if mark != " " {
			(mark == "+" ? Sheet.tone(0x6aab73, 0.13) : Sheet.tone(0xf75464, 0.12)).setFill()
			NSRect(x: x, y: y, width: width, height: tall).fill()
		}
		let inset = (tall - font.ascender + font.descender) / 2
		var at = x
		if left != false {
			number(row["a"] as? Int ?? 0, at, y + inset)
			at += CGFloat(digits + 1) * wide
		}
		if left != true {
			number(row["b"] as? Int ?? 0, at, y + inset)
			at += CGFloat(digits + 1) * wide
		}
		(mark as NSString).draw(at: NSPoint(x: at + wide / 2, y: y + inset), withAttributes: [.font: font, .foregroundColor: NSColor.white.withAlphaComponent(0.4)])
		at += wide * 2
		NSGraphicsContext.saveGraphicsState()
		NSRect(x: at, y: y, width: x + width - at, height: tall).clip()
		if fogging {
			let haze = NSShadow()
			haze.shadowOffset = NSSize(width: -30000, height: 0)
			haze.shadowBlurRadius = 3
			haze.shadowColor = NSColor.white.withAlphaComponent(0.55)
			haze.set()
			ink(id, n, row, ext).draw(at: NSPoint(x: at - shift - CGFloat(dents[id] ?? 0) * wide + 30000, y: y + inset))
		} else {
			ink(id, n, row, ext).draw(at: NSPoint(x: at - shift - CGFloat(dents[id] ?? 0) * wide, y: y + inset))
		}
		NSGraphicsContext.restoreGraphicsState()
	}

	func title(_ section: Section, _ n: Int, _ y: CGFloat) {
		Sheet.tone(0x26282d).setFill()
		NSRect(x: 0, y: y, width: bounds.width, height: band).fill()
		NSColor.white.withAlphaComponent(0.1).setFill()
		NSRect(x: 0, y: y + band - 1, width: bounds.width, height: 1).fill()
		let name = "\(n + 1). " + section.title as NSString
		let inset = (band - bold.ascender + bold.descender) / 2
		name.draw(at: NSPoint(x: wide * 1.5, y: y + inset), withAttributes: [.font: bold, .foregroundColor: NSColor.white.withAlphaComponent(0.92)])
		let after = wide * 3 + name.size(withAttributes: [.font: bold]).width
		let counts = NSMutableAttributedString()
		if section.added > 0 {
			counts.append(NSAttributedString(string: "+\(section.added) ", attributes: [.font: font, .foregroundColor: Sheet.tone(0x6aab73)]))
		}
		if section.removed > 0 {
			counts.append(NSAttributedString(string: "−\(section.removed)", attributes: [.font: font, .foregroundColor: Sheet.tone(0xf75464)]))
		}
		let edge = bounds.width - counts.size().width - wide * 1.5
		counts.draw(at: NSPoint(x: edge, y: y + inset))
		NSGraphicsContext.saveGraphicsState()
		NSRect(x: after, y: y, width: max(0, edge - after - wide), height: band).clip()
		(section.detail as NSString).draw(at: NSPoint(x: after, y: y + inset), withAttributes: [.font: plain, .foregroundColor: NSColor.white.withAlphaComponent(0.5)])
		NSGraphicsContext.restoreGraphicsState()
	}

	func paint(_ item: Item, _ dirty: NSRect) {
		let hunk = hunks[item.hunk]
		let path = hunk.change < paths.count ? paths[hunk.change] : ""
		let ext = (path as NSString).pathExtension.lowercased()
		NSColor.white.withAlphaComponent(0.04).setFill()
		NSRect(x: 0, y: item.top, width: bounds.width, height: head).fill()
		let inset = (head - bold.ascender + bold.descender) / 2
		let label = hunk.label as NSString
		label.draw(at: NSPoint(x: wide * 1.5, y: item.top + inset), withAttributes: [.font: bold, .foregroundColor: NSColor.white.withAlphaComponent(0.9)])
		var said = hunk.status
		if sections[item.section].title != (path as NSString).lastPathComponent {
			said = (path as NSString).lastPathComponent + "  " + said
		}
		if item.rows == 0 {
			said += "  \(hunk.rows.count) lines, collapsed"
		}
		if !hunk.text.isEmpty {
			said += "  “" + hunk.text.replacingOccurrences(of: "\n", with: " ") + "”"
		}
		let tint = hunk.status == "accepted" ? Sheet.tone(0x6aab73) : hunk.status == "rejected" ? Sheet.tone(0xf75464) : NSColor.white.withAlphaComponent(0.5)
		(said as NSString).draw(at: NSPoint(x: wide * 3 + label.size(withAttributes: [.font: bold]).width, y: item.top + inset), withAttributes: [.font: plain, .foregroundColor: tint])
		fogging = fog && item.hunk != current
		if item.rows > 0 {
			let body = item.top + head
			let noted = shown[item.hunk]
			let from = noted != nil ? 0 : max(0, Int(((dirty.minY - body) / tall).rounded(.down)))
			let to = noted != nil ? item.rows : min(item.rows, Int(((dirty.maxY - body) / tall).rounded(.up)))
			let matched = match(item.hunk, hunk.rows)
			if from < to {
				if view == "sides" {
					let half = (bounds.width / 2).rounded(.down)
					for n in from..<to where n < matched.count {
						let y = body + CGFloat(n) * tall + lift(item.hunk, n)
						let (left, right) = matched[n]
						if left >= 0 {
							line(item.hunk, left, hunk.rows[left], ext, true, 0, half, y)
						} else {
							NSColor.white.withAlphaComponent(0.025).setFill()
							NSRect(x: 0, y: y, width: half, height: tall).fill()
						}
						if right >= 0 {
							line(item.hunk, right, hunk.rows[right], ext, false, half, bounds.width - half, y)
						} else {
							NSColor.white.withAlphaComponent(0.025).setFill()
							NSRect(x: half, y: y, width: bounds.width - half, height: tall).fill()
						}
					}
					NSColor.white.withAlphaComponent(0.1).setFill()
					NSRect(x: half, y: body + CGFloat(from) * tall, width: 1, height: noted != nil ? item.tall - head : CGFloat(to - from) * tall).fill()
				} else {
					for n in from..<to where n < hunk.rows.count {
						line(item.hunk, n, hunk.rows[n], ext, nil, 0, bounds.width, body + CGFloat(n) * tall + lift(item.hunk, n))
					}
				}
			}
		}
		for extra in shown[item.hunk] ?? [] where item.rows > 0 {
			let y = item.top + head + CGFloat(extra.at + 1) * tall + lift(item.hunk, extra.at)
			let box = NSRect(x: wide * 3, y: y + 2, width: bounds.width - wide * 6, height: CGFloat(extra.lines.count) * tall + 4)
			Sheet.tone(0x2b2d33).setFill()
			NSBezierPath(roundedRect: box, xRadius: 6, yRadius: 6).fill()
			Sheet.tone(0xef8221).setFill()
			NSBezierPath(roundedRect: NSRect(x: box.minX, y: box.minY, width: 3, height: box.height), xRadius: 1.5, yRadius: 1.5).fill()
			for (n, text) in extra.lines.enumerated() {
				(text as NSString).draw(at: NSPoint(x: box.minX + wide * 1.5, y: box.minY + 2 + CGFloat(n) * tall + (tall - plain.ascender + plain.descender) / 2), withAttributes: [.font: plain, .foregroundColor: NSColor.white.withAlphaComponent(text.hasPrefix("→") ? 0.92 : 0.7)])
			}
		}
		for pick in others + (chosen.map { [$0] } ?? []) where pick.hunk == item.hunk && item.rows > 0 {
			let top = item.top + head + CGFloat(pick.from) * tall + lift(item.hunk, pick.from)
			let end = item.top + head + CGFloat(pick.to + 1) * tall + lift(item.hunk, pick.to)
			NSColor(srgbRed: 0.47, green: 0.63, blue: 0.9, alpha: 0.22).setFill()
			NSRect(x: 0, y: top, width: bounds.width, height: end - top).fill(using: .sourceOver)
		}
		if hunk.status != "pending" {
			tint.setFill()
			NSRect(x: 0, y: item.top, width: 3, height: item.tall).fill()
		}
		if item.hunk != current {
			Sheet.tone(0x1e1f22, item.rows == 0 ? 0.5 : 0.35).setFill()
			NSRect(x: 0, y: item.top, width: bounds.width, height: item.tall).fill(using: .sourceOver)
		}
	}

	override func draw(_ dirty: NSRect) {
		Sheet.tone(0x1e1f22).setFill()
		dirty.fill()
		guard !items.isEmpty else { return }
		var at = first(dirty.minY)
		while at < items.count, items[at].top <= dirty.maxY {
			let item = items[at]
			if item.hunk < 0 {
				title(sections[item.section], item.section, item.top)
			} else if item.hunk < hunks.count {
				paint(item, dirty)
			}
			at += 1
		}
		let seen = visibleRect
		let over = items[min(items.count - 1, first(seen.minY + 1))]
		title(sections[over.section], over.section, seen.minY)
	}

	override func scrollWheel(with event: NSEvent) {
		guard abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) else {
			super.scrollWheel(with: event)
			return
		}
		shift = max(0, min(40000, shift - event.scrollingDeltaX * (event.hasPreciseScrollingDeltas ? 1 : wide * 4)))
		needsDisplay = true
	}

	static func fold(_ text: String, _ cols: Int) -> [String] {
		var out: [String] = []
		for part in text.components(separatedBy: "\n") {
			var line = ""
			for word in part.split(separator: " ", omittingEmptySubsequences: false) {
				if !line.isEmpty, line.count + word.count + 1 > cols {
					out.append(line)
					line = String(word)
				} else {
					line += (line.isEmpty ? "" : " ") + word
				}
			}
			out.append(line)
		}
		return out
	}

	func lift(_ id: Int, _ n: Int) -> CGFloat {
		(shown[id] ?? []).reduce(0) { $0 + ($1.at < n ? CGFloat($1.lines.count) * tall + 8 : 0) }
	}

	func row(_ point: NSPoint) -> (Int, Int)? {
		let at = first(point.y)
		guard at < items.count, items[at].hunk >= 0, items[at].rows > 0, point.y >= items[at].top + head else { return nil }
		let item = items[at]
		guard shown[item.hunk] != nil else {
			return (item.hunk, min(item.rows - 1, Int((point.y - item.top - head) / tall)))
		}
		for n in 0..<item.rows {
			let y = item.top + head + CGFloat(n) * tall + lift(item.hunk, n)
			if point.y >= y, point.y < y + tall {
				return (item.hunk, n)
			}
		}
		return nil
	}

	func read(_ pick: (hunk: Int, from: Int, to: Int)) -> (hunk: Int, line: Int, end: Int, text: String)? {
		guard pick.hunk >= 0, pick.hunk < hunks.count else { return nil }
		let rows = hunks[pick.hunk].rows
		let matched = view == "sides" ? match(pick.hunk, rows) : []
		var picked: [Int] = []
		for n in pick.from...max(pick.from, pick.to) where n < (view == "sides" ? matched.count : rows.count) {
			let pair = view == "sides" ? matched[n] : (n, n)
			for at in [pair.0, pair.1] where at >= 0 && !picked.contains(at) {
				picked.append(at)
			}
		}
		picked.sort()
		let numbers = picked.compactMap { rows[$0]["b"] as? Int }.filter { $0 > 0 }
		let olds = picked.compactMap { rows[$0]["a"] as? Int }.filter { $0 > 0 }
		let text = picked.map { (rows[$0]["t"] as? String ?? " ") + (rows[$0]["s"] as? String ?? "") }.joined(separator: "\n")
		return (pick.hunk, numbers.first ?? olds.first ?? 1, numbers.last ?? olds.last ?? 1, text)
	}

	func selections() -> [(hunk: Int, line: Int, end: Int, text: String)] {
		let picks = others + (chosen.map { [$0] } ?? [])
		if picks.isEmpty, current >= 0, current < hunks.count {
			let last = max(0, (view == "sides" ? hunks[current].pairs : hunks[current].rows.count) - 1)
			return read((hunk: current, from: 0, to: last)).map { [$0] } ?? []
		}
		return picks.compactMap { read($0) }
	}

	override func mouseDown(with event: NSEvent) {
		let point = convert(event.locationInWindow, from: nil)
		let more = event.modifierFlags.contains(.command)
		if more, let chosen {
			others.append(chosen)
		} else if !more {
			others = []
		}
		if let hit = row(point) {
			anchor = hit
			chosen = (hit.0, hit.1, hit.1)
			needsDisplay = true
			return
		}
		anchor = nil
		let at = first(point.y)
		guard at < items.count, items[at].hunk >= 0, point.y >= items[at].top else {
			chosen = nil
			needsDisplay = true
			return
		}
		if more, items[at].rows > 0 {
			chosen = (items[at].hunk, 0, items[at].rows - 1)
			needsDisplay = true
			return
		}
		chosen = nil
		needsDisplay = true
		pick(items[at].hunk)
	}

	override func menu(for event: NSEvent) -> NSMenu? {
		if chosen == nil, others.isEmpty, let hit = row(convert(event.locationInWindow, from: nil)) {
			chosen = (hit.0, hit.1, hit.1)
			needsDisplay = true
		}
		let menu = NSMenu()
		build(menu)
		return menu
	}

	override func mouseDragged(with event: NSEvent) {
		guard let anchor, let hit = row(convert(event.locationInWindow, from: nil)), hit.0 == anchor.0 else { return }
		chosen = (anchor.0, min(anchor.1, hit.1), max(anchor.1, hit.1))
		needsDisplay = true
	}

	override func mouseUp(with event: NSEvent) {
		guard let anchor else { return }
		self.anchor = nil
		if anchor.0 != current, others.isEmpty {
			let kept = chosen
			pick(anchor.0)
			chosen = kept
			needsDisplay = true
		}
	}
}

enum Grammar {
	static var known: [String: (Language, Query)] = [:]
	static var missed: Set<String> = []

	static func pair(_ ext: String) -> (Language, Query)? {
		if let hit = known[ext] {
			return hit
		}
		guard !missed.contains(ext) else { return nil }
		var pointer: OpaquePointer?
		var names: [String] = []
		switch ext {
		case "json", "jsonc", "jsonl", "map": (pointer, names) = (tree_sitter_json(), ["json"])
		case "js", "jsx", "mjs", "cjs": (pointer, names) = (tree_sitter_javascript(), ["javascript"])
		case "ts", "mts", "cts": (pointer, names) = (tree_sitter_typescript(), ["javascript", "typescript"])
		case "tsx": (pointer, names) = (tree_sitter_tsx(), ["javascript", "typescript"])
		case "go": (pointer, names) = (tree_sitter_go(), ["go"])
		case "py", "pyi": (pointer, names) = (tree_sitter_python(), ["python"])
		case "rs": (pointer, names) = (tree_sitter_rust(), ["rust"])
		case "sh", "bash", "zsh": (pointer, names) = (tree_sitter_bash(), ["bash"])
		case "html", "htm": (pointer, names) = (tree_sitter_html(), ["html"])
		case "css": (pointer, names) = (tree_sitter_css(), ["css"])
		case "swift": (pointer, names) = (tree_sitter_swift(), ["swift"])
		default: break
		}
		let rules = names.compactMap { FileManager.default.contents(atPath: pages + "/queries/" + $0 + ".scm") }.reduce(Data()) { $0 + $1 + Data("\n".utf8) }
		guard let pointer, !rules.isEmpty, let query = try? Query(language: Language(pointer), data: rules) else {
			if pointer != nil {
				note("unknown.log", ext + " grammar rules did not load")
			}
			missed.insert(ext)
			return nil
		}
		known[ext] = (Language(pointer), query)
		return known[ext]
	}

	static func tone(_ parts: [String]) -> NSColor? {
		switch parts.first ?? "" {
		case "keyword", "include", "conditional", "repeat", "exception": return Sheet.tone(0xcf8e6d)
		case "string": return Sheet.tone(parts.contains("key") || parts.contains("special") ? 0x56a8f5 : 0x6aab73)
		case "number", "float": return Sheet.tone(0x2aacb8)
		case "boolean", "constant": return Sheet.tone(0xc77dbb)
		case "comment": return Sheet.tone(0x7a7e85)
		case "function", "method": return Sheet.tone(0x56a8f5)
		case "type", "constructor", "namespace", "module": return Sheet.tone(0x57c1c8)
		case "property", "attribute", "label": return Sheet.tone(0xc9a26d)
		case "variable": return parts.contains("builtin") ? Sheet.tone(0xcf8e6d) : nil
		case "operator": return Sheet.tone(0xa9b7c6)
		case "punctuation": return Sheet.tone(0x9aa0a8)
		case "tag": return Sheet.tone(0xd5b778)
		case "escape", "embedded": return Sheet.tone(0x42c3d4)
		default: return nil
		}
	}
}

final class Gutter: NSView {
	weak var pad: Pad?

	override var isFlipped: Bool { true }

	override func draw(_ rect: NSRect) {
		Sheet.tone(0x1e1f22).setFill()
		bounds.fill()
		guard let pad, let layout = pad.layoutManager, let container = pad.textContainer else { return }
		let seen = pad.visibleRect
		let glyphs = layout.glyphRange(forBoundingRect: seen, in: container)
		let attributes: [NSAttributedString.Key: Any] = [.font: pad.font ?? .monospacedSystemFont(ofSize: 11, weight: .regular), .foregroundColor: NSColor.white.withAlphaComponent(0.3)]
		let inset = pad.textContainerInset.height
		var drawn = -1
		layout.enumerateLineFragments(forGlyphRange: glyphs) { box, _, _, range, _ in
			let at = layout.characterIndexForGlyph(at: range.location)
			let line = pad.line(at)
			guard line != drawn, pad.starts[line] == at else { return }
			drawn = line
			let y = box.minY + inset - seen.minY
			let text = String(line + 1) as NSString
			let size = text.size(withAttributes: attributes)
			text.draw(at: NSPoint(x: self.bounds.width - size.width - 8, y: y + (box.height - size.height) / 2), withAttributes: attributes)
			if let act = pad.trace(line + 1) {
				Sheet.tone(act == "wrote" ? pad.tints[2] : act == "edited" ? pad.tints[1] : pad.tints[0], act == "read" ? 0.8 : 1).setFill()
				NSRect(x: self.bounds.width - 3, y: y + 1, width: 2, height: box.height - 2).fill()
			}
			if let change = pad.changes.first(where: { line + 1 >= $0.from && line + 1 <= $0.to }) {
				Sheet.tone(change.gone ? 0xf75464 : pad.shade).setFill()
				NSRect(x: self.bounds.width - 6, y: change.gone ? y - 1.5 : y, width: 3, height: change.gone ? 3 : box.height).fill()
			}
			if pad.folds.contains(where: { pad.line($0.location) == line }) {
				("▸" as NSString).draw(at: NSPoint(x: 1, y: y + (box.height - size.height) / 2), withAttributes: attributes)
			} else if let grave = pad.flagged[line + 1] {
				Sheet.tone(grave ? 0xf75464 : 0xe8bf6a).setFill()
				NSBezierPath(ovalIn: NSRect(x: 2, y: y + box.height / 2 - 2, width: 4, height: 4)).fill()
			}
		}
	}

	override func mouseDown(with event: NSEvent) {
		guard let pad, let layout = pad.layoutManager, let container = pad.textContainer else { return }
		let point = convert(event.locationInWindow, from: nil)
		let at = layout.characterIndex(for: NSPoint(x: 1, y: point.y + pad.visibleRect.minY - pad.textContainerInset.height), in: container, fractionOfDistanceBetweenInsertionPoints: nil)
		let line = pad.line(at) + 1
		guard let change = pad.changes.first(where: { line >= $0.from && line <= $0.to }), pad.isEditable else {
			pad.fold(line, nil)
			return
		}
		let menu = NSMenu()
		let back = menu.addItem(withTitle: "Revert This Change", action: #selector(Pad.settled(_:)), keyEquivalent: "")
		back.tag = change.id * 2 + 1
		back.target = pad
		let keep = menu.addItem(withTitle: "Keep This Change", action: #selector(Pad.settled(_:)), keyEquivalent: "")
		keep.tag = change.id * 2
		keep.target = pad
		NSMenu.popUpContextMenu(menu, with: event, for: self)
	}
}

final class Pad: NSTextView, NSLayoutManagerDelegate, NSTextStorageDelegate {
	var path = ""
	var ext = ""
	var starts: [Int] = [0]
	var traced: [[String: Any]] = []
	var tracing = true
	var tints = [0x56a8f5, 0xef8221, 0x6aab73]
	var flagged: [Int: Bool] = [:]
	var notes: [(NSRange, String)] = []
	var changes: [(from: Int, to: Int, id: Int, gone: Bool)] = []
	var folds: [NSRange] = []
	var grown: [NSRange] = []
	var carets: [Int] = []
	var asked: [NSRange] = []
	var tree: MutableTree?
	var parsing = 0
	var shade = 0x6aab73
	var scrolled: () -> Void = {}
	var offered: [String] = []
	var loading = false
	var settling: DispatchWorkItem?
	var hovering: DispatchWorkItem?
	var offering: DispatchWorkItem?
	weak var gutter: Gutter?
	var edited: (String) -> Void = { _ in }
	var moved: () -> Void = {}
	var ask: (String, String, Int, Int, Any?, @escaping (Any?) -> Void) -> Void = { _, _, _, _, _, answer in answer(nil) }
	var go: (String, Int) -> Void = { _, _ in }
	var resolve: (Int, Bool) -> Void = { _, _ in }
	var tidied: () -> Void = {}
	var build: (NSMenu) -> Void = { _ in }

	static func make() -> (NSView, Pad) {
		let box = NSView(frame: NSRect(x: 0, y: 0, width: 600, height: 400))
		let scroll = NSScrollView(frame: NSRect(x: 40, y: 0, width: 560, height: 400))
		let pad = Pad(frame: NSRect(x: 0, y: 0, width: 560, height: 400))
		pad.isRichText = false
		pad.allowsUndo = true
		pad.usesFindBar = true
		pad.isIncrementalSearchingEnabled = true
		pad.isAutomaticQuoteSubstitutionEnabled = false
		pad.isAutomaticDashSubstitutionEnabled = false
		pad.isAutomaticTextReplacementEnabled = false
		pad.isAutomaticSpellingCorrectionEnabled = false
		pad.isContinuousSpellCheckingEnabled = false
		pad.isGrammarCheckingEnabled = false
		pad.smartInsertDeleteEnabled = false
		pad.backgroundColor = Sheet.tone(0x1e1f22)
		pad.textColor = Sheet.tone(0xbcbec4)
		pad.insertionPointColor = .white
		pad.selectedTextAttributes = [.backgroundColor: NSColor(srgbRed: 0.47, green: 0.63, blue: 0.9, alpha: 0.28)]
		pad.textContainerInset = NSSize(width: 4, height: 6)
		pad.minSize = .zero
		pad.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
		pad.isVerticallyResizable = true
		pad.autoresizingMask = []
		pad.layoutManager?.allowsNonContiguousLayout = true
		pad.layoutManager?.delegate = pad
		pad.textStorage?.delegate = pad
		pad.wrap(false)
		scroll.documentView = pad
		scroll.hasVerticalScroller = true
		scroll.hasHorizontalScroller = false
		scroll.scrollerStyle = .overlay
		scroll.verticalScroller = Scroller()
		scroll.backgroundColor = Sheet.tone(0x1e1f22)
		scroll.autoresizingMask = [.width, .height]
		let gutter = Gutter(frame: NSRect(x: 0, y: 0, width: 40, height: 400))
		gutter.pad = pad
		gutter.autoresizingMask = [.height]
		pad.gutter = gutter
		box.addSubview(gutter)
		box.addSubview(scroll)
		scroll.contentView.postsBoundsChangedNotifications = true
		NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroll.contentView, queue: .main) { [weak pad] _ in
			pad?.tint()
			pad?.gutter?.needsDisplay = true
			pad?.scrolled()
		}
		pad.addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseMoved, .activeInKeyWindow, .inVisibleRect], owner: pad))
		return (box, pad)
	}

	func wrap(_ on: Bool) {
		isHorizontallyResizable = !on
		textContainer?.widthTracksTextView = on
		textContainer?.containerSize = NSSize(width: on ? (enclosingScrollView?.contentSize.width ?? 400) : CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
		if on, let scroll = enclosingScrollView {
			setFrameSize(NSSize(width: scroll.contentSize.width, height: frame.height))
			autoresizingMask = [.width]
		} else {
			autoresizingMask = []
		}
	}

	func fit() {
		guard let gutter, let scroll = enclosingScrollView, let box = gutter.superview, let font else { return }
		let wide = (CGFloat(max(2, String(starts.count).count)) + 2.5) * ("0" as NSString).size(withAttributes: [.font: font]).width
		gutter.frame = NSRect(x: 0, y: 0, width: wide, height: box.bounds.height)
		scroll.frame = NSRect(x: wide, y: 0, width: max(0, box.bounds.width - wide), height: box.bounds.height)
		gutter.needsDisplay = true
	}

	func size(_ scale: Double) {
		let size = CGFloat(12 * scale)
		let family = "Liga Roboto Mono"
		let face = NSFontManager.shared.availableFontFamilies.contains(family) ? NSFont(descriptor: NSFontDescriptor(fontAttributes: [.family: family]), size: size) ?? .monospacedSystemFont(ofSize: size, weight: .regular) : NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
		let style = NSMutableParagraphStyle()
		style.lineHeightMultiple = 1.25
		style.tabStops = []
		style.defaultTabInterval = (" " as NSString).size(withAttributes: [.font: face]).width * 4
		font = face
		defaultParagraphStyle = style
		typingAttributes = [.font: face, .foregroundColor: Sheet.tone(0xbcbec4), .paragraphStyle: style]
		if let storage = textStorage {
			loading = true
			storage.setAttributes(typingAttributes, range: NSRange(location: 0, length: storage.length))
			loading = false
		}
		fit()
		tint()
	}

	func load(_ path: String, _ text: String) {
		loading = true
		self.path = path
		ext = (path as NSString).pathExtension.lowercased()
		if ext.isEmpty {
			ext = (path as NSString).lastPathComponent.lowercased()
		}
		traced = []
		flagged = [:]
		notes = []
		changes = []
		folds = []
		grown = []
		asked = []
		string = text
		textStorage?.setAttributes(typingAttributes, range: NSRange(location: 0, length: (text as NSString).length))
		undoManager?.removeAllActions()
		loading = false
		tree = nil
		parse()
		wrap(["md", "markdown", "mdx", "txt"].contains(ext))
		index()
		setSelectedRange(NSRange(location: 0, length: 0))
		scroll(.zero)
		tint()
		moved()
	}

	func index() {
		let whole = string as NSString
		var found = [0]
		found.reserveCapacity(whole.length / 30)
		var at = 0
		while at < whole.length {
			let hit = whole.range(of: "\n", options: .literal, range: NSRange(location: at, length: whole.length - at))
			guard hit.location != NSNotFound else { break }
			at = hit.location + 1
			found.append(at)
		}
		let digits = String(starts.count).count
		starts = found
		if String(found.count).count != digits || gutter?.frame.width ?? 0 < 10 {
			fit()
		}
		gutter?.needsDisplay = true
	}

	func line(_ at: Int) -> Int {
		var low = 0
		var high = starts.count
		while low < high {
			let mid = (low + high) / 2
			if starts[mid] <= at {
				low = mid + 1
			} else {
				high = mid
			}
		}
		return max(0, low - 1)
	}

	func span(_ line: Int) -> NSRange {
		let n = min(max(1, line), starts.count) - 1
		let end = n + 1 < starts.count ? starts[n + 1] - 1 : (string as NSString).length
		return NSRange(location: starts[n], length: max(0, end - starts[n]))
	}

	func rows(_ range: NSRange) -> NSRange {
		(string as NSString).lineRange(for: range)
	}

	func trace(_ line: Int) -> String? {
		guard tracing else { return nil }
		var found: String?
		for entry in traced where line >= entry["from"] as? Int ?? 0 && line <= entry["to"] as? Int ?? 0 {
			let act = entry["act"] as? String ?? "read"
			if act == "wrote" { return act }
			if act == "edited" || found == nil { found = act }
		}
		return found
	}

	func tint() {
		guard let layout = layoutManager, let container = textContainer else { return }
		let whole = string as NSString
		guard whole.length > 0 else { return }
		let seen = layout.characterRange(forGlyphRange: layout.glyphRange(forBoundingRect: visibleRect, in: container), actualGlyphRange: nil)
		let range = whole.lineRange(for: seen)
		layout.removeTemporaryAttribute(.foregroundColor, forCharacterRange: range)
		layout.removeTemporaryAttribute(.backgroundColor, forCharacterRange: range)
		let back = NSRange(location: max(0, range.location - 20000), length: range.location - max(0, range.location - 20000))
		let opened = whole.range(of: "/*", options: [.literal, .backwards], range: back)
		let closed = whole.range(of: "*/", options: [.literal, .backwards], range: back)
		var inside = opened.location != NSNotFound && (closed.location == NSNotFound || closed.location < opened.location)
		var at = range.location
		if let tree, let found = Grammar.pair(ext) {
			let cursor = found.1.execute(in: tree)
			cursor.setRange(range)
			for named in cursor.resolve(with: .init(string: string)).highlights() {
				let lit = NSIntersectionRange(named.range, range)
				if lit.length > 0, let color = Grammar.tone(named.nameComponents) {
					layout.addTemporaryAttribute(.foregroundColor, value: color, forCharacterRange: lit)
				}
			}
			at = range.location + range.length
		}
		while at < range.location + range.length {
			let row = whole.lineRange(for: NSRange(location: at, length: 0))
			if row.length < 4000 {
				inside = Sheet.tones(whole, row, ext, inside) { layout.addTemporaryAttribute(.foregroundColor, value: $1, forCharacterRange: $0) }
			}
			at = row.location + max(1, row.length)
		}
		for change in changes where !change.gone {
			let from = span(change.from)
			let to = span(change.to)
			let lit = NSIntersectionRange(NSRange(location: from.location, length: to.location + to.length - from.location + 1), range)
			if lit.length > 0 {
				layout.addTemporaryAttribute(.backgroundColor, value: Sheet.tone(shade, 0.12), forCharacterRange: lit)
			}
		}
		pair()
	}

	func parse() {
		parsing += 1
		let mine = parsing
		let text = string
		guard (text as NSString).length < 2000000, let found = Grammar.pair(ext) else {
			tree = nil
			return
		}
		DispatchQueue.global(qos: .userInitiated).async {
			let parser = Parser()
			guard (try? parser.setLanguage(found.0)) != nil, let made = parser.parse(text) else { return }
			DispatchQueue.main.async {
				guard mine == self.parsing else { return }
				self.tree = made
				self.tint()
			}
		}
	}

	func pair() {
		guard let layout = layoutManager else { return }
		let whole = string as NSString
		let at = selectedRange().location
		let opens: [unichar] = [40, 91, 123]
		let closes: [unichar] = [41, 93, 125]
		for spot in [at - 1, at] where spot >= 0 && spot < whole.length && selectedRange().length == 0 {
			let c = whole.character(at: spot)
			guard let kind = opens.firstIndex(of: c) ?? closes.firstIndex(of: c) else { continue }
			let forward = opens.contains(c)
			var depth = 0
			var seek = spot
			var steps = 0
			while seek >= 0, seek < whole.length, steps < 20000 {
				let d = whole.character(at: seek)
				if d == opens[kind] { depth += forward ? 1 : -1 }
				if d == closes[kind] { depth += forward ? -1 : 1 }
				if depth == 0 {
					for hit in [spot, seek] {
						layout.addTemporaryAttribute(.backgroundColor, value: NSColor.white.withAlphaComponent(0.18), forCharacterRange: NSRange(location: hit, length: 1))
					}
					return
				}
				seek += forward ? 1 : -1
				steps += 1
			}
			return
		}
	}

	func mark(_ list: [[String: Any]]) {
		guard let layout = layoutManager else { return }
		let whole = string as NSString
		let all = NSRange(location: 0, length: whole.length)
		layout.removeTemporaryAttribute(.underlineStyle, forCharacterRange: all)
		layout.removeTemporaryAttribute(.underlineColor, forCharacterRange: all)
		flagged = [:]
		notes = []
		for entry in list.prefix(2000) {
			let line = entry["line"] as? Int ?? 1
			let last = entry["endLine"] as? Int ?? line
			let grave = entry["severity"] as? String != "warning"
			let from = span(line)
			let to = span(last)
			let start = min(from.location + from.length, from.location + max(0, (entry["column"] as? Int ?? 1) - 1))
			let end = max(start + 1, min(to.location + to.length, to.location + max(0, (entry["endColumn"] as? Int ?? 1) - 1)))
			let range = NSRange(location: start, length: min(whole.length, end) - start)
			guard range.length > 0 else { continue }
			layout.addTemporaryAttributes([.underlineStyle: NSUnderlineStyle.thick.rawValue, .underlineColor: Sheet.tone(grave ? 0xf75464 : 0xe8bf6a)], forCharacterRange: range)
			flagged[line] = grave || flagged[line] == true
			notes.append((range, entry["message"] as? String ?? ""))
		}
		gutter?.needsDisplay = true
	}

	func show(_ line: Int, _ end: Int) {
		let first = span(line)
		let range = end > line ? NSRange(location: first.location, length: span(end).location + span(end).length - first.location) : NSRange(location: first.location, length: 0)
		setSelectedRange(range)
		if let scroll = enclosingScrollView, let layout = layoutManager, let container = textContainer {
			let box = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: NSRange(location: first.location, length: 0), actualCharacterRange: nil), in: container)
			scroll.contentView.scroll(to: NSPoint(x: 0, y: max(0, box.midY - scroll.contentSize.height / 2)))
			scroll.reflectScrolledClipView(scroll.contentView)
		}
		window?.makeFirstResponder(self)
	}

	func spot() -> (line: Int, end: Int, text: String, column: Int) {
		let range = selectedRange()
		let first = line(range.location)
		let last = line(max(range.location, range.location + range.length - (range.length > 0 ? 1 : 0)))
		let from = starts[first]
		let to = span(last + 1)
		return (first + 1, last + 1, (string as NSString).substring(with: NSRange(location: from, length: to.location + to.length - from)), range.location - from + 1)
	}

	func put(_ range: NSRange, _ text: String, _ select: NSRange? = nil) {
		guard shouldChangeText(in: range, replacementString: text) else { return }
		textStorage?.replaceCharacters(in: range, with: text)
		didChangeText()
		if let select {
			setSelectedRange(select)
		}
	}

	func textStorage(_ storage: NSTextStorage, didProcessEditing mask: NSTextStorageEditActions, range: NSRange, changeInLength delta: Int) {
		guard mask.contains(.editedCharacters), !loading else { return }
		let start = range.location
		asked = asked.compactMap { held in
			if held.location + held.length <= start { return held }
			if held.location >= start + range.length - delta { return NSRange(location: held.location + delta, length: held.length) }
			return held.length + delta > 0 ? NSRange(location: min(held.location, start), length: held.length + delta) : nil
		}
		folds = folds.compactMap { fold in
			if fold.location + fold.length <= start { return fold }
			if fold.location >= start + range.length - delta { return NSRange(location: fold.location + delta, length: fold.length) }
			return nil
		}
	}

	func layoutManager(_ layout: NSLayoutManager, shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>, properties: UnsafePointer<NSLayoutManager.GlyphProperty>, characterIndexes: UnsafePointer<Int>, font: NSFont, forGlyphRange range: NSRange) -> Int {
		guard !folds.isEmpty else { return 0 }
		var changed = false
		var own = Array(UnsafeBufferPointer(start: properties, count: range.length))
		for n in 0..<range.length where folds.contains(where: { NSLocationInRange(characterIndexes[n], $0) }) {
			own[n] = .null
			changed = true
		}
		guard changed else { return 0 }
		layout.setGlyphs(glyphs, properties: own, characterIndexes: characterIndexes, font: font, forGlyphRange: range)
		return range.length
	}

	func fold(_ line: Int, _ shut: Bool?) {
		guard let layout = layoutManager else { return }
		let whole = string as NSString
		let head = span(line)
		if let at = folds.firstIndex(where: { $0.location == head.location + head.length }) {
			guard shut != true else { return }
			let range = folds.remove(at: at)
			layout.invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
			layout.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
		} else if shut != false {
			func dent(_ n: Int) -> Int? {
				let text = whole.substring(with: span(n))
				return text.contains { $0 != " " && $0 != "\t" } ? text.prefix { $0 == " " || $0 == "\t" }.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) } : nil
			}
			guard let own = dent(line) else { return }
			var last = line
			var n = line + 1
			while n <= starts.count {
				if let deep = dent(n) {
					if deep <= own { break }
					last = n
				}
				n += 1
			}
			guard last > line else { return }
			let end = span(last)
			let range = NSRange(location: head.location + head.length, length: end.location + end.length - head.location - head.length)
			folds.append(range)
			if NSIntersectionRange(selectedRange(), range).length > 0 || NSLocationInRange(selectedRange().location, range) {
				setSelectedRange(NSRange(location: range.location, length: 0))
			}
			layout.invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
			layout.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
		}
		gutter?.needsDisplay = true
		tint()
	}

	func foldAll(_ shut: Bool) {
		if shut {
			var n = 1
			while n <= starts.count {
				fold(n, true)
				if let made = folds.last, line(made.location) + 1 == n {
					n = line(made.location + made.length) + 2
				} else {
					n += 1
				}
			}
		} else {
			let all = folds
			folds = []
			for range in all {
				layoutManager?.invalidateGlyphs(forCharacterRange: range, changeInLength: 0, actualCharacterRange: nil)
				layoutManager?.invalidateLayout(forCharacterRange: range, actualCharacterRange: nil)
			}
			gutter?.needsDisplay = true
		}
	}

	override func didChangeText() {
		super.didChangeText()
		guard !loading else { return }
		grown = []
		index()
		tint()
		settling?.cancel()
		let work = DispatchWorkItem { [weak self] in
			guard let self else { return }
			self.edited(self.string)
		}
		settling = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.15, execute: work)
		parse()
	}

	override func setSelectedRanges(_ ranges: [NSValue], affinity: NSSelectionAffinity, stillSelecting: Bool) {
		super.setSelectedRanges(ranges, affinity: affinity, stillSelecting: stillSelecting)
		if !loading, !stillSelecting {
			tint()
			moved()
		}
	}

	override func insertNewline(_ sender: Any?) {
		let whole = string as NSString
		let row = whole.lineRange(for: NSRange(location: selectedRange().location, length: 0))
		let lead = whole.substring(with: row).prefix { $0 == " " || $0 == "\t" }
		super.insertNewline(sender)
		if !lead.isEmpty {
			insertText(String(lead), replacementRange: selectedRange())
		}
	}

	override func insertTab(_ sender: Any?) {
		insertText(["go", "swift", "mk", "makefile", "justfile"].contains(ext) ? "\t" : "    ", replacementRange: selectedRange())
	}

	override func insertText(_ string: Any, replacementRange: NSRange) {
		if let typed = string as? String, spread(typed, false) {
			return
		}
		super.insertText(string, replacementRange: replacementRange)
		guard let typed = string as? String, typed.count == 1, let c = typed.unicodeScalars.first else { return }
		offering?.cancel()
		if typed == "." {
			complete(nil)
		} else if CharacterSet.alphanumerics.contains(c) || typed == "_" {
			let at = selectedRange().location
			let whole = self.string as NSString
			var from = at
			while from > 0, let s = UnicodeScalar(whole.character(at: from - 1)), CharacterSet.alphanumerics.contains(s) || s == "_" { from -= 1 }
			guard at - from >= 2 else { return }
			let work = DispatchWorkItem { [weak self] in self?.complete(nil) }
			offering = work
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
		}
	}

	override func complete(_ sender: Any?) {
		let at = selectedRange().location
		let row = line(at)
		ask("textDocument/completion", string, row, at - starts[row], nil) { [weak self] reply in
			guard let self else { return }
			let items = (reply as? [String: Any])?["items"] as? [[String: Any]] ?? reply as? [[String: Any]] ?? []
			self.offered = items.prefix(400).compactMap { ($0["insertText"] as? String) ?? ($0["label"] as? String) }
			guard !self.offered.isEmpty, self.selectedRange().location == at else { return }
			self.offer(sender)
		}
	}

	func offer(_ sender: Any?) {
		super.complete(sender)
	}

	override func completions(forPartialWordRange charRange: NSRange, indexOfSelectedItem index: UnsafeMutablePointer<Int>) -> [String]? {
		let typed = (string as NSString).substring(with: charRange).lowercased()
		index.pointee = -1
		return offered.filter { typed.isEmpty || ($0.lowercased().hasPrefix(typed) && $0.lowercased() != typed) }
	}

	func local(_ at: Int) -> String {
		let whole = string as NSString
		let word = selectionRange(forProposedRange: NSRange(location: at, length: 0), granularity: .selectByWord)
		guard word.length > 0, word.length < 80 else { return "" }
		let name = whole.substring(with: word)
		guard name.range(of: "^[A-Za-z_$][\\w$]*$", options: .regularExpression) != nil, whole.length < 3000000 else { return "" }
		let safe = NSRegularExpression.escapedPattern(for: name)
		guard let every = try? NSRegularExpression(pattern: "\\b" + safe + "\\b"), let declared = try? NSRegularExpression(pattern: "^.*\\b(func|function|fn|def|class|struct|enum|protocol|interface|type|trait|const|let|var|val|static|local)\\s+" + safe + "\\b.*$", options: [.anchorsMatchLines]) else { return "" }
		let all = NSRange(location: 0, length: whole.length)
		let here = line(at)
		var lines: [String] = []
		for match in declared.matches(in: string, range: all).prefix(6) where line(match.range.location) != here {
			lines.append("line \(line(match.range.location) + 1)  " + whole.substring(with: match.range).trimmingCharacters(in: .whitespaces).prefix(140))
		}
		let uses = every.numberOfMatches(in: string, range: all)
		lines.append(name + " · \(uses) " + (uses == 1 ? "use" : "uses") + " in this file")
		return lines.joined(separator: "\n")
	}

	override func mouseMoved(with event: NSEvent) {
		super.mouseMoved(with: event)
		hovering?.cancel()
		Tips.shared.hide()
		let point = convert(event.locationInWindow, from: nil)
		let work = DispatchWorkItem { [weak self] in
			guard let self, let layout = self.layoutManager, let container = self.textContainer else { return }
			let spot = NSPoint(x: point.x - self.textContainerInset.width, y: point.y - self.textContainerInset.height)
			var part: CGFloat = 0
			let at = layout.characterIndex(for: spot, in: container, fractionOfDistanceBetweenInsertionPoints: &part)
			guard at < (self.string as NSString).length, layout.boundingRect(forGlyphRange: NSRange(location: layout.glyphIndexForCharacter(at: at), length: 1), in: container).insetBy(dx: -2, dy: 0).contains(spot) else { return }
			if let note = self.notes.first(where: { NSLocationInRange(at, $0.0) }) {
				Tips.shared.show(note.1)
				return
			}
			let near = self.local(at)
			let row = self.line(at)
			self.ask("textDocument/hover", self.string, row, at - self.starts[row], nil) { reply in
				let contents = (reply as? [String: Any])?["contents"]
				let text = contents as? String ?? (contents as? [String: Any])?["value"] as? String ?? (contents as? [Any])?.compactMap { $0 as? String ?? ($0 as? [String: Any])?["value"] as? String }.joined(separator: "\n") ?? ""
				let said = [String(text.prefix(600)), near].filter { !$0.isEmpty }.joined(separator: "\n")
				if !said.isEmpty {
					Tips.shared.show(said)
				}
			}
		}
		hovering = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: work)
	}

	func declare() {
		let at = selectedRange().location
		let row = line(at)
		ask("textDocument/definition", string, row, at - starts[row], nil) { [weak self] reply in
			guard let first = (reply as? [[String: Any]])?.first ?? reply as? [String: Any], let uri = first["targetUri"] as? String ?? first["uri"] as? String, let url = URL(string: uri) else { return }
			let range = first["targetSelectionRange"] as? [String: Any] ?? first["range"] as? [String: Any]
			self?.go(url.path, (((range?["start"] as? [String: Any])?["line"] as? Int) ?? 0) + 1)
		}
	}

	func tidy(_ done: @escaping (Bool) -> Void) {
		let before = string
		let whole = before as NSString
		ask("textDocument/formatting", before, 0, 0, ["tabSize": 4, "insertSpaces": !before.prefix(4000).contains("\t")]) { [weak self] reply in
			guard let self, let edits = reply as? [[String: Any]], !edits.isEmpty, self.string == before, let storage = self.textStorage else {
				done(false)
				return
			}
			func offset(_ point: [String: Any]?) -> Int {
				let row = min(point?["line"] as? Int ?? 0, self.starts.count - 1)
				return min(whole.length, self.starts[row] + (point?["character"] as? Int ?? 0))
			}
			let sorted = edits.compactMap { edit -> (NSRange, String)? in
				guard let range = edit["range"] as? [String: Any], let text = edit["newText"] as? String else { return nil }
				let from = offset(range["start"] as? [String: Any])
				return (NSRange(location: from, length: max(0, offset(range["end"] as? [String: Any]) - from)), text)
			}.sorted { $0.0.location > $1.0.location }
			guard self.shouldChangeText(in: NSRange(location: 0, length: whole.length), replacementString: nil) else {
				done(false)
				return
			}
			storage.beginEditing()
			for (range, text) in sorted {
				storage.replaceCharacters(in: range, with: text)
			}
			storage.endEditing()
			self.didChangeText()
			done(true)
		}
	}

	@objc func settled(_ sender: NSMenuItem) {
		resolve(sender.tag / 2, sender.tag % 2 == 1)
	}

	func grow() {
		let whole = string as NSString
		let range = selectedRange()
		var next = selectionRange(forProposedRange: range, granularity: .selectByWord)
		if next.length <= range.length {
			var depth = 0
			var from = range.location - 1
			next = NSRange(location: 0, length: whole.length)
			while from >= 0, range.location - from < 100000 {
				let c = whole.character(at: from)
				if c == 41 || c == 93 || c == 125 { depth += 1 }
				if c == 40 || c == 91 || c == 123 {
					if depth == 0 {
						var to = range.location + range.length
						var deep = 0
						while to < whole.length {
							let d = whole.character(at: to)
							if d == 40 || d == 91 || d == 123 { deep += 1 }
							if d == 41 || d == 93 || d == 125 {
								if deep == 0 { break }
								deep -= 1
							}
							to += 1
						}
						let inner = NSRange(location: from + 1, length: max(0, to - from - 1))
						next = inner.length > range.length ? inner : NSRange(location: from, length: min(whole.length, to + 1) - from)
						break
					}
					depth -= 1
				}
				from -= 1
			}
		}
		guard next.length > range.length else { return }
		let kept = grown + [range]
		setSelectedRange(next)
		grown = kept
	}

	func shrink() {
		guard let last = grown.popLast() else { return }
		let kept = grown
		setSelectedRange(last)
		grown = kept
	}

	func toggle() {
		let whole = string as NSString
		let block = rows(selectedRange())
		let mark = Sheet.hashed.contains(ext) || ["py", "rb", "toml", "yaml", "yml"].contains(ext) ? "#" : ext == "sql" || ext == "lua" ? "--" : "//"
		let lines = whole.substring(with: block).components(separatedBy: "\n")
		let live = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
		let on = !live.isEmpty && live.allSatisfy { $0.trimmingCharacters(in: .whitespaces).hasPrefix(mark) }
		let out = lines.map { text -> String in
			guard !text.trimmingCharacters(in: .whitespaces).isEmpty else { return text }
			let lead = String(text.prefix { $0 == " " || $0 == "\t" })
			let rest = String(text.dropFirst(lead.count))
			if on {
				let cut = rest.dropFirst(mark.count)
				return lead + (cut.hasPrefix(" ") ? String(cut.dropFirst()) : String(cut))
			}
			return lead + mark + " " + rest
		}.joined(separator: "\n")
		put(block, out, NSRange(location: block.location, length: (out as NSString).length - (out.hasSuffix("\n") ? 1 : 0)))
	}

	func shift(_ down: Bool) {
		let whole = string as NSString
		let block = rows(selectedRange())
		let chosen = selectedRange()
		if down {
			guard block.location + block.length < whole.length else { return }
			let next = whole.lineRange(for: NSRange(location: block.location + block.length, length: 0))
			var moving = whole.substring(with: block)
			var other = whole.substring(with: next)
			if !other.hasSuffix("\n") {
				other += "\n"
				moving = String(moving.dropLast())
			}
			put(NSRange(location: block.location, length: block.length + next.length), other + moving, NSRange(location: chosen.location + (other as NSString).length, length: chosen.length))
		} else {
			guard block.location > 0 else { return }
			let before = whole.lineRange(for: NSRange(location: block.location - 1, length: 0))
			var moving = whole.substring(with: block)
			var other = whole.substring(with: before)
			if !moving.hasSuffix("\n") {
				moving += "\n"
				other = String(other.dropLast())
			}
			put(NSRange(location: before.location, length: before.length + block.length), moving + other, NSRange(location: chosen.location - before.length, length: chosen.length))
		}
	}

	func more(_ all: Bool) {
		let whole = string as NSString
		var ranges = selectedRanges.map { $0.rangeValue }
		if ranges.count == 1, ranges[0].length == 0 {
			setSelectedRange(selectionRange(forProposedRange: ranges[0], granularity: .selectByWord))
			return
		}
		guard let first = ranges.first, first.length > 0 else { return }
		let word = whole.substring(with: first)
		var from = all ? 0 : (ranges.last.map { $0.location + $0.length } ?? 0)
		while from < whole.length {
			let hit = whole.range(of: word, options: .literal, range: NSRange(location: from, length: whole.length - from))
			guard hit.location != NSNotFound else { break }
			if !ranges.contains(where: { NSEqualRanges($0, hit) }) {
				ranges.append(hit)
				if !all { break }
			}
			from = hit.location + hit.length
		}
		setSelectedRanges(ranges.sorted { $0.location < $1.location }.map { NSValue(range: $0) }, affinity: .downstream, stillSelecting: false)
		if let last = ranges.last, !all {
			scrollRangeToVisible(last)
		}
	}

	override func mouseDown(with event: NSEvent) {
		if event.modifierFlags.intersection([.command, .shift, .option, .control]) == .command, isEditable {
			let at = characterIndexForInsertion(at: convert(event.locationInWindow, from: nil))
			if selectedRange().length == 0, at != selectedRange().location, !carets.contains(at) {
				carets.append(at)
				needsDisplay = true
			}
			return
		}
		carets = []
		super.mouseDown(with: event)
	}

	func spread(_ text: String, _ back: Bool) -> Bool {
		guard !carets.isEmpty, selectedRange().length == 0, let storage = textStorage else { return false }
		let own = selectedRange().location
		let points = Array(Set(carets + [own])).sorted().filter { !back || $0 > 0 }
		let ranges = points.map { back ? NSRange(location: $0 - 1, length: 1) : NSRange(location: $0, length: 0) }
		guard !ranges.isEmpty, shouldChangeText(inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: ranges.map { _ in text }) else { return true }
		storage.beginEditing()
		for range in ranges.reversed() {
			storage.replaceCharacters(in: range, with: text)
		}
		storage.endEditing()
		let step = back ? -1 : (text as NSString).length
		let moved = points.enumerated().map { $1 + step * ($0 + 1) }
		let kept = points.firstIndex(of: own).map { moved[$0] } ?? moved[0]
		didChangeText()
		setSelectedRange(NSRange(location: kept, length: 0))
		carets = moved.filter { $0 != kept }
		needsDisplay = true
		return true
	}

	override func deleteBackward(_ sender: Any?) {
		if !spread("", true) {
			super.deleteBackward(sender)
		}
	}

	override func draw(_ dirtyRect: NSRect) {
		super.draw(dirtyRect)
		guard let layout = layoutManager, let container = textContainer else { return }
		let whole = string as NSString
		for held in asked where held.location + held.length <= whole.length {
			let box = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: whole.lineRange(for: held), actualCharacterRange: nil), in: container)
			let frame = NSRect(x: textContainerInset.width + 1, y: box.minY + textContainerInset.height, width: max(40, min(box.width, visibleRect.width - textContainerInset.width * 2 - 4)), height: box.height).offsetBy(dx: visibleRect.minX, dy: 0)
			let path = NSBezierPath(roundedRect: frame.insetBy(dx: 0, dy: 0.5), xRadius: 6, yRadius: 6)
			path.setLineDash([4, 3], count: 2, phase: 0)
			path.lineWidth = 1.2
			Sheet.tone(0xef8221, 0.9).setStroke()
			path.stroke()
		}
		guard !carets.isEmpty else { return }
		NSColor.white.setFill()
		let size = (string as NSString).length
		for at in carets where at <= size {
			let glyph = layout.glyphIndexForCharacter(at: min(at, max(0, size - 1)))
			var box = layout.boundingRect(forGlyphRange: NSRange(location: glyph, length: size == 0 ? 0 : 1), in: container)
			if at == size, size > 0 {
				box.origin.x = box.maxX
			}
			NSRect(x: box.minX + textContainerInset.width, y: box.minY + textContainerInset.height, width: 1.5, height: box.height).fill()
		}
	}

	func top() -> Int {
		guard let layout = layoutManager, let container = textContainer else { return 1 }
		return line(layout.characterIndex(for: NSPoint(x: 1, y: max(0, visibleRect.minY - textContainerInset.height + 2)), in: container, fractionOfDistanceBetweenInsertionPoints: nil)) + 1
	}

	func rise(_ line: Int) {
		guard let scroll = enclosingScrollView, let layout = layoutManager, let container = textContainer else { return }
		let box = layout.boundingRect(forGlyphRange: layout.glyphRange(forCharacterRange: NSRange(location: span(line).location, length: 0), actualCharacterRange: nil), in: container)
		scroll.contentView.scroll(to: NSPoint(x: scroll.contentView.bounds.minX, y: max(0, box.minY)))
		scroll.reflectScrolledClipView(scroll.contentView)
	}

	override func menu(for event: NSEvent) -> NSMenu? {
		let menu = NSMenu()
		build(menu)
		return menu
	}

	func search(_ action: NSTextFinder.Action) {
		let item = NSMenuItem()
		item.tag = action.rawValue
		performTextFinderAction(item)
	}

	override func keyDown(with event: NSEvent) {
		let held = event.modifierFlags.intersection([.command, .control, .option, .shift])
		let key = event.charactersIgnoringModifiers?.lowercased() ?? ""
		let code = event.keyCode
		let whole = string as NSString
		let range = selectedRange()
		let row = rows(range)
		switch (held, key, code) {
		case ([.command], "d", _):
			let text = whole.substring(with: row)
			put(NSRange(location: row.location + row.length, length: 0), text.hasSuffix("\n") ? text : "\n" + text, NSRange(location: range.location + (text as NSString).length + (text.hasSuffix("\n") ? 0 : 1), length: range.length))
		case ([.command], "y", _), ([.command], _, 51):
			put(row, "", NSRange(location: min(row.location, whole.length - row.length), length: 0))
		case ([.option, .shift], _, 126), ([.command, .shift], _, 126):
			shift(false)
		case ([.option, .shift], _, 125), ([.command, .shift], _, 125):
			shift(true)
		case ([.option], _, 126):
			grow()
		case ([.option], _, 125):
			shrink()
		case ([.command], "/", _):
			toggle()
		case ([.command, .option], "/", _):
			let text = whole.substring(with: range)
			let on = text.hasPrefix("/*") && text.hasSuffix("*/") && text.count >= 4
			let out = on ? String(text.dropFirst(2).dropLast(2)) : "/*" + text + "*/"
			put(range, out, NSRange(location: range.location, length: (out as NSString).length))
		case ([.shift], _, 36):
			let end = span(line(range.location + range.length) + 1)
			let lead = whole.substring(with: end).prefix { $0 == " " || $0 == "\t" }
			put(NSRange(location: end.location + end.length, length: 0), "\n" + lead, NSRange(location: end.location + end.length + 1 + lead.count, length: 0))
		case ([.command, .option], _, 36):
			let head = span(line(range.location) + 1)
			let lead = whole.substring(with: head).prefix { $0 == " " || $0 == "\t" }
			put(NSRange(location: head.location, length: 0), lead + "\n", NSRange(location: head.location + lead.count, length: 0))
		case ([.command], _, 36):
			put(range, "\n", NSRange(location: range.location, length: 0))
		case ([.control, .shift], "j", _):
			let first = span(line(range.location) + 1)
			let last = span(max(line(range.location) + 2, line(range.location + range.length) + 1))
			guard last.location > first.location else { return }
			let all = NSRange(location: first.location, length: last.location + last.length - first.location)
			let parts = whole.substring(with: all).components(separatedBy: "\n")
			let joined = parts.enumerated().map { $0 == 0 ? $1.replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) : $1.trimmingCharacters(in: .whitespaces) }.joined(separator: " ")
			put(all, joined, NSRange(location: first.location + (parts[0].replacingOccurrences(of: "\\s+$", with: "", options: .regularExpression) as NSString).length, length: 0))
		case ([.command, .shift], "u", _):
			let word = range.length > 0 ? range : selectionRange(forProposedRange: range, granularity: .selectByWord)
			let text = whole.substring(with: word)
			put(word, text == text.uppercased() ? text.lowercased() : text.uppercased(), range)
		case ([.control, .option], "i", _):
			let lines = whole.substring(with: row).components(separatedBy: "\n")
			let above = row.location > 0 ? whole.substring(with: whole.lineRange(for: NSRange(location: row.location - 1, length: 0))) : ""
			var lead = String(above.prefix { $0 == " " || $0 == "\t" })
			if above.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("{") || above.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix(":") {
				lead += lead.contains("\t") || ["go", "swift"].contains(ext) ? "\t" : "    "
			}
			let out = lines.map { $0.trimmingCharacters(in: .whitespaces).isEmpty ? $0 : lead + $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
			put(row, out, NSRange(location: row.location, length: 0))
		case ([.command, .option], "l", _):
			tidied()
		case ([.command], "r", _):
			search(.showReplaceInterface)
		case ([], _, 99), ([.command], "g", _):
			search(.nextMatch)
		case ([.shift], _, 99), ([.command, .shift], "g", _):
			search(.previousMatch)
		case ([.control], "g", _):
			more(false)
		case ([.control, .command], "g", _):
			more(true)
		case ([.control], "-", _):
			fold(line(range.location) + 1, true)
		case ([.control], "=", _):
			fold(line(range.location) + 1, false)
		case ([.control, .shift], "-", _), ([.control, .shift], "_", _):
			foldAll(true)
		case ([.control, .shift], "=", _), ([.control, .shift], "+", _):
			foldAll(false)
		default:
			if !carets.isEmpty, (code >= 123 && code <= 126) || code == 53 {
				carets = []
				needsDisplay = true
			}
			super.keyDown(with: event)
		}
	}
}

final class Sight: ObservableObject {
	@Published var path = ""
	@Published var text = ""
	@Published var kind = ""
	@Published var media = ""
	@Published var zoom = 1.0
	@Published var vitals = ""
}

struct Reel: View {
	let path: String
	@State private var player = AVPlayer()

	var body: some View {
		VideoPlayer(player: player)
			.onAppear { player.replaceCurrentItem(with: AVPlayerItem(url: URL(fileURLWithPath: path))) }
			.onChange(of: path) { _, next in player.replaceCurrentItem(with: AVPlayerItem(url: URL(fileURLWithPath: next))) }
			.onDisappear { player.pause() }
	}
}

struct Paper: NSViewRepresentable {
	let path: String

	func makeNSView(context: Context) -> PDFView {
		let view = PDFView()
		view.autoScales = true
		view.backgroundColor = Sheet.tone(0x1e1f22)
		return view
	}

	func updateNSView(_ view: PDFView, context: Context) {
		if view.document?.documentURL?.path != path {
			view.document = PDFDocument(url: URL(fileURLWithPath: path))
		}
	}
}

struct Idle: View {
	@ObservedObject var sight: Sight
	@State private var breathing = false

	var body: some View {
		GeometryReader { box in
			VStack(spacing: 6) {
				Spacer()
				Image(nsImage: NSApp.applicationIconImage).resizable().aspectRatio(contentMode: .fit)
					.frame(width: min(box.size.width, box.size.height) * 0.28)
					.scaleEffect(breathing ? 1.05 : 1)
					.animation(.easeInOut(duration: 3).repeatForever(autoreverses: true), value: breathing)
				Text("Slyed").font(.system(size: 17, weight: .semibold)).foregroundStyle(Ink.fg).padding(.top, 10)
				Text("See every change before it lands").font(.system(size: 12)).foregroundStyle(Ink.dim)
				Text("Open a file from the sidebar · ⌘K to search").font(.system(size: 12)).foregroundStyle(Ink.dim)
				Text(sight.vitals).font(.system(size: 10)).monospacedDigit().foregroundStyle(Ink.dim.opacity(0.6))
				Spacer()
			}
			.frame(maxWidth: .infinity, maxHeight: .infinity)
		}
		.onAppear { breathing = true }
	}
}

struct Stage: View {
	@ObservedObject var sight: Sight
	let web: WKWebView

	func picture(_ image: NSImage?) -> some View {
		GeometryReader { box in
			ScrollView([.horizontal, .vertical]) {
				if let image {
					Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
						.frame(width: min(box.size.width * 0.94, max(image.size.width, box.size.width * 0.3)) * sight.zoom)
						.frame(minWidth: box.size.width, minHeight: box.size.height)
				}
			}
		}
	}

	var body: some View {
		ZStack {
			Color(red: 0.118, green: 0.122, blue: 0.133)
			Web(view: web).opacity(sight.kind == "html" ? 1 : 0).allowsHitTesting(sight.kind == "html")
			if sight.media == "image" {
				picture(NSImage(contentsOfFile: sight.path))
			} else if sight.kind == "svg" {
				picture(NSImage(data: Data(sight.text.utf8)))
			} else if sight.media == "pdf" {
				Paper(path: sight.path)
			} else if sight.media == "video" || sight.media == "audio" {
				Reel(path: sight.path)
			} else if sight.kind == "markdown" {
				ScrollView {
					Markdown(text: sight.text, base: (sight.path as NSString).deletingLastPathComponent, scale: sight.zoom * 1.1)
						.padding(.horizontal, 22).padding(.vertical, 16)
						.background(Thin())
				}
				.scrollIndicators(.visible)
				.foregroundStyle(Ink.fg)
			} else if sight.kind != "html" {
				Idle(sight: sight)
			}
		}
	}
}

struct Zoomer: View {
	@ObservedObject var pulse: Pulse
	let model: Model
	@State private var over = false

	func key(_ title: String, _ tip: String, _ action: @escaping () -> Void) -> some View {
		Button(action: action) {
			Text(title).font(.system(size: 11, weight: .semibold)).monospacedDigit().foregroundStyle(Ink.fg)
				.padding(.horizontal, 7).padding(.vertical, 3).contentShape(Rectangle())
		}
		.buttonStyle(.plain).focusable(false).tip(tip)
	}

	var body: some View {
		HStack(spacing: 6) {
			if pulse.cursor.contains(" selected") {
				Button(action: { model.remark() }) {
					Image(systemName: "text.bubble").font(.system(size: 13.2)).foregroundStyle(Ink.fg)
						.frame(width: 22.2, height: 20.2).contentShape(Capsule())
				}
				.buttonStyle(.plain).focusable(false).tip("Comment on the selected lines and send it to the agent with the file and line range, ⇧⌘M")
				.background(Capsule().fill(Color(red: 0.118, green: 0.122, blue: 0.133).opacity(0.9)))
				.overlay(Capsule().strokeBorder(Ink.line, lineWidth: 1))
				.opacity(over ? 1 : 0.4)
			}
			HStack(spacing: 0) {
				key("−", "Zoom out, ⌘−") { model.magnify(-0.05) }
				key("\(Int((pulse.zoom * 100).rounded()))%", "Zoom of this file type, click to reset") { model.magnify(0) }
				key("+", "Zoom in, ⌘+") { model.magnify(0.05) }
			}
			.background(Capsule().fill(Color(red: 0.118, green: 0.122, blue: 0.133).opacity(0.9)))
			.overlay(Capsule().strokeBorder(Ink.line, lineWidth: 1))
			.opacity(over ? 1 : 0.4)
		}
		.onHover { over = $0 }
		.padding(.trailing, 16).padding(.bottom, 12)
	}
}

struct Native: NSViewRepresentable {
	let view: NSView
	func makeNSView(context: Context) -> NSView { view }
	func updateNSView(_ view: NSView, context: Context) {}
}

struct Web: NSViewRepresentable {
	let view: WKWebView
	func makeNSView(context: Context) -> WKWebView { view }
	func updateNSView(_ view: WKWebView, context: Context) {}
}

enum Ink {
	static let fg = Color.white.opacity(0.92)
	static let dim = Color.white.opacity(0.6)
	static let line = Color.white.opacity(0.08)
	static let hover = Color.white.opacity(0.1)
	static var accent = Color(red: 0.706, green: 0.388, blue: 0.184)
	static let pane = Color.black.opacity(0.28)
}

func copy(_ text: String) {
	NSPasteboard.general.clearContents()
	NSPasteboard.general.setString(text, forType: .string)
}

final class Tips: ObservableObject {
	static let shared = Tips()
	@Published var text = ""
	@Published var at = CGPoint.zero
	var wait: Timer?

	func show(_ text: String) {
		wait?.invalidate()
		wait = Timer.scheduledTimer(withTimeInterval: 0.45, repeats: false) { _ in
			guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: { $0.isVisible }) else { return }
			let point = window.mouseLocationOutsideOfEventStream
			self.at = CGPoint(x: point.x, y: window.frame.height - point.y)
			self.text = text
		}
	}

	func hide() {
		wait?.invalidate()
		text = ""
	}
}

struct Tipped: ViewModifier {
	let text: String

	func body(content: Content) -> some View {
		content.onHover { over in
			if over && !text.isEmpty {
				Tips.shared.show(text)
			} else {
				Tips.shared.hide()
			}
		}
	}
}

struct Movable: ViewModifier {
	@State private var at = CGSize.zero
	@State private var from = CGSize.zero

	func body(content: Content) -> some View {
		content.offset(at).gesture(DragGesture(minimumDistance: 3, coordinateSpace: .global).onChanged { drag in
			at = CGSize(width: from.width + drag.translation.width, height: from.height + drag.translation.height)
		}.onEnded { _ in from = at })
	}
}

extension View {
	func tip(_ text: String) -> some View {
		modifier(Tipped(text: text))
	}

	func movable() -> some View {
		modifier(Movable())
	}
}

struct Bubble: View {
	@ObservedObject var tips = Tips.shared

	var body: some View {
		GeometryReader { box in
			if !tips.text.isEmpty {
				Text(tips.text).font(.system(size: 11)).foregroundStyle(Ink.fg).lineLimit(3)
					.padding(.horizontal, 8).padding(.vertical, 4)
					.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 7))
					.overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Ink.line, lineWidth: 1))
					.frame(maxWidth: 360, alignment: .leading)
					.fixedSize()
					.position(x: min(max(tips.at.x, 190), box.size.width - 190), y: tips.at.y + 26 > box.size.height - 20 ? tips.at.y - 22 : tips.at.y + 26)
					.transition(.opacity)
			}
		}
		.allowsHitTesting(false)
		.animation(.easeOut(duration: 0.12), value: tips.text)
	}
}

struct Icon: View {
	let name: String
	var on = false
	var tint = Ink.accent
	var size = 12.0
	let tip: String
	let action: () -> Void
	@State private var over = false

	var body: some View {
		Button(action: action) {
			Image(systemName: name).font(.system(size: size * 1.1))
				.foregroundStyle(on ? tint : over ? Color.white : Ink.dim)
				.frame(width: size * 1.1 + 9, height: size * 1.1 + 7)
				.contentShape(Rectangle())
		}
		.buttonStyle(.plain).focusable(false)
		.onHover { over = $0 }
		.tip(tip)
	}
}

struct Toggles<Content: View>: View {
	@ViewBuilder let content: () -> Content

	var body: some View {
		HStack(spacing: 0) { content() }
			.padding(.horizontal, 2).padding(.vertical, 1)
			.background(RoundedRectangle(cornerRadius: 8).fill(Color.white.opacity(0.05)))
			.overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Ink.line, lineWidth: 1))
	}
}

struct Badge: View {
	let text: String
	let color: Color
	var scale = 1.0

	var body: some View {
		Image(systemName: text == "reads" ? "eye" : text == "writes" ? "square.and.pencil" : text == "edits" ? "pencil" : "circle").font(.system(size: 9 * scale, weight: .semibold)).foregroundStyle(color)
			.frame(width: 16 * scale, height: 14 * scale).background(Capsule().fill(color.opacity(0.18))).tip(text)
	}
}

struct Counts: View {
	let added: Int
	let removed: Int

	var body: some View {
		(Text(added > 0 ? "↑\(added)" : "").foregroundColor(Color(red: 0.42, green: 0.78, blue: 0.56)) + Text(added > 0 && removed > 0 ? " " : "") + Text(removed > 0 ? "↓\(removed)" : "").foregroundColor(Color(red: 1, green: 0.49, blue: 0.43)))
			.font(.system(size: 10, weight: .medium)).monospacedDigit().fixedSize()
	}
}

struct Meter: Identifiable {
	let id: String
	let value: String
	let part: Double
	let color: Color
}

struct Meters: View {
	let meters: [Meter]
	let account: String
	let scale: Double

	var body: some View {
		let parts = account.components(separatedBy: " · ")
		let letters = parts[0].split(separator: " ").prefix(2).compactMap { $0.first }.map(String.init).joined().uppercased()
		VStack(alignment: .leading, spacing: 8) {
			if !account.isEmpty {
				HStack(spacing: 8) {
					Text(letters).font(.system(size: 10 * scale, weight: .bold)).foregroundStyle(Color.white)
						.frame(width: 24 * scale, height: 24 * scale)
						.background(Circle().fill(LinearGradient(colors: [Ink.accent, Ink.accent.opacity(0.55)], startPoint: .topLeading, endPoint: .bottomTrailing)))
					VStack(alignment: .leading, spacing: 0) {
						Text(parts[0]).font(.system(size: 12 * scale, weight: .semibold)).lineLimit(1)
						if parts.count > 1 {
							Text(parts[1]).font(.system(size: 10 * scale)).foregroundStyle(Ink.dim).lineLimit(1).truncationMode(.middle)
						}
					}
					Spacer(minLength: 0)
				}
				.tip("The Claude account that is signed in")
			}
			Grid(alignment: .leading, horizontalSpacing: 6, verticalSpacing: 5) {
				ForEach(meters) { meter in
					GridRow {
						Text(meter.id).font(.system(size: 10 * scale)).foregroundStyle(Ink.dim)
						GeometryReader { box in
							ZStack(alignment: .leading) {
								Capsule().fill(Ink.hover)
								Capsule().fill(LinearGradient(colors: [meter.color.opacity(0.6), meter.color], startPoint: .leading, endPoint: .trailing))
									.frame(width: max(4, box.size.width * min(1, max(0, meter.part))))
									.shadow(color: meter.color.opacity(0.6), radius: 3)
							}
						}
						.frame(height: 4)
						Text(meter.value + "%").font(.system(size: 10 * scale, weight: .semibold)).monospacedDigit().gridColumnAlignment(.trailing)
					}
					.tip(meter.id + " " + meter.value + "%")
				}
			}
		}
		.padding(10)
	}
}

struct Markdown: View {
	let text: String
	var base = ""
	var scale = 1.0

	struct Block: Identifiable {
		let id: Int
		let kind: String
		let mark: String
		let text: String
	}

	var blocks: [Block] {
		var out: [Block] = []
		var code: [String]?
		for raw in text.components(separatedBy: "\n") {
			let line = raw.trimmingCharacters(in: .whitespaces)
			if line.hasPrefix("```") {
				if let lines = code {
					out.append(Block(id: out.count, kind: "code", mark: "", text: lines.joined(separator: "\n")))
					code = nil
				} else {
					code = []
				}
				continue
			}
			if code != nil {
				code?.append(raw)
				continue
			}
			if line.isEmpty { continue }
			if line.hasPrefix("|"), line.hasSuffix("|") {
				if line.contains(where: { $0.isLetter || $0.isNumber }) {
					out.append(Block(id: out.count, kind: "row", mark: "", text: String(line.dropFirst().dropLast())))
				}
				continue
			}
			if let found = line.firstMatch(of: #/^#{1,6}\s+(.*)$/#) {
				out.append(Block(id: out.count, kind: "head", mark: "", text: String(found.1)))
			} else if line.hasPrefix("**"), line.hasSuffix("**"), line.count > 4, !line.dropFirst(2).dropLast(2).contains("**") {
				out.append(Block(id: out.count, kind: "head", mark: "", text: String(line.dropFirst(2).dropLast(2))))
			} else if let found = line.firstMatch(of: #/^(Q\d+)[,:.]?\s*(.*)$/#) {
				out.append(Block(id: out.count, kind: "ask", mark: String(found.1), text: String(found.2)))
			} else if let found = line.firstMatch(of: #/^(\d+)[.)]\s+(.*)$/#) {
				out.append(Block(id: out.count, kind: "item", mark: String(found.1) + ".", text: String(found.2)))
			} else if let found = line.firstMatch(of: #/^[-*·•]\s+(.*)$/#) {
				out.append(Block(id: out.count, kind: "item", mark: "•", text: String(found.1)))
			} else {
				out.append(Block(id: out.count, kind: "text", mark: "", text: line))
			}
		}
		if let lines = code {
			out.append(Block(id: out.count, kind: "code", mark: "", text: lines.joined(separator: "\n")))
		}
		return out
	}

	func inline(_ text: String) -> AttributedString {
		var out = (try? AttributedString(markdown: text, options: AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
		let code = out.runs.filter { $0.inlinePresentationIntent?.contains(.code) == true }.map { $0.range }
		for range in code {
			out[range].foregroundColor = Color(red: 0.34, green: 0.66, blue: 0.96)
			out[range].font = .system(size: 11.5 * scale, design: .monospaced)
		}
		let plain = String(out.characters)
		for found in plain.matches(of: #/\b[Qq]\d+\b/#) {
			let lower = out.index(out.startIndex, offsetByCharacters: plain.distance(from: plain.startIndex, to: found.range.lowerBound))
			let upper = out.index(lower, offsetByCharacters: found.output.count)
			out[lower..<upper].foregroundColor = Color(red: 0.94, green: 0.51, blue: 0.13)
			out[lower..<upper].inlinePresentationIntent = .stronglyEmphasized
		}
		guard !base.isEmpty else { return out }
		var allowed = CharacterSet.alphanumerics
		allowed.insert(charactersIn: "-_.~/")
		var from = out.startIndex
		for found in String(out.characters).matches(of: #/(/?[\w.\-]+(?:/[\w.\-]+)*\.\w+):(\d+)/#) {
			let path = String(found.1)
			let full = path.hasPrefix("/") ? path : base + "/" + path
			guard let range = out[from...].range(of: String(found.0)) else { continue }
			from = range.upperBound
			guard FileManager.default.fileExists(atPath: full), let url = URL(string: "slyed://open?path=" + (full.addingPercentEncoding(withAllowedCharacters: allowed) ?? full) + "&line=" + found.2) else { continue }
			out[range].link = url
		}
		return out
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			ForEach(blocks) { block in
				switch block.kind {
				case "head":
					Text(inline(block.text)).font(.system(size: 13 * scale, weight: .semibold)).padding(.top, 4)
				case "code":
					Text(block.text).font(.system(size: 11 * scale, design: .monospaced)).foregroundStyle(Color(red: 0.34, green: 0.66, blue: 0.96))
						.padding(8).frame(maxWidth: .infinity, alignment: .leading)
						.background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
				case "ask":
					HStack(alignment: .firstTextBaseline, spacing: 8) {
						Text(block.mark).font(.system(size: 11 * scale, weight: .bold)).foregroundStyle(Color.white).padding(.horizontal, 6).padding(.vertical, 1)
							.background(Capsule().fill(Ink.accent))
						Text(inline(block.text)).font(.system(size: 12 * scale))
					}
					.padding(7).frame(maxWidth: .infinity, alignment: .leading)
					.background(RoundedRectangle(cornerRadius: 7).fill(Ink.accent.opacity(0.14)))
				case "row":
					HStack(alignment: .firstTextBaseline, spacing: 8) {
						ForEach(Array(block.text.components(separatedBy: "|").enumerated()), id: \.offset) { _, cell in
							Text(inline(cell.trimmingCharacters(in: .whitespaces))).font(.system(size: 12 * scale)).frame(maxWidth: .infinity, alignment: .leading)
						}
					}
					.padding(.vertical, 2)
				case "item":
					HStack(alignment: .firstTextBaseline, spacing: 6) {
						Text(block.mark).font(.system(size: 12 * scale)).monospacedDigit().foregroundStyle(Ink.dim).frame(minWidth: 20, alignment: .trailing)
						Text(inline(block.text)).font(.system(size: 12 * scale))
					}
				default:
					Text(inline(block.text)).font(.system(size: 12 * scale))
				}
			}
		}
		.lineSpacing(3)
		.textSelection(.enabled)
		.frame(maxWidth: .infinity, alignment: .leading)
	}
}

struct Change: Identifiable {
	let path: String
	let staged: String
	let work: String
	var id: String { path }
	var conflict: Bool { staged == "U" || work == "U" || (staged == "A" && work == "A") || (staged == "D" && work == "D") }
}

struct Commit: Identifiable {
	let id: String
	let subject: String
	let who: String
	let when: String
}

struct Note: Identifiable {
	let id: Int
	let side: String
	let line: Int
	let end: Int
	let text: String
	var question = false
	var answer = ""
	var change = -1
	var sent = false
	var status = ""

	var spot: String {
		(status.isEmpty ? "" : status + " ") + (side == "change" ? "the whole change" : side == "plan" ? (change >= 0 ? "the plan, at change \(change + 1)" : "the plan") : (side == "base" ? "current " : "proposed ") + "\(line)" + (end > line ? "-\(end)" : ""))
	}
}

struct Hunk: Identifiable {
	let id: Int
	let change: Int
	let part: Int
	let side: String
	let line: Int
	let end: Int
	let rows: [[String: Any]]
	var status = "pending"
	var text = ""
	var sent = false
	var why = ""
	var on = true
	var added = 0
	var removed = 0
	var pairs = 0

	var label: String { "\(change + 1).\(part)" }

	var tint: Color {
		status == "accepted" ? Color(red: 0.42, green: 0.78, blue: 0.56) : status == "rejected" ? Color(red: 1, green: 0.49, blue: 0.43) : Ink.dim
	}

	var mark: String {
		status == "accepted" ? "checkmark.circle.fill" : status == "rejected" ? "xmark.circle.fill" : "circle.dashed"
	}
}

struct Step: Identifiable {
	let id: Int
	let title: String
	let why: String
	let path: String
	let proposed: String
	let base: String
	var status: String
	var notes: [Note]
	var added = 0
	var removed = 0
	var diff: [String] = []

	var tint: Color {
		status == "accepted" ? Color(red: 0.42, green: 0.78, blue: 0.56) : status == "rejected" ? Color(red: 1, green: 0.49, blue: 0.43) : Ink.dim
	}

	var mark: String {
		status == "accepted" ? "checkmark.circle.fill" : status == "rejected" ? "xmark.circle.fill" : "circle.dashed"
	}
}

struct Act: View {
	let name: String
	let tip: String
	var danger = false
	let action: () -> Void
	@State private var over = false

	var body: some View {
		Button(action: action) {
			Image(systemName: name).font(.system(size: 13.2)).foregroundStyle(over ? (danger ? Color(red: 1, green: 0.49, blue: 0.43) : Ink.fg) : Ink.dim)
				.frame(width: 22.2, height: 20.2).contentShape(Rectangle())
		}
		.buttonStyle(.plain).focusable(false).onHover { over = $0 }.tip(tip)
	}
}

struct Pill: View {
	let title: String
	let on: Bool
	let action: () -> Void
	@State private var over = false

	var body: some View {
		Button(action: action) {
			Text(title).font(.system(size: 11))
				.foregroundStyle(on ? Color.white : over ? Ink.fg : Ink.dim)
				.padding(.horizontal, 8).padding(.vertical, 1)
				.background(Capsule().fill(on ? Ink.accent : Color.clear))
				.overlay(Capsule().strokeBorder(on ? Ink.accent : Ink.line, lineWidth: 1))
				.contentShape(Capsule())
		}
		.buttonStyle(.plain).focusable(false)
		.onHover { over = $0 }
	}
}

struct Board: View {
	let model: Model
	@ObservedObject var live: Live
	@Namespace private var moves
	@State private var grown: Set<String> = []
	static let order = ["draft", "open", "doing", "staged", "review", "blocked", "done"]
	static let asked = Color(red: 0.92, green: 0.74, blue: 0.33)

	func head(_ title: String, _ count: Int) -> some View {
		HStack(spacing: 6) {
			Text(title.uppercased()).font(.system(size: 10, weight: .medium)).tracking(0.6).foregroundStyle(Ink.dim)
			Text("\(count)").font(.system(size: 10)).monospacedDigit().foregroundStyle(Ink.dim)
			Spacer(minLength: 0)
		}
	}

	func card(_ card: Card, _ workers: [Feed], _ repos: Int) -> some View {
		let asking = card.questions > 0 || workers.contains { !$0.questions.isEmpty }
		return VStack(alignment: .leading, spacing: 3) {
			HStack(spacing: 5) {
				Text("#" + card.number).font(.system(size: 10, design: .monospaced)).foregroundStyle(Ink.accent)
				Text(card.kind).font(.system(size: 10)).foregroundStyle(Ink.dim)
				if repos > 1 {
					Text((card.repo as NSString).lastPathComponent).font(.system(size: 10)).foregroundStyle(Ink.dim).lineLimit(1)
				}
				Spacer(minLength: 2)
				ForEach(workers) { feed in
					Circle().fill(feed.busy ? Color(red: 0.95, green: 0.65, blue: 0.42) : Color.white.opacity(0.4)).frame(width: 6, height: 6).tip(feed.name + " · " + feed.detail)
				}
				if asking {
					Image(systemName: "questionmark.bubble.fill").font(.system(size: 10)).foregroundStyle(Board.asked).tip("Open questions")
				}
			}
			Text(card.title).font(.system(size: 12)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
			if !card.tree.isEmpty {
				Label(card.tree, systemImage: "arrow.triangle.branch").font(.system(size: 10)).foregroundStyle(Ink.dim).lineLimit(1).truncationMode(.middle)
			}
		}
		.padding(8)
		.frame(maxWidth: .infinity, alignment: .leading)
		.background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.05)))
		.overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(asking ? Board.asked.opacity(0.6) : Ink.line, lineWidth: 1))
		.matchedGeometryEffect(id: card.id, in: moves)
		.contentShape(Rectangle())
		.onTapGesture {
			let agent = model.agents.first { $0.name == card.session } ?? workers.first.flatMap { feed in model.agents.first { $0.sid == feed.group } }
			model.converse(agent, "#" + card.number + " " + card.title, agent?.logs.first ?? "", card.id)
		}
		.tip(card.id + (card.session.isEmpty ? "" : " · " + card.session))
		.contextMenu { Button("Copy Path") { copy(card.id) } }
	}

	func cell(_ feed: Feed) -> some View {
		let wide = grown.contains(feed.id)
		return VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 6) {
				Circle().fill(feed.busy ? Color(red: 0.95, green: 0.65, blue: 0.42) : Color.white.opacity(0.4)).frame(width: 6, height: 6)
				Text(feed.name).font(.system(size: 11, weight: .semibold)).lineLimit(1)
				Text(feed.detail).font(.system(size: 11)).foregroundStyle(Ink.dim).lineLimit(1).truncationMode(.tail)
				Spacer(minLength: 2)
				if !feed.model.isEmpty {
					Text(feed.model.replacingOccurrences(of: "claude-", with: "")).font(.system(size: 10)).foregroundStyle(Ink.accent).lineLimit(1).fixedSize()
						.padding(.horizontal, 5).background(Capsule().fill(Ink.accent.opacity(0.16))).tip("Model " + feed.model)
				}
				if !feed.questions.isEmpty {
					Label("\(feed.questions.count)", systemImage: "questionmark.bubble.fill").labelStyle(.titleAndIcon).font(.system(size: 10)).foregroundStyle(Board.asked)
						.tip(feed.questions.joined(separator: "\n"))
				}
				Act(name: wide ? "chevron.up" : "chevron.down", tip: wide ? "Collapse" : "Expand the work log") {
					if wide { grown.remove(feed.id) } else { grown.insert(feed.id) }
				}
			}
			ScrollView {
				VStack(alignment: .leading, spacing: 1) {
					ForEach(Array(feed.lines.enumerated()), id: \.offset) { _, line in
						Text(line.hasPrefix("›") ? Markdown(text: line).inline(line) : AttributedString(line)).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(line.hasPrefix("›") ? Ink.fg : Ink.dim).lineLimit(wide ? nil : 1).truncationMode(.tail).fixedSize(horizontal: false, vertical: true).textSelection(.enabled)
					}
				}
				.frame(maxWidth: .infinity, alignment: .leading)
			}
			.defaultScrollAnchor(.bottom)
			.scrollIndicators(.never)
			.frame(minHeight: 80, maxHeight: wide ? 520 : 150)
			if wide {
				ForEach(feed.questions, id: \.self) { asked in
					Text(asked).font(.system(size: 11)).foregroundStyle(Board.asked).fixedSize(horizontal: false, vertical: true)
				}
			}
		}
		.padding(8)
		.background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.04)))
		.overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(feed.questions.isEmpty ? Ink.line : Board.asked.opacity(0.6), lineWidth: 1))
		.contentShape(Rectangle())
		.onTapGesture { model.converse(model.agents.first { $0.sid == feed.group }, feed.name + (feed.detail.isEmpty ? "" : " · " + feed.detail), feed.id, "") }
	}

	var body: some View {
		let lanes = Dictionary(grouping: live.cards, by: \.status)
		let present = Set(lanes.keys)
		let repos = Set(live.cards.map(\.repo)).count
		let cells = Dictionary(grouping: live.feeds, by: \.group)
		let working = live.feeds.reduce(into: [String: [Feed]]()) { found, feed in feed.trees.forEach { found[$0, default: []].append(feed) } }
		let shown = Board.order.filter { ["draft", "doing", "review", "blocked", "done"].contains($0) || present.contains($0) } + present.subtracting(Board.order).sorted()
		let groups = live.feeds.map(\.group).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
		VStack(spacing: 0) {
			HStack(alignment: .top, spacing: 8) {
				ForEach(shown, id: \.self) { status in
					let cards = lanes[status] ?? []
					VStack(alignment: .leading, spacing: 6) {
						head(status, cards.count)
						ScrollView {
							LazyVStack(spacing: 6) { ForEach(cards) { card($0, working[$0.tree] ?? [], repos) } }
						}
						.scrollIndicators(.never)
					}
					.padding(8)
					.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
					.background(RoundedRectangle(cornerRadius: 10).fill(Ink.pane))
				}
			}
			.padding(.bottom, 8)
			.frame(maxHeight: .infinity)
			ScrollView(.horizontal) {
				HStack(alignment: .top, spacing: 8) {
					ForEach(groups, id: \.self) { group in
						let agent = model.agents.first { $0.sid == group }
						VStack(alignment: .leading, spacing: 6) {
							HStack(spacing: 6) {
								Circle().fill(agent?.color ?? Ink.dim).frame(width: 7, height: 7)
								Text(agent?.name ?? group).font(.system(size: 12, weight: .semibold)).lineLimit(1)
								Text(model.short(agent?.dir ?? "")).font(.system(size: 11)).foregroundStyle(Ink.dim).lineLimit(1).truncationMode(.head)
								Spacer(minLength: 0)
							}
							.contentShape(Rectangle())
							.onTapGesture {
								if let agent {
									model.converse(agent, agent.name, agent.logs.first ?? "", "")
								}
							}
							ScrollView {
								VStack(spacing: 8) {
									ForEach(cells[group] ?? []) { cell($0) }
								}
								.background(Thin())
							}
							.scrollIndicators(.visible)
						}
						.padding(8)
						.frame(maxHeight: .infinity, alignment: .top)
						.background(RoundedRectangle(cornerRadius: 10).fill(Ink.pane))
						.containerRelativeFrame(.horizontal, count: min(max(groups.count, 1), 4), spacing: 8)
					}
				}
			}
			.scrollIndicators(.never)
			.frame(maxHeight: .infinity)
		}
		.foregroundStyle(Ink.fg)
		.animation(.spring(response: 0.45, dampingFraction: 0.82), value: live.cards.map { $0.id + $0.status })
	}
}

struct GitPanel: View {
	@ObservedObject var model: Model
	@State private var name = ""

	func head(_ title: String) -> some View {
		Text(title.uppercased()).font(.system(size: 10, weight: .medium)).tracking(0.6).foregroundStyle(Ink.dim).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
	}

	func file(_ change: Change, _ staged: Bool) -> some View {
		let code = change.conflict ? "!" : staged ? change.staged : change.work == "?" ? "U" : change.work
		let tint = change.conflict ? Color(red: 1, green: 0.49, blue: 0.43) : code == "U" || code == "A" ? Color(red: 0.42, green: 0.78, blue: 0.56) : code == "D" ? Color(red: 1, green: 0.49, blue: 0.43) : Color(red: 0.92, green: 0.74, blue: 0.33)
		return HStack(spacing: 6) {
			Text(code).font(.system(size: 10, weight: .bold)).foregroundStyle(tint).frame(width: 12)
			Text((change.path as NSString).lastPathComponent).font(.system(size: 12)).lineLimit(1)
			Text((change.path as NSString).deletingLastPathComponent).font(.system(size: 10)).foregroundStyle(Ink.dim).lineLimit(1).truncationMode(.head)
			Spacer(minLength: 2)
			if let count = model.counts[model.top + "/" + change.path], !staged {
				Counts(added: count.0, removed: count.1)
			}
			if staged {
				Act(name: "minus", tip: "Unstage") { model.git(["restore", "--staged", "--", change.path], "") }
			} else {
				Act(name: "arrow.uturn.backward", tip: "Discard the changes in this file, asks first", danger: true) {
					model.git(change.work == "?" ? ["clean", "-f", "--", change.path] : ["restore", "--", change.path], "discard " + change.path)
				}
				Act(name: "plus", tip: change.conflict ? "Mark as resolved" : "Stage") { model.git(["add", "--", change.path], "") }
			}
		}
		.padding(.horizontal, 4).padding(.vertical, 2)
		.contentShape(Rectangle())
		.onTapGesture { model.review(model.top + "/" + change.path) }
	}

	var body: some View {
		let staged = model.changes.filter { $0.staged != " " && $0.staged != "?" && !$0.conflict }
		let work = model.changes.filter { $0.work != " " || $0.conflict }
		VStack(spacing: 0) {
			HStack(spacing: 8) {
				Image(systemName: "arrow.triangle.branch").font(.system(size: 13)).foregroundStyle(Ink.accent)
				Text(model.branch.isEmpty ? "no repository" : model.branch).font(.system(size: 14, weight: .semibold))
				if !model.tracking.isEmpty {
					Text(model.tracking).font(.system(size: 11)).foregroundStyle(Ink.dim)
				}
				if !model.state.isEmpty {
					Text(model.state).font(.system(size: 10, weight: .semibold)).foregroundStyle(Color.white).padding(.horizontal, 7).padding(.vertical, 1).background(Capsule().fill(Color(red: 0.79, green: 0.29, blue: 0.23)))
					Pill(title: "continue", on: false) { model.git([model.state == "merging" ? "merge" : model.state == "rebasing" ? "rebase" : "cherry-pick", "--continue"], "") }
					Pill(title: "abort", on: false) { model.git([model.state == "merging" ? "merge" : model.state == "rebasing" ? "rebase" : "cherry-pick", "--abort"], "abort the " + model.state) }
				}
				Spacer(minLength: 8)
				Icon(name: "arrow.triangle.2.circlepath", tip: "Fetch from every remote and prune") { model.git(["fetch", "--all", "--prune"], "") }
				Icon(name: "arrow.down", tip: "Pull, fast forward only") { model.git(["pull", "--ff-only"], "") }
				Icon(name: "arrow.up", tip: "Push the current branch") { model.git(["push"], "") }
				Icon(name: "xmark", tip: "Close, esc") { model.gitOpen = false }
			}
			.padding(.horizontal, 14).padding(.vertical, 10)
			Rectangle().fill(Ink.line).frame(height: 1)
			HStack(alignment: .top, spacing: 0) {
				VStack(alignment: .leading, spacing: 3) {
					HStack {
						head("Staged · \(staged.count)")
						Act(name: "minus.circle", tip: "Unstage everything") { model.git(["reset", "-q"], "") }
					}
					ScrollView { VStack(spacing: 0) { ForEach(staged) { file($0, true) } } }.scrollIndicators(.never).frame(maxHeight: 130)
					HStack {
						head("Changes · \(work.count)")
						Act(name: "plus.circle", tip: "Stage everything") { model.git(["add", "-A"], "") }
					}
					ScrollView { VStack(spacing: 0) { ForEach(work) { file($0, false) } } }.scrollIndicators(.never)
					TextField("Commit message", text: $model.message, axis: .vertical).textFieldStyle(.plain).font(.system(size: 12)).lineLimit(1...4)
						.padding(7).background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
						.onSubmit { model.commit(false) }
					HStack(spacing: 6) {
						Pill(title: "commit", on: !staged.isEmpty && !model.message.isEmpty) { model.commit(false) }
						Pill(title: "amend", on: false) { model.commit(true) }
						Spacer(minLength: 0)
						Pill(title: "stash", on: false) { model.git(["stash", "push", "-u"], "") }
					}
				}
				.padding(10).frame(width: 330)
				Rectangle().fill(Ink.line).frame(width: 1)
				VStack(alignment: .leading, spacing: 3) {
					head("Branches")
					HStack(spacing: 6) {
						TextField("new branch", text: $name).textFieldStyle(.plain).font(.system(size: 12)).padding(5).background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
							.onSubmit {
								if !name.isEmpty {
									model.git(["switch", "-c", name], "")
									name = ""
								}
							}
					}
					ScrollView {
						VStack(spacing: 0) {
							ForEach(model.branches, id: \.self) { branch in
								HStack(spacing: 5) {
									Image(systemName: branch == model.branch ? "checkmark" : "arrow.triangle.branch").font(.system(size: 9)).foregroundStyle(branch == model.branch ? Ink.accent : Ink.dim).frame(width: 12)
									Text(branch).font(.system(size: 12, weight: branch == model.branch ? .semibold : .regular)).lineLimit(1).truncationMode(.middle)
									Spacer(minLength: 2)
									Act(name: "plus.forwardslash.minus", tip: "Compare open files against \(branch)") { model.compare(branch) }
									if branch != model.branch {
										Act(name: "arrow.triangle.merge", tip: "Merge \(branch) into \(model.branch)") { model.git(["merge", "--no-edit", branch], "") }
										Act(name: "arrow.right.circle", tip: "Switch to \(branch)") { model.git(["switch", branch], "") }
										Act(name: "trash", tip: "Delete \(branch), asks first", danger: true) { model.git(["branch", "-d", branch], "delete branch " + branch) }
									}
								}
								.padding(.horizontal, 4).padding(.vertical, 2)
							}
						}
					}
					.scrollIndicators(.never)
					head("Stashes · \(model.stashes.count)")
					ScrollView {
						VStack(spacing: 0) {
							ForEach(model.stashes, id: \.self) { entry in
								let parts = entry.components(separatedBy: "\t")
								HStack(spacing: 5) {
									Text(parts.count > 1 ? parts[1] : parts[0]).font(.system(size: 11)).foregroundStyle(Ink.dim).lineLimit(1)
									Spacer(minLength: 2)
									Act(name: "arrow.down.to.line", tip: "Pop this stash") { model.git(["stash", "pop", parts[0]], "") }
									Act(name: "trash", tip: "Drop this stash, asks first", danger: true) { model.git(["stash", "drop", parts[0]], "drop " + parts[0]) }
								}
								.padding(.horizontal, 4).padding(.vertical, 2)
							}
						}
					}
					.scrollIndicators(.never).frame(maxHeight: 90)
				}
				.padding(10).frame(width: 290)
				Rectangle().fill(Ink.line).frame(width: 1)
				VStack(alignment: .leading, spacing: 3) {
					head("History")
					ScrollView {
						VStack(spacing: 0) {
							ForEach(model.commits) { commit in
								HStack(spacing: 6) {
									Text(commit.id).font(.system(size: 10, design: .monospaced)).foregroundStyle(Ink.accent)
									Text(commit.subject).font(.system(size: 12)).lineLimit(1)
									Spacer(minLength: 2)
									Text(commit.when).font(.system(size: 10)).foregroundStyle(Ink.dim).lineLimit(1).fixedSize()
									Act(name: "plus.forwardslash.minus", tip: "Compare open files against \(commit.id)") { model.compare(commit.id) }
									Act(name: "arrow.down.left.circle", tip: "Cherry-pick \(commit.id) onto \(model.branch)") { model.git(["cherry-pick", commit.id], "") }
									Act(name: "arrow.uturn.backward.circle", tip: "Revert \(commit.id) with a new commit") { model.git(["revert", "--no-edit", commit.id], "") }
								}
								.padding(.horizontal, 4).padding(.vertical, 2)
								.tip(commit.subject + " · " + commit.who)
							}
						}
					}
					.scrollIndicators(.never)
				}
				.padding(10).frame(maxWidth: .infinity)
			}
			Rectangle().fill(Ink.line).frame(height: 1)
			HStack(spacing: 8) {
				if !model.armedGit.isEmpty {
					Text("click again to " + model.armedGit).foregroundStyle(Color(red: 1, green: 0.49, blue: 0.43))
				} else {
					Text(model.said).foregroundStyle(model.failed ? Color(red: 1, green: 0.49, blue: 0.43) : Ink.dim).lineLimit(2)
				}
				Spacer(minLength: 0)
				Text("comparing against " + model.base).foregroundStyle(Ink.dim)
				if model.base != "HEAD" {
					Pill(title: "HEAD", on: false) { model.compare("HEAD") }
				}
			}
			.font(.system(size: 11)).padding(.horizontal, 14).padding(.vertical, 6)
		}
		.foregroundStyle(Ink.fg)
		.frame(width: 1000, height: 580)
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
		.overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.line, lineWidth: 1))
		.shadow(color: .black.opacity(0.45), radius: 28, y: 10)
	}
}

struct Tuning: View {
	@ObservedObject var model: Model
	@State private var typed: [String: String] = [:]

	func head(_ title: String) -> some View {
		Text(title.uppercased()).font(.system(size: 10, weight: .medium)).tracking(0.6).foregroundStyle(Ink.dim).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 8)
	}

	func flag(_ key: String) -> some View {
		Toggle(isOn: Binding(get: { model.set[key] as? Bool ?? true }, set: { model.store(key, $0 ? "true" : "false") })) {
			Text(key).font(.system(size: 12)).frame(maxWidth: .infinity, alignment: .leading)
		}
		.toggleStyle(.switch).controlSize(.mini)
	}

	func field(_ key: String) -> some View {
		let stored = model.set[key] as? String ?? ""
		let rgb = stored.hasPrefix("#") ? Int(stored.dropFirst(), radix: 16) : nil
		return HStack(spacing: 8) {
			Text(key).font(.system(size: 12))
			Spacer(minLength: 8)
			if let rgb {
				RoundedRectangle(cornerRadius: 4).fill(Color(red: Double(rgb >> 16 & 255) / 255, green: Double(rgb >> 8 & 255) / 255, blue: Double(rgb & 255) / 255)).frame(width: 16, height: 16)
			}
			TextField(stored, text: Binding(get: { typed[key] ?? stored }, set: { typed[key] = $0 }))
				.textFieldStyle(.plain).font(.system(size: 12, design: .monospaced)).multilineTextAlignment(.trailing)
				.padding(.horizontal, 6).padding(.vertical, 3).frame(width: rgb == nil ? 200 : 90)
				.background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
				.onSubmit {
					if let text = typed.removeValue(forKey: key), !text.isEmpty {
						model.store(key, text)
					}
				}
		}
	}

	func dial(_ key: String, _ range: ClosedRange<Double>, _ step: Double) -> some View {
		let value = (model.set[key] as? NSNumber)?.doubleValue ?? range.lowerBound
		return HStack(spacing: 8) {
			Text(key).font(.system(size: 12))
			Spacer(minLength: 8)
			Text(String(format: step < 1 ? "%.2f" : "%.0f", value)).font(.system(size: 11)).monospacedDigit().foregroundStyle(Ink.dim)
			Stepper("", value: Binding(get: { value }, set: { model.store(key, String(format: "%.2f", min(range.upperBound, max(range.lowerBound, $0)))) }), step: step).labelsHidden().controlSize(.small)
		}
	}

	var body: some View {
		VStack(spacing: 0) {
			HStack(spacing: 8) {
				Image(systemName: "gearshape").font(.system(size: 13)).foregroundStyle(Ink.accent)
				Text("Settings").font(.system(size: 14, weight: .semibold))
				Text("~/.slycbar/settings.json").font(.system(size: 11)).foregroundStyle(Ink.dim)
				Spacer(minLength: 8)
				Icon(name: "xmark", tip: "Close, esc") { model.setOpen = false }
			}
			.padding(.horizontal, 14).padding(.vertical, 10)
			Rectangle().fill(Ink.line).frame(height: 1)
			VStack(alignment: .leading, spacing: 6) {
				head("Editor")
				field("font")
				flag("ligatures")
				flag("smoothing")
				flag("traces")
				dial("zoom", 0.5...3, 0.05)
				head("Colours")
				field("accent")
				field("read")
				field("edited")
				field("wrote")
				head("Review keys")
				field("accept")
				field("reject")
				field("ask")
				head("Sidebar")
				flag("agents")
				flag("meters")
				flag("stats")
				flag("warp")
				dial("width", 140...900, 10)
				dial("scale", 0.7...2, 0.05)
			}
			.padding(.horizontal, 14).padding(.bottom, 14)
		}
		.foregroundStyle(Ink.fg)
		.frame(width: 440)
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
		.overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.line, lineWidth: 1))
		.shadow(color: .black.opacity(0.45), radius: 28, y: 10)
	}
}

struct Talking: View {
	@ObservedObject var model: Model
	@FocusState private var focus: Bool

	var body: some View {
		if let talk = model.talk {
			VStack(spacing: 0) {
				HStack(spacing: 8) {
					Circle().fill(talk.agent?.color ?? Ink.dim).frame(width: 9, height: 9)
					Text(talk.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
					Text(talk.detail).font(.system(size: 11)).foregroundStyle(Ink.dim).lineLimit(1).truncationMode(.head)
					Spacer(minLength: 8)
					if !talk.file.isEmpty {
						Icon(name: "square.and.pencil", tip: "Open the task file in the editor") {
							model.talk = nil
							model.boardOpen = false
							model.jump(talk.file, nil)
						}
					}
					Icon(name: "xmark", tip: "Close, esc") { model.talk = nil }
				}
				.padding(.horizontal, 14).padding(.vertical, 10)
				Rectangle().fill(Ink.line).frame(height: 1)
				ScrollView {
					VStack(alignment: .leading, spacing: 10) {
						ForEach(Array(talk.lines.enumerated()), id: \.offset) { _, line in
							if line.hasPrefix("· ") {
								Text(line).font(.system(size: 10.5, design: .monospaced)).foregroundStyle(Ink.dim).textSelection(.enabled)
							} else {
								Markdown(text: line, base: talk.agent?.dir ?? "")
							}
						}
					}
					.padding(14).frame(maxWidth: .infinity, alignment: .leading).background(Thin())
				}
				.defaultScrollAnchor(.bottom)
				.scrollIndicators(.visible)
				if let agent = talk.agent {
					Rectangle().fill(Ink.line).frame(height: 1)
					if !agent.questions.isEmpty {
						ScrollView(.horizontal) {
							HStack(spacing: 5) {
								Text("open").font(.system(size: 10)).foregroundStyle(Ink.dim)
								ForEach(agent.questions, id: \.self) { entry in
									let parts = entry.components(separatedBy: "\t")
									Button(action: { model.reply += (model.reply.isEmpty || model.reply.hasSuffix(" ") ? "" : " ") + parts[0].lowercased() + " " }) {
										Text(parts[0]).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.white).padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Ink.accent))
									}
									.buttonStyle(.plain).focusable(false).tip(parts.count > 1 ? parts[1] : "")
								}
							}
							.padding(.horizontal, 12).padding(.top, 8)
						}
						.scrollIndicators(.never)
					}
					HStack(alignment: .bottom, spacing: 8) {
						TextField("Answer " + agent.name + ", ↩ sends", text: $model.reply, axis: .vertical)
							.textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...8).focused($focus)
							.onSubmit { model.tell() }
						Icon(name: "paperplane.fill", on: true, tip: "Send") { model.tell() }
					}
					.padding(12)
				}
			}
			.foregroundStyle(Ink.fg)
			.frame(width: 900, height: 720)
			.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
			.overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.line, lineWidth: 1))
			.shadow(color: .black.opacity(0.45), radius: 28, y: 10)
			.environment(\.openURL, OpenURLAction { model.follow($0) })
			.onAppear { focus = true }
		}
	}
}

struct KitPanel: View {
	@ObservedObject var model: Model

	func head(_ title: String) -> some View {
		Text(title.uppercased()).font(.system(size: 10, weight: .medium)).tracking(0.6).foregroundStyle(Ink.dim).frame(maxWidth: .infinity, alignment: .leading).padding(.top, 4)
	}

	func open(_ path: String, _ line: Int?) {
		model.kitOpen = false
		model.boardOpen = false
		model.jump(path, line)
	}

	func row(_ title: String, _ detail: String, _ path: String) -> some View {
		Hover { over in
			HStack(spacing: 6) {
				Text(title).font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
				Spacer(minLength: 2)
				Text(detail).font(.system(size: 10)).foregroundStyle(Ink.dim).lineLimit(1)
			}
			.padding(.horizontal, 4).padding(.vertical, 3)
			.background(RoundedRectangle(cornerRadius: 6).fill(over ? Ink.hover : Color.clear))
			.contentShape(Rectangle())
			.onTapGesture { open(path, nil) }
		}
		.tip(path)
	}

	var body: some View {
		let kit = model.kit
		VStack(spacing: 0) {
			HStack(spacing: 8) {
				Image(systemName: "shippingbox").font(.system(size: 13)).foregroundStyle(Ink.accent)
				Text("Project").font(.system(size: 14, weight: .semibold))
				Text(model.short(kit.top) + "/.claude").font(.system(size: 11)).foregroundStyle(Ink.dim).lineLimit(1).truncationMode(.head)
				Spacer(minLength: 8)
				Icon(name: "xmark", tip: "Close, esc") { model.kitOpen = false }
			}
			.padding(.horizontal, 14).padding(.vertical, 10)
			Rectangle().fill(Ink.line).frame(height: 1)
			HStack(alignment: .top, spacing: 0) {
				VStack(alignment: .leading, spacing: 3) {
					head("Tasks · \(kit.tasks.count)")
					ScrollView {
						VStack(spacing: 0) {
							ForEach(Array(kit.tasks.enumerated()), id: \.offset) { _, task in
								row("#" + task.id + " " + task.title, task.status, task.path)
							}
						}
					}
					.scrollIndicators(.never)
				}
				.padding(10).frame(width: 340)
				Rectangle().fill(Ink.line).frame(width: 1)
				VStack(alignment: .leading, spacing: 3) {
					head("Agents · \(kit.agents.count)")
					ForEach(kit.agents, id: \.self) { path in
						row(((path as NSString).lastPathComponent as NSString).deletingPathExtension, "", path)
					}
					head("Skills · \(kit.skills.count)")
					ScrollView {
						VStack(spacing: 0) {
							ForEach(kit.skills, id: \.self) { path in
								row(((path as NSString).deletingLastPathComponent as NSString).lastPathComponent, "", path)
							}
						}
					}
					.scrollIndicators(.never)
					head("Facts")
					row("slyed.json", FileManager.default.fileExists(atPath: kit.top + "/.claude/slyed.json") ? "" : "not written, run slyed-init", kit.top + "/.claude/slyed.json")
				}
				.padding(10).frame(width: 250)
				Rectangle().fill(Ink.line).frame(width: 1)
				VStack(alignment: .leading, spacing: 3) {
					head("Memory · \(kit.memory.count)")
					ScrollView {
						LazyVStack(alignment: .leading, spacing: 2) {
							ForEach(Array(kit.memory.enumerated()), id: \.offset) { _, entry in
								Hover { over in
									VStack(alignment: .leading, spacing: 1) {
										HStack(spacing: 6) {
											Text(entry.kind).font(.system(size: 9, weight: .semibold)).foregroundStyle(Ink.accent)
											Text(entry.asked).font(.system(size: 12, weight: .semibold)).lineLimit(2)
										}
										Text(entry.answer).font(.system(size: 11)).foregroundStyle(Ink.dim).lineLimit(3)
									}
									.padding(.horizontal, 4).padding(.vertical, 4)
									.frame(maxWidth: .infinity, alignment: .leading)
									.background(RoundedRectangle(cornerRadius: 6).fill(over ? Ink.hover : Color.clear))
									.contentShape(Rectangle())
									.onTapGesture { open(kit.file, entry.line) }
								}
							}
						}
						.background(Thin())
					}
					.scrollIndicators(.visible)
				}
				.padding(10).frame(maxWidth: .infinity)
			}
		}
		.foregroundStyle(Ink.fg)
		.frame(width: 1060, height: 620)
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
		.overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Ink.line, lineWidth: 1))
		.shadow(color: .black.opacity(0.45), radius: 28, y: 10)
	}
}

struct Verdict: View {
	let accept: Bool
	let on: Bool
	let tip: String
	var symbol = ""
	let action: () -> Void
	@State private var over = false

	var body: some View {
		let green = Color(red: 0.42, green: 0.78, blue: 0.56)
		let red = symbol.isEmpty ? Color(red: 1, green: 0.49, blue: 0.43) : Color(red: 0.34, green: 0.66, blue: 0.96)
		let filled = accept || on
		Button(action: action) {
			Image(systemName: !symbol.isEmpty ? symbol : accept ? "checkmark" : "xmark")
				.font(.system(size: accept ? 15 : 11, weight: .bold))
				.foregroundStyle(filled ? Color.white : over ? red : Ink.fg)
				.frame(width: accept ? 34 : 26, height: accept ? 34 : 26)
				.background(Capsule().fill(accept ? green.opacity(on ? 1 : over ? 0.95 : 0.8) : on ? red : Color.clear))
				.overlay(Capsule().strokeBorder(filled ? Color.white.opacity(on ? 0.5 : 0) : over ? red : Ink.dim.opacity(0.6), lineWidth: 1))
				.contentShape(Capsule())
		}
		.buttonStyle(.plain).focusable(false)
		.onHover { over = $0 }
		.tip(tip)
	}
}

struct Remark: View {
	let note: Note
	var base = ""

	var body: some View {
		VStack(alignment: .leading, spacing: 1) {
			HStack(alignment: .firstTextBaseline, spacing: 6) {
				Image(systemName: note.question ? "questionmark.bubble" : "text.bubble").font(.system(size: 10)).foregroundStyle(note.question ? Color(red: 0.34, green: 0.66, blue: 0.96) : Ink.accent)
				Text(note.spot).font(.system(size: 10, weight: .medium)).monospacedDigit().foregroundStyle(Ink.accent)
				Markdown(text: note.text, base: base)
				if !note.sent {
					Text("unsent").font(.system(size: 9)).foregroundStyle(Ink.dim)
				}
			}
			if !note.answer.isEmpty {
				Markdown(text: note.answer, base: base).foregroundStyle(Ink.dim).padding(.leading, 16)
			}
		}
	}
}

struct Draft: View {
	@ObservedObject var pulse: Pulse
	@FocusState private var typing: Bool
	let hint: String
	let deep: Double

	var body: some View {
		TextField(hint, text: $pulse.draft, axis: .vertical)
			.textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...(deep > 0 ? max(6, Int((deep - 160) / 17)) : 6))
			.padding(.horizontal, 4).padding(.top, 4)
			.frame(maxHeight: deep > 0 ? .infinity : nil, alignment: .topLeading)
			.focused($typing)
			.onChange(of: pulse.focus) { _, _ in typing = true }
	}
}

struct Readout: View {
	@ObservedObject var pulse: Pulse
	let cursor: Bool

	var body: some View {
		if cursor {
			Text(pulse.cursor)
		} else {
			ForEach(pulse.stats, id: \.self) { Text($0) }
		}
	}
}

struct Marked: View {
	@ObservedObject var pulse: Pulse
	let model: Model
	var aim = ""

	var body: some View {
		if pulse.mark.isEmpty, !aim.isEmpty {
			Label(aim, systemImage: "scope").labelStyle(.titleAndIcon).font(.system(size: 11, weight: .medium)).foregroundStyle(Ink.dim)
				.padding(.horizontal, 8).padding(.vertical, 2)
				.overlay(Capsule().strokeBorder(Ink.line, lineWidth: 1))
				.tip("What a question or comment is about when no lines are selected")
		}
		if !pulse.mark.isEmpty {
			HStack(spacing: 5) {
				Image(systemName: "text.viewfinder").font(.system(size: 10, weight: .semibold))
				Text(pulse.mark.replacingOccurrences(of: "\n", with: "   +   ")).font(.system(size: 11, weight: .semibold)).monospacedDigit().lineLimit(1).truncationMode(.middle)
				Button(action: { model.unmark() }) {
					Image(systemName: "xmark").font(.system(size: 8, weight: .bold)).contentShape(Rectangle())
				}
				.buttonStyle(.plain).focusable(false)
			}
			.foregroundStyle(Color.white)
			.padding(.horizontal, 8).padding(.vertical, 3)
			.background(Capsule().fill(Ink.accent.opacity(0.75)))
			.tip("The selected lines go with the question or the comment; × clears the selection")
		}
	}
}

struct Feedback: View {
	@ObservedObject var model: Model

	var body: some View {
		if model.reviewing || model.sheeted || model.noting {
			card
		}
	}

	var card: some View {
		let hunk = model.reviewing ? model.hunks[model.hunk] : nil
		let step = hunk.map { model.steps[$0.change] }
		let review = hunk != nil && !model.inquiring
		return VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 7) {
				if let hunk, let step {
					Image(systemName: hunk.mark).font(.system(size: 12)).foregroundStyle(hunk.tint)
					Text(hunk.label).font(.system(size: 13, weight: .bold)).monospacedDigit()
					Text("\(model.hunk + 1) of \(model.hunks.count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(Ink.dim)
					Text(step.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
					Text(model.short(step.path) + ":\(hunk.line)" + (hunk.end > hunk.line ? "-\(hunk.end)" : "")).font(.system(size: 11)).foregroundStyle(Ink.dim).lineLimit(1).truncationMode(.head)
						.textSelection(.enabled)
					Spacer(minLength: 6)
					Counts(added: step.added, removed: step.removed)
					Text(model.phase + (model.round > 1 ? " · round \(model.round)" : "") + " · \(model.decided)/\(model.aimed)").font(.system(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(Ink.dim)
						.padding(.horizontal, 7).padding(.vertical, 1).background(Capsule().fill(Ink.hover))
				} else {
					Image(systemName: "sparkles").font(.system(size: 12)).foregroundStyle(Ink.accent)
					Text(model.comparing.isEmpty ? (model.file as NSString).lastPathComponent : model.comparing).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
					Text(model.short(model.file)).font(.system(size: 11)).foregroundStyle(Ink.dim).lineLimit(1).truncationMode(.head)
					Spacer(minLength: 6)
					if model.sheeted, !model.region.isEmpty {
						Text(model.region).font(.system(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(Ink.dim)
							.padding(.horizontal, 7).padding(.vertical, 1).background(Capsule().fill(Ink.hover))
					}
					if !model.sheeted {
						Icon(name: "xmark", tip: "Close") { model.noting = false }
					}
				}
			}
			if let hunk, !hunk.why.isEmpty {
				HStack(alignment: .firstTextBaseline, spacing: 6) {
					Image(systemName: "sparkles").font(.system(size: 10)).foregroundStyle(Ink.accent)
					Markdown(text: hunk.why, base: model.folder)
				}
			}
			if let step, !step.notes.isEmpty || !model.remarks.isEmpty {
				ScrollView {
					VStack(alignment: .leading, spacing: 4) {
						ForEach(step.notes) { Remark(note: $0, base: model.folder) }
						ForEach(model.remarks) { Remark(note: $0, base: model.folder) }
					}
					.frame(maxWidth: .infinity, alignment: .leading)
				}
				.scrollIndicators(.never)
				.frame(maxHeight: 120)
				.fixedSize(horizontal: false, vertical: true)
			}
			VStack(spacing: 4) {
				Draft(pulse: model.pulse, hint: review ? "Comment on \(hunk?.label ?? ""), it goes with accept or reject" : model.sheeted ? "Ask Claude Code about the selected lines, or this change when nothing is selected" : "Ask Claude Code about the selected lines, or tell it what to change there", deep: model.deep)
				HStack(spacing: 2) {
					if model.sheeted {
						Icon(name: "chevron.up", tip: "Previous change, ⌥↑") { model.walk(false) }
						Icon(name: "chevron.down", tip: "Next change, ⌥↓") { model.walk(true) }
					}
					if hunk != nil {
						Toggles {
							Icon(name: "checklist", on: !model.inquiring, tip: "Review: the text is a comment that goes with accept or reject") { model.inquiring = false }
							Icon(name: "questionmark.bubble", on: model.inquiring, tip: "Ask: the text is a question to Claude Code and no verdict is given") { model.inquiring = true }
						}
						.padding(.leading, 8)
					}
					Marked(pulse: model.pulse, model: model, aim: hunk.map { "change " + $0.label } ?? (model.sheeted ? "the change in focus" : "the line under the cursor")).padding(.leading, 8)
					Spacer(minLength: 6)
					if let hunk, review {
						Verdict(accept: false, on: false, tip: "Ask Claude Code about the selected lines, or this change, with the text in the field", symbol: "questionmark") {
							model.inquire(model.pulse.draft)
							model.pulse.draft = ""
						}
						.padding(.trailing, 6)
						Verdict(accept: false, on: hunk.status == "rejected", tip: "Reject \(hunk.label) with the comment, ⌥↩") { model.judge(model.hunk, "rejected") }
							.padding(.trailing, 6)
						Verdict(accept: true, on: hunk.status == "accepted", tip: "Accept \(hunk.label) with or without the comment, ⌘↩") { model.judge(model.hunk, "accepted") }
					} else {
						if !model.sheeted {
							Icon(name: "pencil.line", tip: "Send as an instruction to change the selected lines") {
								model.comment(model.pulse.draft)
								model.pulse.draft = ""
							}
						}
						Verdict(accept: false, on: false, tip: "Send the question with the selected lines and their git history, ⌘↩", symbol: "questionmark") {
							model.inquire(model.pulse.draft)
							model.pulse.draft = ""
						}
					}
				}
			}
			.frame(maxHeight: model.deep > 0 ? .infinity : nil)
			.padding(8)
			.background(RoundedRectangle(cornerRadius: 12).fill(LinearGradient(colors: [Color.white.opacity(0.1), Color.white.opacity(0.03)], startPoint: .top, endPoint: .bottom)))
			.overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(LinearGradient(colors: [Color.white.opacity(0.35), Ink.accent.opacity(0.3), Color.white.opacity(0.08)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
		}
		.foregroundStyle(Ink.fg)
		.padding(10)
		.frame(maxWidth: .infinity, maxHeight: model.deep > 0 ? .infinity : nil, alignment: .topLeading)
		.frame(height: model.deep > 0 ? model.deep : nil)
		.background(GeometryReader { box in
			Color.clear.onAppear { model.depth = box.size.height }.onChange(of: box.size.height) { _, tall in model.depth = tall }
		})
		.background(RoundedRectangle(cornerRadius: 14).fill(LinearGradient(colors: [Color.white.opacity(0.12), Color.white.opacity(0.02), Ink.accent.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing)))
		.background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 14))
		.overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(LinearGradient(colors: [Color.white.opacity(0.45), Color.white.opacity(0.06), Color.white.opacity(0.2)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
		.shadow(color: .black.opacity(0.35), radius: 16, y: 6)
		.environment(\.openURL, OpenURLAction { model.follow($0) })
		.overlay(alignment: .top) {
			Color.clear.frame(height: 7)
				.contentShape(Rectangle())
				.onHover { $0 ? NSCursor.resizeUpDown.push() : NSCursor.pop() }
				.gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global).onChanged { drag in
					model.deep = min(900, max(110, (model.deep > 0 ? model.deep : model.depth) - drag.translation.height + model.dragged))
					model.dragged = drag.translation.height
					UserDefaults.standard.set(model.deep, forKey: "deep")
				}.onEnded { _ in model.dragged = 0 })
				.onTapGesture(count: 2) {
					model.deep = 0
					UserDefaults.standard.set(0, forKey: "deep")
				}
				.tip("Drag to resize the review panel, double click to fit it")
		}
	}
}

struct Palette: View {
	@ObservedObject var model: Model
	@FocusState private var focus: Bool

	var body: some View {
		VStack(spacing: 0) {
			if model.palette == "answer", let agent = model.asking {
				VStack(alignment: .leading, spacing: 6) {
					HStack(spacing: 8) {
						Circle().fill(agent.color).frame(width: 9, height: 9).shadow(color: agent.color, radius: 5)
						Text(agent.name).font(.system(size: 14, weight: .semibold))
						Text(agent.status).font(.system(size: 10, weight: .semibold)).foregroundStyle(agent.color).padding(.horizontal, 7).padding(.vertical, 1).background(Capsule().fill(agent.color.opacity(0.18)))
						Spacer(minLength: 0)
						Text(model.short(agent.dir)).font(.system(size: 10)).foregroundStyle(Ink.dim).lineLimit(1).truncationMode(.head)
					}
					ScrollView {
						Markdown(text: agent.last.isEmpty ? "No message read from this session." : agent.last)
					}
						.frame(maxHeight: 360)
					if !agent.questions.isEmpty {
						ScrollView(.horizontal) {
							HStack(spacing: 5) {
								Text("open").font(.system(size: 10)).foregroundStyle(Ink.dim)
								ForEach(agent.questions, id: \.self) { entry in
									let parts = entry.components(separatedBy: "\t")
									Button(action: { model.query += (model.query.isEmpty || model.query.hasSuffix(" ") ? "" : " ") + parts[0].lowercased() + " " }) {
										Text(parts[0]).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.white).padding(.horizontal, 7).padding(.vertical, 2).background(Capsule().fill(Ink.accent))
									}
									.buttonStyle(.plain).focusable(false).tip(parts.count > 1 ? parts[1] : "")
								}
							}
						}
						.scrollIndicators(.never)
					}
				}
				.padding(10)
				Rectangle().fill(Ink.line).frame(height: 1)
			}
			HStack(spacing: 8) {
				Image(systemName: model.palette == "answer" ? "arrowshape.turn.up.left" : model.palette == "comment" ? "text.bubble" : model.palette == "line" ? "number" : "magnifyingglass").font(.system(size: 13)).foregroundStyle(Ink.dim)
			TextField(model.palette == "line" ? "Go to line" : model.palette == "answer" ? "Answer the agent" : model.palette == "comment" ? (model.step >= 0 ? "Comment on this change, it goes with accept or reject" : "Comment to the agent on this spot") : model.palette == "recent" ? "Recent files" : model.palette == "search" ? "Search actions, files and text" : "Go to file, or type / or ~ to browse", text: $model.query)
				.textFieldStyle(.plain).font(.system(size: 14)).padding(.vertical, 10)
				.focused($focus)
				.onSubmit { model.pick() }
				.onKeyPress(.downArrow) { model.at = min(model.at + 1, max(0, model.count - 1)); return .handled }
				.onKeyPress(.upArrow) { model.at = max(model.at - 1, 0); return .handled }
				.onKeyPress(.escape) { model.close(); return .handled }
				if model.busy && model.palette == "search" {
					ProgressView().controlSize(.small)
				}
				Text("esc").font(.system(size: 10, weight: .medium)).foregroundStyle(Ink.dim).padding(.horizontal, 6).padding(.vertical, 2).overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Ink.line, lineWidth: 1))
					.onTapGesture { model.close() }
			}
			.padding(.horizontal, 12)
			if model.palette == "search" && !model.hits.isEmpty {
				Rectangle().fill(Ink.line).frame(height: 1)
				ScrollView {
					VStack(alignment: .leading, spacing: 0) {
						ForEach(Array(model.hits.enumerated()), id: \.element.id) { at, hit in
							if at == 0 || model.hits[at - 1].section != hit.section {
								Text(hit.section.uppercased()).font(.system(size: 10, weight: .medium)).tracking(0.6).foregroundStyle(Ink.dim).padding(.horizontal, 12).padding(.top, 8).padding(.bottom, 3)
							}
							HStack(spacing: 9) {
								Image(systemName: hit.icon).font(.system(size: 12)).foregroundStyle(at == model.at ? Color.white : Ink.dim).frame(width: 18)
								Text(hit.title).font(.system(size: 13, weight: .medium)).lineLimit(1)
								Text(hit.detail).font(.system(size: 11)).foregroundStyle(Ink.dim).lineLimit(1).truncationMode(.head)
								Spacer(minLength: 6)
								if !hit.hint.isEmpty {
									Text(hit.hint).font(.system(size: 10, weight: .medium)).foregroundStyle(Ink.dim).padding(.horizontal, 5).padding(.vertical, 1)
										.overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Ink.line, lineWidth: 1))
								}
							}
							.padding(.horizontal, 10).padding(.vertical, 5)
							.background(RoundedRectangle(cornerRadius: 7).fill(at == model.at ? Ink.accent.opacity(0.55) : Color.clear).padding(.horizontal, 4))
							.contentShape(Rectangle())
							.onTapGesture {
								model.at = at
								model.pick()
							}
						}
					}
					.padding(.bottom, 6)
				}
				.scrollIndicators(.never)
				.frame(maxHeight: 420)
				Rectangle().fill(Ink.line).frame(height: 1)
				HStack(spacing: 12) {
					Text("↑↓ move")
					Text("↵ open")
					Text("esc close")
					Spacer(minLength: 0)
				}
				.font(.system(size: 10)).foregroundStyle(Ink.dim).padding(.horizontal, 12).padding(.vertical, 5)
			}
			if model.palette != "line" && model.palette != "search" && !model.results.isEmpty {
				Rectangle().fill(Ink.line).frame(height: 1)
				VStack(spacing: 0) {
					ForEach(Array(model.results.enumerated()), id: \.element) { at, entry in
						let parts = entry.components(separatedBy: "\t")
						let path = parts[0].hasSuffix("/") ? String(parts[0].dropLast()) : parts[0]
						HStack(spacing: 8) {
							Text((path as NSString).lastPathComponent + (parts[0].hasSuffix("/") ? "/" : parts.count > 1 ? ":" + parts[1] : "")).fontWeight(.semibold).fixedSize()
							Text(parts.count > 2 ? parts[2] : model.short((path as NSString).deletingLastPathComponent)).foregroundStyle(Ink.dim).lineLimit(1).truncationMode(parts.count > 2 ? .tail : .head)
							Spacer(minLength: 0)
						}
						.font(.system(size: 12))
						.padding(.horizontal, 10).padding(.vertical, 4)
						.background(at == model.at ? Ink.accent.opacity(0.5) : Color.clear)
						.contentShape(Rectangle())
						.onTapGesture {
							model.at = at
							model.pick()
						}
					}
				}
				.padding(.vertical, 4)
			}
		}
		.foregroundStyle(Ink.fg)
		.frame(width: 560)
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
		.overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(model.palette == "answer" ? AnyShapeStyle(LinearGradient(colors: [Ink.accent, Ink.accent.opacity(0.15), Color(red: 0.34, green: 0.66, blue: 0.96).opacity(0.7)], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Ink.line), lineWidth: 1))
		.shadow(color: .black.opacity(0.4), radius: 24, y: 8)
		.onAppear { focus = true }
	}
}

final class Handle: NSView {
	var across = true
	var moved: (CGPoint, Bool) -> Void = { _, _ in }

	override var mouseDownCanMoveWindow: Bool { false }

	override func resetCursorRects() {
		addCursorRect(bounds, cursor: across ? .resizeLeftRight : .resizeUpDown)
	}

	override func mouseDown(with event: NSEvent) {
		if event.clickCount == 2 {
			moved(.zero, true)
		}
	}

	override func mouseDragged(with event: NSEvent) {
		guard let window else { return }
		moved(CGPoint(x: event.locationInWindow.x, y: window.contentLayoutRect.height - event.locationInWindow.y + (window.frame.height - window.contentLayoutRect.height)), false)
	}
}

struct Grip: NSViewRepresentable {
	let across: Bool
	let moved: (CGPoint, Bool) -> Void

	func makeNSView(context: Context) -> Handle {
		let view = Handle()
		view.across = across
		view.moved = moved
		return view
	}

	func updateNSView(_ view: Handle, context: Context) {
		view.moved = moved
	}
}

struct Trail: View {
	@ObservedObject var model: Model

	var body: some View {
		ScrollViewReader { proxy in
			ScrollView(.horizontal) {
				HStack(spacing: 1) {
					ForEach(Array(model.trail().dropLast().enumerated()), id: \.element) { at, path in
						if at > 0 {
							Image(systemName: "chevron.right").font(.system(size: 6, weight: .semibold)).foregroundStyle(Ink.dim.opacity(0.6))
						}
						Hover { over in
							Text(path == "/" ? "/" : path == NSHomeDirectory() ? "~" : (path as NSString).lastPathComponent)
								.font(.system(size: 9.5 * model.scale))
								.foregroundStyle(over ? Ink.fg : Ink.dim)
								.padding(.horizontal, 3).padding(.vertical, 1)
								.background(Capsule().fill(over ? Ink.hover : Color.clear))
								.contentShape(Rectangle())
								.onTapGesture { model.climb(path) }
						}
						.tip("Go up to " + path)
						.id(path)
					}
				}
			}
			.scrollIndicators(.never)
			.onAppear { proxy.scrollTo(model.trail().dropLast().last, anchor: .trailing) }
			.onChange(of: model.root) { _, _ in proxy.scrollTo(model.trail().dropLast().last, anchor: .trailing) }
		}
	}
}

struct Mark: View {
	@ObservedObject var model: Model
	let path: String
	let on: Bool

	var body: some View {
		if let image = model.icon(path) {
			Image(nsImage: image).resizable().interpolation(.high).aspectRatio(contentMode: .fit)
				.frame(width: 18 * model.scale, height: 18 * model.scale).clipShape(RoundedRectangle(cornerRadius: 4)).opacity(on ? 1 : 0.7)
		} else {
			Image(systemName: on ? "folder.fill" : "folder").font(.system(size: 11 * model.scale)).foregroundStyle(on ? Ink.accent : Ink.dim).frame(width: 18 * model.scale)
		}
	}
}

struct Project: View {
	@ObservedObject var model: Model
	let path: String
	@State private var over = false

	var body: some View {
		let on = path == model.root
		HStack(spacing: 7) {
			Mark(model: model, path: path, on: on)
			VStack(alignment: .leading, spacing: 0) {
				Text(model.label(path)).font(.system(size: 12 * model.scale, weight: .semibold)).lineLimit(1)
				if on {
					Trail(model: model)
				} else {
					Text(model.short((path as NSString).deletingLastPathComponent)).font(.system(size: 9.5 * model.scale)).foregroundStyle(Ink.dim).lineLimit(1).truncationMode(.head)
				}
			}
			Spacer(minLength: 2)
			if on {
				More(model: model, path: path, dir: true, top: true)
			} else {
				Icon(name: "xmark", tip: "Close this project") { model.drop(path) }.opacity(over ? 1 : 0).allowsHitTesting(over)
			}
		}
		.padding(.horizontal, 6).padding(.vertical, 3)
		.background(RoundedRectangle(cornerRadius: 8).fill(on ? Ink.hover : over ? Color.white.opacity(0.05) : Color.clear))
		.contentShape(Rectangle())
		.onHover { over = $0 }
		.onTapGesture {
			if !on {
				model.ask(path)
			}
		}
		.tip(path)
		.contextMenu {
			Ops(model: model, path: path, dir: true, top: on)
		}
	}
}

struct Hover<Content: View>: View {
	@State private var over = false
	@ViewBuilder let content: (Bool) -> Content

	var body: some View {
		content(over).onHover { over = $0 }
	}
}

struct Shell: View {
	@ObservedObject var model: Model
	let web: WKWebView
	let sheet: NSScrollView
	let pad: NSView
	let twin: NSView

	var files: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 6) {
				Mark(model: model, path: model.root, on: true)
				VStack(alignment: .leading, spacing: 0) {
					Text(model.label(model.root)).font(.system(size: 12 * model.scale, weight: .semibold)).lineLimit(1).truncationMode(.tail).tip(model.root)
						.contextMenu { Ops(model: model, path: model.root, dir: true, top: true) }
					Trail(model: model)
				}
				Spacer(minLength: 0)
				More(model: model, path: model.root, dir: true, top: true)
			}
			.padding(.trailing, 6)
			ScrollView {
				LazyVStack(spacing: 1) {
					ForEach(model.nodes()) { Row(model: model, node: $0) }
				}
				.background(Thin())
			}
			.scrollIndicators(.visible)
		}
		.padding(EdgeInsets(top: 6, leading: 6, bottom: 0, trailing: 0))
	}

	var review: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 4) {
				Image(systemName: "checklist").font(.system(size: 10 * model.scale)).foregroundStyle(Ink.accent)
				Text("REVIEW").font(.system(size: 10 * model.scale)).tracking(0.6).foregroundStyle(Ink.dim)
				Text("\(model.decided)/\(model.aimed)").font(.system(size: 10 * model.scale)).monospacedDigit().foregroundStyle(Ink.dim)
				Spacer(minLength: 0)
				Act(name: "arrow.up.forward.square", tip: "Open the review, ⇧⌘R") { model.resume() }
			}
			.padding(.horizontal, 4)
			Text(model.heading).font(.system(size: 12 * model.scale, weight: .semibold)).lineLimit(1).truncationMode(.tail).padding(.horizontal, 4)
			let accepted = model.steps.filter { $0.status == "accepted" }.count
			let rejected = model.steps.filter { $0.status == "rejected" }.count
			let notes = model.steps.reduce(0) { $0 + $1.notes.count } + model.remarks.count
			HStack(spacing: 6) {
				Text(model.phase + (model.round > 1 ? " \(model.round)" : ""))
				Counts(added: model.steps.reduce(0) { $0 + $1.added }, removed: model.steps.reduce(0) { $0 + $1.removed })
				Text("\(accepted)").foregroundStyle(Color(red: 0.42, green: 0.78, blue: 0.56))
				Text("\(rejected)").foregroundStyle(Color(red: 1, green: 0.49, blue: 0.43))
				Text("\(model.steps.count - accepted - rejected) pending")
				if notes > 0 {
					Label("\(notes)", systemImage: "text.bubble").labelStyle(.titleAndIcon).foregroundStyle(Ink.accent)
				}
			}
			.font(.system(size: 10 * model.scale)).monospacedDigit().foregroundStyle(Ink.dim).lineLimit(1).padding(.horizontal, 4)
			.tip("\(model.steps.count) changes in \(Set(model.steps.map { $0.path }).count) files, \(accepted) accepted, \(rejected) rejected, \(notes) comments")
			if !model.remarks.isEmpty {
				Label("\(model.remarks.count) on the plan", systemImage: model.remarks.contains { $0.question } ? "questionmark.bubble" : "text.bubble").labelStyle(.titleAndIcon)
					.font(.system(size: 11 * model.scale)).foregroundStyle(Ink.accent).padding(.horizontal, 4)
					.tip(model.remarks.map { ($0.question ? "? " : "") + $0.text }.joined(separator: "\n"))
			}
			ForEach(Array(model.steps.enumerated()), id: \.element.id) { at, step in
				HStack(spacing: 5) {
					Image(systemName: step.mark).font(.system(size: 10 * model.scale)).foregroundStyle(step.tint)
					Text("\(at + 1)").monospacedDigit().foregroundStyle(Ink.dim)
					Text(step.title).foregroundStyle(at == model.step ? Ink.fg : Ink.dim).lineLimit(1).truncationMode(.tail)
					Spacer(minLength: 2)
					if !step.notes.isEmpty {
						Label("\(step.notes.count)", systemImage: step.notes.contains { $0.question } ? "questionmark.bubble" : "text.bubble").labelStyle(.titleAndIcon).font(.system(size: 10 * model.scale)).foregroundStyle(Ink.accent)
					}
					Counts(added: step.added, removed: step.removed)
				}
				.font(.system(size: 12 * model.scale))
				.padding(.horizontal, 4).padding(.vertical, 2)
				.background(RoundedRectangle(cornerRadius: 6).fill(at == model.step ? Ink.hover : Color.clear))
				.contentShape(Rectangle())
				.onTapGesture { model.visit(at) }
				.tip(model.short(step.path) + (step.why.isEmpty ? "" : " · " + step.why))
				.contextMenu {
					Button("Copy Path") { copy(step.path) }
					Button("Copy Proposed Path") { copy(step.proposed) }
				}
			}
		}
		.padding(6)
	}

	var agents: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 0) {
				Text("AGENTS").font(.system(size: 10 * model.scale)).tracking(0.6).foregroundStyle(Ink.dim).padding(.horizontal, 4)
				Spacer(minLength: 0)
				Icon(name: "square.grid.3x1.below.line.grid.1x2", size: 12 * model.scale, tip: "Board: the tasks and the live work of every agent, esc closes") {
					model.board()
				}
				.padding(.trailing, -5)
			}
				VStack(alignment: .leading, spacing: 1) {
					ForEach(model.agents) { agent in
						HStack(spacing: 6) {
							Circle().fill(agent.color).frame(width: 7, height: 7)
							Text(agent.name).fontWeight(.semibold).lineLimit(1)
							Text(agent.status).foregroundStyle(Ink.dim)
							Spacer(minLength: 0)
							Act(name: "checklist", tip: "Review what " + agent.name + " wrote, in the order it wrote it") { model.audit(agent) }
						}
						.font(.system(size: 12 * model.scale))
						.padding(.horizontal, 4).padding(.top, 4)
						.contentShape(Rectangle())
						.onTapGesture {
							model.asking = agent
							model.palette = "answer"
							model.query = ""
						}
						.tip(agent.status == "busy" || agent.status == "idle" ? agent.dir : agent.name + " is waiting, click to answer")
						ForEach(agent.files, id: \.self) { path in
							HStack(spacing: 5) {
								Text((path as NSString).lastPathComponent).foregroundStyle(path == model.file ? Ink.fg : Ink.dim).lineLimit(1).truncationMode(.middle)
								Spacer(minLength: 2)
								if let count = model.counts[path] {
									Counts(added: count.0, removed: count.1)
								}
								Badge(text: agent.acts[path] ?? "open", color: agent.color, scale: model.scale)
							}
								.font(.system(size: 12 * model.scale))
								.padding(.leading, 17).padding(.vertical, 2)
								.frame(maxWidth: .infinity, alignment: .leading)
								.background(RoundedRectangle(cornerRadius: 6).fill(path == model.file ? Ink.hover : Color.clear))
								.contentShape(Rectangle())
								.onTapGesture { model.review(path) }
								.tip(model.hint(agent, path))
								.onHover { model.status = $0 ? model.hint(agent, path) : "" }
								.contextMenu { Button("Copy Path") { copy(path) } }
						}
					}
				}
		}
		.padding(6)
	}

	var body: some View {
		let coding = !model.file.isEmpty && model.media.isEmpty
		return 		VStack(spacing: 0) {
			HStack(spacing: 6) {
				Spacer().frame(width: 70)
				Icon(name: "sidebar.left", tip: "Files, ⌘1") { withAnimation(.easeOut(duration: 0.2)) { model.side.toggle() } }
				Icon(name: "chevron.left", tip: "Back, ⌘[") { model.back() }.disabled(!model.earlier).opacity(model.earlier ? 1 : 0.3)
				Icon(name: "chevron.right", tip: "Forward, ⌘]") { model.forward() }.disabled(!model.later).opacity(model.later ? 1 : 0.3)
				Text(model.file.isEmpty ? "Slyed" : (model.file as NSString).lastPathComponent).font(.system(size: 13, weight: .semibold))
				if model.dirty.contains(model.file) {
					Circle().fill(Ink.dim).frame(width: 6, height: 6)
				}
				if !model.file.isEmpty {
					Text(model.short(model.file)).font(.system(size: 11)).foregroundStyle(Ink.dim).lineLimit(1).truncationMode(.head)
						.textSelection(.enabled)
						.tip("Click to copy the path")
						.onTapGesture {
							copy(model.file)
							model.status = "path copied"
						}
						.contextMenu {
							Button("Copy Path") { copy(model.file) }
							Button("Copy Relative Path") { copy(model.relative(model.file)) }
							Button("Copy File Name") { copy((model.file as NSString).lastPathComponent) }
							Button("Reveal in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: model.file)]) }
						}
				}
				Spacer(minLength: 8)
				if let agent = model.agents.first(where: { $0.files.contains(model.file) }) {
					HStack(spacing: 4) {
						Circle().fill(agent.color).frame(width: 7, height: 7)
						Text(agent.name + " " + agent.status).font(.system(size: 11)).foregroundStyle(Ink.dim)
					}
					.tip("An agent touched this file recently")
				}
				if model.preview {
					Toggles {
						Icon(name: "chevron.left.forwardslash.chevron.right", on: model.mode == "code", tip: "Code") { model.show("code") }
						Icon(name: "rectangle.split.2x1", on: model.mode == "both", tip: "Code and preview") { model.show("both") }
						Icon(name: "eye", on: model.mode == "preview", tip: "Preview") { model.show("preview") }
					}
				}
				if !model.comparing.isEmpty {
					Text(model.comparing + (model.region.isEmpty ? "" : " · " + model.region)).font(.system(size: 11)).foregroundStyle(Ink.dim).lineLimit(1).truncationMode(.middle)
					Icon(name: "chevron.up", tip: "Previous changed region") { model.walk(false) }
					Icon(name: "chevron.down", tip: "Next changed region") { model.walk(true) }
					Icon(name: "xmark", tip: "Close the comparison") { model.leave() }
				}
				if !model.proposal.isEmpty {
					Text("Claude Code proposes a change to " + model.proposal).font(.system(size: 11)).foregroundStyle(Ink.dim).lineLimit(1).truncationMode(.middle)
					Pill(title: "accept", on: true) { model.decide(true) }
					Pill(title: "reject", on: false) { model.decide(false) }
				}
					if model.reviewing {
						Toggles {
							Icon(name: "rectangle", on: model.view == "single", tip: "Single view, each change in one column") { model.look("single") }
							Icon(name: "rectangle.split.2x1", on: model.view == "sides", tip: "Side by side, the current lines left and the proposed right") { model.look("sides") }
						}
					}
				if !model.plan.isEmpty {
					Icon(name: "checklist", tip: "Review, ⇧⌘R") { model.resume() }
				}
				if !model.agents.isEmpty {
					Icon(name: "square.grid.3x1.below.line.grid.1x2", tip: "Board: the tasks and the live work of every agent, esc closes") { model.board() }
				}
				if model.tracked {
					Toggles {
						Icon(name: "plus.forwardslash.minus", on: model.diff, tip: "Inline diff against " + model.base + ", ⇧⌘D", action: model.flip)
						Icon(name: "arrow.left.arrow.right", on: model.sides, tip: "Side by side with " + model.base, action: model.flipSides)
					}
				}
				if !model.top.isEmpty {
					Icon(name: "arrow.triangle.branch", on: model.gitOpen, tip: "Git: stage, commit, branches, merge, cherry-pick, stash, ⌘9") { model.openGit() }
				}
				Icon(name: "shippingbox", on: model.kitOpen, tip: "Project: its tasks, agents, skills and memory") { model.openKit() }
			}
			.padding(.trailing, 8)
			.frame(height: 34)
			HStack(spacing: 0) {
				if model.side {
					VStack(spacing: 0) {
						ForEach(model.roots.contains(model.root) ? model.roots : model.roots + [model.root], id: \.self) { path in
							if path == model.root {
								files.frame(maxHeight: .infinity)
									.background(RoundedRectangle(cornerRadius: 10).fill(Ink.pane))
									.overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(LinearGradient(colors: [Color.white.opacity(0.3), Color.white.opacity(0.05), Color.white.opacity(0.14)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1))
									.padding(.bottom, 4)
							} else {
								Project(model: model, path: path)
									.background(RoundedRectangle(cornerRadius: 10).fill(Ink.pane))
									.overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.line, lineWidth: 1))
									.padding(.bottom, 4)
							}
						}
						if !model.plan.isEmpty {
							ScrollView {
								review.fixedSize(horizontal: false, vertical: true).background(Thin())
							}
							.scrollIndicators(.visible)
							.frame(maxHeight: 300)
							.fixedSize(horizontal: false, vertical: true)
							.background(RoundedRectangle(cornerRadius: 9).fill(Ink.accent.opacity(0.1)))
							.overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Ink.accent.opacity(0.45), lineWidth: 1))
							.padding(.bottom, 4)
						}
						if !model.agents.isEmpty, !model.hidden.contains("agents") {
							Color.clear.frame(height: 4)
								.contentShape(Rectangle())
								.onHover { $0 ? NSCursor.resizeUpDown.push() : NSCursor.pop() }
								.gesture(DragGesture(minimumDistance: 1, coordinateSpace: .global).onChanged { drag in
									model.high = max(40, (model.high > 0 ? model.high : model.grown) - drag.translation.height + model.dragged)
									model.dragged = drag.translation.height
									UserDefaults.standard.set(model.high, forKey: "high")
								}.onEnded { _ in model.dragged = 0 })
								.onTapGesture(count: 2) {
									model.high = 0
									UserDefaults.standard.set(0, forKey: "high")
								}
								.tip("Drag to resize, double click to fit the agents")
							ScrollView {
								agents.fixedSize(horizontal: false, vertical: true)
									.background(GeometryReader { box in
										Color.clear.onAppear { model.fit(box.size.height) }.onChange(of: box.size.height) { _, tall in model.fit(tall) }
									})
									.background(Thin())
							}
							.scrollIndicators(.visible)
							.frame(height: model.high > 0 ? min(model.high, model.fitted) : model.fitted)
							.background(RoundedRectangle(cornerRadius: 9).fill(Color(red: 0.282, green: 0.463, blue: 0.839).opacity(0.1)))
							.overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Color(red: 0.45, green: 0.6, blue: 0.9).opacity(0.3), lineWidth: 1))
							.onHover {
								model.resting = !$0
								if !$0 {
									model.fitted = model.grown
								}
							}
						}
						if !model.meters.isEmpty, !model.hidden.contains("meters") {
							Color.clear.frame(height: 4)
							Meters(meters: model.meters, account: model.account, scale: model.scale)
						}
					}
					.frame(width: model.width)
					.padding(EdgeInsets(top: 6, leading: 6, bottom: 6, trailing: 0))
					.onHover { model.over = $0 }
					.transition(.move(edge: .leading).combined(with: .opacity))
					Grip(across: true) { at, _ in
						model.width = min(900, max(140, at.x - 9))
						UserDefaults.standard.set(model.width, forKey: "width")
					}
					.frame(width: 7)
				}
				VStack(spacing: 0) {
					VStack(spacing: 6) {
						ZStack {
							HStack(spacing: coding && model.preview && model.mode == "both" || (coding && model.twinned) ? 6 : 0) {
								Native(view: twin).frame(maxWidth: coding && model.twinned ? .infinity : 0, maxHeight: .infinity)
									.clipShape(RoundedRectangle(cornerRadius: 10))
									.opacity(coding && model.twinned ? 1 : 0)
								Native(view: pad).frame(maxWidth: coding && !(model.preview && model.mode == "preview") ? .infinity : 0, maxHeight: .infinity)
									.clipShape(RoundedRectangle(cornerRadius: 10))
									.opacity(coding && !(model.preview && model.mode == "preview") ? 1 : 0)
								Stage(sight: model.sight, web: web).frame(maxWidth: !coding || (model.preview && model.mode != "code") ? .infinity : 0, maxHeight: .infinity)
									.clipShape(RoundedRectangle(cornerRadius: 10))
									.opacity(!coding || (model.preview && model.mode != "code") ? 1 : 0)
							}
							.overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.line, lineWidth: 1).opacity(coding && model.preview && model.mode == "both" ? 0 : 1))
							.shadow(color: .black.opacity(0.4), radius: 9, y: 2)
							.opacity(model.boardOpen || model.sheeted ? 0 : 1).allowsHitTesting(!model.boardOpen && !model.sheeted)
							if !model.boardOpen, coding || model.sheeted {
								Zoomer(pulse: model.pulse, model: model).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
							}
							if model.sheeted, !model.boardOpen {
								Native(view: sheet).frame(maxWidth: .infinity, maxHeight: .infinity)
									.clipShape(RoundedRectangle(cornerRadius: 10))
									.overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.line, lineWidth: 1))
							}
							if model.boardOpen {
								Board(model: model, live: model.live).transition(.opacity)
							}
						}
						if model.reviewing || model.sheeted || model.noting, !model.boardOpen {
							Feedback(model: model)
						}
					}
					.padding(EdgeInsets(top: 6, leading: model.side ? 0 : 6, bottom: 2, trailing: 6))
					HStack(spacing: 10) {
						if !model.status.isEmpty {
							Label(model.status, systemImage: "info.circle").labelStyle(.titleAndIcon).font(.system(size: 11, weight: .medium)).lineLimit(1)
								.foregroundStyle(Ink.fg).padding(.horizontal, 8).padding(.vertical, 2)
								.background(Capsule().fill(Ink.accent.opacity(0.35)))
								.overlay(Capsule().strokeBorder(Ink.accent.opacity(0.6), lineWidth: 1))
								.transition(.opacity)
						}
						if let count = model.counts[model.file] {
							Counts(added: count.0, removed: count.1).tip("Lines added and removed against HEAD")
						}
						if !model.hidden.contains("stats") {
							Readout(pulse: model.pulse, cursor: false)
						}
						Spacer(minLength: 8)
						if model.claude {
							Text("Claude Code").tip("A Claude Code session is connected to this editor through /ide")
						}
						Text(model.server)
						Readout(pulse: model.pulse, cursor: true)
						Icon(name: "wand.and.stars", tip: "Format the file", action: model.format)
						Hover { over in
							Button(action: model.impact) {
								Text("☢").font(.system(size: 17)).foregroundStyle(over ? Ink.fg : Ink.dim).contentShape(Rectangle())
							}
							.buttonStyle(.plain).focusable(false)
						}
						.tip("What your total token usage costs the planet in energy and water")
						Hover { over in
							Button(action: model.warp) {
								Text("WARP").font(.custom("Impact", size: 11)).tracking(1.5).foregroundStyle(over ? Ink.fg : Ink.dim).contentShape(Rectangle())
							}
							.buttonStyle(.plain).focusable(false)
						}
						.tip("Warp through the git history of what is open, by who did what")
						.opacity(model.hidden.contains("warp") ? 0 : 1).allowsHitTesting(!model.hidden.contains("warp")).frame(maxWidth: model.hidden.contains("warp") ? 0 : nil)
					}
					.font(.system(size: 11)).monospacedDigit().foregroundStyle(Ink.dim).lineLimit(1)
					.padding(.leading, 12).padding(.trailing, 6).frame(height: 22).padding(.bottom, 5)
				}
			}
		}
		.foregroundStyle(Ink.fg)
		.background(alignment: .leading) {
			if model.side {
				Ink.accent.opacity(0.14).frame(width: model.width + 9)
			}
		}
		.background(Color(red: 0.031, green: 0.039, blue: 0.071).opacity(0.34))
		.overlay(alignment: .top) {
			ZStack(alignment: .top) {
			if model.kitOpen {
				ZStack(alignment: .top) {
					Color.black.opacity(0.25).contentShape(Rectangle()).onTapGesture { model.kitOpen = false }
					KitPanel(model: model).movable().padding(.top, 60).transition(.scale(scale: 0.95, anchor: .top).combined(with: .opacity))
				}
			}
			if model.talk != nil {
				ZStack(alignment: .top) {
					Color.black.opacity(0.4).contentShape(Rectangle()).onTapGesture { model.talk = nil }
					Talking(model: model).movable().padding(.top, 50).transition(.scale(scale: 0.95, anchor: .top).combined(with: .opacity))
				}
			}
			if model.setOpen {
				ZStack(alignment: .top) {
					Color.black.opacity(0.25).contentShape(Rectangle()).onTapGesture { model.setOpen = false }
					Tuning(model: model).movable().padding(.top, 60).transition(.scale(scale: 0.95, anchor: .top).combined(with: .opacity))
				}
			}
			if model.gitOpen {
				ZStack(alignment: .top) {
					Color.black.opacity(0.25).contentShape(Rectangle()).onTapGesture { model.gitOpen = false }
					GitPanel(model: model).movable().padding(.top, 60).transition(.scale(scale: 0.95, anchor: .top).combined(with: .opacity))
				}
			}
			if !model.palette.isEmpty {
				ZStack(alignment: .top) {
					Color.black.opacity(0.2).contentShape(Rectangle()).onTapGesture { model.close() }
					Palette(model: model).movable().padding(.top, 70).transition(.scale(scale: 0.92, anchor: .top).combined(with: .opacity).combined(with: .offset(y: -14)))
				}
			}
			}
			.animation(.spring(response: 0.32, dampingFraction: 0.78), value: model.palette.isEmpty)
		}
		.overlay { Bubble() }
		.ignoresSafeArea()
		.preferredColorScheme(.dark)
	}
}

final class Files: NSObject, WKURLSchemeHandler {
	func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
		guard let url = task.request.url, url.host == "file", let handle = FileHandle(forReadingAtPath: url.path) else {
			task.didFailWithError(URLError(.fileDoesNotExist))
			return
		}
		defer { handle.closeFile() }
		let size = handle.seekToEndOfFile()
		let type = UTType(filenameExtension: (url.path as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
		var from: UInt64 = 0
		var to = size == 0 ? 0 : size - 1
		var status = 200
		var fields = ["Content-Type": type, "Accept-Ranges": "bytes"]
		if let range = task.request.value(forHTTPHeaderField: "Range"), range.hasPrefix("bytes="), size > 0 {
			let parts = range.dropFirst(6).split(separator: "-", omittingEmptySubsequences: false)
			from = min(UInt64(parts.first ?? "") ?? 0, size - 1)
			to = min(parts.count > 1 ? UInt64(parts[1]) ?? size - 1 : size - 1, min(size - 1, from + 4194303))
			status = 206
			fields["Content-Range"] = "bytes \(from)-\(to)/\(size)"
		}
		handle.seek(toFileOffset: from)
		let data = size == 0 ? Data() : handle.readData(ofLength: Int(to - from + 1))
		fields["Content-Length"] = String(data.count)
		task.didReceive(HTTPURLResponse(url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: fields)!)
		task.didReceive(data)
		task.didFinish()
	}

	func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

struct Proposal {
	let tab: String
	let path: String
	let contents: String
	let client: ObjectIdentifier
	let answer: ([[String: Any]]?) -> Void
}

final class Ide {
	var authToken = ""
	var listener: NWListener?
	var port = 0
	var lock = ""
	var clients: [ObjectIdentifier: NWConnection] = [:]
	var workspaceFolders: () -> [String] = { [] }
	var call: (String, [String: Any], ObjectIdentifier, @escaping ([[String: Any]]?) -> Void) -> Void = { _, _, _, answer in answer(nil) }
	var connected: () -> Void = {}
	var closed: (ObjectIdentifier) -> Void = { _ in }
	let tools: [[String: Any]] = [
		Ide.tool("openDiff", "Open a diff of proposed file contents and wait until it is accepted or rejected", ["old_file_path", "new_file_path", "new_file_contents", "tab_name"], ["old_file_path", "new_file_path", "new_file_contents", "tab_name"]),
		Ide.tool("close_tab", "Close the diff opened under a tab name", ["tab_name"], ["tab_name"]),
		Ide.tool("closeAllDiffTabs", "Close every diff this client opened", [], []),
		Ide.tool("getDiagnostics", "Language server diagnostics for one file uri, or for every file the editor has diagnostics on", ["uri"], []),
	]

	static func tool(_ name: String, _ description: String, _ properties: [String], _ required: [String]) -> [String: Any] {
		["name": name, "description": description, "inputSchema": ["type": "object", "properties": Dictionary(uniqueKeysWithValues: properties.map { ($0, ["type": "string"]) }), "required": required] as [String: Any]]
	}

	func start() {
		var bytes = [UInt8](repeating: 0, count: 32)
		guard SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes) == errSecSuccess else { return }
		let authToken = bytes.map { String(format: "%02x", $0) }.joined()
		self.authToken = authToken
		let options = NWProtocolWebSocket.Options()
		options.autoReplyPing = true
		options.setClientRequestHandler(.main) { subprotocols, headers in
			let allowed = headers.contains { $0.name.lowercased() == "x-claude-code-ide-authorization" && $0.value == authToken }
			return NWProtocolWebSocket.Response(status: allowed ? .accept : .reject, subprotocol: allowed && subprotocols.contains("mcp") ? "mcp" : nil)
		}
		let parameters = NWParameters.tcp
		parameters.defaultProtocolStack.applicationProtocols.insert(options, at: 0)
		parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: .any)
		guard let listener = try? NWListener(using: parameters) else { return }
		listener.newConnectionHandler = { [weak self] in self?.accept($0) }
		listener.stateUpdateHandler = { [weak self] state in
			guard let self, case .ready = state, let port = listener.port?.rawValue else { return }
			self.port = Int(port)
			self.write()
		}
		listener.start(queue: .main)
		self.listener = listener
	}

	func write() {
		guard port > 0 else { return }
		let dir = (ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? NSHomeDirectory() + "/.claude") + "/ide"
		try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
		lock = dir + "/\(port).lock"
		let body: [String: Any] = ["pid": Int(ProcessInfo.processInfo.processIdentifier), "workspaceFolders": workspaceFolders(), "ideName": "Slyed", "transport": "ws", "runningInWindows": false, "authToken": authToken]
		guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
		try? FileManager.default.removeItem(atPath: lock + ".next")
		guard FileManager.default.createFile(atPath: lock + ".next", contents: data, attributes: [.posixPermissions: 0o600]) else { return }
		rename(lock + ".next", lock)
	}

	func stop() {
		listener?.cancel()
		clients.values.forEach { $0.cancel() }
		if !lock.isEmpty {
			try? FileManager.default.removeItem(atPath: lock)
		}
	}

	func accept(_ connection: NWConnection) {
		let id = ObjectIdentifier(connection)
		clients[id] = connection
		connection.stateUpdateHandler = { [weak self] state in
			switch state {
			case .failed, .cancelled:
				guard let self, self.clients.removeValue(forKey: id) != nil else { return }
				self.closed(id)
			default:
				break
			}
		}
		connection.start(queue: .main)
		read(connection)
	}

	func read(_ connection: NWConnection) {
		connection.receiveMessage { [weak self] data, context, _, error in
			let meta = context?.protocolMetadata(definition: NWProtocolWebSocket.definition) as? NWProtocolWebSocket.Metadata
			guard let self, error == nil, let meta, meta.opcode != .close else {
				connection.cancel()
				return
			}
			if let data, let message = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
				self.take(message, connection)
			}
			self.read(connection)
		}
	}

	func send(_ message: [String: Any], _ connection: NWConnection) {
		var body = message
		body["jsonrpc"] = "2.0"
		guard let data = try? JSONSerialization.data(withJSONObject: body) else { return }
		let context = NWConnection.ContentContext(identifier: "text", metadata: [NWProtocolWebSocket.Metadata(opcode: .text)])
		connection.send(content: data, contentContext: context, isComplete: true, completion: .idempotent)
	}

	func notify(_ method: String, _ params: [String: Any]) {
		clients.values.forEach { send(["method": method, "params": params], $0) }
	}

	func take(_ message: [String: Any], _ connection: NWConnection) {
		guard let method = message["method"] as? String else { return }
		let params = message["params"] as? [String: Any] ?? [:]
		guard let id = message["id"] else {
			if method == "ide_connected" {
				connected()
			}
			return
		}
		switch method {
		case "initialize":
			let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
			send(["id": id, "result": ["protocolVersion": params["protocolVersion"] as? String ?? "2025-03-26", "capabilities": ["tools": [:] as [String: Any]], "serverInfo": ["name": "Slyed", "version": version]] as [String: Any]], connection)
		case "ping":
			send(["id": id, "result": [:] as [String: Any]], connection)
		case "tools/list":
			send(["id": id, "result": ["tools": tools]], connection)
		case "tools/call":
			call(params["name"] as? String ?? "", params["arguments"] as? [String: Any] ?? [:], ObjectIdentifier(connection)) { [weak self] content in
				if let content {
					self?.send(["id": id, "result": ["content": content]], connection)
				} else {
					self?.send(["id": id, "error": ["code": -32602, "message": "Unknown tool"] as [String: Any]], connection)
				}
			}
		default:
			send(["id": id, "error": ["code": -32601, "message": "Method not found"] as [String: Any]], connection)
		}
	}
}

final class Host: NSObject, NSApplicationDelegate, NSWindowDelegate, WKScriptMessageHandlerWithReply {
	let model = Model()
	let servers = Servers()
	let index = Index()
	let sheet = Sheet()
	let editor = Pad.make()
	var pad: Pad { editor.1 }
	var original: String?
	var sections: [Sheet.Section] = []
	var spread = ""
	var cuts: [Hunk] = []
	var kept: Set<String> = []
	var marking = 0
	var tally: [String] = []
	var zooms: [String: Double] = [:]
	var reloading: DispatchWorkItem?
	let mirror = Pad.make()
	var twin: Pad { mirror.1 }
	var mirrored = ""
	var fogged = false
	var chords: [String: (NSEvent.ModifierFlags, UInt16)] = [:]
	var staged = false
	let scroller = NSScrollView()
	let bar = tray.Host(script: Bundle.main.object(forInfoDictionaryKey: "SlycbarCli") as? String ?? "", dir: (cache as NSString).deletingLastPathComponent + "/tray", show: CommandLine.arguments.contains("show"))
	var quiet = false
	var ending = false
	var seeking = false
	var tuned = Date.distantFuture
	var win: NSWindow!
	var web: WKWebView!
	var ready = false
	var first: [String] = []
	var drafts: [String: String] = [:]
	var top = ""
	var past: [String] = [] {
		didSet { model.earlier = !past.isEmpty }
	}
	var ahead: [String] = [] {
		didSet { model.later = !ahead.isEmpty }
	}
	var rolled = 0.0
	var picked: [String: Any] = [:]
	var parsed: [Int: (String, Agent)] = [:]
	var streaming = false
	var streamed: [String: (Int, Feed)] = [:]
	var worktrees: [String: String] = [:]
	var listed = Date.distantPast
	let reader = DispatchQueue(label: "no.slytech.slyed.stream", qos: .utility)
	var carded: [String: (Date, Card)] = [:]
	var primaries: [String: String] = [:]
	var swiped = 0.0
	var fired = false
	var pending: Int?
	var pendingEnd: Int?
	let ide = Ide()
	let quit = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
	var proposals: [Proposal] = []
	var before = ""
	var held = false
	var displayed = false
	var diagnostics: [String: [[String: Any]]] = [:]
	var spotted = ""
	var folders: AnyCancellable?
	var body: [String: Any] = [:]
	var stamped = Date.distantPast
	var firstPlan = ""
	var firstPair: (String, String)?
	var drawn = false
	var cutRound = 0
	var repos: [String: String] = [:]
	var loading = 0
	var writing = 0
	let writer = DispatchQueue(label: "no.slytech.slyed.plan", qos: .utility)
	var bands: [(String, [Int])] = []
	var order: [Int] = []

	func stamp(_ path: String) -> Date {
		(try? FileManager.default.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
	}

	func load(plan path: String) {
		guard let data = FileManager.default.contents(atPath: path), let read = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
			model.status = "the plan at " + model.short(path) + " is not readable json"
			return
		}
		let fresh = model.plan != path
		let kept = fresh ? [] : model.steps
		let held = fresh ? -1 : model.hunk
		body = read
		stamped = stamp(path)
		let parse = { (c: [String: Any], n: Int) -> Note in
			let line = c["line"] as? Int ?? 0
			return Note(id: n, side: c["side"] as? String ?? (line > 0 ? "proposed" : "change"), line: line, end: c["end"] as? Int ?? line, text: c["text"] as? String ?? "",
				question: c["question"] as? Bool ?? false, answer: c["answer"] as? String ?? "", change: (c["change"] as? Int ?? 0) - 1, sent: c["sent"] as? Bool ?? false, status: c["status"] as? String ?? "")
		}
		let steps = (read["changes"] as? [[String: Any]] ?? []).enumerated().map { at, change -> Step in
			let notes = (change["comments"] as? [[String: Any]] ?? []).enumerated().map { parse($1, $0) }
			let target = change["path"] as? String ?? ""
			var step = Step(id: at, title: change["title"] as? String ?? (target as NSString).lastPathComponent, why: change["why"] as? String ?? "", path: target,
				proposed: change["proposed"] as? String ?? "", base: change["base"] as? String ?? "", status: change["status"] as? String ?? "pending", notes: notes)
			step.diff = change["diff"] as? [String] ?? []
			if at < kept.count, kept[at].path == step.path, kept[at].proposed == step.proposed {
				step.added = kept[at].added
				step.removed = kept[at].removed
			}
			return step
		}
		model.plan = path
		model.heading = read["title"] as? String ?? (path as NSString).lastPathComponent
		model.steps = steps
		model.remarks = (read["comments"] as? [[String: Any]] ?? []).enumerated().map { n, c in
			let note = parse(c, n)
			return Note(id: n, side: "plan", line: 0, end: 0, text: note.text, question: note.question, answer: note.answer, change: note.change, sent: note.sent)
		}
		model.phase = read["state"] as? String ?? "open"
		model.round = read["round"] as? Int ?? 1
		model.folder = read["dir"] as? String ?? ""
		model.side = true
		model.view = read["view"] as? String == "single" ? "single" : "sides"
		let focus = Set(read["focus"] as? [String] ?? [])
		let groups = (read["groups"] as? [[String: Any]] ?? []).map { (title: $0["title"] as? String ?? "", hunks: $0["hunks"] as? [String] ?? [], collapsed: $0["collapsed"] as? Bool ?? false) }
		let shown = Set(groups.filter { !$0.collapsed }.flatMap { $0.hunks })
		let same = kept.count == steps.count && zip(kept, steps).allSatisfy { $0.path == $1.path && $0.proposed == $1.proposed && $0.base == $1.base && $0.diff == $1.diff }
		let cut = fresh || !same || model.hunks.isEmpty || model.round != cutRound ? [] : model.hunks
		cutRound = model.round
		if fresh {
			model.step = -1
			model.hunk = -1
			model.hunks = []
		}
		DispatchQueue.global().async {
			var found = cut.isEmpty ? self.split(steps) : cut
			var steps = steps
			var verdicts: [Int: [String: Note]] = [:]
			for (at, step) in steps.enumerated() {
				for note in step.notes where !note.status.isEmpty {
					verdicts[at, default: [:]]["\(note.side) \(note.line) \(note.end)"] = note
				}
			}
			let whys = steps.map { step in step.why.split(separator: "\n").compactMap { $0.trimmingCharacters(in: .whitespaces).firstMatch(of: #/^\d+[.)]\s+(.*)$/#).map { String($0.1) } } }
			var used: [Int: Set<Int>] = [:]
			var added = Array(repeating: 0, count: steps.count)
			var removed = Array(repeating: 0, count: steps.count)
			for at in found.indices {
				var hunk = found[at]
				let note = verdicts[hunk.change]?["\(hunk.side) \(hunk.line) \(hunk.end)"]
				hunk.status = note?.status ?? "pending"
				hunk.text = note?.text ?? ""
				hunk.sent = note?.sent ?? false
				if let note {
					used[hunk.change, default: []].insert(note.id)
				}
				hunk.why = whys[hunk.change].isEmpty ? steps[hunk.change].why : hunk.part <= whys[hunk.change].count ? whys[hunk.change][hunk.part - 1] : ""
				hunk.on = (focus.isEmpty && groups.isEmpty) || focus.contains(hunk.label) || shown.contains(hunk.label)
				added[hunk.change] += hunk.added
				removed[hunk.change] += hunk.removed
				found[at] = hunk
			}
			let missed = !(focus.isEmpty && groups.isEmpty) && !found.contains { $0.on }
			if missed {
				for at in found.indices {
					found[at].on = true
				}
			}
			for at in steps.indices {
				steps[at].notes.removeAll { used[at]?.contains($0.id) == true }
				steps[at].added = added[at]
				steps[at].removed = removed[at]
			}
			var bands: [(String, [Int])] = []
			if !groups.isEmpty {
				let ids = Dictionary(found.map { ($0.label, $0.id) }) { first, _ in first }
				var taken: Set<Int> = []
				for group in groups {
					bands.append((group.title, group.hunks.compactMap { ids[$0] }.filter { taken.insert($0).inserted }))
				}
				let rest = found.indices.filter { !taken.contains($0) }
				if !rest.isEmpty {
					bands.append(("Everything else", rest))
				}
			}
			if cut.isEmpty {
				let lines = found.compactMap { hunk -> String? in
					let row: [String: Any] = ["hunk": hunk.label, "change": hunk.change + 1, "path": steps[hunk.change].path, "side": hunk.side, "line": hunk.line, "end": hunk.end, "added": hunk.added, "removed": hunk.removed]
					return (try? JSONSerialization.data(withJSONObject: row, options: [.sortedKeys, .withoutEscapingSlashes])).map { String(decoding: $0, as: UTF8.self) }
				}
				try? (lines.joined(separator: "\n") + "\n").write(toFile: (path as NSString).deletingLastPathComponent + "/hunks.jsonl", atomically: true, encoding: .utf8)
			}
			DispatchQueue.main.async {
				guard self.model.plan == path, self.model.steps.count == steps.count else { return }
				self.model.steps = steps
				self.model.hunks = found
				self.bands = bands
				let parts = Dictionary(grouping: found, by: \.change)
				self.spread = ""
				self.sections = bands.isEmpty
					? steps.enumerated().map { n, step in Sheet.Section(title: (step.path as NSString).lastPathComponent, detail: self.model.short(step.path) + (step.title == (step.path as NSString).lastPathComponent ? "" : "  " + step.title), added: step.added, removed: step.removed, ids: (parts[n] ?? []).map(\.id)) }
					: bands.map { band in Sheet.Section(title: band.0, detail: "\(band.1.count) " + (band.1.count == 1 ? "change" : "changes"), added: band.1.reduce(0) { $0 + found[$1].added }, removed: band.1.reduce(0) { $0 + found[$1].removed }, ids: band.1) }
				self.order = bands.isEmpty ? Array(found.indices) : bands.flatMap { $0.1 }
				self.drawn = false
				guard !found.isEmpty else {
					self.model.status = "the plan changes nothing against the files on disk"
					return
				}
				if missed {
					self.model.status = "the focus names no hunk of this plan, every hunk is shown"
				}
				let start = self.order.first { found[$0].on && found[$0].status == "pending" } ?? self.order.first { found[$0].on } ?? 0
				if fresh {
					self.seek(start, record: false)
				} else if held >= 0 {
					self.seek(held < found.count && found[held].on ? held : start, record: false)
				}
			}
		}
	}

	func pairs(_ rows: [[String: Any]]) -> Int {
		var count = 0
		var minus = 0
		var plus = 0
		for row in rows {
			let mark = row["t"] as? String
			if mark == " " {
				count += max(minus, plus) + 1
				minus = 0
				plus = 0
			} else if mark == "-" {
				minus += 1
			} else {
				plus += 1
			}
		}
		return count + max(minus, plus)
	}

	func split(_ steps: [Step]) -> [Hunk] {
		let fm = FileManager.default
		var found: [Hunk] = []
		for (change, step) in steps.enumerated() {
			let left = !step.base.isEmpty ? step.base : fm.fileExists(atPath: step.path) ? step.path : "/dev/null"
			let out = String(decoding: call("/usr/bin/git", ["diff", "--no-index", "--no-color", "-U3"] + self.flags(step.diff) + ["--", left, step.proposed]).out, as: UTF8.self)
			var old = 0
			var new = 0
			var rows: [[String: Any]] = []
			var part = 0
			let close = {
				var runs: [(Int, Int)] = []
				for (at, row) in rows.enumerated() where row["t"] as? String != " " {
					if let last = runs.last, last.1 == at - 1 {
						runs[runs.count - 1].1 = at
					} else {
						runs.append((at, at))
					}
				}
				for (n, run) in runs.enumerated() {
					let before = n == 0 ? 0 : runs[n - 1].1 + 1 + min(3, run.0 - runs[n - 1].1 - 1)
					let after = n == runs.count - 1 ? rows.count - 1 : run.1 + min(3, runs[n + 1].0 - run.1 - 1)
					let own = Array(rows[run.0...run.1])
					let plus = own.filter { $0["t"] as? String == "+" }.compactMap { $0["b"] as? Int }
					let minus = own.filter { $0["t"] as? String == "-" }.compactMap { $0["a"] as? Int }
					let lines = plus.isEmpty ? minus : plus
					part += 1
					var hunk = Hunk(id: found.count, change: change, part: part, side: plus.isEmpty ? "base" : "proposed", line: lines.first ?? 1, end: lines.last ?? 1, rows: Array(rows[before...after]))
					hunk.added = plus.count
					hunk.removed = minus.count
					hunk.pairs = self.pairs(hunk.rows)
					found.append(hunk)
				}
				rows = []
			}
			for line in out.split(separator: "\n", omittingEmptySubsequences: false) {
				if line.hasPrefix("@@") {
					close()
					let parts = line.split(separator: " ")
					guard parts.count > 2 else { continue }
					old = Int(parts[1].dropFirst().split(separator: ",").first ?? "") ?? 0
					new = Int(parts[2].dropFirst().split(separator: ",").first ?? "") ?? 0
					continue
				}
				guard old + new > 0 || !rows.isEmpty, let mark = line.first, mark == " " || mark == "+" || mark == "-" else { continue }
				let text = String(line.dropFirst())
				if mark == " " {
					rows.append(["t": " ", "a": old, "b": new, "s": text])
					old += 1
					new += 1
				} else if mark == "+" {
					rows.append(["t": "+", "a": 0, "b": new, "s": text])
					new += 1
				} else {
					rows.append(["t": "-", "a": old, "b": 0, "s": text])
					old += 1
				}
			}
			close()
		}
		return found
	}

	func flags(_ asked: [String]) -> [String] {
		let ways = ["myers", "minimal", "patience", "histogram"]
		let loose = ["ignore-all-space", "ignore-space-change", "ignore-space-at-eol", "ignore-blank-lines", "ignore-cr-at-eol"]
		return ["--diff-algorithm=" + (asked.first { ways.contains($0) } ?? "histogram")] + asked.filter { loose.contains($0) }.map { "--" + $0 }
	}

	func repo(_ dir: String) -> String {
		if let known = repos[dir] {
			return known
		}
		let found = git(dir, ["rev-parse", "--show-toplevel"])
		let top = found.code == 0 ? String(decoding: found.out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : ""
		repos[dir] = top
		return top
	}

	func anchor(_ path: String, top: Bool = false) {
		var dir = (path as NSString).deletingLastPathComponent
		while dir.count > 1, !FileManager.default.fileExists(atPath: dir) {
			dir = (dir as NSString).deletingLastPathComponent
		}
		model.stepping = true
		let repo = top ? self.repo(dir) : ""
		if !repo.isEmpty {
			model.adopt(repo)
		} else if let held = model.roots.filter({ path.hasPrefix($0 + "/") }).max(by: { $0.count < $1.count }) {
			model.root = held
		} else {
			let project = self.repo(dir)
			model.adopt(project.isEmpty ? dir : project)
		}
		model.stepping = false
		var at = dir
		while at.count > model.root.count {
			model.open.insert(at)
			at = (at as NSString).deletingLastPathComponent
		}
	}

	func here(_ root: String) -> String {
		root + "\t" + (model.reviewing ? "\t\(model.hunk)" : model.file)
	}

	func record(_ place: String) {
		guard place != "\t", place != past.last else { return }
		past.append(place)
		ahead = []
	}

	func go(_ place: String) {
		let parts = place.components(separatedBy: "\t")
		if !parts[0].isEmpty, parts[0] != model.root {
			model.stepping = true
			if model.roots.contains(parts[0]) {
				model.root = parts[0]
			} else {
				model.roots = model.roots.map { $0 == model.root ? parts[0] : $0 }
				model.adopt(parts[0])
			}
			model.stepping = false
		}
		if parts.count > 2, let at = Int(parts[2]), at < model.hunks.count {
			seek(at, record: false)
		} else if parts.count > 1, !parts[1].isEmpty, parts[1] != model.file || model.step >= 0 || !model.comparing.isEmpty {
			show(parts[1], record: false)
		} else {
			refresh()
		}
	}

	func seek(_ at: Int, record: Bool = true) {
		guard at >= 0, at < model.hunks.count else { return }
		guard model.proposal.isEmpty else {
			model.status = "answer the open Claude Code proposal first"
			return
		}
		let step = model.steps[model.hunks[at].change]
		let draw = {
			if record, at != self.model.hunk {
				self.record(self.here(self.model.root))
			}
			self.loading += 1
			self.displayed = false
			self.model.file = step.path
			self.model.tracked = false
			self.model.diff = false
			self.model.sides = false
			self.model.preview = false
			self.model.comparing = ""
			self.model.region = ""
			self.win.title = self.model.hunks[at].label + " " + step.title
			let turned = !self.drawn || self.model.step != self.model.hunks[at].change
			if turned {
				self.anchor(step.path, top: true)
			}
			self.model.hunk = at
			self.model.step = self.model.hunks[at].change
			self.model.pulse.draft = self.model.hunks[at].text
			self.drawn = true
			if self.spread != self.model.plan {
				self.fill(self.model.hunks, self.model.steps.map(\.path), self.sections, self.model.view)
				self.inline()
				self.spread = self.model.plan
			}
			self.model.sheeted = true
			self.sheet.focus(at)
			if turned {
				self.refresh()
			}
		}
		stash()
		draw()
	}

	func judge(_ at: Int, _ status: String) {
		guard at >= 0, at < model.hunks.count else { return }
		let text = at == model.hunk ? model.pulse.draft.trimmingCharacters(in: .whitespacesAndNewlines) : model.hunks[at].text
		model.hunks[at].status = model.hunks[at].status == status && model.hunks[at].text == text ? "pending" : status
		model.hunks[at].text = text
		model.hunks[at].sent = false
		let change = model.hunks[at].change
		let marks = model.hunks.filter { $0.change == change }.map { $0.status }
		model.steps[change].status = marks.contains("rejected") ? "rejected" : marks.allSatisfy { $0 == "accepted" } ? "accepted" : "pending"
		persist()
		guard model.hunks.contains(where: { $0.on && $0.status == "pending" }) else {
			finish()
			return
		}
		if at < sheet.hunks.count {
			sheet.hunks[at].status = model.hunks[at].status
			sheet.hunks[at].text = model.hunks[at].text
		}
		sheet.needsDisplay = true
		if at == model.hunk, model.hunks[at].status != "pending", let next = order.drop(while: { $0 != at }).dropFirst().first(where: { model.hunks[$0].on && model.hunks[$0].status == "pending" }) ?? order.first(where: { model.hunks[$0].on && model.hunks[$0].status == "pending" }) {
			seek(next)
		}
	}

	func walk(_ forward: Bool) {
		if !model.comparing.isEmpty {
			let next = sheet.current + (forward ? 1 : -1)
			if next >= 0, next < sheet.hunks.count {
				sheet.focus(next)
				model.region = "region \(next + 1) of \(sheet.hunks.count)"
			} else {
				model.status = forward ? "no later difference" : "no earlier difference"
			}
			return
		}
		guard !model.hunks.isEmpty else { return }
		var next = (order.firstIndex(of: model.hunk) ?? (forward ? -1 : order.count)) + (forward ? 1 : -1)
		while next >= 0, next < order.count, !model.hunks[order[next]].on {
			next += forward ? 1 : -1
		}
		guard next >= 0, next < order.count else {
			model.status = forward ? "this is the last change" : "this is the first change"
			return
		}
		seek(order[next])
	}

	func look(_ view: String) {
		guard model.reviewing, model.view != view else { return }
		model.view = view
		persist { $0["view"] = view }
		sheet.view = view
		sheet.focus(model.hunk)
	}

	func ask(_ text: String) {
		let asked = text.trimmingCharacters(in: .whitespacesAndNewlines)
		guard !asked.isEmpty else {
			model.status = "write the question first"
			return
		}
		var chosen = (hunk: -1, line: 1, end: 1, text: "")
		var path = model.file
		var what = "the open file"
		var planned = ""
		var why = ""
		if model.sheeted {
			let all = sheet.selections().filter { $0.hunk < sheet.hunks.count }
			guard let found = all.first else {
				model.status = "nothing is selected in the diff"
				return
			}
			chosen = (found.hunk, found.line, found.end, all.map { one in (all.count > 1 ? "lines \(one.line)-\(one.end) of change " + sheet.hunks[one.hunk].label + ":\n" : "") + one.text }.joined(separator: "\n\n"))
			let hunk = sheet.hunks[found.hunk]
			if model.reviewing, hunk.change < model.steps.count {
				let next = (model.steps[hunk.change].notes.map(\.id).max() ?? -1) + 1
				model.steps[hunk.change].notes.append(Note(id: next, side: hunk.side, line: found.line, end: found.end, text: asked, question: true, sent: true))
				persist()
				inline()
				sheet.arrange()
				planned = "\nWrite the answer into the review so it shows under those lines: read the plan with review_status and the plan path " + model.plan + ", set answer on the comment with this text under change \(hunk.change + 1), and call review_open with that plan path and that change as its path and its comments."
			}
			path = hunk.change < sheet.paths.count ? sheet.paths[hunk.change] : model.file
			what = model.reviewing ? "the review \"" + model.heading + "\", change " + hunk.label : !model.comparing.isEmpty ? "the comparison " + model.comparing : "the diff of " + model.short(path) + " against " + model.base
			why = model.reviewing ? hunk.why : ""
		} else {
			guard pad.path == model.file, !model.file.isEmpty else { return }
			let spot = pad.spot()
			chosen = (-1, spot.line, spot.end, spot.text)
			let from = pad.span(spot.line)
			let to = pad.span(spot.end)
			pad.asked.append(NSRange(location: from.location, length: to.location + to.length - from.location))
			pad.needsDisplay = true
		}
		let sid = body["session"] as? String ?? ""
		let agent = (model.reviewing ? model.agents.first { $0.sid == sid } : nil) ?? model.agents.first { $0.files.contains(path) } ?? model.agents.first { !$0.dir.isEmpty && path.hasPrefix($0.dir + "/") }
		model.status = "gathering the history of those lines…"
		DispatchQueue.global(qos: .userInitiated).async {
			let dir = (path as NSString).deletingLastPathComponent
			let name = (path as NSString).lastPathComponent
			var history = String(decoding: git(dir, ["log", "-n", "6", "--date=short", "--format=%x01%h %ad %an: %s", "-L\(chosen.line),\(chosen.end):" + name]).out, as: UTF8.self).split(separator: "\n").filter { $0.hasPrefix("\u{1}") }.map { String($0.dropFirst()) }
			if history.isEmpty {
				history = String(decoding: git(dir, ["log", "-n", "6", "--date=short", "--format=%h %ad %an: %s", "--", name]).out, as: UTF8.self).split(separator: "\n").map(String.init)
			}
			let pending = String(decoding: git(dir, ["diff", "--stat", "HEAD", "--", name]).out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
			var message = "Question from Slyed on \(path):\(chosen.line)" + (chosen.end > chosen.line ? "-\(chosen.end)" : "") + ", in " + what + ". " + asked
			message += "\nSelected lines, + added, - removed:\n" + chosen.text
			if !why.isEmpty {
				message += "\nWhy given for this change: " + why
			}
			if !history.isEmpty {
				message += "\nCommits that touched these lines:\n" + history.joined(separator: "\n")
			}
			if !pending.isEmpty {
				message += "\nUncommitted in this file: " + pending
			}
			message += "\nAnswer about this selection only, from the code and its history, and change no file." + planned
			DispatchQueue.main.async {
				slyed.copy(message)
				guard let agent, !agent.socket.isEmpty else {
					self.model.status = "no Claude Code session on this file, the question is copied"
					return
				}
				self.model.status = self.post(agent.socket, message) ? "question sent to " + agent.name : "not sent to " + agent.name + ", the question is copied"
				note("comments.log", agent.name + " question " + path + ":\(chosen.line)")
				self.converse(agent, agent.name, agent.logs.first ?? "", "")
			}
		}
	}

	func retalk() {
		guard let talk = model.talk, let agent = talk.agent, talk.file.isEmpty, let log = model.agents.first(where: { $0.id == agent.id })?.logs.first else { return }
		let title = talk.title
		DispatchQueue.global(qos: .utility).async {
			let lines = self.statements(log)
			DispatchQueue.main.async {
				if self.model.talk?.title == title, !lines.isEmpty, self.model.talk?.lines.count != lines.count || self.model.talk?.lines.last != lines.last {
					self.model.talk?.lines = lines
				}
			}
		}
	}

	func inline() {
		var found: [Int: [(row: Int, text: String)]] = [:]
		for hunk in model.hunks where hunk.change < model.steps.count {
			for note in model.steps[hunk.change].notes where note.status.isEmpty && (note.side == "base" || note.side == "proposed") {
				let key = note.side == "base" ? "a" : "b"
				guard let row = hunk.rows.lastIndex(where: { ($0[key] as? Int ?? 0) == note.end }) else { continue }
				found[hunk.id, default: []].append((row, (note.question ? "? " : "") + note.text + (note.answer.isEmpty ? "" : "\n→ " + note.answer)))
			}
		}
		sheet.notes = found
	}

	func chord(_ text: String) -> (NSEvent.ModifierFlags, UInt16)? {
		let codes: [String: UInt16] = ["return": 36, "enter": 36, "space": 49, "a": 0, "s": 1, "d": 2, "f": 3, "h": 4, "g": 5, "z": 6, "x": 7, "c": 8, "v": 9, "b": 11, "q": 12, "w": 13, "e": 14, "r": 15, "y": 16, "t": 17, "o": 31, "u": 32, "i": 34, "p": 35, "l": 37, "j": 38, "k": 40, "n": 45, "m": 46, "/": 44, ".": 47, ",": 43]
		var flags: NSEvent.ModifierFlags = []
		var code: UInt16?
		for part in text.lowercased().split(separator: "+").map({ $0.trimmingCharacters(in: .whitespaces) }) {
			switch part {
			case "cmd", "command", "⌘": flags.insert(.command)
			case "opt", "option", "alt", "⌥": flags.insert(.option)
			case "ctrl", "control", "⌃": flags.insert(.control)
			case "shift", "⇧": flags.insert(.shift)
			default: code = codes[part]
			}
		}
		return code.map { (flags, $0) }
	}

	func struck(_ name: String, _ event: NSEvent) -> Bool {
		guard let chord = chords[name] else { return false }
		return event.modifierFlags.intersection([.command, .control, .option, .shift]) == chord.0 && (event.keyCode == chord.1 || (chord.1 == 36 && event.keyCode == 76))
	}

	func resume() {
		guard !model.plan.isEmpty else {
			model.status = "no review is open, an agent opens one with slybar review"
			return
		}
		seek(model.hunk >= 0 ? model.hunk : order.first { model.hunks[$0].on && model.hunks[$0].status == "pending" } ?? order.first { model.hunks[$0].on } ?? 0)
	}

	func finish() {
		let approved = model.hunks.allSatisfy { !$0.on || $0.status == "accepted" }
		for at in model.hunks.indices {
			model.hunks[at].sent = true
		}
		for at in model.remarks.indices {
			model.remarks[at].sent = true
		}
		for at in model.steps.indices {
			for n in model.steps[at].notes.indices {
				model.steps[at].notes[n].sent = true
			}
		}
		let state = approved ? "approved" : "sent"
		let stamp = ISO8601DateFormatter().string(from: Date())
		persist {
			$0["state"] = state
			$0["sent"] = stamp
		}
		annotate()
		let said = body["live"] as? Bool == true ? relay() : approved ? "every change is accepted, the review is back with Claude Code" : "the review is back with Claude Code"
		note("comments.log", "review " + state + " " + model.plan)
		leave()
		model.status = said
	}

	func audit(_ agent: Agent) {
		let sid = agent.sid
		let ref = "refs/slyed/" + sid
		let folder = cache + "/live/" + sid
		let path = folder + "/plan.json"
		DispatchQueue.global().async {
			let fm = FileManager.default
			func text(_ args: [String], _ at: String) -> String { String(decoding: git(at, args).out, as: UTF8.self) }
			let top = text(["rev-parse", "--show-toplevel"], agent.dir).trimmingCharacters(in: .whitespacesAndNewlines)
			let ids = top.isEmpty ? [] : text(["rev-list", "--reverse", ref, "--not", "--branches", "--remotes"], top).split(separator: "\n").map(String.init)
			let old = (fm.contents(atPath: path).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] })?["changes"] as? [[String: Any]] ?? []
			try? fm.createDirectory(atPath: folder, withIntermediateDirectories: true)
			var changes: [[String: Any]] = []
			for id in ids {
				let why = text(["log", "-1", "--format=%B", id], top).trimmingCharacters(in: .whitespacesAndNewlines)
				guard why != "base" else { continue }
				for name in text(["diff-tree", "--no-commit-id", "--name-only", "-r", "-z", id], top).split(separator: "\0").map(String.init) {
					if let kept = old.first(where: { $0["commit"] as? String == id && $0["path"] as? String == top + "/" + name }) {
						changes.append(kept)
						continue
					}
					let stem = folder + "/" + id.prefix(10) + "." + (name as NSString).lastPathComponent
					let before = git(top, ["show", id + "^:" + name])
					let after = git(top, ["show", id + ":" + name])
					fm.createFile(atPath: stem + ".base", contents: before.code == 0 ? before.out : Data())
					fm.createFile(atPath: stem, contents: after.code == 0 ? after.out : Data())
					changes.append(["commit": id, "title": String((why.split(separator: "\n").first ?? Substring(name)).prefix(90)), "why": why, "path": top + "/" + name, "base": stem + ".base", "proposed": stem, "status": "pending", "comments": [] as [Any]])
				}
			}
			DispatchQueue.main.async {
				guard !changes.isEmpty else {
					self.model.status = agent.name + " has no snapshotted changes on " + ref
					return
				}
				let plan: [String: Any] = ["title": agent.name + ", changes as written", "session": sid, "dir": top, "live": true, "state": "open", "round": 1, "changes": changes]
				guard let data = try? JSONSerialization.data(withJSONObject: plan, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]), (try? data.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil else {
					self.model.status = "the review of " + agent.name + " was not written to " + self.model.short(path)
					return
				}
				self.load(plan: path)
			}
		}
	}

	func annotate() {
		let raw = body["changes"] as? [[String: Any]] ?? []
		var marks: [String: (dir: String, said: [String])] = [:]
		for hunk in model.hunks where hunk.change < raw.count {
			guard let commit = raw[hunk.change]["commit"] as? String else { continue }
			marks[commit, default: ((model.steps[hunk.change].path as NSString).deletingLastPathComponent, [])].said.append("\(hunk.part) " + hunk.status + (hunk.text.isEmpty ? "" : " " + hunk.text))
		}
		DispatchQueue.global().async {
			for (commit, mark) in marks {
				_ = git(mark.dir, ["notes", "--ref=slyed", "add", "-f", "-m", mark.said.joined(separator: "\n"), commit])
			}
		}
	}

	func relay() -> String {
		let sid = body["session"] as? String ?? ""
		let top = body["dir"] as? String ?? ""
		let rejected = model.hunks.filter { $0.status == "rejected" }
		var lines = ["Review from Slyed of the changes you wrote: \(model.hunks.filter { $0.status == "accepted" }.count) accepted, \(rejected.count) rejected."]
		for hunk in model.hunks {
			let path = model.steps[hunk.change].path
			let spot = (path.hasPrefix(top + "/") ? String(path.dropFirst(top.count + 1)) : path) + ":\(hunk.line)" + (hunk.end > hunk.line ? "-\(hunk.end)" : "")
			if hunk.status == "rejected" || !hunk.text.isEmpty {
				lines.append(hunk.status + " " + spot + (hunk.text.isEmpty ? "" : ": " + hunk.text))
			}
		}
		if !rejected.isEmpty {
			lines.append("Redo only the rejected spots.")
		}
		let message = lines.joined(separator: "\n")
		slyed.copy(message)
		if let holder = model.agents.first(where: { $0.sid == sid }), !rejected.isEmpty {
			let body = lines.filter { $0.hasPrefix("rejected ") }.map { "- " + $0 }.joined(separator: "\n")
			DispatchQueue.global().async { self.held(holder).forEach { self.minute($0, "Review", body) } }
		}
		guard let agent = model.agents.first(where: { $0.sid == sid }), !agent.socket.isEmpty else { return "the session is gone, the review is copied" }
		return post(agent.socket, message) ? "the review is sent to " + agent.name : "not sent to " + agent.name + ", the review is copied"
	}

	func statements(_ log: String) -> [String] {
		guard let handle = FileHandle(forReadingAtPath: log) else { return [] }
		let size = handle.seekToEndOfFile()
		handle.seek(toFileOffset: size > 2500000 ? size - 2500000 : 0)
		let text = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
		handle.closeFile()
		var found: [String] = []
		for line in text.split(separator: "\n") where line.contains("\"type\":\"assistant\"") {
			guard let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
			for block in ((entry["message"] as? [String: Any])?["content"] as? [[String: Any]]) ?? [] {
				if block["type"] as? String == "text", let said = block["text"] as? String, !said.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
					found.append(said)
				}
				if block["type"] as? String == "tool_use", let tool = block["name"] as? String {
					let input = block["input"] as? [String: Any] ?? [:]
					let subject = ["file_path", "notebook_path", "command", "pattern", "description", "url", "query", "prompt", "skill"].lazy.compactMap { input[$0] as? String }.first ?? ""
					found.append("· " + tool + " " + (subject.split(separator: "\n").first.map(String.init) ?? "").prefix(220))
				}
			}
		}
		return Array(found.suffix(90))
	}

	func converse(_ agent: Agent?, _ title: String, _ log: String, _ file: String) {
		model.reply = ""
		model.talk = Model.Talk(agent: agent, title: title, detail: file.isEmpty ? model.short(agent?.dir ?? "") : model.short(file), file: file, lines: [])
		DispatchQueue.global().async {
			var lines: [String] = []
			if !file.isEmpty {
				let parts = self.decode(file).components(separatedBy: "\n---\n")
				lines.append(parts.count > 1 ? parts.dropFirst().joined(separator: "\n---\n") : parts[0])
			}
			if !log.isEmpty {
				lines += self.statements(log)
			}
			DispatchQueue.main.async {
				guard self.model.talk?.title == title else { return }
				self.model.talk?.lines = lines.isEmpty ? ["Nothing is read from this session yet."] : lines
			}
		}
	}

	func held(_ agent: Agent) -> [String] {
		let first = String(decoding: git(agent.dir, ["worktree", "list", "--porcelain"]).out, as: UTF8.self).split(separator: "\n").first.map(String.init) ?? ""
		guard first.hasPrefix("worktree ") else { return [] }
		let dir = String(first.dropFirst(9)) + "/.claude/tasks"
		return ((try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []).filter { $0.hasSuffix(".md") }.map { dir + "/" + $0 }.filter { path in
			String(decoding: (FileManager.default.contents(atPath: path) ?? Data()).prefix(3000), as: UTF8.self).split(separator: "\n").contains { $0 == "session: " + agent.name }
		}
	}

	func minute(_ file: String, _ heading: String, _ body: String) {
		var text = decode(file)
		guard !text.isEmpty, !body.isEmpty else { return }
		if !text.contains("\n## " + heading + "\n") {
			text += (text.hasSuffix("\n") ? "" : "\n") + "\n## " + heading + "\n\n"
		}
		text += body + "\n"
		try? text.write(toFile: file, atomically: true, encoding: .utf8)
	}

	func loadKit() {
		let base = top.isEmpty ? model.root : top
		DispatchQueue.global().async {
			let fm = FileManager.default
			let dir = base + "/.claude"
			var kit = Model.Kit()
			kit.top = base
			kit.file = dir + "/memory.jsonl"
			func number(_ name: String) -> Int { Int(name.prefix { $0.isNumber }) ?? 0 }
			for name in ((try? fm.contentsOfDirectory(atPath: dir + "/tasks")) ?? []).filter({ $0.hasSuffix(".md") }).sorted(by: { number($0) > number($1) }) {
				let rows = String(decoding: (fm.contents(atPath: dir + "/tasks/" + name) ?? Data()).prefix(4000), as: UTF8.self).split(separator: "\n")
				func field(_ key: String) -> String {
					rows.first { $0.hasPrefix(key + ":") }.map { String($0.dropFirst(key.count + 1)).trimmingCharacters(in: .whitespaces) } ?? ""
				}
				kit.tasks.append((dir + "/tasks/" + name, field("id"), field("title"), field("status")))
			}
			kit.agents = ((try? fm.contentsOfDirectory(atPath: dir + "/agents")) ?? []).filter { $0.hasSuffix(".md") }.sorted().map { dir + "/agents/" + $0 }
			kit.skills = ((try? fm.contentsOfDirectory(atPath: dir + "/skills")) ?? []).sorted().map { dir + "/skills/" + $0 + "/SKILL.md" }.filter { fm.fileExists(atPath: $0) }
			for (n, line) in String(decoding: fm.contents(atPath: kit.file) ?? Data(), as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
				guard let row = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
				kit.memory.append((n + 1, row["c"] as? String ?? "", row["q"] as? String ?? "", row["a"] as? String ?? ""))
			}
			DispatchQueue.main.async { self.model.kit = kit }
		}
	}

	@objc func kitPanel(_ sender: Any?) {
		model.kitOpen.toggle()
		if model.kitOpen {
			loadKit()
		}
	}

	func recheck() {
		guard !model.plan.isEmpty, writing == 0, stamp(model.plan) > stamped else { return }
		load(plan: model.plan)
		model.status = "the plan changed on disk and was read again"
	}

	func persist(_ also: (inout [String: Any]) -> Void = { _ in }) {
		guard !model.plan.isEmpty else { return }
		if writing == 0, stamp(model.plan) > stamped, let data = FileManager.default.contents(atPath: model.plan), let read = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
			body = read
		}
		let entry = { (note: Note) -> [String: Any] in
			var item: [String: Any] = ["text": note.text]
			if note.side != "plan" {
				item["side"] = note.side
			}
			if note.side == "base" || note.side == "proposed" {
				item["line"] = note.line
				item["end"] = note.end
			}
			if note.question {
				item["question"] = true
			}
			if !note.answer.isEmpty {
				item["answer"] = note.answer
			}
			if note.change >= 0 {
				item["change"] = note.change + 1
			}
			if note.sent {
				item["sent"] = true
			}
			if !note.status.isEmpty {
				item["status"] = note.status
			}
			return item
		}
		var raw = body["changes"] as? [[String: Any]] ?? []
		for step in model.steps where step.id < raw.count {
			raw[step.id]["status"] = step.status
			raw[step.id]["comments"] = step.notes.map(entry) + model.hunks.filter { $0.change == step.id && $0.status != "pending" }.map { entry(Note(id: $0.id, side: $0.side, line: $0.line, end: $0.end, text: $0.text, sent: $0.sent, status: $0.status)) }
		}
		body["changes"] = raw
		body["comments"] = model.remarks.map(entry)
		also(&body)
		let plan = model.plan
		let body = self.body
		writing += 1
		writer.async {
			var failed = "the plan is not json"
			if let data = try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) {
				do {
					try data.write(to: URL(fileURLWithPath: plan), options: .atomic)
					failed = ""
				} catch {
					failed = error.localizedDescription
				}
			}
			let written = self.stamp(plan)
			DispatchQueue.main.async {
				self.writing -= 1
				if !failed.isEmpty {
					self.model.status = "the plan was not saved: " + failed
				} else if self.model.plan == plan {
					self.stamped = written
				}
			}
		}
	}

	func stash() {
		if model.dirty.contains(model.file), pad.path == model.file {
			drafts[model.file] = pad.string
		}
	}

	func fill(_ hunks: [Hunk], _ paths: [String], _ sections: [Sheet.Section], _ view: String) {
		sheet.hunks = hunks
		sheet.paths = paths
		sheet.sections = sections
		sheet.view = view
		sheet.digits = String(hunks.reduce(0) { max($0, $1.rows.last?["a"] as? Int ?? 0, $1.rows.last?["b"] as? Int ?? 0) }).count
		sheet.opened = []
		sheet.pairs = [:]
		sheet.cuts = [:]
		sheet.dents = [:]
		sheet.inked.removeAllObjects()
		sheet.current = -1
		sheet.shift = 0
		sheet.others = []
		sheet.notes = [:]
		sheet.chosen = nil
		sheet.fog = false
	}

	func lay(_ left: String, _ right: String, _ path: String, _ view: String) {
		loading += 1
		let mine = loading
		let name = (path as NSString).lastPathComponent
		spread = ""
		let step = Step(id: 0, title: name, why: "", path: path, proposed: right, base: left, status: "pending", notes: [])
		DispatchQueue.global(qos: .userInitiated).async {
			let found = self.trim(self.split([step]), path)
			DispatchQueue.main.async {
				guard mine == self.loading else { return }
				self.cuts = found
				self.fill(found, [path], [Sheet.Section(title: name, detail: self.model.short(path), added: found.reduce(0) { $0 + $1.added }, removed: found.reduce(0) { $0 + $1.removed }, ids: Array(found.indices))], view)
				self.sheet.fog = self.fogged
				self.fogged = false
				self.sheet.focus(0)
				self.model.sheeted = true
				self.model.region = found.isEmpty ? "no differences" : "region 1 of \(found.count)"
			}
		}
	}

	func sign(_ hunk: Hunk) -> String {
		hunk.rows.filter { $0["t"] as? String != " " }.map { ($0["t"] as? String ?? "") + ($0["s"] as? String ?? "") }.joined(separator: "\n")
	}

	func trim(_ found: [Hunk], _ path: String) -> [Hunk] {
		found.filter { !kept.contains(path + sign($0)) }.enumerated().map { n, old in
			var hunk = Hunk(id: n, change: old.change, part: n + 1, side: old.side, line: old.line, end: old.end, rows: old.rows)
			hunk.added = old.added
			hunk.removed = old.removed
			hunk.pairs = old.pairs
			return hunk
		}
	}

	func contrast() {
		guard model.diff || model.sides, model.tracked || !model.proposal.isEmpty, let original, pad.path == model.file else {
			if model.step < 0, model.comparing.isEmpty {
				model.sheeted = false
			}
			model.twinned = false
			pad.changes = []
			pad.tint()
			pad.gutter?.needsDisplay = true
			return
		}
		let path = model.file
		let dir = cache + "/diff"
		let name = (path as NSString).lastPathComponent
		try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
		try? original.write(toFile: dir + "/base." + name, atomically: true, encoding: .utf8)
		var right = path
		if model.dirty.contains(path) || !model.proposal.isEmpty {
			right = dir + "/now." + name
			try? pad.string.write(toFile: right, atomically: true, encoding: .utf8)
		}
		model.sheeted = false
		model.twinned = model.sides
		if model.sides, mirrored != path {
			twin.load(dir + "/base." + name, original)
			twin.ext = pad.ext
			twin.wrap(false)
			twin.tint()
			mirrored = path
		}
		marking += 1
		let mine = marking
		let step = Step(id: 0, title: name, why: "", path: path, proposed: right, base: dir + "/base." + name, status: "pending", notes: [])
		DispatchQueue.global(qos: .userInitiated).async {
			let found = self.trim(self.split([step]), path)
			DispatchQueue.main.async {
				guard mine == self.marking, self.pad.path == path else { return }
				self.cuts = found
				self.pad.changes = found.map { hunk in
					let plus = hunk.rows.filter { $0["t"] as? String == "+" }.compactMap { $0["b"] as? Int }
					if let first = plus.first, let last = plus.last {
						return (first, last, hunk.id, false)
					}
					let at = hunk.rows.firstIndex { $0["t"] as? String == "-" } ?? 0
					let after = hunk.rows[at...].first { $0["t"] as? String == " " }?["b"] as? Int ?? self.pad.starts.count
					return (after, after, hunk.id, true)
				}
				self.pad.tint()
				self.pad.gutter?.needsDisplay = true
				self.twin.changes = found.compactMap { hunk in
					let minus = hunk.rows.filter { $0["t"] as? String == "-" }.compactMap { $0["a"] as? Int }
					return minus.first.map { ($0, minus.last ?? $0, hunk.id, false) }
				}
				self.twin.tint()
				self.twin.gutter?.needsDisplay = true
				self.model.region = found.isEmpty ? "no differences" : "\(found.count) " + (found.count == 1 ? "change" : "changes")
			}
		}
	}

	func resolve(_ id: Int, _ revert: Bool) {
		guard id >= 0, id < cuts.count, pad.path == model.file else { return }
		let hunk = cuts[id]
		guard revert else {
			kept.insert(model.file + sign(hunk))
			contrast()
			return
		}
		let plus = hunk.rows.filter { $0["t"] as? String == "+" }.compactMap { $0["b"] as? Int }
		let old = hunk.rows.filter { $0["t"] as? String == "-" }.compactMap { $0["s"] as? String }
		let size = (pad.string as NSString).length
		if let first = plus.first, let last = plus.last {
			let from = pad.span(first)
			let to = pad.span(last)
			var range = NSRange(location: from.location, length: to.location + to.length - from.location)
			if old.isEmpty {
				range.length = min(size - range.location, range.length + 1)
			}
			pad.put(range, old.joined(separator: "\n"))
		} else {
			let at = hunk.rows.firstIndex { $0["t"] as? String == "-" } ?? 0
			if let after = hunk.rows[at...].first(where: { $0["t"] as? String == " " })?["b"] as? Int {
				pad.put(NSRange(location: pad.span(after).location, length: 0), old.joined(separator: "\n") + "\n")
			} else {
				pad.put(NSRange(location: size, length: 0), (pad.string.hasSuffix("\n") || size == 0 ? "" : "\n") + old.joined(separator: "\n") + "\n")
			}
		}
		model.dirty.insert(model.file)
		win.isDocumentEdited = true
		contrast()
	}

	func pretty() {
		let path = model.file
		let text = pad.string
		DispatchQueue.global(qos: .userInitiated).async {
			let task = Process()
			let feed = Pipe()
			let out = Pipe()
			task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
			task.arguments = ["prettier", "--stdin-filepath", path]
			task.environment = tools()
			task.standardInput = feed
			task.standardOutput = out
			task.standardError = FileHandle.nullDevice
			var made = ""
			if (try? task.run()) != nil {
				DispatchQueue.global().async {
					feed.fileHandleForWriting.write(Data(text.utf8))
					feed.fileHandleForWriting.closeFile()
				}
				made = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
				task.waitUntilExit()
				if task.terminationStatus != 0 {
					made = ""
				}
			}
			DispatchQueue.main.async {
				guard !made.isEmpty, made != text, self.pad.string == text, self.pad.path == path else {
					self.model.status = "nothing to format"
					return
				}
				self.pad.put(NSRange(location: 0, length: (text as NSString).length), made, NSRange(location: 0, length: 0))
				self.model.status = "formatted"
			}
		}
	}

	func kind(_ path: String) -> String {
		let name = (path as NSString).lastPathComponent.lowercased()
		let last = name.contains(".") ? (name as NSString).pathExtension : name
		return "zoom.code." + (last.filter { $0.isLetter || $0.isNumber || "_+-".contains($0) }.isEmpty ? "plain" : last.filter { $0.isLetter || $0.isNumber || "_+-".contains($0) })
	}

	func scale(_ scale: Double) {
		model.pulse.zoom = scale
		guard abs(sheet.scale - scale) > 0.001 else { return }
		sheet.scale = scale
		sheet.measure()
		sheet.arrange()
		pad.size(scale)
		twin.size(scale)
	}

	func keep(_ key: String, _ value: Double) {
		let path = NSHomeDirectory() + "/.slycbar/settings.json"
		var stored = FileManager.default.contents(atPath: path).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
		stored[key] = NSDecimalNumber(string: String(format: "%.2f", min(3, max(0.5, value))))
		try? FileManager.default.createDirectory(atPath: NSHomeDirectory() + "/.slycbar", withIntermediateDirectories: true)
		try? JSONSerialization.data(withJSONObject: stored, options: [.prettyPrinted, .sortedKeys]).write(to: URL(fileURLWithPath: path), options: .atomic)
	}

	func count() {
		let text = pad.string
		let whole = text as NSString
		guard whole.length < 2000000 else {
			tally = []
			return
		}
		let all = NSRange(location: 0, length: whole.length)
		func n(_ pattern: String) -> Int {
			(try? NSRegularExpression(pattern: pattern, options: [.anchorsMatchLines]))?.numberOfMatches(in: text, range: all) ?? 0
		}
		var out: [String] = []
		func add(_ count: Int, _ label: String) {
			if count > 0 {
				out.append("\(count) " + label)
			}
		}
		let words = n("\\S+")
		out.append("\(words) words")
		let ext = pad.ext
		if ["md", "markdown", "mdx", "txt", "text"].contains(ext) {
			add(n("^#{1,6}\\s"), "headings")
			add(n("\\]\\("), "links")
			add(n("^```") / 2, "code blocks")
			out.append("\(max(1, Int((Double(words) / 220).rounded(.up)))) min read")
		} else if ["json", "jsonl", "jsonc"].contains(ext) {
			add(n("\"(?:[^\"\\\\]|\\\\.)*\"\\s*:"), "keys")
			add(n("\\["), "arrays")
		} else if ["css", "scss", "less"].contains(ext) {
			add(n("\\{"), "rules")
			add(n("--[\\w-]+\\s*:"), "variables")
			add(n("@media"), "media queries")
		} else if ["html", "htm", "vue", "svelte", "xml", "svg"].contains(ext) {
			add(n("<[a-zA-Z][^>]*>"), "tags")
			add(n("(?i)<script\\b"), "scripts")
			add(n("(?i)<style\\b"), "styles")
		} else if ["yaml", "yml", "toml", "ini", "env", "conf", "cfg", "properties"].contains(ext) {
			add(n("^\\s*[\\w.\"'-]+\\s*[:=]"), "keys")
			add(n("^\\s*\\[[^\\]]+\\]"), "sections")
		} else {
			add(n("\\b(function|func|fn|def|sub|proc)\\b|=>"), "functions")
			add(n("\\b(const|let|var|val|local|my)\\s+[\\w$]+"), "variables")
			add(n("\\b(class|struct|interface|enum|trait|protocol)\\s+\\w+"), "types")
			add(n("^\\s*(import|from|use|require|#include|source|package)\\b"), "imports")
		}
		add(n("\\b(TODO|FIXME|XXX|HACK)\\b"), "todos")
		tally = out
	}

	func compare(_ left: String, _ right: String) {
		stash()
		model.step = -1
		model.hunk = -1
		model.comparing = model.short(left) + " ↔ " + model.short(right)
		model.region = ""
		displayed = false
		model.file = right
		model.media = ""
		model.tracked = false
		model.diff = false
		model.sides = true
		win.title = (left as NSString).lastPathComponent + " ↔ " + (right as NSString).lastPathComponent
		lay(left, right, right, "sides")
		fogged = true
	}

	func leave() {
		model.sheeted = false
		let path = model.file
		let pairing = model.step >= 0 || !model.comparing.isEmpty
		if model.comparing.isEmpty {
			model.plan = ""
			model.heading = ""
			model.steps = []
			model.remarks = []
			model.phase = ""
			model.round = 1
			model.folder = ""
			model.pulse.draft = ""
			model.hunks = []
			body = [:]
		}
		model.step = -1
		model.hunk = -1
		model.comparing = ""
		model.region = ""
		guard pairing else { return }
		model.sides = false
		if FileManager.default.fileExists(atPath: path) {
			show(path, record: false)
		} else {
			model.file = ""
			model.tracked = false
			stage("", "", "", "")
		}
	}

	func trace(_ path: String) {
		let agents = model.agents
		let home = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? NSHomeDirectory() + "/.claude"
		let draft = drafts[path]
		DispatchQueue.global(qos: .utility).async {
			let text = draft ?? self.decode(path)
			let fm = FileManager.default
			let clock = ISO8601DateFormatter()
			clock.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
			let shown = DateFormatter()
			shown.dateFormat = "d MMM HH:mm"
			let count = text.components(separatedBy: "\n").count
			var found: [[String: Any]] = []
			for agent in agents where !agent.sid.isEmpty {
				for project in (try? fm.contentsOfDirectory(atPath: home + "/projects")) ?? [] {
					guard let handle = FileHandle(forReadingAtPath: home + "/projects/" + project + "/" + agent.sid + ".jsonl") else { continue }
					let size = handle.seekToEndOfFile()
					handle.seek(toFileOffset: size > 2000000 ? size - 2000000 : 0)
					let body = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
					handle.closeFile()
					for line in body.split(separator: "\n") where line.contains(path) && line.contains("\"tool_use\"") {
						guard let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
						let when = (entry["timestamp"] as? String).flatMap { clock.date(from: $0) }.map { shown.string(from: $0) } ?? ""
						for block in (entry["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? [] {
							guard block["type"] as? String == "tool_use", let input = block["input"] as? [String: Any], input["file_path"] as? String == path, let tool = block["name"] as? String else { continue }
							if tool == "Read" {
								let from = max(1, input["offset"] as? Int ?? 1)
								found.append(["from": from, "to": min(count, from + (input["limit"] as? Int ?? 2000) - 1), "act": "read", "who": agent.name, "when": when])
							} else if tool == "Write" {
								found.append(["from": 1, "to": count, "act": "wrote", "who": agent.name, "when": when])
							} else if tool == "Edit", let new = input["new_string"] as? String, !new.isEmpty, let hit = text.range(of: new) {
								let from = text[..<hit.lowerBound].components(separatedBy: "\n").count
								found.append(["from": from, "to": from + new.components(separatedBy: "\n").count - 1, "act": "edited", "who": agent.name, "when": when])
							}
						}
					}
					break
				}
			}
			DispatchQueue.main.async {
				guard self.model.file == path else { return }
				self.pad.traced = Array(found.suffix(400))
				self.pad.gutter?.needsDisplay = true
			}
		}
	}

	func tune() {
		let path = NSHomeDirectory() + "/.slycbar/settings.json"
		let changed = stamp(path)
		guard ready, changed != tuned else { return }
		tuned = changed
		let given = FileManager.default.contents(atPath: path).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
		pad.tracing = given["traces"] as? Bool != false
		for (name, usual) in [("accept", "cmd+return"), ("reject", "opt+return"), ("ask", "ctrl+return")] {
			chords[name] = chord(given[name] as? String ?? usual) ?? chord(usual)
		}
		zooms = given.filter { $0.key.hasPrefix("zoom.") }.compactMapValues { ($0 as? NSNumber)?.doubleValue }
		pad.tints = ["read", "edited", "wrote"].enumerated().map { n, key in (given[key] as? String).flatMap { Int($0.dropFirst(), radix: 16) } ?? [0x56a8f5, 0xef8221, 0x6aab73][n] }
		pad.gutter?.needsDisplay = true
		model.hidden = Set(["agents", "meters", "stats", "warp"].filter { given[$0] as? Bool == false })
		if let hex = given["accent"] as? String, hex.count == 7, let rgb = Int(hex.dropFirst(), radix: 16) {
			Ink.accent = Color(red: Double(rgb >> 16 & 255) / 255, green: Double(rgb >> 8 & 255) / 255, blue: Double(rgb & 255) / 255)
		} else {
			Ink.accent = Color(red: 0.706, green: 0.388, blue: 0.184)
		}
		let kept = UserDefaults.standard
		if kept.double(forKey: "width") == 0, let wide = (given["width"] as? NSNumber)?.doubleValue {
			model.width = min(900, max(140, wide))
		}
		if kept.double(forKey: "scale") == 0, let scale = (given["scale"] as? NSNumber)?.doubleValue {
			model.scale = min(2, max(0.7, scale))
		}
		if kept.double(forKey: "zoom") == 0, let zoom = (given["zoom"] as? NSNumber)?.doubleValue {
			model.zoomed = min(3, max(0.5, zoom))
			scale(zooms[kind(model.file)] ?? model.zoomed * 0.8)
		}
		model.objectWillChange.send()
	}

	func decode(_ path: String) -> String {
		guard let data = FileManager.default.contents(atPath: path) else { return "" }
		return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
	}

	func propose() {
		guard let proposal = proposals.first else { return }
		let name = (proposal.path as NSString).lastPathComponent
		model.proposal = name
		stash()
		before = model.file
		held = model.dirty.contains(proposal.path)
		displayed = true
		loading += 1
		original = FileManager.default.fileExists(atPath: proposal.path) ? decode(proposal.path) : ""
		model.file = proposal.path
		model.media = ""
		model.preview = false
		model.tracked = false
		model.diff = true
		model.sides = false
		model.sheeted = false
		win.title = name
		pad.load(proposal.path, proposal.contents)
		count()
		contrast()
	}

	func restore(_ path: String, _ expected: String?, _ left: Int) {
		model.sheeted = false
		model.diff = false
		model.proposal = ""
		model.sides = false
		if !held {
			model.dirty.remove(path)
			drafts[path] = nil
		}
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
			guard self.model.proposal.isEmpty else { return }
			if !self.proposals.isEmpty {
				self.propose()
				return
			}
			if let expected, left > 0, self.decode(path) != expected {
				self.restore(path, expected, left - 1)
				return
			}
			let target = FileManager.default.fileExists(atPath: path) ? path : self.before
			if FileManager.default.fileExists(atPath: target) {
				self.show(target, record: false)
			} else {
				self.model.file = ""
				self.model.tracked = false
				self.stage("", "", "", "")
			}
		}
	}

	func decide(_ accepted: Bool) {
		guard !model.proposal.isEmpty, !proposals.isEmpty else { return }
		let proposal = proposals.removeFirst()
		guard accepted else {
			proposal.answer([["type": "text", "text": "DIFF_REJECTED"]])
			restore(proposal.path, nil, 0)
			return
		}
		let saved = displayed && pad.path == proposal.path ? pad.string : proposal.contents
		proposal.answer([["type": "text", "text": "FILE_SAVED"], ["type": "text", "text": saved]])
		restore(proposal.path, saved, 8)
	}

	func withdraw(_ match: (Proposal) -> Bool) {
		guard let first = proposals.first else { return }
		let shown = !model.proposal.isEmpty && match(first)
		proposals.removeAll(where: match)
		if shown {
			restore(first.path, nil, 0)
		}
	}

	func report(_ path: String, _ uri: String) -> [String: Any] {
		["uri": uri, "diagnostics": (diagnostics[path] ?? []).map { d -> [String: Any] in
			["message": d["message"] as? String ?? "", "severity": ["Error", "Warning", "Info", "Hint"][min(3, max(0, (d["severity"] as? Int ?? 1) - 1))],
				"range": d["range"] ?? [:] as [String: Any], "source": d["source"] ?? NSNull(), "code": d["code"] ?? NSNull()]
		}]
	}

	func tool(_ name: String, _ args: [String: Any], _ client: ObjectIdentifier, _ answer: @escaping ([[String: Any]]?) -> Void) {
		func text(_ value: String) -> [[String: Any]] { [["type": "text", "text": value]] }
		switch name {
		case "openDiff":
			guard let path = args["new_file_path"] as? String ?? args["old_file_path"] as? String, let contents = args["new_file_contents"] as? String else {
				answer(text("DIFF_REJECTED"))
				return
			}
			proposals.append(Proposal(tab: args["tab_name"] as? String ?? path, path: path, contents: contents, client: client, answer: answer))
			if model.proposal.isEmpty, proposals.count == 1 {
				propose()
			}
		case "close_tab":
			let tab = args["tab_name"] as? String ?? ""
			withdraw { $0.tab == tab && $0.client == client }
			answer(text("TAB_CLOSED"))
		case "closeAllDiffTabs":
			let count = proposals.filter { $0.client == client }.count
			withdraw { $0.client == client }
			answer(text("CLOSED_\(count)_DIFF_TABS"))
		case "getDiagnostics":
			var list: [[String: Any]] = []
			if let uri = args["uri"] as? String {
				let raw = uri.hasPrefix("file://") ? String(uri.dropFirst(7)) : uri
				let path = FileManager.default.fileExists(atPath: raw) ? raw : raw.removingPercentEncoding ?? raw
				if diagnostics[path] != nil {
					list = [report(path, uri)]
				}
			} else {
				list = diagnostics.keys.sorted().filter { !(diagnostics[$0] ?? []).isEmpty }.map { report($0, "file://" + $0) }
			}
			let data = (try? JSONSerialization.data(withJSONObject: list)) ?? Data("[]".utf8)
			answer(text(String(decoding: data, as: UTF8.self)))
		default:
			answer(nil)
		}
	}

	func select(_ path: String, _ cursor: String) {
		guard !ide.clients.isEmpty, model.proposal.isEmpty, !path.isEmpty, path + cursor != spotted else { return }
		spotted = path + cursor
		let fileUrl = URL(fileURLWithPath: path).absoluteString
		guard cursor.contains(" selected") else {
			let at = cursor.firstMatch(of: #/Ln (\d+), Col (\d+)/#)
			let position: [String: Any] = ["line": (at.flatMap { Int($0.1) } ?? 1) - 1, "character": (at.flatMap { Int($0.2) } ?? 1) - 1]
			ide.notify("selection_changed", ["selection": ["start": position, "end": position, "isEmpty": true] as [String: Any], "text": "", "filePath": path, "fileUrl": fileUrl])
			return
		}
		do {
			let spot = self.pad.spot()
			let from = spot.line
			let to = spot.end
			let text = spot.text
			let last = text.components(separatedBy: "\n").last?.utf16.count ?? 0
			self.ide.notify("selection_changed", ["selection": ["start": ["line": from - 1, "character": 0], "end": ["line": to - 1, "character": last], "isEmpty": false] as [String: Any], "text": text, "filePath": path, "fileUrl": fileUrl])
		}
	}

	@objc func mention(_ sender: Any?) {
		let path = model.file
		guard !path.isEmpty else { return }
		guard !ide.clients.isEmpty else {
			model.status = "Claude Code is not connected, run /ide in a session"
			return
		}
		do {
			let spot = self.pad.spot()
			let from = spot.line
			let to = spot.end
			self.ide.notify("at_mentioned", ["filePath": path, "lineStart": from - 1, "lineEnd": to - 1])
			self.model.status = "mentioned to Claude Code"
		}
	}

	func applicationWillTerminate(_ notification: Notification) {
		ide.stop()
	}

	func refresh() {
		let root = model.root
		guard !root.isEmpty else { return }
		DispatchQueue.global().async {
			let found = git(root, ["rev-parse", "--show-toplevel"])
			let top = found.code == 0 ? String(decoding: found.out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : ""
			var ignored: [String] = []
			var marks: [String: String] = [:]
			var counts: [String: (Int, Int)] = [:]
			if !top.isEmpty {
				let parts = String(decoding: git(top, ["status", "--porcelain=v1", "-z", "--ignored"]).out, as: UTF8.self).split(separator: "\0").map(String.init)
				var skip = false
				for part in parts {
					if skip {
						skip = false
						continue
					}
					guard part.count > 3 else { continue }
					let code = String(part.prefix(2))
					var path = top + "/" + part.dropFirst(3)
					if path.hasSuffix("/") {
						path.removeLast()
					}
					if code == "!!" {
						ignored.append(path)
					} else {
						marks[path] = code == "??" ? "?" : code.trimmingCharacters(in: .whitespaces).prefix(1).description
					}
					skip = code.hasPrefix("R") || code.hasPrefix("C")
				}
			}
			if !top.isEmpty {
				for line in String(decoding: git(top, ["diff", "--numstat", "HEAD"]).out, as: UTF8.self).split(separator: "\n") {
					let parts = line.split(separator: "\t", maxSplits: 2)
					if parts.count == 3, let added = Int(parts[0]), let removed = Int(parts[1]) {
						counts[top + "/" + parts[2]] = (added, removed)
					}
				}
			}
			DispatchQueue.main.async {
				self.top = top
				self.model.top = top
				self.model.ignored = ignored
				self.model.marks = marks
				self.model.counts = counts
				self.model.kids = [:]
			}
		}
	}

	func base(_ path: String, _ ref: String) -> String? {
		let dir = (path as NSString).deletingLastPathComponent
		let shown = git(dir, ["show", ref + ":./" + (path as NSString).lastPathComponent])
		return shown.code == 0 ? String(data: shown.out, encoding: .utf8) : nil
	}

	func root(for path: String) -> String {
		top.isEmpty || !path.hasPrefix(top + "/") ? (path as NSString).deletingLastPathComponent : top
	}

	func settle(_ path: String, _ text: String) {
		servers.with(path, root(for: path)) { server, language in
			server?.when { server?.sync(path, language, text) }
		}
	}

	func show(_ path: String, record: Bool = true) {
		var isDir: ObjCBool = false
		guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else { return }
		if isDir.boolValue {
			model.adopt(path)
			refresh()
			return
		}
		let was = here(model.root)
		let moved = model.file != path || model.step >= 0 || !model.comparing.isEmpty
		if model.step >= 0 || !model.comparing.isEmpty {
			model.step = -1
			model.hunk = -1
			model.comparing = ""
			model.region = ""
			model.sides = false
		}
		displayed = false
		if record, moved {
			self.record(was)
		}
		model.recent.removeAll { $0 == path }
		model.recent.insert(path, at: 0)
		model.recent = Array(model.recent.prefix(30))
		anchor(path)
		let load = {
			let ext = (path as NSString).pathExtension.lowercased()
			let media = ["mp4", "mov", "m4v", "webm"].contains(ext) ? "video" : ["mp3", "m4a", "wav", "aac", "flac", "ogg", "aiff"].contains(ext) ? "audio" : ["png", "jpg", "jpeg", "gif", "webp", "heic", "bmp", "tiff", "ico", "icns"].contains(ext) ? "image" : ext == "pdf" ? "pdf" : ""
			let draft = self.drafts[path]
			let ref = self.model.base
			self.loading += 1
			let mine = self.loading
			DispatchQueue.global(qos: .userInitiated).async {
				let text = media.isEmpty ? draft ?? self.decode(path) : ""
				let original = media.isEmpty ? self.base(path, ref) : nil
				DispatchQueue.main.async {
					guard mine == self.loading else { return }
					self.model.status = ""
					self.original = original
					self.mirrored = ""
					self.model.file = path
					self.model.media = media
					self.model.tracked = original != nil
					self.model.sheeted = false
					self.win.title = (path as NSString).lastPathComponent
					self.win.representedURL = URL(fileURLWithPath: path)
					let kind = !media.isEmpty ? "" : ["md", "markdown", "mdx"].contains(ext) ? "markdown" : ["html", "htm"].contains(ext) ? "html" : ext == "svg" ? "svg" : ""
					self.model.preview = !kind.isEmpty
					if media.isEmpty {
						self.pad.load(path, text)
						self.scale(self.zooms[self.kind(path)] ?? (self.model.zoomed * 0.8))
						self.count()
						if Sheet.lingo[self.pad.ext] == nil, !Sheet.keyed.contains(self.pad.ext), !Sheet.hashed.contains(self.pad.ext), !["md", "markdown", "mdx", "txt", "log", "html", "htm", "css", "scss", "less", "xml", "svg", "plist", "csv", "tsv"].contains(self.pad.ext) {
							note("unknown.log", self.pad.ext + " generic " + path)
						}
						self.win.isDocumentEdited = self.model.dirty.contains(path)
						self.settle(path, text)
						self.trace(path)
						self.contrast()
						if let line = self.pending {
							self.pad.show(line, self.pendingEnd ?? 0)
							self.pending = nil
							self.pendingEnd = nil
						} else {
							self.win.makeFirstResponder(self.pad)
						}
					}
					self.stage(path, kind.isEmpty ? "" : text, kind, media)
					self.refresh()
				}
			}
		}
		stash()
		load()
	}

	@objc func save(_ sender: Any?) {
		let path = model.file
		guard !path.isEmpty, pad.path == path else { return }
		guard model.step < 0, model.comparing.isEmpty, model.proposal.isEmpty else {
			model.status = "a review or comparison is read only"
			return
		}
		do {
			try pad.string.write(toFile: path, atomically: true, encoding: .utf8)
		} catch {
			model.status = "not saved: " + error.localizedDescription
			return
		}
		model.dirty.remove(path)
		drafts[path] = nil
		win.isDocumentEdited = false
		servers.with(path, root(for: path)) { server, _ in
			server?.when { server?.notify("textDocument/didSave", ["textDocument": ["uri": URL(fileURLWithPath: path).absoluteString]]) }
		}
		refresh()
		contrast()
	}

	@objc func pick(_ sender: Any?) {
		let panel = NSOpenPanel()
		panel.canChooseDirectories = true
		panel.canChooseFiles = true
		panel.showsHiddenFiles = true
		if panel.runModal() == .OK, let url = panel.url {
			show(url.path)
		}
	}

	func zoom(_ side: Bool, _ step: Double) {
		if side {
			model.scale = step == 0 ? 1.1 : min(2, max(0.7, model.scale + step * 1.1))
			UserDefaults.standard.set(model.scale, forKey: "scale")
		} else if model.sheeted || (model.media.isEmpty && !model.file.isEmpty && !(model.preview && model.mode == "preview")) {
			let next = step == 0 ? model.zoomed * 0.8 : min(3, max(0.5, sheet.scale + step))
			zooms[kind(model.file)] = next
			keep(kind(model.file), next)
			scale(next)
		} else {
			let key = "zoom.preview." + (model.sight.kind.isEmpty ? model.sight.media : model.sight.kind)
			let next = step == 0 ? 1 : min(3, max(0.5, model.sight.zoom + step))
			zooms[key] = next
			keep(key, next)
			model.sight.zoom = next
			if model.sight.kind == "html" {
				web.pageZoom = next
			}
		}
	}

	@objc func zoomIn(_ sender: Any?) { zoom(model.over, 0.1) }
	@objc func zoomOut(_ sender: Any?) { zoom(model.over, -0.1) }
	@objc func zoomReset(_ sender: Any?) { zoom(model.over, 0) }

	@objc func side(_ sender: Any?) { withAnimation(.easeOut(duration: 0.2)) { model.side.toggle() } }

	@objc func tuning(_ sender: Any?) {
		model.setOpen.toggle()
		if model.setOpen {
			store("", "")
		}
	}

	func store(_ key: String, _ value: String) {
		let script = Bundle.main.object(forInfoDictionaryKey: "SlycbarCli") as? String ?? ""
		DispatchQueue.global().async {
			let out = call(script, key.isEmpty ? ["settings"] : ["settings", key, value]).out
			let found = (try? JSONSerialization.jsonObject(with: out)) as? [String: Any]
			DispatchQueue.main.async {
				guard let found else {
					self.model.status = key.isEmpty ? "slybar settings did not answer" : key + " was not stored, slybar settings refused " + value
					return
				}
				self.model.set = found
				let number = (found[key] as? NSNumber)?.doubleValue ?? 0
				if key == "width" {
					self.model.width = number
					UserDefaults.standard.set(number, forKey: "width")
				} else if key == "scale" {
					self.model.scale = number
					UserDefaults.standard.set(number, forKey: "scale")
				} else if key == "zoom" {
					self.model.zoomed = number
					self.scale(self.zooms[self.kind(self.model.file)] ?? number * 0.8)
					UserDefaults.standard.set(number, forKey: "zoom")
				}
				self.tune()
			}
		}
	}
	@objc func gitPanel(_ sender: Any?) {
		model.gitOpen.toggle()
		if model.gitOpen {
			reloadGit()
		}
	}

	func gitText(_ args: [String]) -> (code: Int32, text: String) {
		let task = Process()
		let pipe = Pipe()
		task.executableURL = URL(fileURLWithPath: "/usr/bin/git")
		task.arguments = ["-C", top] + args
		var env = tools()
		env["GIT_TERMINAL_PROMPT"] = "0"
		env["GIT_EDITOR"] = "true"
		task.environment = env
		task.standardOutput = pipe
		task.standardError = pipe
		do {
			try task.run()
		} catch {
			return (127, "git did not start")
		}
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		task.waitUntilExit()
		return (task.terminationStatus, String(decoding: data, as: UTF8.self))
	}

	func reloadGit() {
		guard !top.isEmpty else {
			model.branch = ""
			return
		}
		let top = self.top
		DispatchQueue.global().async {
			let status = String(decoding: git(top, ["status", "--porcelain=v1", "-b", "-z"]).out, as: UTF8.self).split(separator: "\0").map(String.init)
			var branch = ""
			var tracking = ""
			var changes: [Change] = []
			var skip = false
			for part in status {
				if skip {
					skip = false
					continue
				}
				if part.hasPrefix("## ") {
					let head = String(part.dropFirst(3))
					branch = head.components(separatedBy: "...")[0].replacingOccurrences(of: "No commits yet on ", with: "")
					if let from = head.range(of: "...") {
						tracking = String(head[from.upperBound...])
					}
					continue
				}
				guard part.count > 3 else { continue }
				let code = Array(part.prefix(2))
				changes.append(Change(path: String(part.dropFirst(3)), staged: String(code[0]), work: String(code[1])))
				skip = code[0] == "R" || code[0] == "C"
			}
			let branches = String(decoding: git(top, ["branch", "--format=%(refname:short)"]).out, as: UTF8.self).split(separator: "\n").map(String.init)
			let commits = String(decoding: git(top, ["log", "-n", "60", "--format=%h%x09%s%x09%an%x09%cr"]).out, as: UTF8.self).split(separator: "\n").compactMap { line -> Commit? in
				let parts = line.split(separator: "\t", omittingEmptySubsequences: false).map(String.init)
				return parts.count == 4 ? Commit(id: parts[0], subject: parts[1], who: parts[2], when: parts[3]) : nil
			}
			let stashes = String(decoding: git(top, ["stash", "list", "--format=%gd%x09%s"]).out, as: UTF8.self).split(separator: "\n").map(String.init)
			let dir = String(decoding: git(top, ["rev-parse", "--absolute-git-dir"]).out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
			let fm = FileManager.default
			let state = fm.fileExists(atPath: dir + "/MERGE_HEAD") ? "merging" : fm.fileExists(atPath: dir + "/CHERRY_PICK_HEAD") ? "cherry-picking"
				: fm.fileExists(atPath: dir + "/rebase-merge") || fm.fileExists(atPath: dir + "/rebase-apply") ? "rebasing" : ""
			DispatchQueue.main.async {
				self.model.branch = branch
				self.model.tracking = tracking
				self.model.changes = changes
				self.model.branches = branches
				self.model.commits = commits
				self.model.stashes = stashes
				self.model.state = state
			}
		}
	}

	func gitRun(_ args: [String]) {
		guard !top.isEmpty else { return }
		model.said = "git " + args.prefix(3).joined(separator: " ") + "…"
		model.failed = false
		DispatchQueue.global().async {
			let result = self.gitText(args)
			DispatchQueue.main.async {
				let lines = result.text.split(separator: "\n").map(String.init)
				self.model.failed = result.code != 0
				self.model.said = (result.code != 0 ? lines.last { $0.contains("error") || $0.contains("fatal") || $0.contains("CONFLICT") } ?? lines.last : lines.last) ?? "done"
				if result.code == 0, args.first == "commit" {
					self.model.message = ""
				}
				self.refresh()
				self.reloadGit()
				if !self.model.file.isEmpty, !self.model.dirty.contains(self.model.file) {
					self.show(self.model.file, record: false)
				}
			}
		}
	}


	@objc func back(_ sender: Any?) {
		guard let place = past.popLast() else {
			model.status = "nothing earlier"
			return
		}
		ahead.append(here(model.root))
		go(place)
	}

	@objc func forward(_ sender: Any?) {
		guard let place = ahead.popLast() else {
			model.status = "nothing later"
			return
		}
		past.append(here(model.root))
		go(place)
	}

	@objc func declaration(_ sender: Any?) {
		pad.declare()
	}

	@objc func find(_ sender: Any?) {
		let item = NSMenuItem()
		item.tag = NSTextFinder.Action.showFindInterface.rawValue
		pad.performTextFinderAction(item)
	}

	@objc func format(_ sender: Any?) {
		pad.tidy { done in
			if done {
				self.model.status = "formatted by the language server"
			} else {
				self.pretty()
			}
		}
	}

	@objc func cutText(_ sender: Any?) { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
	@objc func copyText(_ sender: Any?) { NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil) }
	@objc func pasteText(_ sender: Any?) { NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil) }
	@objc func copyPath(_ sender: Any?) { slyed.copy(model.file) }
	@objc func copyRelative(_ sender: Any?) { slyed.copy(model.relative(model.file)) }
	@objc func reveal(_ sender: Any?) { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: model.file)]) }

	@objc func copySpot(_ sender: Any?) {
		let path = model.file
		do {
			let spot = self.pad.spot()
			let from = spot.line
			let to = spot.end
			slyed.copy(path + ":\(from)" + (to > from ? "-\(to)" : ""))
			self.model.status = "path and line copied"
		}
	}

	@objc func findServer(_ sender: Any?) {
		let path = model.file
		let script = (Bundle.main.object(forInfoDictionaryKey: "SlycbarCli") as? String) ?? ""
		model.status = "looking for a language server…"
		DispatchQueue.global().async {
			let out = call(script, ["server", path, "install"]).out
			let reply = (try? JSONSerialization.jsonObject(with: out)) as? [String: Any] ?? [:]
			DispatchQueue.main.async {
				if let name = reply["server"] as? String {
					self.servers.failed = []
					self.model.status = reply["installed"] as? Bool == true ? name + " is installed" : name + " did not install"
					self.show(path, record: false)
				} else {
					let found = reply["brew"] as? [String] ?? []
					self.model.status = found.isEmpty ? "brew has no language server for this file type" : "brew has " + found.joined(separator: ", ")
				}
			}
		}
	}

	func menu(_ menu: NSMenu) {
		menu.removeAllItems()
		func add(_ title: String, _ action: Selector, _ on: Bool = false) {
			let item = menu.addItem(withTitle: title, action: action, keyEquivalent: "")
			item.target = self
			item.state = on ? .on : .off
		}
		add("Cut", #selector(cutText(_:)))
		add("Copy", #selector(copyText(_:)))
		add("Paste", #selector(pasteText(_:)))
		guard !model.file.isEmpty else { return }
		menu.addItem(.separator())
		add("Go to Declaration", #selector(declaration(_:)))
		add("Go to Line…", #selector(goLine(_:)))
		add("Search Everywhere…", #selector(goSearch(_:)))
		menu.addItem(.separator())
		add("Format File", #selector(format(_:)))
		add("Send to Agent…", #selector(goComment(_:)))
		add("Mention to Claude Code", #selector(mention(_:)))
		if model.tracked {
			add("Inline Diff", #selector(flip(_:)), model.diff)
			add("Side by Side Diff", #selector(flipSides(_:)), model.sides)
		}
		menu.addItem(.separator())
		add("Copy Path", #selector(copyPath(_:)))
		add("Copy Relative Path", #selector(copyRelative(_:)))
		add("Copy Path and Line", #selector(copySpot(_:)))
		add("Reveal in Finder", #selector(reveal(_:)))
		menu.addItem(.separator())
		if let (entry, _) = servers.entry(model.file) {
			let running = servers.live.contains { $0.key.hasPrefix(entry.name + " ") && $0.value.process.isRunning }
			add(running ? "Language Server: " + entry.name + " is running" : "Install and Start " + entry.name, #selector(findServer(_:)), running)
		} else {
			add("Find a Language Server with brew", #selector(findServer(_:)))
		}
	}

	@objc func goSearch(_ sender: Any?) {
		loadPool()
		model.palette = "search"
		model.query = ""
	}

	@objc func goComment(_ sender: Any?) {
		guard !model.file.isEmpty else { return }
		if model.sheeted {
			model.pulse.focus += 1
			return
		}
		if model.media.isEmpty, model.sight.kind != "html" || model.mode != "preview" {
			model.noting = true
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.model.pulse.focus += 1 }
			return
		}
		picked = [:]
		model.palette = "comment"
		model.query = ""
	}

	func post(_ path: String, _ text: String) -> Bool {
		let fd = socket(AF_UNIX, SOCK_STREAM, 0)
		guard fd >= 0 else { return false }
		defer { close(fd) }
		var address = sockaddr_un()
		address.sun_family = sa_family_t(AF_UNIX)
		let bytes = Array(path.utf8)
		guard bytes.count < MemoryLayout.size(ofValue: address.sun_path) else { return false }
		withUnsafeMutableBytes(of: &address.sun_path) { $0.copyBytes(from: bytes) }
		let joined = withUnsafePointer(to: &address) { $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) } }
		guard joined == 0 else { return false }
		let line = Array((text.replacingOccurrences(of: "\n", with: " ⏎ ") + "\n").utf8)
		return write(fd, line, line.count) == line.count
	}

	func comment(_ text: String) {
		if model.reviewing {
			model.pulse.draft = text
			return
		}
		let path = model.file
		if picked.isEmpty, pad.path == path {
			let spot = pad.spot()
			let from = pad.span(spot.line)
			let to = pad.span(spot.end)
			pad.asked.append(NSRange(location: from.location, length: to.location + to.length - from.location))
			pad.needsDisplay = true
		}
		if !picked.isEmpty {
			let line = picked["line"] as? Int ?? 0
			let files = picked["files"] as? [String] ?? []
			var message = "Comment from Slyed on the preview of \(path)" + (line > 0 ? ":\(line)" : "") + ", on the element " + (picked["trail"] as? String ?? "") + ". " + text + "\nElement:\n" + (picked["html"] as? String ?? "")
			if !files.isEmpty {
				message += "\nFiles the preview is built from:\n" + files.joined(separator: "\n")
			}
			message += "\nChange only that element, in this file or in the files it is built from."
			picked = [:]
			hand(path, message, "preview")
			return
		}
		do {
			let spot = self.pad.spot()
			let from = spot.line
			let to = spot.end
			let dir = (path as NSString).deletingLastPathComponent
			DispatchQueue.global(qos: .userInitiated).async {
				var hunk = ""
				var keep = false
				for line in String(decoding: git(dir, ["diff", "-U0", "HEAD", "--", path]).out, as: UTF8.self).split(separator: "\n", omittingEmptySubsequences: false) {
					if line.hasPrefix("@@") {
						let plus = line.split(separator: " ").first { $0.hasPrefix("+") }?.dropFirst().split(separator: ",") ?? []
						let start = Int(plus.first ?? "") ?? 0
						let count = plus.count > 1 ? Int(plus[1]) ?? 1 : 1
						keep = start <= to && start + max(count, 1) > from
					}
					if keep {
						hunk += line + "\n"
					}
				}
				var message = "Comment from Slyed on \(path):\(from)" + (to > from ? "-\(to)" : "") + ". " + text + "\nCode at that spot:\n" + (spot.text)
				if !hunk.isEmpty {
					message += "\nUncommitted change there:\n" + hunk
				}
				message += "\nChange only this spot."
				let whole = message
				DispatchQueue.main.async { self.hand(path, whole, String(from)) }
			}
		}
	}

	func hand(_ path: String, _ message: String, _ spot: String) {
		slyed.copy(message)
		let agent = model.agents.first { $0.files.contains(path) } ?? model.agents.first { !$0.dir.isEmpty && path.hasPrefix($0.dir + "/") }
		guard let agent, !agent.socket.isEmpty else {
			model.status = "no agent on this file, comment copied"
			return
		}
		model.status = post(agent.socket, message) ? "comment sent to " + agent.name : "not sent to " + agent.name + ", comment copied"
		note("comments.log", agent.name + " " + path + ":" + spot)
	}

	@objc func goLine(_ sender: Any?) {
		model.palette = "line"
		model.query = ""
	}

	@objc func goRecent(_ sender: Any?) {
		model.palette = "recent"
		model.query = ""
	}

	@objc func goFile(_ sender: Any?) {
		model.palette = "files"
		model.query = ""
		loadPool()
	}

	func loadPool() {
		let root = model.root
		let top = self.top
		DispatchQueue.global().async {
			var pool: [String] = []
			if !top.isEmpty {
				pool = String(decoding: git(top, ["ls-files", "-co", "--exclude-standard", "-z"]).out, as: UTF8.self).split(separator: "\0").prefix(40000).map { top + "/" + $0 }
			} else if let walk = FileManager.default.enumerator(at: URL(fileURLWithPath: root), includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) {
				for case let url as URL in walk {
					if (try? url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true {
						pool.append(url.path)
					}
					if pool.count >= 40000 { break }
				}
			}
			self.index.put(top.isEmpty ? root : top, pool)
			DispatchQueue.main.async {
				self.model.search()
			}
		}
	}

	func stream() {
		guard !streaming, win == nil || win.isVisible else { return }
		streaming = true
		let agents = model.agents
		let known = streamed
		let had = carded
		let start = primaries
		let wired = worktrees
		let due = Date().timeIntervalSince(listed) > 30
		reader.async {
			let fm = FileManager.default
			func trim(_ text: String) -> String { text.trimmingCharacters(in: .whitespacesAndNewlines) }
			var tops = start
			var repos: [String] = []
			for agent in agents where !agent.dir.isEmpty {
				if tops[agent.dir] == nil {
					let common = trim(String(decoding: git(agent.dir, ["rev-parse", "--path-format=absolute", "--git-common-dir"]).out, as: UTF8.self))
					tops[agent.dir] = common.hasSuffix("/.git") ? String(common.dropLast(5)) : ""
				}
				if let top = tops[agent.dir], !top.isEmpty, !repos.contains(top) {
					repos.append(top)
				}
			}
			var worktrees = due ? [:] : wired
			for repo in due ? repos : [] {
				var path = ""
				for line in String(decoding: git(repo, ["worktree", "list", "--porcelain"]).out, as: UTF8.self).split(separator: "\n") {
					if line.hasPrefix("worktree ") {
						path = String(line.dropFirst(9))
					}
					if line.hasPrefix("branch refs/heads/"), path != repo {
						worktrees[path] = String(line.dropFirst(18))
					}
				}
			}
			var fresh: [String: (Int, Feed)] = [:]
			var feeds: [Feed] = []
			for agent in agents {
				for log in agent.logs {
					let size = ((try? fm.attributesOfItem(atPath: log)[.size]) as? NSNumber)?.intValue ?? 0
					let main = log == agent.logs.first
					var meta: [String: Any] = [:]
					if !main, let data = fm.contents(atPath: String(log.dropLast(6)) + ".meta.json") {
						meta = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
					}
					var lines: [String] = []
					var asked: [String] = []
					var trees: Set<String> = []
					var used = ""
					var read = 0
					if let hit = known[log], hit.0 <= size {
						read = hit.0
						used = hit.1.model
						lines = hit.1.lines
						asked = hit.1.questions
						trees = hit.1.trees
					}
					if size > read, let handle = FileHandle(forReadingAtPath: log) {
						let begin = read == 0 ? max(0, size - 300000) : max(read, size - 2000000)
						handle.seek(toFileOffset: UInt64(begin))
						let data = handle.readDataToEndOfFile()
						handle.closeFile()
						let cut = data.lastIndex(of: 10).map { $0 + 1 } ?? 0
						let text = String(decoding: data.prefix(cut), as: UTF8.self)
						read = begin + cut
						for (path, branch) in worktrees where text.contains(path + "/") || text.contains(path + " ") || text.contains(path + "\"") {
							trees.insert(branch)
						}
						for line in text.split(separator: "\n") where line.contains("\"type\":\"assistant\"") {
							guard let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
							if let branch = entry["gitBranch"] as? String, !branch.isEmpty {
								trees.insert(branch)
							}
							if let named = (entry["message"] as? [String: Any])?["model"] as? String, !named.hasPrefix("<") {
								used = named
							}
							for block in ((entry["message"] as? [String: Any])?["content"] as? [[String: Any]]) ?? [] {
								if block["type"] as? String == "text", let said = block["text"] as? String {
									let first = said.split(separator: "\n").map { trim(String($0)) }.first { !$0.isEmpty } ?? ""
									if !first.isEmpty {
										lines.append("› " + first.prefix(300))
									}
									asked = said.matches(of: #/(?m)^(Q\d+)[,:.]?\s*(.*)$/#).map { String($0.1) + " " + String($0.2) }
								}
								if block["type"] as? String == "tool_use", let tool = block["name"] as? String {
									let input = block["input"] as? [String: Any] ?? [:]
									let subject = ["file_path", "notebook_path", "command", "pattern", "description", "url", "query", "prompt", "skill"].lazy.compactMap { input[$0] as? String }.first ?? ""
									let shown = subject.hasPrefix("/") && !subject.contains(" ") ? (subject as NSString).lastPathComponent : subject.split(separator: "\n").first.map(String.init) ?? ""
									lines.append(tool + " " + shown.prefix(300))
								}
							}
						}
						lines = Array(lines.suffix(40))
					}
					let feed = Feed(id: log, group: agent.sid, name: main ? agent.name : meta["agentType"] as? String ?? "agent", detail: main ? agent.status : meta["description"] as? String ?? "", model: used.isEmpty ? meta["model"] as? String ?? "" : used,
						busy: main ? agent.status == "busy" : meta["finished"] as? Bool != true, lines: lines, questions: main ? agent.questions.map { $0.replacingOccurrences(of: "\t", with: " ") } : asked, trees: trees)
					fresh[log] = (read, feed)
					feeds.append(feed)
				}
			}
			var cards: [Card] = []
			var kept: [String: (Date, Card)] = [:]
			let stale = Date().addingTimeInterval(-86400)
			let stamp = ISO8601DateFormatter()
			for repo in repos {
				let dir = repo + "/.claude/tasks"
				for name in (try? fm.contentsOfDirectory(atPath: dir)) ?? [] where name.hasSuffix(".md") {
					let path = dir + "/" + name
					let changed = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
					var card: Card
					if let hit = had[path], hit.0 == changed {
						card = hit.1
					} else {
						guard let handle = FileHandle(forReadingAtPath: path) else { continue }
						let text = String(decoding: handle.readData(ofLength: 16000), as: UTF8.self)
						handle.closeFile()
						var fields: [String: String] = [:]
						var asked = 0
						var key = ""
						for (at, line) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
							if at == 0 {
								if line != "---" { break }
								continue
							}
							if line == "---" { break }
							if line.hasPrefix("- ") || line.hasPrefix("  - ") {
								if key == "questions" { asked += 1 }
								continue
							}
							guard let colon = line.firstIndex(of: ":"), !line.hasPrefix(" ") else { continue }
							key = String(line[..<colon])
							let value = trim(String(line[line.index(after: colon)...]))
							fields[key] = value.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
							if key == "questions", value.hasPrefix("["), value != "[]" {
								asked = value.split(separator: ",").count
							}
						}
						card = Card(id: path, repo: repo, number: fields["id"] ?? "", title: fields["title"] ?? name, kind: fields["type"] ?? "", status: fields["status"].flatMap { $0.isEmpty ? nil : $0 } ?? "draft",
							tree: fields["tree"] ?? "", session: fields["session"] ?? "", updated: stamp.date(from: fields["updated_at"] ?? "") ?? changed, questions: asked)
					}
					kept[path] = (changed, card)
					if card.status != "done" || card.updated > stale {
						cards.append(card)
					}
				}
			}
			cards.sort { $0.updated > $1.updated }
			DispatchQueue.main.async {
				self.streaming = false
				self.streamed = fresh
				self.carded = kept
				self.primaries = tops
				if due {
					self.worktrees = worktrees
					self.listed = Date()
				}
				if self.model.live.cards != cards {
					self.model.live.cards = cards
				}
				if self.model.live.feeds != feeds {
					self.model.live.feeds = feeds
				}
			}
		}
	}

	func watch() {
		guard win == nil || win.isVisible else { return }
		let home = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? NSHomeDirectory() + "/.claude"
		let known = parsed
		DispatchQueue.global().async {
			let fm = FileManager.default
			var agents: [Agent] = []
			var fresh: [Int: (String, Agent)] = [:]
			let pattern = try? NSRegularExpression(pattern: "\"name\":\"(Read|Edit|Write|MultiEdit|NotebookEdit)\",\"input\":\\{\"(?:file_path|notebook_path)\":\"([^\"\\\\]+)\"")
			for name in ((try? fm.contentsOfDirectory(atPath: home + "/sessions")) ?? []).sorted() where name.hasSuffix(".json") {
				guard let data = fm.contents(atPath: home + "/sessions/" + name),
					let manifest = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
					let pid = manifest["pid"] as? Int, kill(pid_t(pid), 0) == 0,
					let id = manifest["sessionId"] as? String else { continue }
				let dir = manifest["cwd"] as? String ?? ""
				var logs: [String] = []
				for project in (try? fm.contentsOfDirectory(atPath: home + "/projects")) ?? [] {
					let base = home + "/projects/" + project + "/" + id
					guard fm.fileExists(atPath: base + ".jsonl") else { continue }
					logs.append(base + ".jsonl")
					for sub in (try? fm.contentsOfDirectory(atPath: base + "/subagents")) ?? [] where sub.hasSuffix(".jsonl") {
						let path = base + "/subagents/" + sub
						let changed = (try? fm.attributesOfItem(atPath: path)[.modificationDate] as? Date) ?? .distantPast
						if Date().timeIntervalSince(changed) < 900 {
							logs.append(path)
						}
					}
					break
				}
				let stamp = logs.map { $0 + ":" + String(((try? fm.attributesOfItem(atPath: $0)[.size]) as? NSNumber)?.intValue ?? 0) }.joined(separator: "|")
				if let hit = known[pid], hit.0 == stamp {
					let old = hit.1
					let agent = Agent(id: pid, name: manifest["name"] as? String ?? (dir as NSString).lastPathComponent, dir: dir, status: manifest["status"] as? String ?? "idle", files: old.files, acts: old.acts, socket: old.socket, last: old.last, questions: old.questions, sid: id, logs: logs)
					agents.append(agent)
					fresh[pid] = (stamp, agent)
					continue
				}
				var files: [String] = []
				var acts: [String: String] = [:]
				var last = ""
				var open: [(String, String)] = []
				if let first = logs.first, let handle = FileHandle(forReadingAtPath: first) {
					let size = handle.seekToEndOfFile()
					handle.seek(toFileOffset: size > 900000 ? size - 900000 : 0)
					let lines = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self).split(separator: "\n")
					handle.closeFile()
					for line in lines where line.contains("\"type\":\"assistant\"") || line.contains("\"type\":\"user\"") {
						guard let entry = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any], let role = entry["type"] as? String else { continue }
						let message = (entry["message"] as? [String: Any])?["content"]
						let content = message as? [[String: Any]] ?? []
						if role == "user" {
							let said = (message as? String ?? content.filter { $0["type"] as? String == "text" }.compactMap { $0["text"] as? String }.joined(separator: " ")).lowercased()
							guard !said.isEmpty, !said.hasPrefix("<") else { continue }
							open.removeAll { said.firstMatch(of: try! Regex("\\b" + $0.0.lowercased() + "\\b")) != nil }
							continue
						}
						guard role == "assistant" else { continue }
						var parts: [String] = []
						for block in content {
							if let text = block["text"] as? String, block["type"] as? String == "text" {
								parts.append(text)
							}
							for question in (block["input"] as? [String: Any])?["questions"] as? [[String: Any]] ?? [] {
								let options = (question["options"] as? [[String: Any]] ?? []).compactMap { $0["label"] as? String }
								parts.append((question["question"] as? String ?? "") + (options.isEmpty ? "" : "\n- " + options.joined(separator: "\n- ")))
							}
						}
						guard !parts.isEmpty else { continue }
						let text = parts.joined(separator: "\n\n")
						last = String(text.suffix(4000))
						for found in text.matches(of: #/(?m)^(Q\d+)[,:.]?\s*(.*)$/#) {
							open.removeAll { $0.0 == String(found.1) }
							open.append((String(found.1), String(found.2)))
						}
					}
				}
				for log in logs {
					guard let handle = FileHandle(forReadingAtPath: log) else { continue }
					let size = handle.seekToEndOfFile()
					handle.seek(toFileOffset: size > 500000 ? size - 500000 : 0)
					let text = String(decoding: handle.readDataToEndOfFile(), as: UTF8.self)
					handle.closeFile()
					let found = pattern?.matches(in: text, range: NSRange(text.startIndex..., in: text)) ?? []
					for match in found.reversed() {
						guard let range = Range(match.range(at: 2), in: text), let tool = Range(match.range(at: 1), in: text) else { continue }
						let path = String(text[range])
						if !files.contains(path) && fm.fileExists(atPath: path) {
							files.append(path)
							acts[path] = text[tool] == "Read" ? "reads" : text[tool] == "Write" ? "writes" : "edits"
						}
						if files.count >= 6 { break }
					}
				}
				agents.append(Agent(id: pid, name: manifest["name"] as? String ?? (dir as NSString).lastPathComponent, dir: dir, status: manifest["status"] as? String ?? "idle", files: Array(files.prefix(6)), acts: acts, socket: manifest["messagingSocketPath"] as? String ?? "", last: last, questions: open.map { $0.0 + "\t" + $0.1 }, sid: id, logs: logs))
				if let made = agents.last {
					fresh[pid] = (stamp, made)
				}
			}
			var meters: [Meter] = []
			var account = ""
			func tone(_ pct: Double) -> Color { pct >= 90 ? Color(red: 0.788, green: 0.29, blue: 0.227) : pct >= 70 ? Color(red: 0.788, green: 0.541, blue: 0.106) : Color(red: 0.247, green: 0.604, blue: 0.353) }
			if let data = fm.contents(atPath: (cache as NSString).deletingLastPathComponent + "/tray/state.json"), let state = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
				let checks = (state["resources"] as? [String: Any])?["check"] as? [[String: Any]] ?? []
				for name in ["cpu", "mem"] {
					if let check = checks.first(where: { $0["name"] as? String == name }), let value = check["value"] as? Double {
						meters.append(Meter(id: name, value: "\(Int(value))", part: value / 100, color: tone(value * 90 / max(1, check["limit"] as? Double ?? 100))))
					}
				}
				if let active = (state["accounts"] as? [[String: Any]] ?? []).first(where: { $0["active"] as? Bool == true }) {
					account = (active["name"] as? String ?? "") + ((active["email"] as? String).map { " · " + $0 } ?? "")
					for (label, key) in [("5h", "five"), ("7d", "seven"), ("fable", "fable")] {
						if let pct = (active[key] as? [String: Any])?["pct"] as? Double {
							meters.append(Meter(id: label, value: "\(Int(pct.rounded()))", part: pct / 100, color: tone(pct)))
						}
					}
				}
			}
			DispatchQueue.main.async {
				self.model.agents = agents
				self.parsed = fresh
				if self.seeking {
					self.seeking = false
					let edited = agents.flatMap { agent in agent.files.filter { agent.acts[$0] != "reads" } }
					if let latest = edited.max(by: { self.stamp($0) < self.stamp($1) }) {
						self.show(latest)
					}
				}
				self.model.meters = meters
				func share(_ id: String) -> Double { (Double(meters.first { $0.id == id }?.value ?? "") ?? 0) / 100 }
				self.model.sight.vitals = "cpu \(Int(share("cpu") * 100))% · memory \(Int(share("mem") * 100))% · \(agents.filter { $0.status == "busy" }.count) busy agents"
				self.model.account = account
			}
		}
	}

	@objc func openReview(_ sender: Any?) { resume() }
	@objc func nextStep(_ sender: Any?) { walk(true) }
	@objc func previousStep(_ sender: Any?) { walk(false) }
	@objc func acceptStep(_ sender: Any?) { judge(model.hunk, "accepted") }
	@objc func rejectStep(_ sender: Any?) { judge(model.hunk, "rejected") }
	@objc func closeReview(_ sender: Any?) { leave() }

	@objc func flipSides(_ sender: Any?) {
		guard model.step < 0, model.comparing.isEmpty, model.proposal.isEmpty else { return }
		model.sides.toggle()
		if model.sides {
			model.diff = false
		}
		contrast()
	}

	@objc func flip(_ sender: Any?) {
		guard model.step < 0, model.comparing.isEmpty, model.proposal.isEmpty else { return }
		model.diff.toggle()
		if model.diff {
			model.sides = false
		}
		contrast()
	}

	func lsp(_ method: String, _ path: String, _ text: String, _ line: Int, _ character: Int, _ options: Any?, _ reply: @escaping (Any?) -> Void) {
		var answered = false
		let answer: (Any?) -> Void = { result in
			guard !answered else { return }
			answered = true
			reply(result is NSNull ? nil : result)
		}
		servers.with(path, root(for: path)) { server, language in
			guard let server, server.ready else {
				answer(nil)
				return
			}
			server.sync(path, language, text)
			var params: [String: Any] = ["textDocument": ["uri": URL(fileURLWithPath: path).absoluteString], "position": ["line": line, "character": character]]
			if let options {
				params = ["textDocument": params["textDocument"] as Any, "options": options]
			}
			server.request(method, params, answer)
			DispatchQueue.main.asyncAfter(deadline: .now() + 4) { answer(nil) }
		}
	}

	func read() {
		let range = pad.selectedRange()
		let row = pad.line(range.location)
		let cursor = "Ln \(row + 1), Col \(range.location - pad.starts[row] + 1)" + (range.length > 0 ? " · \(range.length) selected" : "")
		let errors = pad.flagged.values.filter { $0 }.count
		var stats = ["\(pad.starts.count) lines", "\((pad.string as NSString).length) chars"] + tally
		if errors > 0 {
			stats.append("\(errors) errors")
		}
		if pad.flagged.count > errors {
			stats.append("\(pad.flagged.count - errors) warnings")
		}
		if model.pulse.stats != stats {
			model.pulse.stats = stats
		}
		if model.pulse.cursor != cursor {
			model.pulse.cursor = cursor
		}
		if !model.sheeted {
			let spot = pad.spot()
			let mark = range.length > 0 ? (pad.path as NSString).lastPathComponent + ":\(spot.line)" + (spot.end > spot.line ? "-\(spot.end)" : "") + " · \(spot.end - spot.line + 1) " + (spot.end == spot.line ? "line" : "lines") : ""
			if model.pulse.mark != mark {
				model.pulse.mark = mark
			}
		}
		select(pad.path, cursor)
	}

	func stage(_ path: String, _ text: String, _ kind: String, _ media: String) {
		let sight = model.sight
		sight.path = path
		sight.text = text
		sight.kind = kind
		sight.media = media
		sight.zoom = zooms["zoom.preview." + (kind.isEmpty ? media : kind)] ?? 1
		reloading?.cancel()
		if kind == "html" {
			web.pageZoom = sight.zoom
			web.loadHTMLString(text, baseURL: URL(string: "slyed://file" + (((path as NSString).deletingLastPathComponent + "/").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "/")))
		} else if staged {
			web.loadHTMLString("", baseURL: nil)
		}
		staged = kind == "html"
	}

	func feed(_ text: String) {
		model.sight.text = text
		guard model.sight.kind == "html" else { return }
		reloading?.cancel()
		let path = model.sight.path
		let work = DispatchWorkItem { [unowned self] in
			guard self.model.sight.path == path else { return }
			self.web.loadHTMLString(text, baseURL: URL(string: "slyed://file" + (((path as NSString).deletingLastPathComponent + "/").addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? "/")))
		}
		reloading = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
	}

	func begin() {
		ready = true
		first.forEach { show($0) }
		first = []
		if !firstPlan.isEmpty {
			load(plan: firstPlan)
			firstPlan = ""
		}
		if let (left, right) = firstPair {
			compare(left, right)
			firstPair = nil
		}
		if model.root.isEmpty {
			model.root = model.roots.last ?? NSHomeDirectory()
			refresh()
		}
		tune()
	}

	func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
		replyHandler(nil, nil)
		guard message.frameInfo.isMainFrame, model.sight.kind == "html", !model.reviewing, let body = message.body as? [String: Any], let found = body["picked"] as? [String: Any] else { return }
		let source = pad.string
		let id = found["id"] as? String ?? ""
		let text = found["text"] as? String ?? ""
		var hit = id.isEmpty ? nil : source.range(of: "id=\"" + id + "\"")
		var size = min(40, text.count)
		while hit == nil, size >= 3 {
			hit = source.range(of: String(text.prefix(size)))
			size /= 2
		}
		let files = (found["files"] as? [String] ?? []).filter { $0.hasPrefix("slyed://file/") }.compactMap { URL(string: $0)?.path }
		picked = ["trail": found["trail"] as? String ?? "", "text": text, "html": found["html"] as? String ?? "", "files": files, "line": hit.map { source[..<$0.lowerBound].components(separatedBy: "\n").count } ?? 0]
		model.palette = "comment"
		model.query = ""
	}

	func surface() {
		guard win != nil else { return }
		NSApp.setActivationPolicy(.regular)
		win.makeKeyAndOrderFront(nil)
		NSApp.activate(ignoringOtherApps: true)
	}

	func windowWillClose(_ notification: Notification) {
		NSApp.setActivationPolicy(.accessory)
	}

	func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
		let why = NSAppleEventManager.shared().currentAppleEvent?.attributeDescriptor(forKeyword: kAEQuitReason)?.enumCodeValue ?? 0
		if ending || [kAELogOut, kAEReallyLogOut, kAEShowRestartDialog, kAEShowShutdownDialog].contains(why) {
			return .terminateNow
		}
		win?.close()
		return .terminateCancel
	}

	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		surface()
		return true
	}

	func application(_ application: NSApplication, open urls: [URL]) {
		for url in urls where url.scheme == "slycbar" {
			quiet = true
			if url.host == "reload" {
				WidgetCenter.shared.reloadAllTimelines()
			} else {
				bar.reveal()
			}
		}
		guard urls.contains(where: { $0.scheme != "slycbar" }) else { return }
		for url in urls where url.scheme == "slyed" {
			let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
			if url.host == "review", let plan = items.first(where: { $0.name == "plan" })?.value {
				if ready {
					load(plan: plan)
				} else {
					firstPlan = plan
				}
				continue
			}
			if url.host == "compare", let left = items.first(where: { $0.name == "a" })?.value, let right = items.first(where: { $0.name == "b" })?.value {
				if ready {
					compare(left, right)
				} else {
					firstPair = (left, right)
				}
				continue
			}
			guard let path = items.first(where: { $0.name == "path" })?.value else { continue }
			pending = items.first(where: { $0.name == "line" })?.value.flatMap { Int($0) }
			pendingEnd = items.first(where: { $0.name == "end" })?.value.flatMap { Int($0) }
			if ready {
				show(path)
			} else {
				first.append(path)
			}
		}
		let paths = urls.filter { $0.isFileURL }.map { $0.path }
		if ready {
			paths.forEach { show($0) }
		} else {
			first += paths
		}
		surface()
	}

	func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

	func windowDidBecomeKey(_ notification: Notification) {
		repos = [:]
		refresh()
		if model.gitOpen {
			reloadGit()
		}
	}

	func menu() {
		let main = NSMenu()
		func add(_ title: String, _ items: [(String, Selector?, String, NSEvent.ModifierFlags)]) {
			let top = NSMenuItem()
			let menu = NSMenu(title: title)
			for (name, action, key, flags) in items {
				if name == "-" {
					menu.addItem(.separator())
					continue
				}
				let item = menu.addItem(withTitle: name, action: action, keyEquivalent: key)
				item.keyEquivalentModifierMask = flags
			}
			top.submenu = menu
			main.addItem(top)
		}
		add("Slyed", [("Settings…", #selector(tuning(_:)), ",", .command), ("-", nil, "", []), ("Hide", #selector(NSApplication.hide(_:)), "h", .command), ("Quit", #selector(NSApplication.terminate(_:)), "q", .command)])
		add("File", [("Open…", #selector(pick(_:)), "o", .command), ("Save", #selector(save(_:)), "s", .command), ("-", nil, "", []), ("Close", #selector(NSWindow.performClose(_:)), "w", .command)])
		add("Edit", [("Undo", Selector(("undo:")), "z", .command), ("Redo", Selector(("redo:")), "z", [.command, .shift]), ("-", nil, "", []), ("Cut", #selector(NSText.cut(_:)), "x", .command), ("Copy", #selector(NSText.copy(_:)), "c", .command), ("Paste", #selector(NSText.paste(_:)), "v", .command), ("Select All", #selector(NSText.selectAll(_:)), "a", .command), ("Find…", #selector(find(_:)), "f", .command)])
		add("Navigate", [("Search Everywhere…", #selector(goSearch(_:)), "k", .command), ("Search Everywhere…", #selector(goSearch(_:)), "k", .control), ("Go to File…", #selector(goFile(_:)), "o", [.command, .shift]), ("Recent Files", #selector(goRecent(_:)), "e", .command), ("Go to Line…", #selector(goLine(_:)), "l", .command), ("-", nil, "", []), ("Back", #selector(back(_:)), "[", .command), ("Forward", #selector(forward(_:)), "]", .command), ("Declaration", #selector(declaration(_:)), "b", .command), ("-", nil, "", []), ("Comment to Agent…", #selector(goComment(_:)), "m", [.command, .shift]), ("Mention to Claude Code", #selector(mention(_:)), "k", [.command, .option])])
		add("Review", [("Open Review", #selector(openReview(_:)), "r", [.command, .shift]), ("-", nil, "", []),
			("Next", #selector(nextStep(_:)), "]", [.command, .option]), ("Previous", #selector(previousStep(_:)), "[", [.command, .option]), ("-", nil, "", []),
			("Accept Change", #selector(acceptStep(_:)), "y", [.command, .option]), ("Reject Change", #selector(rejectStep(_:)), "n", [.command, .option]), ("-", nil, "", []),
			("Close Review", #selector(closeReview(_:)), "", [])])
		add("View", [("Files", #selector(side(_:)), "1", .command), ("Git", #selector(gitPanel(_:)), "9", .command), ("Inline Diff", #selector(flip(_:)), "d", [.command, .shift]), ("-", nil, "", []), ("Zoom In", #selector(zoomIn(_:)), "+", .command), ("Zoom In", #selector(zoomIn(_:)), "=", .command), ("Zoom Out", #selector(zoomOut(_:)), "-", .command), ("Actual Size", #selector(zoomReset(_:)), "0", .command), ("Increase Font Size", #selector(zoomIn(_:)), ".", [.control, .shift]), ("Decrease Font Size", #selector(zoomOut(_:)), ",", [.control, .shift]), ("Reset Font Size", #selector(zoomReset(_:)), "0", [.control, .shift])])
		NSApp.mainMenu = main
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		menu()
		let config = WKWebViewConfiguration()
		config.setURLSchemeHandler(Files(), forURLScheme: "slyed")
		config.userContentController.addScriptMessageHandler(self, contentWorld: .page, name: "editor")
		config.userContentController.addUserScript(WKUserScript(source: probing, injectionTime: .atDocumentEnd, forMainFrameOnly: true))
		web = WKWebView(frame: .zero, configuration: config)
		web.setValue(false, forKey: "drawsBackground")
		model.ask = { [unowned self] in self.show($0) }
		model.flip = { [unowned self] in self.flip(nil) }
		model.flipSides = { [unowned self] in self.flipSides(nil) }
		model.format = { [unowned self] in self.format(nil) }
		model.act = { [unowned self] in self.gitRun($0) }
		model.openGit = { [unowned self] in self.gitPanel(nil) }
		model.choose = { [unowned self] in self.pick(nil) }
		model.changed = { [unowned self] in self.refresh() }
		model.warp = { [unowned self] in
			let tray = (cache as NSString).deletingLastPathComponent + "/tray"
			let pid = pid_t((try? String(contentsOfFile: tray + "/pid", encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
			guard pid > 0, kill(pid, 0) == 0 else {
				self.model.status = "the tray is not running"
				return
			}
			guard CGPreflightScreenCaptureAccess() else {
				CGRequestScreenCaptureAccess()
				NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
				self.model.status = "warp waits for Screen Recording to be allowed for Slyed in System Settings"
				return
			}
			let target = self.model.file.isEmpty ? self.model.root : self.model.file
			guard !self.model.file.isEmpty || !self.top.isEmpty else {
				self.model.status = "nothing to warp, " + self.model.short(target) + " is in no git repository"
				return
			}
			if !self.model.file.isEmpty {
				let dir = (target as NSString).deletingLastPathComponent
				guard !git(dir, ["log", "-n", "1", "--format=%h", "--follow", "--", target]).out.isEmpty || !git(dir, ["diff", "--numstat", "HEAD", "--", target]).out.isEmpty else {
					self.model.status = "nothing to warp, " + (target as NSString).lastPathComponent + " has no git history"
					return
				}
			}
			try? "open \(Int(Date().timeIntervalSince1970))\nchanges \(target)".write(toFile: tray + "/play", atomically: true, encoding: .utf8)
		}
		model.impact = { [unowned self] in
			let tray = (cache as NSString).deletingLastPathComponent + "/tray"
			let pid = pid_t((try? String(contentsOfFile: tray + "/pid", encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "") ?? 0
			guard pid > 0, kill(pid, 0) == 0 else {
				self.model.status = "the tray is not running"
				return
			}
			guard CGPreflightScreenCaptureAccess() else {
				CGRequestScreenCaptureAccess()
				NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
				self.model.status = "impact waits for Screen Recording to be allowed for Slyed in System Settings"
				return
			}
			try? "open \(Int(Date().timeIntervalSince1970))\nimpact".write(toFile: tray + "/play", atomically: true, encoding: .utf8)
		}
		model.compare = { [unowned self] ref in
			self.model.base = ref
			self.model.diff = true
			self.model.sides = false
			self.model.gitOpen = false
			if !self.model.file.isEmpty {
				self.show(self.model.file, record: false)
			}
		}
		let commands: [(String, String, String, Selector)] = [("Go to File…", "⇧⌘O", "doc.text.magnifyingglass", #selector(goFile(_:))), ("Recent Files", "⌘E", "clock", #selector(goRecent(_:))),
			("Go to Line…", "⌘L", "number", #selector(goLine(_:))), ("Go to Declaration", "⌘B", "arrow.turn.down.right", #selector(declaration(_:))), ("Back", "⌘[", "chevron.left", #selector(back(_:))),
			("Forward", "⌘]", "chevron.right", #selector(forward(_:))), ("Format File", "", "wand.and.stars", #selector(format(_:))), ("Save", "⌘S", "square.and.arrow.down", #selector(save(_:))),
			("Open…", "⌘O", "folder", #selector(pick(_:))), ("Toggle Files Sidebar", "⌘1", "sidebar.left", #selector(side(_:))), ("Inline Diff", "⇧⌘D", "plusminus", #selector(flip(_:))),
			("Side by Side Diff", "", "square.split.2x1", #selector(flipSides(_:))), ("Comment to Agent…", "⇧⌘M", "text.bubble", #selector(goComment(_:))), ("Mention to Claude Code", "⌥⌘K", "at", #selector(mention(_:))), ("Copy Path", "", "doc.on.doc", #selector(copyPath(_:))),
			("Copy Path and Line", "", "doc.on.doc", #selector(copySpot(_:))), ("Reveal in Finder", "", "folder", #selector(reveal(_:))), ("Zoom In", "⌘=", "plus.magnifyingglass", #selector(zoomIn(_:))),
			("Zoom Out", "⌘−", "minus.magnifyingglass", #selector(zoomOut(_:))), ("Actual Size", "⌘0", "1.magnifyingglass", #selector(zoomReset(_:))), ("Find a Language Server", "", "shippingbox", #selector(findServer(_:))),
			("Open Review", "⇧⌘R", "checklist", #selector(openReview(_:))), ("Next Change", "⌥⌘]", "chevron.down", #selector(nextStep(_:))),
			("Previous Change", "⌥⌘[", "chevron.up", #selector(previousStep(_:))), ("Accept Change", "⌥⌘Y", "checkmark.circle", #selector(acceptStep(_:))), ("Reject Change", "⌥⌘N", "xmark.circle", #selector(rejectStep(_:))), ("Close Review", "", "xmark", #selector(closeReview(_:)))]
		model.actions = commands.map { title, hint, icon, action in
			Hit(id: "action " + title, section: "Actions", icon: icon, title: title, detail: "", hint: hint) { [unowned self] in _ = self.perform(action, with: nil) }
		}
		model.show = { [unowned self] mode in
			self.model.mode = mode
		}
		model.review = { [unowned self] path in
			self.model.diff = true
			self.model.sides = false
			self.show(path)
		}
		model.comment = { [unowned self] in self.comment($0) }
		model.store = { [unowned self] in self.store($0, $1) }
		model.answer = { [unowned self] agent, text in
			self.model.status = self.post(agent.socket, text) ? "answer sent to " + agent.name : "not sent to " + agent.name
			let ruled = agent.questions.map { $0.components(separatedBy: "\t") }.filter { $0.count > 1 && text.range(of: "\\b" + $0[0] + "\\b", options: [.regularExpression, .caseInsensitive]) != nil }
			if !ruled.isEmpty {
				let body = ruled.map { "- " + $0[0] + ": " + $0[1] + "\n  " + text.replacingOccurrences(of: "\n", with: " ") }.joined(separator: "\n")
				DispatchQueue.global().async { self.held(agent).forEach { self.minute($0, "Answers", body) } }
			}
			if self.model.talk?.agent?.id == agent.id {
				self.model.talk?.lines.append("**You** " + text)
			}
			note("comments.log", agent.name + " answer")
		}
		model.jump = { [unowned self] path, line in
			self.pending = line
			self.show(path)
		}
		model.line = { [unowned self] in self.pad.show($0, 0) }
		model.done = { [unowned self] in
			self.win.makeFirstResponder(self.model.media.isEmpty && !self.model.file.isEmpty ? self.pad : self.web)
		}
		NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [unowned self] event in
			if self.model.reviewing, self.model.palette.isEmpty, !self.model.gitOpen, !self.model.boardOpen {
				let held = event.modifierFlags.intersection([.command, .control, .option, .shift])
				if held == .option, event.keyCode == 126 || event.keyCode == 125 {
					self.walk(event.keyCode == 125)
					return nil
				}
				if self.struck("ask", event) || (self.model.inquiring && self.struck("accept", event)) {
					self.ask(self.model.pulse.draft)
					self.model.pulse.draft = ""
					return nil
				}
				if !self.model.inquiring, self.struck("accept", event) || self.struck("reject", event) {
					self.judge(self.model.hunk, self.struck("reject", event) ? "rejected" : "accepted")
					return nil
				}
			}
			if !self.model.reviewing, self.model.sheeted || self.model.noting, self.model.palette.isEmpty, !self.model.boardOpen, self.struck("ask", event) || self.struck("accept", event), !self.model.pulse.draft.isEmpty {
				self.ask(self.model.pulse.draft)
				self.model.pulse.draft = ""
				return nil
			}
			guard event.keyCode == 53, self.model.gitOpen || self.model.setOpen || self.model.kitOpen || self.model.talk != nil || !self.model.palette.isEmpty || self.model.boardOpen else { return event }
			if self.model.talk != nil {
				self.model.talk = nil
				return nil
			}
			if !self.model.gitOpen && !self.model.setOpen && !self.model.kitOpen && self.model.palette.isEmpty {
				self.model.boardOpen = false
			}
			self.model.gitOpen = false
			self.model.setOpen = false
			self.model.kitOpen = false
			if !self.model.palette.isEmpty {
				self.model.close()
			}
			return nil
		}
		NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [unowned self] event in
			if event.modifierFlags.intersection([.command, .control, .option]).isEmpty, self.model.over, event.hasPreciseScrollingDeltas {
				if event.phase == .began {
					self.swiped = 0
					self.fired = false
				}
				if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) * 1.5 {
					self.swiped += event.scrollingDeltaX
					if !self.fired, abs(self.swiped) > 70, event.momentumPhase == [] {
						self.fired = true
						self.swiped > 0 ? self.back(nil) : self.forward(nil)
					}
					return nil
				}
				return event
			}
			guard event.modifierFlags.contains(.command) || event.modifierFlags.contains(.control) else { return event }
			self.rolled += event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.1 : 1)
			if abs(self.rolled) >= 1 {
				self.zoom(self.model.over, self.rolled > 0 ? 0.05 : -0.05)
				self.rolled = 0
			}
			return nil
		}
		model.decide = { [unowned self] in self.decide($0) }
		model.visit = { [unowned self] change in self.seek(self.model.hunks.firstIndex { $0.change == change } ?? -1) }
		model.judge = { [unowned self] in self.judge($0, $1) }
		model.audit = { [unowned self] in self.audit($0) }
		model.converse = { [unowned self] in self.converse($0, $1, $2, $3) }
		model.openKit = { [unowned self] in self.kitPanel(nil) }
		model.walk = { [unowned self] in self.walk($0) }
		model.get = { [unowned self] in self.index.get($0, $1, $2) }
		model.getSymbols = { [unowned self] in self.index.getSymbols($0, $1, $2) }
		model.look = { [unowned self] in self.look($0) }
		model.magnify = { [unowned self] in self.zoom(false, $0) }
		model.remark = { [unowned self] in
			self.model.noting = true
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { self.model.pulse.focus += 1 }
		}
		sheet.build = { [unowned self] menu in
			let item = menu.addItem(withTitle: "Send to Agent…", action: #selector(self.goComment(_:)), keyEquivalent: "")
			item.target = self
		}
		model.inquire = { [unowned self] in self.ask($0) }
		model.unmark = { [unowned self] in
			if !self.model.sheeted {
				self.pad.setSelectedRange(NSRange(location: self.pad.selectedRange().location, length: 0))
			}
			self.sheet.others = []
			self.sheet.chosen = nil
			self.sheet.needsDisplay = true
			self.model.pulse.mark = ""
		}
		sheet.marked = { [unowned self] in
			guard self.sheet.chosen != nil || !self.sheet.others.isEmpty else {
				self.model.pulse.mark = ""
				return
			}
			self.model.pulse.mark = self.sheet.selections().filter { $0.hunk < self.sheet.hunks.count }.map { chosen in
				let change = self.sheet.hunks[chosen.hunk].change
				let name = change < self.sheet.paths.count ? (self.sheet.paths[change] as NSString).lastPathComponent : ""
				let count = chosen.text.split(separator: "\n", omittingEmptySubsequences: false).count
				return name + ":\(chosen.line)" + (chosen.end > chosen.line ? "-\(chosen.end)" : "") + " · \(count) " + (count == 1 ? "line" : "lines")
			}.joined(separator: "\n")
		}
		pad.build = { [unowned self] in self.menu($0) }
		let code = model.zoomed * 0.8
		sheet.scale = code
		sheet.measure()
		pad.size(code)
		pad.edited = { [unowned self] text in
			let path = self.pad.path
			self.model.dirty.insert(path)
			self.win.isDocumentEdited = true
			self.settle(path, text)
			self.count()
			self.read()
			if self.model.diff || self.model.sides {
				self.contrast()
			}
			if self.model.preview {
				self.feed(text)
			}
		}
		pad.moved = { [unowned self] in self.read() }
		twin.isEditable = false
		twin.shade = 0xf75464
		twin.size(code)
		model.pulse.zoom = code
		pad.scrolled = { [unowned self] in
			guard self.model.twinned else { return }
			let top = self.pad.top()
			var shift = 0
			for change in self.pad.changes where change.from < top && change.id < self.cuts.count {
				shift += self.cuts[change.id].removed - self.cuts[change.id].added
			}
			self.twin.rise(max(1, top + shift))
		}
		pad.resolve = { [unowned self] in self.resolve($0, $1) }
		pad.tidied = { [unowned self] in self.format(nil) }
		pad.ask = { [unowned self] method, text, line, character, options, answer in self.lsp(method, self.pad.path, text, line, character, options, answer) }
		pad.go = { [unowned self] path, line in
			self.pending = line
			self.show(path)
		}
		sheet.measure()
		sheet.pick = { [unowned self] id in
			if self.model.reviewing {
				self.seek(id)
			} else {
				self.sheet.focus(id)
				self.model.region = "region \(id + 1) of \(self.sheet.hunks.count)"
			}
		}
		sheet.autoresizingMask = [.width]
		scroller.documentView = sheet
		scroller.hasVerticalScroller = true
		scroller.scrollerStyle = .overlay
		scroller.verticalScroller = Scroller()
		scroller.backgroundColor = Sheet.tone(0x1e1f22)
		scroller.contentView.postsBoundsChangedNotifications = true
		scroller.contentView.postsFrameChangedNotifications = true
		NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: scroller.contentView, queue: .main) { [unowned self] _ in self.sheet.needsDisplay = true }
		NotificationCenter.default.addObserver(forName: NSView.frameDidChangeNotification, object: scroller.contentView, queue: .main) { [unowned self] _ in self.sheet.arrange() }
		model.resume = { [unowned self] in self.resume() }
		model.back = { [unowned self] in self.back(nil) }
		model.forward = { [unowned self] in self.forward(nil) }
		model.turned = { [unowned self] in self.record(self.here($0)) }
		NSEvent.addLocalMonitorForEvents(matching: .otherMouseDown) { [unowned self] event in
			guard event.buttonNumber == 3 || event.buttonNumber == 4 else { return event }
			event.buttonNumber == 3 ? self.back(nil) : self.forward(nil)
			return nil
		}
		model.leave = { [unowned self] in self.leave() }
		ide.workspaceFolders = { [unowned self] in self.model.root.isEmpty || self.model.roots.contains(self.model.root) ? self.model.roots : self.model.roots + [self.model.root] }
		ide.call = { [unowned self] in self.tool($0, $1, $2, $3) }
		ide.connected = { [unowned self] in
			self.model.claude = true
			self.model.status = "Claude Code connected"
			self.spotted = ""
			self.select(self.model.file, self.model.pulse.cursor)
		}
		ide.closed = { [unowned self] client in
			self.model.claude = !self.ide.clients.isEmpty
			self.withdraw { $0.client == client }
		}
		folders = model.$roots.combineLatest(model.$root).receive(on: DispatchQueue.main).sink { [unowned self] _ in self.ide.write() }
		signal(SIGTERM, SIG_IGN)
		quit.setEventHandler { [unowned self] in
			self.ending = true
			NSApp.terminate(nil)
		}
		quit.resume()
		ide.start()
		Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [unowned self] _ in
			self.watch()
			self.recheck()
			self.retalk()
			self.tune()
		}
		Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [unowned self] _ in
			if self.model.boardOpen {
				self.stream()
			}
		}
		model.stream = { [unowned self] in self.stream() }
		watch()
		model.up = { [unowned self] in
			let parent = (self.model.root as NSString).deletingLastPathComponent
			guard !parent.isEmpty, parent != self.model.root else { return }
			self.model.open.insert(self.model.root)
			self.model.roots.removeAll { $0 == self.model.root }
			self.model.adopt(parent)
			self.refresh()
		}
		servers.status = { [unowned self] in self.model.server = $0 }
		servers.diagnosed = { [unowned self] path, list in
			self.diagnostics[path] = list
			let rows: [[String: Any]] = list.map { d in
				let range = d["range"] as? [String: Any] ?? [:]
				let start = range["start"] as? [String: Any] ?? [:]
				let end = range["end"] as? [String: Any] ?? [:]
				return ["line": (start["line"] as? Int ?? 0) + 1, "column": (start["character"] as? Int ?? 0) + 1,
					"endLine": (end["line"] as? Int ?? 0) + 1, "endColumn": (end["character"] as? Int ?? 0) + 1,
					"message": d["message"] as? String ?? "", "severity": (d["severity"] as? Int ?? 1) == 1 ? "error" : "warning"]
			}
			if path == self.pad.path {
				self.pad.mark(rows)
				self.read()
			}
		}

		let screen = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
		let size = NSSize(width: min(1280, screen.width * 0.7), height: min(860, screen.height * 0.8))
		win = NSWindow(contentRect: NSRect(origin: .zero, size: size), styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
		win.title = "Slyed"
		win.isReleasedWhenClosed = false
		win.appearance = NSAppearance(named: .darkAqua)
		win.titlebarAppearsTransparent = true
		win.titleVisibility = .hidden
		win.isOpaque = false
		win.backgroundColor = .clear
		win.delegate = self
		let shell = NSHostingView(rootView: Shell(model: model, web: web, sheet: scroller, pad: editor.0, twin: mirror.0))
		shell.sizingOptions = []
		let glass = NSVisualEffectView(frame: NSRect(origin: .zero, size: size))
		glass.material = .hudWindow
		glass.blendingMode = .behindWindow
		glass.state = .active
		shell.frame = glass.bounds
		shell.autoresizingMask = [.width, .height]
		glass.addSubview(shell)
		win.contentView = glass
		win.setFrameAutosaveName("editor")
		if win.frame.origin == .zero {
			win.center()
		}
		bar.edit = { [unowned self] in
			self.surface()
			self.seeking = true
			self.watch()
		}
		bar.start()
		if !CommandLine.arguments.contains("tray") {
			DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
				if !self.quiet {
					self.surface()
				}
			}
		}
		first += CommandLine.arguments.dropFirst().filter { $0.hasPrefix("/") }
		DispatchQueue.main.async { self.begin() }
	}
}

if CommandLine.arguments.count > 1 && CommandLine.arguments[1] == "default" {
	let named = ["public.plain-text", "public.source-code", "public.script", "public.shell-script", "public.json", "public.xml", "public.yaml", "public.css", "public.log",
		"public.comma-separated-values-text", "public.tab-separated-values-text", "net.daringfireball.markdown", "com.netscape.javascript-source", "public.swift-source",
		"public.c-source", "public.c-header", "public.c-plus-plus-source", "public.objective-c-source", "public.python-script", "public.ruby-script", "public.php-script",
		"public.perl-script", "com.sun.java-source", "public.make-source", "com.apple.property-list"]
	let extensions = ["ts", "tsx", "mts", "cts", "js", "jsx", "mjs", "cjs", "vue", "svelte", "go", "mod", "sum", "rs", "toml", "lock", "env", "ini", "conf", "cfg", "sql", "tengo", "tf", "tfvars", "hcl",
		"kt", "dart", "lua", "zig", "ex", "exs", "erl", "hs", "ml", "nim", "cs", "graphql", "proto", "gradle", "sh", "zsh", "bash", "fish", "yml", "yaml", "md", "txt", "json", "jsonl", "jsonc",
		"tsv", "csv", "log", "gitignore", "editorconfig", "tmpl", "scss", "less", "just", "mk", "diff", "patch", "swift", "py", "rb", "php", "java", "c", "h", "cpp", "hpp", "m", "mm", "xml", "plist", "css"]
	var types: [UTType] = []
	for type in named.compactMap({ UTType($0) }) + extensions.compactMap({ UTType(filenameExtension: $0) }) where !types.contains(type) {
		types.append(type)
	}
	let group = DispatchGroup()
	var failed: [String] = []
	for type in types {
		group.enter()
		NSWorkspace.shared.setDefaultApplication(at: Bundle.main.bundleURL, toOpen: type) { error in
			if error != nil {
				DispatchQueue.main.async { failed.append(type.identifier) }
			}
			group.leave()
		}
	}
	group.notify(queue: .main) {
		print("default for \(types.count - failed.count) of \(types.count) types")
		failed.forEach { print("not set: " + $0) }
		exit(failed.isEmpty ? 0 : 1)
	}
	RunLoop.main.run()
}

let host = Host()
NSApplication.shared.setActivationPolicy(.accessory)
NSApplication.shared.delegate = host
NSApplication.shared.run()
