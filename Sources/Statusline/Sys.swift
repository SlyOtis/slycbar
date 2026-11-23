import Foundation

extension Array where Element == UInt8 {
	func find(_ needle: [UInt8], _ from: Int = 0) -> Int? {
		withUnsafeBytes { $0.find(needle, from) }
	}

	func split(_ mark: UInt8) -> [[UInt8]] {
		split(separator: mark, omittingEmptySubsequences: false).map { Array($0) }
	}
}

extension Sequence where Element == UInt8 {
	var text: String { String(decoding: Array(self), as: UTF8.self) }
}

extension UnsafeRawBufferPointer {
	func find(_ needle: [UInt8], _ from: Int = 0) -> Int? {
		guard let base = baseAddress, from >= 0, from + needle.count <= count, !needle.isEmpty else {
			return nil
		}
		guard let hit = memmem(base + from, count - from, needle, needle.count) else {
			return nil
		}
		return base.distance(to: UnsafeRawPointer(hit))
	}
}

enum Sys {
	struct Job {
		let pid: pid_t
		let fd: Int32
	}

	static func which(_ tool: String, _ env: [String: String]) -> String? {
		for dir in (env["PATH"] ?? "/usr/bin:/bin:/usr/sbin:/sbin").split(separator: ":") {
			let at = "\(dir)/\(tool)"
			if access(at, X_OK) == 0 {
				return at
			}
		}
		return nil
	}

	static func spawn(_ path: String, _ args: [String], _ env: [String: String], _ out: Int32?) -> pid_t? {
		var acts: posix_spawn_file_actions_t?
		var attr: posix_spawnattr_t?
		posix_spawn_file_actions_init(&acts)
		posix_spawnattr_init(&attr)
		defer {
			posix_spawn_file_actions_destroy(&acts)
			posix_spawnattr_destroy(&attr)
		}
		posix_spawn_file_actions_addopen(&acts, 0, "/dev/null", O_RDONLY, 0)
		posix_spawn_file_actions_addopen(&acts, 2, "/dev/null", O_WRONLY, 0)
		if let out {
			posix_spawn_file_actions_adddup2(&acts, out, 1)
			posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT))
		} else {
			posix_spawn_file_actions_addopen(&acts, 1, "/dev/null", O_WRONLY, 0)
			posix_spawnattr_setflags(&attr, Int16(POSIX_SPAWN_CLOEXEC_DEFAULT | POSIX_SPAWN_SETSID))
		}
		let argv = args.map { strdup($0) } + [nil]
		let envp = env.map { strdup("\($0.key)=\($0.value)") } + [nil]
		defer {
			argv.forEach { free($0) }
			envp.forEach { free($0) }
		}
		var pid: pid_t = 0
		return posix_spawn(&pid, path, &acts, &attr, argv, envp) == 0 ? pid : nil
	}

	static func start(_ tool: String, _ args: [String], _ env: [String: String]) -> Job? {
		guard let path = which(tool, env) else {
			return nil
		}
		var fds: [Int32] = [0, 0]
		guard pipe(&fds) == 0 else {
			return nil
		}
		let pid = spawn(path, [tool] + args, env, fds[1])
		close(fds[1])
		guard let pid else {
			close(fds[0])
			return nil
		}
		return Job(pid: pid, fd: fds[0])
	}

	static func finish(_ job: Job?) -> (code: Int32, out: [UInt8]) {
		guard let job else {
			return (127, [])
		}
		var out = [UInt8]()
		var buf = [UInt8](repeating: 0, count: 65536)
		while true {
			let n = Darwin.read(job.fd, &buf, buf.count)
			if n > 0 {
				out.append(contentsOf: buf[0..<n])
			} else if n == 0 || errno != EINTR {
				break
			}
		}
		close(job.fd)
		var status: Int32 = 0
		while waitpid(job.pid, &status, 0) < 0 && errno == EINTR {}
		return (status & 0x7f == 0 ? (status >> 8) & 0xff : 128 + (status & 0x7f), out)
	}

	static func alive(_ pid: String) -> Bool {
		guard let pid = pid_t(pid) else {
			return false
		}
		return kill(pid, 0) == 0
	}

	static func ctl(_ name: String) -> Int? {
		var value: Int64 = 0
		var size = MemoryLayout<Int64>.size
		guard sysctlbyname(name, &value, &size, nil, 0) == 0 else {
			return nil
		}
		return size == 4 ? Int(Int32(truncatingIfNeeded: value)) : Int(value)
	}

	static func info(_ path: String) -> (size: Int, time: Int, file: Bool)? {
		var st = Darwin.stat()
		guard stat(path, &st) == 0 else {
			return nil
		}
		return (Int(st.st_size), st.st_mtimespec.tv_sec, st.st_mode & S_IFMT == S_IFREG)
	}

	static func file(_ path: String) -> Bool {
		info(path)?.file == true
	}

	static func read(_ path: String) -> [UInt8]? {
		guard let data = FileManager.default.contents(atPath: path) else {
			return nil
		}
		return [UInt8](data)
	}

	static func text(_ path: String) -> String {
		trim(read(path) ?? [])
	}

	static func trim(_ bytes: [UInt8]) -> String {
		var end = bytes.count
		while end > 0 && bytes[end - 1] == 10 {
			end -= 1
		}
		return String(decoding: bytes[0..<end], as: UTF8.self)
	}

	static func line(_ bytes: [UInt8], _ at: inout Int) -> (text: String, whole: Bool) {
		var end = at
		while end < bytes.count && bytes[end] != 10 {
			end += 1
		}
		var from = at
		var to = end
		while from < to && (bytes[from] == 32 || bytes[from] == 9) {
			from += 1
		}
		while to > from && (bytes[to - 1] == 32 || bytes[to - 1] == 9) {
			to -= 1
		}
		at = min(end + 1, bytes.count)
		return (String(decoding: bytes[from..<to], as: UTF8.self), end < bytes.count)
	}

	static func put(_ path: String, _ bytes: [UInt8]) -> Bool {
		let fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
		guard fd >= 0 else {
			return false
		}
		defer { close(fd) }
		var at = 0
		while at < bytes.count {
			let n = bytes[at...].withUnsafeBytes { write(fd, $0.baseAddress, $0.count) }
			if n <= 0 {
				return false
			}
			at += n
		}
		return true
	}

	static func swap(_ path: String, _ text: String, _ tag: String) {
		if put(path + "." + tag, Array(text.utf8)) {
			rename(path + "." + tag, path)
		}
	}

	static func names(_ dir: String, _ lead: String, _ tail: String) -> [String] {
		let all = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
		return all.filter { $0.hasPrefix(lead) && $0.hasSuffix(tail) && !$0.hasPrefix(".") && $0.utf8.count >= lead.utf8.count + tail.utf8.count }
			.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
	}

	static func leaf(_ path: String) -> String {
		guard let cut = path.lastIndex(of: "/") else {
			return path
		}
		return String(path[path.index(after: cut)...])
	}

	static func chop(_ text: String) -> String {
		guard let cut = text.lastIndex(of: ".") else {
			return text
		}
		return String(text[..<cut])
	}
}
