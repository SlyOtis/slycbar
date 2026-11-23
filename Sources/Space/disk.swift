import Foundation

extension Work {
	static let image = "/Library/Group Containers/HUAQ24HBR6.dev.orbstack/data/data.img.raw"
	static let hex = re("^[0-9a-f]{64}$")

	var suspects: [String] {
		[
			"/Library/Caches", "/Library/Developer", "/Library/Containers", "/Library/Group Containers",
			"/Library/Application Support", "/Library/Logs", "/Library/pnpm", "/Library/Caches/ms-playwright",
			"/Library/Caches/ms-playwright-mcp", "/Library/Android", "/go", "/.cache", "/.npm", "/.pnpm-store",
			"/.gradle", "/.android", "/.orbstack", "/OrbStack", "/.docker", "/.ollama", "/.cargo",
			"/.rustup", "/.bun", "/.claude", "/Downloads", "/.Trash",
		].map { home + $0 }
	}

	func load() {
		read = true
		sizes = []
		known = [:]
		guard let d = FileManager.default.contents(atPath: cache) else { return }
		for l in lines(String(decoding: d, as: UTF8.self)) {
			let t = tabs(l)
			guard t.count > 1 else { continue }
			sizes.append((t[0], t[1]))
			if known[t[1]] == nil { known[t[1]] = t[0] }
		}
	}

	func cached(_ path: String) -> Int { whole(known[path] ?? "0") }

	func tree() throws {
		if sh("find", [cache, "-mmin", "-" + fresh]).out.isEmpty {
			note("walking \(home) once, cached in \(cache) for \(fresh) minutes")
			let tmp = cache + ".tmp"
			FileManager.default.createFile(atPath: tmp, contents: nil)
			if let h = FileHandle(forWritingAtPath: tmp) {
				sh("du", ["-xk", "-d4", home], out: h)
				try? h.close()
			}
			let n = (try? FileManager.default.attributesOfItem(atPath: tmp)[.size] as? Int) ?? 0
			guard n > 0 else {
				err("slybar space: du read nothing under \(home)\n")
				throw Halt(code: 1)
			}
			rename(tmp, cache)
		}
		load()
	}

	func under(_ dir: String, _ n: Int) -> [String] {
		let pre = dir + "/"
		return sizes.filter { starts($0.path, pre) && $0.path.utf8.dropFirst(pre.utf8.count).filter { $0 == 47 }.count == n - 1 }
			.map { "\($0.kb) \($0.path)" }
	}

	func docker() -> Bool {
		if sh("docker", ["info"], out: .nullDevice).code == 0 { return true }
		guard which("orb") != nil else { return false }
		note("starting orbstack to read docker")
		sh("orb", ["start"], out: .nullDevice)
		for _ in 0..<30 {
			if sh("docker", ["info"], out: .nullDevice).code == 0 { return true }
			sleep(2)
		}
		return false
	}

	func volumes() -> [(name: String, links: String, kb: Int)] {
		var r: [(name: String, links: String, kb: Int)] = []
		for l in lines(sh("docker", ["system", "df", "-v", "--format", "{{json .Volumes}}"]).out) {
			guard let a = try? JSONSerialization.jsonObject(with: Data(l.utf8)) as? [[String: Any]] else { continue }
			for v in a {
				let size = v["Size"].map { "\($0)" } ?? ""
				let n = num(size)
				let k = size.contains("GB") ? n * 1048576 : size.contains("MB") ? n * 1024 : size.contains("kB") ? n : n / 1024
				r.append((v["Name"].map { "\($0)" } ?? "", v["Links"].map { "\($0)" } ?? "", Int(k)))
			}
		}
		return r
	}

	func files(_ found: String) -> [String] {
		let paths = cut(found, by: 0, keep: false)
		var r: [String] = []
		var i = 0
		while i < paths.count {
			let part = Array(paths[i..<min(i + 1000, paths.count)])
			r += lines(sh("du", ["-sk"] + part).out)
			i += 1000
		}
		return r
	}

	func disk() throws {
		section("free")
		let df = words(at(lines(sh("df", ["-h", "/System/Volumes/Data"]).out), 1))
		if !df.isEmpty { put("\(at(df, 3)) free of \(at(df, 1)), \(at(df, 4)) used\n") }
		let snaps = lines(sh("tmutil", ["listlocalsnapshots", "/"]).out).filter { $0.contains("com.apple") }.count
		if snaps > 0 { put("\(snaps) local time machine snapshots\n") }
		try tree()

		section("home, top 15")
		put(human(Array(ranked(under(home, 1), down: true).prefix(15))))

		section("usual suspects")
		put(human(ranked(suspects.flatMap { d in sizes.filter { $0.path == d }.map { "\($0.kb) \($0.path)" } }, down: true)))

		section("library, two levels, top 15")
		put(human(Array(ranked(under(home + "/Library", 2), down: true).prefix(15))))

		section("docker")
		if exists(home + Work.image) {
			put(lines(human(lines(size(home + Work.image)))).map { $0 + ", the orbstack disk image, shrinks after a prune\n" }.joined())
		}
		if docker() {
			put(sh("docker", ["system", "df"]).out)
			let stopped = lines(sh("docker", ["ps", "-aq", "-f", "status=exited", "-f", "status=created"]).out).count
			let dangling = lines(sh("docker", ["images", "-qf", "dangling=true"]).out).count
			put("stopped containers: \(stopped), dangling images: \(dangling)\n")
			var count: [String: Int] = [:]
			var sum: [String: Int] = [:]
			for v in volumes() {
				let k = (Double(v.links) == 0 ? "unused" : "in use") + " " + (hit(Work.hex, v.name) ? "anonymous" : "named")
				count[k, default: 0] += 1
				sum[k, default: 0] += v.kb
			}
			put(human(ranked(count.keys.map { "\(sum[$0] ?? 0)\t\($0) volumes, \(count[$0] ?? 0)" }, down: true).map {
				let t = tabs($0)
				return at(t, 0) + " " + at(t, 1)
			}))
		} else {
			put("docker unreachable, orb start did not bring the engine up\n")
		}

		section("models, simulators, emulators")
		if which("ollama") != nil {
			for l in lines(sh("ollama", ["list"]).out).dropFirst() {
				let w = words(l)
				put("\(at(w, 2))\(at(w, 3))  ollama \(at(w, 0))\n")
			}
		}
		put(human(ranked(under(home + "/.android/avd", 1), down: true)))
		let sims = lines(sh("xcrun", ["simctl", "list", "devices", "unavailable"]).out).filter { $0.contains("(") }.count
		if sims > 0 { put("\(sims) unavailable simulators\n") }
		let dev = [home + "/Library/Developer/CoreSimulator/Devices", home + "/Library/Developer/Xcode/DerivedData"]
		put(human(sizes.filter { dev.contains($0.path) }.map { "\($0.kb) \($0.path)" }))

		section("files over 500M in home outside library, containers and models")
		let found = sh("find", [
			home, "-xdev", "(", "-path", home + "/Library", "-o", "-path", home + "/OrbStack", "-o", "-path", home + "/.orbstack",
			"-o", "-path", home + "/.ollama", "-o", "-name", "node_modules", "-o", "-name", "target", "-o", "-name", ".git", ")",
			"-prune", "-o", "-type", "f", "-size", "+500M", "-print0",
		], limit: limit).out
		put(human(Array(ranked(files(found), down: true).prefix(20))))
	}

	func build(_ days: String, show: Bool) -> [(kb: String, state: String, dir: String)] {
		let days = days.isEmpty ? "\(stale)" : days
		let ref = mark(DateComponents(day: -(Int(days) ?? stale)))
		defer { drop(ref) }
		if !read { load() }
		if show { section("build artifacts under \(projects), stale = project untouched for \(days) days") }
		note("sizing the build folders under \(projects)")
		var out: [String] = []
		for d in lines(sh("find", ["-E", projects, "-type", "d", "-regex", ".*/(\(Work.artifacts))", "-prune", "-print"]).out) {
			let k = known[d] ?? at(tabs(at(lines(size(d)), 0)), 0)
			guard let n = Int(k), n > 51200 else { continue }
			let touched = sh("find", [
				"-E", dirname(d), "-maxdepth", "4", "(", "-type", "d", "-regex", ".*/(\(Work.artifacts)|\\.git)", "-prune", ")",
				"-o", "-type", "f", "-newer", ref, "-print", "-quit",
			]).out
			out.append("\(k)\t\(touched.isEmpty ? "stale" : "active")\t\(d)")
		}
		let rows = ranked(out, down: true).map { tabs($0) }.map { (kb: at($0, 0), state: at($0, 1), dir: at($0, 2)) }
		if show {
			for r in rows.prefix(40) { put(f("%6.1fG  ", num(r.kb) / 1048576) + left(r.state, 6) + "  " + r.dir + "\n") }
			let total = rows.reduce(0.0) { $0 + num($1.kb) }
			let old = rows.filter { $0.state == "stale" }.reduce(0.0) { $0 + num($1.kb) }
			put(f("total %.1fG, stale %.1fG\n", total / 1048576, old / 1048576))
		}
		return rows
	}
}
