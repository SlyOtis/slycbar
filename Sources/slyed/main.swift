import AppKit
import Combine
import Network
import SwiftUI
import UniformTypeIdentifiers
import WebKit
import WidgetKit
import tray

let cache = (ProcessInfo.processInfo.environment["SLYCBAR_CACHE"] ?? NSHomeDirectory() + "/.cache/slycbar") + "/editor"
let pages = (Bundle.main.resourcePath ?? "") + "/editor"

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
		entries = (try? JSONDecoder().decode([Entry].self, from: data)) ?? []
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

	var color: Color {
		status == "busy" ? Color(red: 0.95, green: 0.65, blue: 0.42) : status == "idle" ? Color.white.opacity(0.4) : Color(red: 0.92, green: 0.74, blue: 0.33)
	}
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
			if !stepping, oldValue != root, !oldValue.isEmpty {
				turned(oldValue)
			}
		}
	}
	var stepping = false
	var turned: (String) -> Void = { _ in }
	var back: () -> Void = {}
	var forward: () -> Void = {}
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
	@Published var open: Set<String> = []
	@Published var kids: [String: [(String, Bool)]] = [:]
	@Published var dirty: Set<String> = []
	@Published var ignored: [String] = []
	@Published var marks: [String: String] = [:]
	@Published var diff = false
	@Published var sides = false
	@Published var gitOpen = false
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
	@Published var stats: [String] = []
	@Published var cursor = ""
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
	@Published var asking: Agent?
	var answer: (Agent, String) -> Void = { _, _ in }
	@Published var counts: [String: (Int, Int)] = [:]
	var review: (String) -> Void = { _ in }
	var pool: [String] = []
	var recent: [String] = []
	var top = ""
	var line: (Int) -> Void = { _ in }
	var zoom: (Bool, Double) -> Void = { _, _ in }
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
	@Published var draft = ""
	@Published var folder = ""
	@Published var deep = UserDefaults.standard.double(forKey: "deep")
	var depth = 0.0
	var visit: (Int) -> Void = { _ in }
	var judge: (Int, String) -> Void = { _, _ in }
	var walk: (Bool) -> Void = { _ in }
	var resume: () -> Void = {}
	var leave: () -> Void = {}

	var decided: Int { hunks.filter { $0.status != "pending" }.count }
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
			let pool = self.pool
			let jump = self.jump
			let short = self.short
			DispatchQueue.global().asyncAfter(deadline: .now() + 0.2) {
				guard mine == self.asked else { return }
				var found: [Hit] = []
				var named: [(Int, String)] = []
				for path in pool {
					let name = (path as NSString).lastPathComponent.lowercased()
					if let at = name.range(of: q) {
						named.append((name.distance(from: name.startIndex, to: at.lowerBound) * 10 + name.count, path))
					}
				}
				for (_, path) in named.sorted(by: { $0.0 < $1.0 }).prefix(5) {
					found.append(Hit(id: "file " + path, section: "Files", icon: "doc", title: (path as NSString).lastPathComponent, detail: short((path as NSString).deletingLastPathComponent), hint: "") { jump(path, nil) })
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
		let from = palette == "recent" ? recent : pool
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
			Text("⋮").font(.system(size: 13, weight: .bold)).foregroundStyle(Ink.dim).frame(width: 14, height: 13)
		}
		.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 14, height: 13)
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
				Badge(text: agent.acts[node.path] ?? "open", color: agent.color).tip(agent.name + " " + (agent.acts[node.path] ?? "") + ", " + agent.status)
			}
			if model.dirty.contains(node.path) {
				Circle().fill(Color.white.opacity(0.7)).frame(width: 6, height: 6)
			} else if !mark.isEmpty && mark != "·" {
				Text(mark == "?" ? "U" : mark).font(.system(size: 10, weight: .semibold)).foregroundStyle(tint)
			}
			More(model: model, path: node.path, dir: node.dir).opacity(over ? 1 : 0).allowsHitTesting(over)
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
	static let accent = Color(red: 0.706, green: 0.388, blue: 0.184)
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
			Image(systemName: name).font(.system(size: size))
				.foregroundStyle(on ? Color.white : over ? Ink.fg : Ink.dim)
				.frame(width: size + 14, height: size + 10)
				.background(RoundedRectangle(cornerRadius: 6).fill(on ? tint : over ? Ink.hover : Color.clear))
				.contentShape(Rectangle())
		}
		.buttonStyle(.plain).focusable(false)
		.onHover { over = $0 }
		.tip(tip)
	}
}

struct Badge: View {
	let text: String
	let color: Color

	var body: some View {
		Image(systemName: text == "reads" ? "eye" : text == "writes" ? "square.and.pencil" : text == "edits" ? "pencil" : "circle").font(.system(size: 9, weight: .semibold)).foregroundStyle(color)
			.frame(width: 16, height: 14).background(Capsule().fill(color.opacity(0.18))).tip(text)
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
			out[range].font = .system(size: 11.5, design: .monospaced)
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
					Text(inline(block.text)).font(.system(size: 13, weight: .semibold)).padding(.top, 4)
				case "code":
					Text(block.text).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color(red: 0.34, green: 0.66, blue: 0.96))
						.padding(8).frame(maxWidth: .infinity, alignment: .leading)
						.background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
				case "ask":
					HStack(alignment: .firstTextBaseline, spacing: 8) {
						Text(block.mark).font(.system(size: 11, weight: .bold)).foregroundStyle(Color.white).padding(.horizontal, 6).padding(.vertical, 1)
							.background(Capsule().fill(Ink.accent))
						Text(inline(block.text)).font(.system(size: 12))
					}
					.padding(7).frame(maxWidth: .infinity, alignment: .leading)
					.background(RoundedRectangle(cornerRadius: 7).fill(Ink.accent.opacity(0.14)))
				case "item":
					HStack(alignment: .firstTextBaseline, spacing: 6) {
						Text(block.mark).font(.system(size: 12)).monospacedDigit().foregroundStyle(Ink.dim).frame(minWidth: 20, alignment: .trailing)
						Text(inline(block.text)).font(.system(size: 12))
					}
				default:
					Text(inline(block.text)).font(.system(size: 12))
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
			Image(systemName: name).font(.system(size: 10, weight: .medium)).foregroundStyle(over ? (danger ? Color(red: 1, green: 0.49, blue: 0.43) : Ink.fg) : Ink.dim)
				.frame(width: 20, height: 18).background(RoundedRectangle(cornerRadius: 5).fill(over ? Ink.hover : Color.clear)).contentShape(Rectangle())
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

struct Verdict: View {
	let accept: Bool
	let on: Bool
	var small = false
	let tip: String
	let action: () -> Void
	@State private var over = false

	var body: some View {
		let green = Color(red: 0.42, green: 0.78, blue: 0.56)
		let red = Color(red: 1, green: 0.49, blue: 0.43)
		let filled = accept || on
		Button(action: action) {
			Label(accept ? (on ? "Accepted" : "Accept") : (on ? "Rejected" : "Reject"), systemImage: accept ? (on ? "checkmark.circle.fill" : "checkmark") : (on ? "xmark.circle.fill" : "xmark"))
				.labelStyle(.titleAndIcon)
				.font(.system(size: small ? 11 : 12, weight: accept ? .bold : .semibold))
				.foregroundStyle(filled ? Color.white : over ? red : Ink.fg)
				.padding(.horizontal, small ? 8 : 11).frame(height: small ? 20 : 26)
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

struct Feedback: View {
	@ObservedObject var model: Model

	var body: some View {
		let hunk = model.hunks[model.hunk]
		let step = model.steps[hunk.change]
		VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 7) {
				Image(systemName: hunk.mark).font(.system(size: 12)).foregroundStyle(hunk.tint)
				Text(hunk.label).font(.system(size: 13, weight: .bold)).monospacedDigit()
				Text("\(model.hunk + 1) of \(model.hunks.count)").font(.system(size: 11)).monospacedDigit().foregroundStyle(Ink.dim)
				Text(step.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
				Text(model.short(step.path) + ":\(hunk.line)" + (hunk.end > hunk.line ? "-\(hunk.end)" : "")).font(.system(size: 11)).foregroundStyle(Ink.dim).lineLimit(1).truncationMode(.head)
					.textSelection(.enabled)
				Spacer(minLength: 6)
				Counts(added: step.added, removed: step.removed)
				Text(model.phase + (model.round > 1 ? " · round \(model.round)" : "") + " · \(model.decided)/\(model.hunks.count)").font(.system(size: 10, weight: .semibold)).monospacedDigit().foregroundStyle(Ink.dim)
					.padding(.horizontal, 7).padding(.vertical, 1).background(Capsule().fill(Ink.hover))
			}
			if !step.why.isEmpty || !step.notes.isEmpty || !model.remarks.isEmpty {
				ScrollView {
					VStack(alignment: .leading, spacing: 4) {
						if !step.why.isEmpty {
							Markdown(text: step.why, base: model.folder).foregroundStyle(Ink.fg.opacity(0.85))
						}
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
				TextField("Comment on \(hunk.label), it goes with accept or reject", text: $model.draft, axis: .vertical)
					.textFieldStyle(.plain).font(.system(size: 13)).lineLimit(1...(model.deep > 0 ? max(6, Int((model.deep - 160) / 17)) : 6))
					.padding(.horizontal, 4).padding(.top, 4)
					.frame(maxHeight: model.deep > 0 ? .infinity : nil, alignment: .topLeading)
				HStack(spacing: 2) {
					Icon(name: "chevron.up", size: 15, tip: "Previous change, ⌥⌘[") { model.walk(false) }
					Icon(name: "chevron.down", size: 15, tip: "Next change, ⌥⌘]") { model.walk(true) }
					Spacer(minLength: 6)
					Verdict(accept: false, on: hunk.status == "rejected", small: true, tip: "Reject \(hunk.label) with the comment, ⌥⌘N") { model.judge(model.hunk, "rejected") }
					Verdict(accept: true, on: hunk.status == "accepted", small: true, tip: "Accept \(hunk.label) with the comment, ⌥⌘Y") { model.judge(model.hunk, "accepted") }
				}
			}
			.frame(maxHeight: model.deep > 0 ? .infinity : nil)
			.padding(8)
			.background(RoundedRectangle(cornerRadius: 12).fill(Color.white.opacity(0.06)))
			.overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Ink.accent.opacity(0.35), lineWidth: 1))
		}
		.foregroundStyle(Ink.fg)
		.padding(10)
		.frame(maxWidth: .infinity, maxHeight: model.deep > 0 ? .infinity : nil, alignment: .topLeading)
		.frame(height: model.deep > 0 ? model.deep : nil)
		.background(GeometryReader { box in
			Color.clear.onAppear { model.depth = box.size.height }.onChange(of: box.size.height) { _, tall in model.depth = tall }
		})
		.background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
		.overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.line, lineWidth: 1))
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

	var files: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 6) {
				Mark(model: model, path: model.root, on: true)
				VStack(alignment: .leading, spacing: 0) {
					Text(model.label(model.root)).font(.system(size: 12 * model.scale, weight: .semibold)).lineLimit(1).truncationMode(.head).tip(model.root)
						.contextMenu { Ops(model: model, path: model.root, dir: true, top: true) }
					Trail(model: model)
				}
				Spacer(minLength: 0)
				More(model: model, path: model.root, dir: true, top: true)
			}
			.padding(.trailing, 6)
			ScrollView {
				LazyVStack(spacing: 1) {
					ForEach(model.rows(model.root, 0)) { Row(model: model, node: $0) }
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
				Text("\(model.decided)/\(model.hunks.count)").font(.system(size: 10 * model.scale)).monospacedDigit().foregroundStyle(Ink.dim)
				Spacer(minLength: 0)
				Act(name: "arrow.up.forward.square", tip: "Open the review, ⇧⌘R") { model.resume() }
			}
			.padding(.horizontal, 4)
			Text(model.heading).font(.system(size: 12 * model.scale, weight: .semibold)).lineLimit(2).padding(.horizontal, 4)
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
			Text("AGENTS").font(.system(size: 10 * model.scale)).tracking(0.6).foregroundStyle(Ink.dim).padding(.horizontal, 4)
				VStack(alignment: .leading, spacing: 1) {
					ForEach(model.agents) { agent in
						HStack(spacing: 6) {
							Circle().fill(agent.color).frame(width: 7, height: 7)
							Text(agent.name).fontWeight(.semibold).lineLimit(1)
							Text(agent.status).foregroundStyle(Ink.dim)
							Spacer(minLength: 0)
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
								Badge(text: agent.acts[path] ?? "open", color: agent.color)
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
		VStack(spacing: 0) {
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
					Icon(name: "chevron.left.forwardslash.chevron.right", on: model.mode == "code", tip: "Code") { model.show("code") }
					Icon(name: "rectangle.split.2x1", on: model.mode == "both", tip: "Code and preview") { model.show("both") }
					Icon(name: "eye", on: model.mode == "preview", tip: "Preview") { model.show("preview") }
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
				if model.tracked {
					Icon(name: "plus.forwardslash.minus", on: model.diff, tip: "Inline diff against " + model.base + ", ⇧⌘D", action: model.flip)
					Icon(name: "arrow.left.arrow.right", on: model.sides, tip: "Side by side with " + model.base, action: model.flipSides)
				}
				if !model.top.isEmpty {
					Icon(name: "arrow.triangle.branch", on: model.gitOpen, tip: "Git: stage, commit, branches, merge, cherry-pick, stash, ⌘9") { model.openGit() }
				}
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
						if !model.agents.isEmpty {
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
						if !model.meters.isEmpty {
							Color.clear.frame(height: 4)
							Meters(meters: model.meters, account: model.account, scale: model.scale)
								.background(RoundedRectangle(cornerRadius: 9).fill(Ink.accent.opacity(0.14)))
								.overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(Ink.accent.opacity(0.4), lineWidth: 1))
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
						Web(view: web).frame(maxWidth: .infinity, maxHeight: .infinity)
							.clipShape(RoundedRectangle(cornerRadius: 10))
							.overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Ink.line, lineWidth: 1))
							.shadow(color: .black.opacity(0.4), radius: 9, y: 2)
						if model.reviewing {
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
						ForEach(model.stats, id: \.self) { Text($0) }
						Spacer(minLength: 8)
						if model.claude {
							Text("Claude Code").tip("A Claude Code session is connected to this editor through /ide")
						}
						Text(model.server)
						Text(model.cursor)
						HStack(spacing: 0) {
							Act(name: "minus", tip: "Zoom out, ⌘−") { model.zoom(false, -0.1) }
							Text("\(Int((model.zoomed / 1.2 * 100).rounded()))%").frame(minWidth: 36).contentShape(Rectangle()).onTapGesture { model.zoom(false, 0) }.tip("Zoom of the code and preview, click to reset")
							Act(name: "plus", tip: "Zoom in, ⌘=") { model.zoom(false, 0.1) }
						}
						Icon(name: "wand.and.stars", tip: "Format the file", action: model.format)
						Hover { over in
							Button(action: model.warp) {
								Text("WARP").font(.custom("Impact", size: 11)).tracking(1.5).foregroundStyle(over ? Ink.fg : Ink.dim).contentShape(Rectangle())
							}
							.buttonStyle(.plain).focusable(false)
						}
						.tip("Warp through the git history of what is open, by who did what")
					}
					.font(.system(size: 11)).monospacedDigit().foregroundStyle(Ink.dim).lineLimit(1)
					.padding(.leading, 12).padding(.trailing, 6).frame(height: 22).padding(.bottom, 5)
				}
			}
		}
		.foregroundStyle(Ink.fg)
		.background(Color(red: 0.031, green: 0.039, blue: 0.071).opacity(0.34))
		.overlay(alignment: .top) {
			ZStack(alignment: .top) {
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

final class Page: WKWebView {
	var build: (NSMenu) -> Void = { _ in }

	override func willOpenMenu(_ menu: NSMenu, with event: NSEvent) {
		build(menu)
	}
}

final class Files: NSObject, WKURLSchemeHandler {
	func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
		guard let url = task.request.url else { return }
		let path = url.host == "file" ? url.path : pages + (url.path.isEmpty || url.path == "/" ? "/index.html" : url.path)
		guard let handle = FileHandle(forReadingAtPath: path) else {
			task.didFailWithError(URLError(.fileDoesNotExist))
			return
		}
		defer { handle.closeFile() }
		let size = handle.seekToEndOfFile()
		let type = UTType(filenameExtension: (path as NSString).pathExtension)?.preferredMIMEType ?? "application/octet-stream"
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
	var parsed: [Int: (String, Agent)] = [:]
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
		if fresh {
			model.step = -1
			model.hunk = -1
			model.hunks = []
		}
		DispatchQueue.global().async {
			var found = self.split(steps)
			DispatchQueue.main.async {
				guard self.model.plan == path, self.model.steps.count == steps.count else { return }
				for at in found.indices {
					let hunk = found[at]
					if let n = self.model.steps[hunk.change].notes.firstIndex(where: { !$0.status.isEmpty && $0.side == hunk.side && $0.line == hunk.line && $0.end == hunk.end }) {
						let note = self.model.steps[hunk.change].notes.remove(at: n)
						found[at].status = note.status
						found[at].text = note.text
						found[at].sent = note.sent
					}
					let added = hunk.rows.filter { $0["t"] as? String == "+" }.count
					let removed = hunk.rows.filter { $0["t"] as? String == "-" }.count
					self.model.steps[hunk.change].added = (hunk.part == 1 ? 0 : self.model.steps[hunk.change].added) + added
					self.model.steps[hunk.change].removed = (hunk.part == 1 ? 0 : self.model.steps[hunk.change].removed) + removed
				}
				self.model.hunks = found
				self.drawn = false
				guard !found.isEmpty else {
					self.model.status = "the plan changes nothing against the files on disk"
					return
				}
				if fresh {
					self.seek(found.firstIndex { $0.status == "pending" } ?? 0, record: false)
				} else if held >= 0 {
					self.seek(min(held, found.count - 1), record: false)
				}
			}
		}
	}

	func split(_ steps: [Step]) -> [Hunk] {
		let fm = FileManager.default
		var found: [Hunk] = []
		for (change, step) in steps.enumerated() {
			let left = !step.base.isEmpty ? step.base : fm.fileExists(atPath: step.path) ? step.path : "/dev/null"
			let out = String(decoding: call("/usr/bin/git", ["diff", "--no-index", "--no-color", "-U3", "--", left, step.proposed]).out, as: UTF8.self)
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
					found.append(Hunk(id: found.count, change: change, part: part, side: plus.isEmpty ? "base" : "proposed", line: lines.first ?? 1, end: lines.last ?? 1, rows: Array(rows[before...after])))
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

	func tree(_ at: Int) -> [String: Any] {
		["at": at, "files": model.steps.enumerated().map { n, step -> [String: Any] in
			["n": n + 1, "name": (step.path as NSString).lastPathComponent, "path": model.short(step.path), "title": step.title, "why": step.why, "added": step.added, "removed": step.removed,
				"hunks": model.hunks.filter { $0.change == n }.map { ["id": $0.id, "label": $0.label, "status": $0.status, "text": $0.text, "rows": $0.rows] as [String: Any] }]
		}]
	}

	func anchor(_ path: String) {
		var dir = (path as NSString).deletingLastPathComponent
		while dir.count > 1, !FileManager.default.fileExists(atPath: dir) {
			dir = (dir as NSString).deletingLastPathComponent
		}
		model.stepping = true
		if let held = model.roots.filter({ path.hasPrefix($0 + "/") }).max(by: { $0.count < $1.count }) {
			model.root = held
		} else {
			let found = git(dir, ["rev-parse", "--show-toplevel"])
			let project = found.code == 0 ? String(decoding: found.out, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines) : dir
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
			self.displayed = false
			self.model.file = step.path
			self.model.tracked = false
			self.model.diff = false
			self.model.sides = false
			self.model.preview = false
			self.model.comparing = ""
			self.model.region = ""
			self.win.title = self.model.hunks[at].label + " " + step.title
			self.anchor(step.path)
			self.model.hunk = at
			self.model.step = self.model.hunks[at].change
			self.model.draft = self.model.hunks[at].text
			if self.drawn {
				self.page("return window.slyc.hunk(at, marks)", ["at": at, "marks": self.model.hunks.map { ["status": $0.status, "text": $0.text] }])
			} else {
				self.drawn = true
				self.page("return window.slyc.review(doc)", ["doc": self.tree(at)])
			}
			self.refresh()
		}
		if model.dirty.contains(model.file), model.step < 0, model.comparing.isEmpty {
			let old = model.file
			page("return window.slyc.text()", [:]) { text in
				if let text = text as? String {
					self.drafts[old] = text
				}
				draw()
			}
		} else {
			draw()
		}
	}

	func judge(_ at: Int, _ status: String) {
		guard at >= 0, at < model.hunks.count else { return }
		let text = at == model.hunk ? model.draft.trimmingCharacters(in: .whitespacesAndNewlines) : model.hunks[at].text
		model.hunks[at].status = model.hunks[at].status == status && model.hunks[at].text == text ? "pending" : status
		model.hunks[at].text = text
		model.hunks[at].sent = false
		let change = model.hunks[at].change
		let marks = model.hunks.filter { $0.change == change }.map { $0.status }
		model.steps[change].status = marks.contains("rejected") ? "rejected" : marks.allSatisfy { $0 == "accepted" } ? "accepted" : "pending"
		persist()
		guard model.hunks.contains(where: { $0.status == "pending" }) else {
			finish()
			return
		}
		if at == model.hunk, model.hunks[at].status != "pending", let next = model.hunks.indices.first(where: { $0 > at && model.hunks[$0].status == "pending" }) ?? model.hunks.firstIndex(where: { $0.status == "pending" }) {
			seek(next)
		} else {
			page("return window.slyc.hunk(at, marks)", ["at": model.hunk, "marks": model.hunks.map { ["status": $0.status, "text": $0.text] }])
		}
	}

	func walk(_ forward: Bool) {
		if !model.comparing.isEmpty {
			page("return window.slyc.region(t)", ["t": forward ? "next" : "prev"]) { result in
				if (result as? [String: Any])?["done"] as? Bool ?? true {
					self.model.status = forward ? "no later difference" : "no earlier difference"
				}
			}
			return
		}
		guard !model.hunks.isEmpty else { return }
		let next = model.hunk < 0 ? (forward ? 0 : model.hunks.count - 1) : model.hunk + (forward ? 1 : -1)
		guard next >= 0, next < model.hunks.count else {
			model.status = forward ? "this is the last change" : "this is the first change"
			return
		}
		seek(next)
	}

	func resume() {
		guard !model.plan.isEmpty else {
			model.status = "no review is open, an agent opens one with slybar review"
			return
		}
		seek(model.hunk >= 0 ? model.hunk : model.hunks.firstIndex { $0.status == "pending" } ?? 0)
	}

	func finish() {
		let approved = model.hunks.allSatisfy { $0.status == "accepted" }
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
		note("comments.log", "review " + state + " " + model.plan)
		leave()
		model.status = approved ? "every change is accepted, the review is back with Claude Code" : "the review is back with Claude Code"
	}

	func recheck() {
		guard !model.plan.isEmpty, stamp(model.plan) > stamped else { return }
		load(plan: model.plan)
		model.status = "the plan changed on disk and was read again"
	}

	func persist(_ also: (inout [String: Any]) -> Void = { _ in }) {
		guard !model.plan.isEmpty else { return }
		if stamp(model.plan) > stamped, let data = FileManager.default.contents(atPath: model.plan), let read = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
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
		guard let data = try? JSONSerialization.data(withJSONObject: body, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]) else { return }
		do {
			try data.write(to: URL(fileURLWithPath: model.plan), options: .atomic)
		} catch {
			model.status = "the plan was not saved: " + error.localizedDescription
			return
		}
		stamped = stamp(model.plan)
	}

	func pair(_ path: String, _ left: String, _ right: String, _ title: String, _ target: String) {
		let load = {
			self.displayed = false
			self.model.file = path
			self.model.tracked = false
			self.model.diff = false
			self.model.sides = true
			self.win.title = title
			self.page("return window.slyc.show(doc)", ["doc": ["path": path, "name": (path as NSString).lastPathComponent, "text": right, "original": left, "media": "", "url": "", "locked": true]]) { result in
				self.model.preview = (result as? [String: Any])?["preview"] as? Bool ?? false
				self.page("return window.slyc.diff(on, undefined, sides)", ["on": false, "sides": true]) { _ in
					if !target.isEmpty {
						self.page("return window.slyc.region(t)", ["t": target])
					}
				}
			}
		}
		if model.dirty.contains(model.file), model.step < 0, model.comparing.isEmpty {
			let old = model.file
			page("return window.slyc.text()", [:]) { text in
				if let text = text as? String {
					self.drafts[old] = text
				}
				load()
			}
		} else {
			load()
		}
	}

	func compare(_ left: String, _ right: String) {
		let title = (left as NSString).lastPathComponent + " ↔ " + (right as NSString).lastPathComponent
		pair(right, decode(left), decode(right), title, "first")
		model.step = -1
		model.hunk = -1
		model.comparing = model.short(left) + " ↔ " + model.short(right)
		model.region = ""
	}

	func leave() {
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
			model.draft = ""
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
			page("return window.slyc.show(doc)", ["doc": ["path": "", "name": ".txt", "text": "", "original": NSNull(), "media": "", "url": ""]])
		}
	}

	func trace(_ path: String) {
		let agents = model.agents
		let home = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"] ?? NSHomeDirectory() + "/.claude"
		let text = drafts[path] ?? decode(path)
		DispatchQueue.global().async {
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
				self.page("return window.slyc.traces(path, list)", ["path": path, "list": Array(found.suffix(400))])
			}
		}
	}

	func tune() {
		let path = NSHomeDirectory() + "/.slycbar/settings.json"
		let changed = stamp(path)
		guard ready, changed != tuned else { return }
		tuned = changed
		let given = FileManager.default.contents(atPath: path).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
		page("return window.slyc.settings(given)", ["given": given])
	}

	func decode(_ path: String) -> String {
		guard let data = FileManager.default.contents(atPath: path) else { return "" }
		return String(data: data, encoding: .utf8) ?? String(decoding: data, as: UTF8.self)
	}

	func page(_ body: String, _ args: [String: Any], _ done: ((Any?) -> Void)? = nil) {
		web.callAsyncJavaScript(body, arguments: args, in: nil, in: .page) { result in
			done?(try? result.get())
		}
	}

	func propose() {
		guard let proposal = proposals.first else { return }
		model.proposal = (proposal.path as NSString).lastPathComponent
		let load = {
			self.before = self.model.file
			self.held = self.model.dirty.contains(proposal.path)
			self.displayed = true
			self.model.file = proposal.path
			self.model.tracked = false
			self.model.diff = false
			self.model.sides = true
			self.win.title = (proposal.path as NSString).lastPathComponent
			self.page("return window.slyc.show(doc)", ["doc": ["path": proposal.path, "name": (proposal.path as NSString).lastPathComponent, "text": proposal.contents, "original": self.decode(proposal.path), "media": "", "url": ""]]) { result in
				self.model.preview = (result as? [String: Any])?["preview"] as? Bool ?? false
				self.page("return window.slyc.diff(on, undefined, sides)", ["on": false, "sides": true])
			}
		}
		if model.dirty.contains(model.file) {
			let old = model.file
			page("return window.slyc.text()", [:]) { text in
				if let text = text as? String {
					self.drafts[old] = text
				}
				load()
			}
		} else {
			load()
		}
	}

	func restore(_ path: String, _ expected: String?, _ left: Int) {
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
				self.page("return window.slyc.show(doc)", ["doc": ["path": "", "name": ".txt", "text": "", "original": NSNull(), "media": "", "url": ""]])
			}
		}
	}

	func decide(_ accepted: Bool) {
		guard !model.proposal.isEmpty, !proposals.isEmpty else { return }
		let proposal = proposals.removeFirst()
		let shown = displayed && model.file == proposal.path
		guard accepted else {
			proposal.answer([["type": "text", "text": "DIFF_REJECTED"]])
			restore(proposal.path, nil, 0)
			return
		}
		page("return window.slyc.text()", [:]) { text in
			let saved = shown ? text as? String ?? proposal.contents : proposal.contents
			proposal.answer([["type": "text", "text": "FILE_SAVED"], ["type": "text", "text": saved]])
			self.restore(proposal.path, saved, 8)
		}
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
		page("return window.slyc.spot()", [:]) { result in
			let spot = result as? [String: Any] ?? [:]
			let from = spot["line"] as? Int ?? 1
			let to = spot["end"] as? Int ?? from
			let text = spot["text"] as? String ?? ""
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
		page("return window.slyc.spot()", [:]) { result in
			let spot = result as? [String: Any] ?? [:]
			let from = spot["line"] as? Int ?? 1
			let to = spot["end"] as? Int ?? from
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

	func base(_ path: String) -> String? {
		let dir = (path as NSString).deletingLastPathComponent
		let shown = git(dir, ["show", model.base + ":./" + (path as NSString).lastPathComponent])
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
			let text = media.isEmpty ? self.drafts[path] ?? self.decode(path) : ""
			self.model.status = ""
			let original = media.isEmpty ? self.base(path) : nil
			self.model.file = path
			self.model.tracked = original != nil
			self.win.title = (path as NSString).lastPathComponent
			self.win.representedURL = URL(fileURLWithPath: path)
			self.page("return window.slyc.show(doc)", ["doc": ["path": path, "name": (path as NSString).lastPathComponent, "text": text, "original": original as Any? ?? NSNull(), "media": media, "url": "slyed://file" + (path.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? path)]]) { result in
				let info = result as? [String: Any]
				self.model.preview = info?["preview"] as? Bool ?? false
				self.model.mode = info?["mode"] as? String ?? "both"
				self.trace(path)
				self.page("return window.slyc.diff(on, undefined, sides)", ["on": self.model.diff && original != nil, "sides": self.model.sides && original != nil])
				if let line = self.pending {
					self.page("return window.slyc.line(n, e)", ["n": line, "e": self.pendingEnd ?? 0])
					self.pending = nil
					self.pendingEnd = nil
				}
			}
			if media.isEmpty {
				self.settle(path, text)
			}
			self.refresh()
		}
		if model.dirty.contains(model.file) {
			let old = model.file
			page("return window.slyc.text()", [:]) { text in
				if let text = text as? String {
					self.drafts[old] = text
				}
				load()
			}
		} else {
			load()
		}
	}

	@objc func save(_ sender: Any?) {
		let path = model.file
		guard !path.isEmpty else { return }
		guard model.step < 0, model.comparing.isEmpty else {
			model.status = "a review or comparison is read only"
			return
		}
		page("return window.slyc.text()", [:]) { text in
			guard let text = text as? String else { return }
			do {
				try text.write(toFile: path, atomically: true, encoding: .utf8)
			} catch {
				self.model.status = "not saved: " + error.localizedDescription
				return
			}
			self.model.dirty.remove(path)
			self.drafts[path] = nil
			self.win.isDocumentEdited = false
			self.servers.with(path, self.root(for: path)) { server, _ in
				server?.when { server?.notify("textDocument/didSave", ["textDocument": ["uri": URL(fileURLWithPath: path).absoluteString]]) }
			}
			self.refresh()
		}
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
		} else {
			model.zoomed = step == 0 ? 1.2 : min(3, max(0.5, model.zoomed + step * 1.2))
			web.pageZoom = model.zoomed
			if model.step >= 0 {
				page("return window.slyc.loose()", [:])
			}
			UserDefaults.standard.set(model.zoomed, forKey: "zoom")
		}
	}

	@objc func zoomIn(_ sender: Any?) { zoom(model.over, 0.1) }
	@objc func zoomOut(_ sender: Any?) { zoom(model.over, -0.1) }
	@objc func zoomReset(_ sender: Any?) { zoom(model.over, 0) }

	@objc func side(_ sender: Any?) { withAnimation(.easeOut(duration: 0.2)) { model.side.toggle() } }
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
		page("return window.slyc.declaration()", [:])
	}

	@objc func format(_ sender: Any?) {
		page("return window.slyc.format()", [:]) { result in
			self.model.status = result as? String == "server" ? "formatted by the language server" : result as? String == "editor" ? "formatted" : "nothing to format"
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
		page("return window.slyc.spot()", [:]) { result in
			let spot = result as? [String: Any] ?? [:]
			let from = spot["line"] as? Int ?? 1
			let to = spot["end"] as? Int ?? from
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
		add("Comment to Agent…", #selector(goComment(_:)))
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
			model.draft = text
			return
		}
		let path = model.file
		page("return window.slyc.spot()", [:]) { result in
			let spot = result as? [String: Any] ?? [:]
			let from = spot["line"] as? Int ?? 1
			let to = spot["end"] as? Int ?? from
			var hunk = ""
			let dir = (path as NSString).deletingLastPathComponent
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
			var message = "Comment from Slyed on \(path):\(from)" + (to > from ? "-\(to)" : "") + ". " + text + "\nCode at that spot:\n" + (spot["text"] as? String ?? "")
			if !hunk.isEmpty {
				message += "\nUncommitted change there:\n" + hunk
			}
			message += "\nChange only this spot."
			slyed.copy(message)
			let agent = self.model.agents.first { $0.files.contains(path) } ?? self.model.agents.first { !$0.dir.isEmpty && path.hasPrefix($0.dir + "/") }
			guard let agent, !agent.socket.isEmpty else {
				self.model.status = "no agent on this file, comment copied"
				return
			}
			self.model.status = self.post(agent.socket, message) ? "comment sent to " + agent.name : "not sent to " + agent.name + ", comment copied"
			note("comments.log", agent.name + " " + path + ":\(from)")
		}
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
			DispatchQueue.main.async {
				self.model.pool = pool
				self.model.search()
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
					let agent = Agent(id: pid, name: manifest["name"] as? String ?? (dir as NSString).lastPathComponent, dir: dir, status: manifest["status"] as? String ?? "idle", files: old.files, acts: old.acts, socket: old.socket, last: old.last, questions: old.questions, sid: id)
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
				agents.append(Agent(id: pid, name: manifest["name"] as? String ?? (dir as NSString).lastPathComponent, dir: dir, status: manifest["status"] as? String ?? "idle", files: Array(files.prefix(6)), acts: acts, socket: manifest["messagingSocketPath"] as? String ?? "", last: last, questions: open.map { $0.0 + "\t" + $0.1 }, sid: id))
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
				self.page("return window.slyc.vitals(v)", ["v": ["cpu": share("cpu"), "mem": share("mem"), "seven": share("7d"), "fable": share("fable"), "busy": agents.filter { $0.status == "busy" }.count]])
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
		guard model.step < 0, model.comparing.isEmpty else { return }
		model.sides.toggle()
		if model.sides {
			model.diff = false
		}
		page("return window.slyc.diff(on, undefined, sides)", ["on": model.diff, "sides": model.sides])
	}

	@objc func flip(_ sender: Any?) {
		guard model.step < 0, model.comparing.isEmpty else { return }
		model.diff.toggle()
		if model.diff {
			model.sides = false
		}
		page("return window.slyc.diff(on, undefined, sides)", ["on": model.diff, "sides": model.sides])
	}

	func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage, replyHandler: @escaping (Any?, String?) -> Void) {
		guard message.frameInfo.isMainFrame, let body = message.body as? [String: Any] else {
			replyHandler(nil, nil)
			return
		}
		if body["ready"] != nil {
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
			replyHandler(nil, nil)
		} else if let at = body["hunk"] as? Int {
			seek(at)
			replyHandler(nil, nil)
		} else if let region = body["region"] as? [String: Any] {
			let at = region["at"] as? Int ?? -1
			let of = region["of"] as? Int ?? 0
			model.region = of == 0 ? "no differences" : at < 0 ? "\(of) " + (of == 1 ? "region" : "regions") : "region \(at + 1) of \(of)"
			replyHandler(nil, nil)
		} else if let text = body["change"] as? String, let path = body["path"] as? String {
			model.dirty.insert(path)
			win.isDocumentEdited = true
			settle(path, text)
			replyHandler(nil, nil)
		} else if let uri = body["goto"] as? String, let url = URL(string: uri) {
			pending = body["line"] as? Int ?? 1
			show(url.path)
			replyHandler(nil, nil)
		} else if let stats = body["stats"] as? [String] {
			model.stats = stats
			model.cursor = body["cursor"] as? String ?? ""
			select(body["path"] as? String ?? "", model.cursor)
			replyHandler(nil, nil)
		} else if let unknown = body["unknown"] as? [String: Any], let path = body["path"] as? String {
			let ext = (path as NSString).pathExtension
			note("unknown.log", "\(ext.isEmpty ? "-" : ext) \(unknown["guess"] as? String ?? "") \(path)")
			model.status = "unknown file type, highlighted as " + (unknown["guess"] as? String ?? "generic")
			replyHandler(nil, nil)
		} else if let method = body["lsp"] as? String, let path = body["path"] as? String {
			let text = body["text"] as? String ?? ""
			let position: [String: Any] = ["line": body["line"] as? Int ?? 0, "character": body["character"] as? Int ?? 0]
			var answered = false
			let answer: (Any?) -> Void = { result in
				guard !answered else { return }
				answered = true
				replyHandler(result is NSNull ? nil : result, nil)
			}
			servers.with(path, root(for: path)) { server, language in
				guard let server, server.ready else {
					answer(nil)
					return
				}
				server.sync(path, language, text)
				var params: [String: Any] = ["textDocument": ["uri": URL(fileURLWithPath: path).absoluteString], "position": position]
				if let options = body["options"] {
					params = ["textDocument": params["textDocument"] as Any, "options": options]
				}
				server.request(method, params, answer)
				DispatchQueue.main.asyncAfter(deadline: .now() + 4) { answer(nil) }
			}
		} else {
			replyHandler(nil, nil)
		}
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
		add("Slyed", [("Hide", #selector(NSApplication.hide(_:)), "h", .command), ("Quit", #selector(NSApplication.terminate(_:)), "q", .command)])
		add("File", [("Open…", #selector(pick(_:)), "o", .command), ("Save", #selector(save(_:)), "s", .command), ("-", nil, "", []), ("Close", #selector(NSWindow.performClose(_:)), "w", .command)])
		add("Edit", [("Undo", Selector(("undo:")), "z", .command), ("Redo", Selector(("redo:")), "z", [.command, .shift]), ("-", nil, "", []), ("Cut", #selector(NSText.cut(_:)), "x", .command), ("Copy", #selector(NSText.copy(_:)), "c", .command), ("Paste", #selector(NSText.paste(_:)), "v", .command), ("Select All", #selector(NSText.selectAll(_:)), "a", .command)])
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
		let view = Page(frame: .zero, configuration: config)
		view.build = { [unowned self] in self.menu($0) }
		web = view
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
			self.page("return window.slyc.mode(mode)", ["mode": mode])
		}
		web.pageZoom = model.zoomed
		model.zoom = { [unowned self] in self.zoom($0, $1) }
		model.review = { [unowned self] path in
			self.model.diff = true
			self.model.sides = false
			self.show(path)
		}
		model.comment = { [unowned self] in self.comment($0) }
		model.answer = { [unowned self] agent, text in
			self.model.status = self.post(agent.socket, text) ? "answer sent to " + agent.name : "not sent to " + agent.name
			note("comments.log", agent.name + " answer")
		}
		model.jump = { [unowned self] path, line in
			self.pending = line
			self.show(path)
		}
		model.line = { [unowned self] in self.page("return window.slyc.line(n)", ["n": $0]) }
		model.done = { [unowned self] in
			self.win.makeFirstResponder(self.web)
			self.page("return window.slyc.focus()", [:])
		}
		NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [unowned self] event in
			guard event.keyCode == 53, self.model.gitOpen || !self.model.palette.isEmpty else { return event }
			self.model.gitOpen = false
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
		model.walk = { [unowned self] in self.walk($0) }
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
			self.select(self.model.file, self.model.cursor)
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
			self.tune()
		}
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
			self.page("return window.slyc.diagnose(path, list)", ["path": path, "list": rows])
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
		let shell = NSHostingView(rootView: Shell(model: model, web: web))
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
		web.load(URLRequest(url: URL(string: "slyed://app/index.html")!))
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
