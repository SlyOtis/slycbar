import Foundation

extension Work {
	typealias Emit = (Space.Row) -> Void

	func row(_ kind: String, _ kb: String, _ action: String, _ target: String, _ why: String, _ group: String) -> Space.Row {
		Space.Row(kind: kind, kb: whole(kb), action: action, target: target, why: why, group: group)
	}

	func pgrep(_ args: [String]) -> Bool { sh("pgrep", args, out: .nullDevice).code == 0 }

	func pids(_ args: [String]) -> [String] { words(sh("pgrep", args).out.replacingOccurrences(of: "\n", with: " ")) }

	func git(_ dir: String, _ args: [String]) -> Ran {
		let r = sh("git", ["-C", dir] + args)
		var out = r.out
		while out.hasSuffix("\n") { out.removeLast() }
		return Ran(out: out, code: r.code)
	}

	func watch() {
		var dirs: Set<String> = []
		for l in lines(sh("lsof", ["-d", "cwd", "-Fpn"]).out) where l.hasPrefix("n") {
			let d = String(l.dropFirst())
			if d != "/", starts(d, "/Users/") { dirs.insert(d) }
		}
		for pid in pids(["-x", "claude"]) {
			let d = cwd(pid)
			if let last = moved(d), now - last < idle * 3600 { dirs.insert(d) }
		}
		active = dirs.sorted(by: before)
	}

	func inuse(_ path: String) -> Bool {
		let p = path + "/"
		return active.contains { a in
			let d = a + "/"
			if starts(d, p) { return true }
			return a.utf8.dropFirst(home.utf8.count).filter { $0 == 47 }.count >= 3 && starts(p, d)
		}
	}

	func loaded(_ path: String) -> Bool {
		lines(sh("ps", ["-axo", "command="]).out).contains { $0.contains(path + "/") }
	}

	func shield() {
		var par: [String: String] = [:]
		var roots: [String] = []
		for l in lines(sh("ps", ["-axco", "pid=,ppid=,comm="]).out) {
			let w = words(l)
			par[at(w, 0)] = at(w, 1)
			if at(w, 2) == "claude" { roots.append(at(w, 0)) }
		}
		guarded = below(roots, par)
	}

	func candidates(_ days: String, _ emit: Emit) throws {
		let days = days.isEmpty ? "\(stale)" : days
		watch()
		shield()

		for l in lines(sh("ps", ["-axo", "pid=,ppid=,rss=,etime=,command="]).out) {
			let v = fields(l, 4)
			let pid = v[0], ppid = v[1], rss = v[2], etime = v[3], cmd = v[4]
			if guarded.contains(pid) { continue }
			let age = secs(etime)
			if ["pnpm dlx", "npm exec", "uvx", " mcp", "mcp-server", "claude -p"].contains(where: { cmd.contains($0) }) {
				if ppid == "1" { emit(row("orphan", rss, "kill", pid, "parent gone: \(head(cmd, 80))", "processes")) }
			} else if cmd.contains("vite/bin") || cmd.contains("storybook") || cmd.hasSuffix("/air") || cmd.contains("go run") {
				guard age > 86400 else { continue }
				let dir = cwd(pid)
				if let last = moved(dir), now - last < idle * 3600 { continue }
				emit(row("stale", rss, "kill", pid, "dev server in \(dir) running \(etime), no claude work there for \(idle)h", "processes"))
			}
		}

		for pid in pids(["-x", "claude"]) {
			if sh("ps", ["-o", "tty=", "-p", pid]).out.filter({ $0 != " " && $0 != "\n" }) == "??" { continue }
			let dir = cwd(pid)
			guard let last = moved(dir) else { continue }
			if now - last > idle * 3600 {
				let rss = sh("ps", ["-o", "rss=", "-p", pid]).out.filter { $0 != " " && $0 != "\n" }
				emit(row("stale", rss, "kill", pid, "claude session in \(dir) idle \((now - last) / 3600)h", "processes"))
			}
		}

		if docker() {
			var ids = ""
			for l in lines(sh("docker", ["ps", "-a", "-f", "status=exited", "-f", "status=created", "--format", "{{.ID}}\\t{{.Label \"com.docker.compose.project.working_dir\"}}"]).out) {
				let t = cut(l, by: 9, keep: false)
				let dir = t.dropFirst().joined(separator: "\t")
				if !dir.isEmpty, inuse(dir) { continue }
				ids += at(t, 0) + " "
			}
			if !ids.isEmpty { emit(row("stale", "0", "run", "docker rm \(ids)", "stopped containers outside active projects", "docker")) }
			for l in lines(sh("docker", ["system", "df", "--format", "{{.Type}}\\t{{.Reclaimable}}"]).out) {
				let t = tabs(l)
				let v = at(cut(at(t, 1), by: 32), 0)
				let n = num(v)
				let kb = v.contains("GB") ? Int(n * 1048576) : v.contains("MB") ? Int(n * 1024) : Int(n)
				guard kb > 0 else { continue }
				if at(t, 0) == "Images" { emit(row("cache", "\(kb)", "run", "docker image prune -af", "unused docker images", "docker")) }
				if at(t, 0) == "Build Cache" { emit(row("cache", "\(kb)", "run", "docker builder prune -af", "docker build cache", "docker")) }
			}
			var spare: [(name: String, kb: Int)] = []
			for v in volumes() where Double(v.links) == 0 && hit(Work.hex, v.name) {
				var p = sh("docker", ["volume", "inspect", v.name, "--format", "{{index .Labels \"com.docker.compose.project\"}}"]).out
				while p.hasSuffix("\n") { p.removeLast() }
				if !p.isEmpty, let r = re("/" + p + "$"), active.contains(where: { hit(r, $0) }) { continue }
				spare.append((v.name, v.kb))
			}
			if !spare.isEmpty {
				emit(row("data", "\(spare.reduce(0) { $0 + $1.kb })", "run", "docker volume rm \(spare.map { $0.name + " " }.joined())",
					"\(spare.count) anonymous docker volumes no container uses, named project volumes are never listed", "docker volumes"))
			}
		}

		try tree()
		let builds = build(days, show: false)
		for b in builds where b.state == "stale" {
			if inuse(dirname(b.dir)) || tracked(b.dir) { continue }
			emit(row("stale", b.kb, "rm", b.dir, "build folder of a project untouched for \(days) days", "build folders"))
		}
		outputs(builds.filter { $0.state == "active" }, emit)

		worktrees(emit)

		let held = Set(lines(sh("lsof", ["-n", "-P", "-Fn"]).out).filter { starts($0, "n" + home + "/") }.map { String($0.dropFirst()) })
		let opened = { (path: String) in held.contains { starts($0, path + "/") } }
		let has = { (tool: String) in which(tool) != nil }
		let caches = [
			("\(home)/Library/Caches/go-build", "run", "go clean -cache -testcache", "go build cache", "package caches"),
			("\(home)/Library/pnpm/store", "run", "pnpm store prune", "pnpm store, packages no project links", "package caches"),
			("\(home)/Library/Caches/pnpm", "rm", "\(home)/Library/Caches/pnpm", "pnpm dlx and metadata cache", "package caches"),
			("\(home)/Library/Caches/Homebrew", "run", "brew cleanup --prune=all", "homebrew downloads", "package caches"),
			("\(home)/.npm", "run", "npm cache clean --force", "npm cache", "package caches"),
			("\(home)/Library/Caches/ms-playwright", "rm", "\(home)/Library/Caches/ms-playwright", "playwright browsers, reinstalled on demand", "browser caches"),
			("\(home)/Library/Caches/ms-playwright-mcp", "rm", "\(home)/Library/Caches/ms-playwright-mcp", "playwright mcp browsers, reinstalled on demand", "browser caches"),
			("\(home)/.cache/uv", "run", "uv cache clean", "uv package cache", "package caches"),
			("\(home)/Library/Developer/Xcode/DerivedData", "rm", "\(home)/Library/Developer/Xcode/DerivedData", "xcode derived data", "build folders"),
			("\(home)/.Trash", "run", "find \"\(home)/.Trash\" -mindepth 1 -maxdepth 1 -exec rm -rf {} +", "trash", "trash"),
			("\(home)/.cargo/registry", has("cargo-cache") ? "run" : "rm", has("cargo-cache") ? "cargo cache --autoclean" : "\(home)/.cargo/registry", "cargo registry, crates and their sources, downloaded again on the next build", "package caches"),
			("\(home)/.cargo/git", "rm", "\(home)/.cargo/git", "cargo git checkouts of dependencies, cloned again on the next build", "package caches"),
			("\(home)/go/pkg/mod", "run", "go clean -modcache", "go module cache", "package caches"),
			("\(home)/.gradle/caches", "rm", "\(home)/.gradle/caches", "gradle dependency and build cache", "package caches"),
			("\(home)/.m2/repository", "rm", "\(home)/.m2/repository", "maven local repository", "package caches"),
			("\(home)/Library/Caches/pip", "rm", "\(home)/Library/Caches/pip", "pip download and wheel cache", "package caches"),
			("\(home)/Library/Caches/pypoetry", "rm", "\(home)/Library/Caches/pypoetry", "poetry package cache", "package caches"),
			("\(home)/Library/Caches/CocoaPods", has("pod") ? "run" : "rm", has("pod") ? "pod cache clean --all" : "\(home)/Library/Caches/CocoaPods", "cocoapods pod and spec cache", "package caches"),
			("\(home)/.bun/install/cache", has("bun") ? "run" : "rm", has("bun") ? "bun pm cache rm" : "\(home)/.bun/install/cache", "bun package cache", "package caches"),
			("\(home)/Library/Caches/deno", has("deno") ? "run" : "rm", has("deno") ? "deno clean" : "\(home)/Library/Caches/deno", "deno module cache", "package caches"),
			("\(home)/Library/Caches/Yarn", "rm", "\(home)/Library/Caches/Yarn", "yarn package cache", "package caches"),
			("\(home)/.yarn/berry/cache", "rm", "\(home)/.yarn/berry/cache", "yarn berry package cache", "package caches"),
			("\(home)/.pub-cache", has("dart") ? "run" : "rm", has("dart") ? "dart pub cache clean --force" : "\(home)/.pub-cache", "dart and flutter package cache", "package caches"),
			("\(home)/.hex/packages", "rm", "\(home)/.hex/packages", "hex package cache", "package caches"),
			("\(home)/Library/Caches/org.swift.swiftpm", "rm", "\(home)/Library/Caches/org.swift.swiftpm", "swift package manager repository cache", "package caches"),
			("\(home)/Library/Caches/node-gyp", "rm", "\(home)/Library/Caches/node-gyp", "node-gyp headers, downloaded again on the next native build", "package caches"),
			("\(home)/Library/Caches/typescript", "rm", "\(home)/Library/Caches/typescript", "typescript type acquisition cache", "package caches"),
			("\(home)/Library/Caches/electron", "rm", "\(home)/Library/Caches/electron", "electron downloads", "package caches"),
			("\(home)/Library/Caches/electron-builder", "rm", "\(home)/Library/Caches/electron-builder", "electron-builder downloads", "package caches"),
			("\(home)/Library/Caches/ms-playwright-go", "rm", "\(home)/Library/Caches/ms-playwright-go", "playwright go browsers, reinstalled on demand", "browser caches"),
			("\(home)/Library/Caches/gopls", "rm", "\(home)/Library/Caches/gopls", "gopls index cache, rebuilt on its next start", "tool caches"),
			("\(home)/Library/Caches/golangci-lint", has("golangci-lint") ? "run" : "rm", has("golangci-lint") ? "golangci-lint cache clean" : "\(home)/Library/Caches/golangci-lint", "golangci-lint cache", "tool caches"),
			("\(home)/.cache/pre-commit", "rm", "\(home)/.cache/pre-commit", "pre-commit hook environments", "tool caches"),
			("\(home)/.gradle/wrapper/dists", "rm", "\(home)/.gradle/wrapper/dists", "gradle distributions the wrappers downloaded", "toolchains and images"),
			("\(home)/.konan", "rm", "\(home)/.konan", "kotlin native toolchains and caches", "toolchains and images"),
		]
		for (path, action, target, why, group) in caches {
			if loaded(path) || opened(path) { continue }
			guard exists(path) else { continue }
			let k = cached(path)
			if k > 102400 { emit(row("cache", "\(k)", action, target, why, group)) }
		}

		let named = Set(caches.map { $0.0 })
		let kept = re("^(com\\.apple\\.|slycbar|claude|cloudkit|geoservices|huggingface|torch|whisper|lm-studio|models)")
		for (root, group) in [("\(home)/.cache", "tool caches"), ("\(home)/Library/Caches", "app caches")] {
			for l in under(root, 1) {
				let v = fields(l, 1)
				let d = v[1]
				guard whole(v[0]) > 102400, folder(d), !named.contains(d), !hit(kept, basename(d).lowercased()) else { continue }
				if loaded(d) || opened(d) { continue }
				emit(row("cache", v[0], "rm", d, group == "app caches" ? "cache of \(basename(d)), no process holds a file in it, rebuilt when it runs next" : "\(basename(d)) cache, no process holds a file in it, rebuilt by its tool on the next run", group))
			}
		}

		for avd in glob("\(home)/.android/avd", ".avd") {
			let name = basename(avd, ".avd")
			if pgrep(["-f", "avd \(name)"]) { continue }
			let k = cached(avd)
			guard k > 1048576 else { continue }
			emit(row("data", "\(k)", "rm", avd, "android emulator \(name) and its saved state", "emulators"))
			emit(row("data", "0", "rm", String(avd.dropLast(4)) + ".ini", "android emulator \(name) entry", "emulators"))
		}
		let found = sh("find", [
			"\(home)/Downloads", "-maxdepth", "2", "-type", "f", "(", "-iname", "*.dmg", "-o", "-iname", "*.pkg", "-o", "-iname", "*.iso", "-o", "-iname", "*.zip",
			"-o", "-iname", "*.xip", "-o", "-iname", "*.apk", "-o", "-iname", "*.tar.gz", ")", "-size", "+100M", "-mmin", "+1440", "-print0",
		]).out
		for l in files(found) {
			let t = cut(l, by: 9, keep: false)
			emit(row("data", at(t, 0), "rm", t.dropFirst().joined(separator: "\t"), "installer in Downloads, older than a day", "installers"))
		}

		redundant(emit)
	}

	func worktrees(_ emit: Emit) {
		let recent = mark(DateComponents(hour: -idle))
		let old = mark(DateComponents(day: -unused))
		defer {
			drop(recent)
			drop(old)
		}
		for g in lines(sh("find", [projects, "-maxdepth", "3", "-name", ".git", "-type", "d", "-prune", "-print"]).out) {
			guard folder(g + "/worktrees") else { continue }
			let main = dirname(g)
			let tip = git(main, ["rev-parse", "--abbrev-ref", "HEAD"]).out
			var trees: [String] = []
			var t = "", b = "", p = "0"
			for l in lines(git(main, ["worktree", "list", "--porcelain"]).out) {
				if l.hasPrefix("worktree ") {
					t = String(l.utf8.dropFirst(9)) ?? ""
					b = ""
					p = "0"
				}
				if l.hasPrefix("branch ") {
					b = at(words(l), 1)
					if let r = b.range(of: "refs/heads/", options: .literal) { b.removeSubrange(r) }
				}
				if l.hasPrefix("prunable") { p = "1" }
				if l.isEmpty {
					if !t.isEmpty { trees.append("\(t)\t\(b)\t\(p)") }
					t = ""
				}
			}
			if !t.isEmpty { trees.append("\(t)\t\(b)\t\(p)") }
			for l in trees {
				let v = cut(l, by: 9, keep: false)
				let t = at(v, 0), b = at(v, 1), p = v.dropFirst(2).joined(separator: "\t")
				if t == main { continue }
				if p == "1" {
					emit(row("stale", "0", "run", "git -C \"\(main)\" worktree prune", "worktree records of \(basename(main)) whose folder is gone", "worktrees"))
					continue
				}
				guard folder(t), !b.isEmpty else { continue }
				if inuse(t) { continue }
				if !git(t, ["status", "--porcelain"]).out.isEmpty { continue }
				if !sh("find", [t, "-maxdepth", "2", "-newer", recent, "-print", "-quit"]).out.isEmpty { continue }
				var a = stat(), i = stat()
				let logs = git(t, ["rev-parse", "--git-dir"]).out + "/logs/HEAD"
				if stat(logs, &a) == 0, stat(recent, &i) != 0 || a.st_mtimespec.tv_sec > i.st_mtimespec.tv_sec { continue }
				if folder(main + "/.claude/tasks"), pending(main + "/.claude/tasks", t) { continue }
				let n = git(main, ["rev-list", "--count", "HEAD..\(b)"])
				let ahead = n.code == 0 ? n.out : n.out + "1"
				if ahead == "0" {
					emit(row("stale", "\(cached(t))", "run", "git -C \"\(main)\" worktree remove \"\(t)\"",
						"worktree of \(basename(main)), clean and every commit of its branch is on \(tip)", "worktrees"))
				} else if sh("find", ["-E", t, "(", "-type", "d", "-regex", ".*/(\(Work.artifacts))", "-prune", ")", "-o", "-type", "f", "-newer", old, "-print", "-quit"], limit: limit).out.isEmpty {
					emit(row("stale", "\(cached(t))", "run", "git -C \"\(main)\" worktree remove \"\(t)\"",
						"worktree of \(basename(main)), clean and untouched for \(unused) days, its branch keeps the commits", "worktrees"))
				}
			}
		}
	}

	func tracked(_ dir: String) -> Bool {
		!git(dir, ["ls-files", "--", "."]).out.isEmpty
	}

	func outputs(_ builds: [(kb: String, state: String, dir: String)], _ emit: Emit) {
		let ref = mark(DateComponents(day: -unused))
		defer { drop(ref) }
		let still = { (path: String) in sh("find", [path, "-newer", ref, "-print", "-quit"], limit: self.limit).out.isEmpty }
		for b in builds {
			let project = dirname(b.dir)
			let name = basename(b.dir)
			if inuse(project) || tracked(b.dir) { continue }
			if Work.caches.contains(name) {
				guard still(b.dir) else { continue }
				emit(row("cache", b.kb, "rm", b.dir, "\(name) cache of \(basename(project)), not written for \(unused) days, rebuilt on the next run", "build folders"))
			} else if name == ".next", folder(b.dir + "/cache") {
				let k = at(tabs(at(lines(size(b.dir + "/cache")), 0)), 0)
				guard whole(k) > 51200, still(b.dir + "/cache") else { continue }
				emit(row("cache", k, "rm", b.dir + "/cache", "next.js build cache of \(basename(project)), not written for \(unused) days, rebuilt on the next build", "build folders"))
			} else if name == "target", exists(project + "/Cargo.toml") {
				let cargo = which("cargo") != nil
				for p in ((try? FileManager.default.contentsOfDirectory(atPath: b.dir)) ?? []).sorted(by: before) {
					let d = b.dir + "/" + p
					guard folder(d) else { continue }
					guard still(d) else {
						let old = lines(sh("find", [d + "/incremental", "-mindepth", "1", "-maxdepth", "1", "-type", "d", "!", "-newer", ref]).out)
						guard !old.isEmpty else { continue }
						let k = at(tabs(lines(sh("du", ["-skc"] + old, limit: limit).out).last ?? ""), 0)
						guard whole(k) > 102400 else { continue }
						emit(row("stale", k, "run", "find \"\(d)/incremental\" -mindepth 1 -maxdepth 1 -type d -mtime +\(unused) -exec rm -rf {} +",
							"incremental data of \(old.count) crates in the rust \(p) build of \(basename(project)), not written for \(unused) days while that build is in use", "build folders"))
						continue
					}
					let k = at(tabs(at(lines(size(d)), 0)), 0)
					guard whole(k) > 102400 else { continue }
					let manifest = "cargo clean --manifest-path \"\(project)/Cargo.toml\""
					let why = "rust \(p) output of \(basename(project)), not written for \(unused) days while the project moved"
					if cargo, folder(d + "/.fingerprint") {
						emit(row("stale", k, "run", manifest + " --profile " + (p == "debug" ? "dev" : p), why, "build folders"))
					} else if cargo, p == "doc" {
						emit(row("stale", k, "run", manifest + " --doc", why, "build folders"))
					} else {
						emit(row("stale", k, "rm", d, why, "build folders"))
					}
				}
			}
		}
	}

	func pending(_ tasks: String, _ tree: String) -> Bool {
		var found = false
		for file in glob(tasks, ".md") {
			guard let d = FileManager.default.contents(atPath: file) else { return false }
			var s = "", r = ""
			for l in lines(String(decoding: d, as: UTF8.self)) {
				if l.hasPrefix("state:") { s = at(words(l), 1) }
				if l.hasPrefix("tree:") { r = at(words(l), 1) }
				if r == tree, !s.isEmpty, s != "served", s != "review", s != "done" { found = true }
			}
		}
		return found
	}

	func redundant(_ emit: Emit) {
		var dup: [String] = []
		for l in lines(sh("ps", ["-axo", "pid=,ppid=,rss=,etime=,command="]).out) {
			let v = fields(l, 4)
			guard v[1] == "1", starts(v[4], home + "/") || starts(v[4], "/opt/homebrew/") || starts(v[4], "/usr/local/") else { continue }
			dup.append("\(secs(v[3]))\t\(v[0])\t\(v[2])\t\(v[4])")
		}
		dup = ranked(dup)
		var count: [String: Int] = [:]
		for l in dup { count[at(tabs(l), 3), default: 0] += 1 }
		var seen: Set<String> = []
		for l in dup {
			let t = tabs(l)
			let cmd = at(t, 3), pid = at(t, 1)
			guard let n = count[cmd], n > 1, !seen.insert(cmd).inserted else { continue }
			if guarded.contains(pid) { continue }
			if !sh("lsof", ["-a", "-p", pid, "-iTCP", "-sTCP:ESTABLISHED", "-Fn"]).out.isEmpty { continue }
			emit(row("redundant", at(t, 2), "kill", pid, "one of \(n) instances of \(head(cmd, 60)), older than the newest and holding no open tcp connection", "processes"))
		}

		for app in glob("\(home)/Applications", ".app") + glob("/Applications", ".app") {
			let info = app + "/Contents/Resources/product-info.json"
			var d: ObjCBool = false
			guard FileManager.default.fileExists(atPath: info, isDirectory: &d), !d.boolValue else { continue }
			guard let data = FileManager.default.contents(atPath: info), let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
			guard var sel = json["dataDirectoryName"] as? String else { continue }
			while let c = sel.utf8.last, c == 46 || (c >= 48 && c <= 57) { sel.removeLast() }
			guard !sel.isEmpty else { continue }
			if pgrep(["-f", "--", app + "/"]) { continue }
			let lib = home + "/Library"
			if !sh("find", ["\(lib)/Application Support/JetBrains", "\(lib)/Caches/JetBrains", "\(lib)/Application Support/Google", "\(lib)/Caches/Google", "-maxdepth", "1", "-name", sel + "*", "-print", "-quit"]).out.isEmpty { continue }
			var k = "\(cached(app))"
			if cached(app) <= 0 { k = at(tabs(at(lines(size(app)), 0)), 0) }
			emit(row("redundant", k, "rm", app, "\(basename(app, ".app")) has no \(sel) settings or cache folder under Library, it was never opened", "applications"))
		}

		let big = sh("find", ["\(home)/.claude/projects", "-maxdepth", "2", "-type", "f", "-name", "*.jsonl", "-size", "+200M", "-mtime", "+\(unused)", "-print0"]).out
		for l in files(big) {
			let t = cut(l, by: 9, keep: false)
			emit(row("redundant", at(t, 0), "rm", t.dropFirst().joined(separator: "\t"), "claude transcript over 200M untouched for \(unused) days, its session can no longer be resumed", "transcripts"))
		}

		let bundles = "\(home)/Library/Application Support/Claude/vm_bundles"
		if folder(bundles), !pgrep(["-f", "vm_bundles"]) {
			let k = cached(bundles)
			if k > 102400 { emit(row("redundant", "\(k)", "rm", bundles, "claude desktop vm bundles, no running process names them", "toolchains and images")) }
		}

		if which("rustup") != nil {
			for l in lines(sh("rustup", ["toolchain", "list"]).out) where !l.contains("default") && !l.contains("active") {
				let t = at(words(l), 0)
				guard !t.isEmpty else { continue }
				let v = at(cut(t, by: 45), 0)
				if !sh("find", [projects, "-maxdepth", "4", "-name", "rust-toolchain*", "-exec", "grep", "-lF", v, "{}", "+"]).out.isEmpty { continue }
				emit(row("redundant", "\(cached("\(home)/.rustup/toolchains/\(t)"))", "run", "rustup toolchain uninstall \(t)",
					"rust toolchain \(t), not the default and named by no rust-toolchain file under \(projects)", "toolchains and images"))
			}
		}

		let images = "\(home)/Library/Android/sdk/system-images"
		if folder(images), !pgrep(["-f", "qemu-system|/emulator"]) {
			let k = cached(images)
			if k > 102400 {
				emit(row("redundant", "\(k)", "rm", images, "android system images, no emulator is running, an emulator downloads its image again before it starts", "toolchains and images"))
			}
		}

		dormant(emit)
	}

	func dormant(_ emit: Emit) {
		let ref = mark(DateComponents(day: -stale))
		defer { drop(ref) }
		var listed: [String] = []
		var casks: [(app: String, token: String)] = []
		if which("brew") != nil, let json = try? JSONSerialization.jsonObject(with: Data(sh("brew", ["info", "--cask", "--json=v2", "--installed"]).out.utf8)) as? [String: Any] {
			for cask in json["casks"] as? [[String: Any]] ?? [] {
				let token = cask["token"].map { "\($0)" } ?? ""
				for artifact in cask["artifacts"] as? [[String: Any]] ?? [] {
					for app in artifact["app"] as? [Any] ?? [] {
						if let name = app as? String { casks.append((basename(name), token)) }
					}
				}
			}
		}

		for app in glob("/Applications", ".app") + glob("\(home)/Applications", ".app") {
			guard folder(app) else { continue }
			if pgrep(["-f", "--", app + "/"]) { continue }
			let info = NSDictionary(contentsOfFile: app + "/Contents/Info.plist")
			guard let id = info?["CFBundleIdentifier"] as? String, let exe = info?["CFBundleExecutable"] as? String, !id.isEmpty, !exe.isEmpty else { continue }
			if id.hasPrefix("com.apple.") { continue }
			let name = basename(app, ".app")
			let lib = home + "/Library"
			let times = [stamp("\(app)/Contents/MacOS/\(exe)", read: true)] + [
				"\(lib)/Preferences/\(id).plist", "\(lib)/Saved Application State/\(id).savedState", "\(lib)/Caches/\(id)",
				"\(lib)/Containers/\(id)", "\(lib)/HTTPStorages/\(id)", "\(lib)/Application Support/\(name)",
			].map { stamp($0) }
			guard let last = times.compactMap({ $0 }).max(), now - last > stale * 86400 else { continue }
			let k = at(tabs(at(lines(size(app)), 0)), 0)
			let days = (now - last) / 86400
			if let cask = casks.first(where: { $0.app == name + ".app" })?.token, !cask.isEmpty {
				emit(row("redundant", k, "run", "brew uninstall --cask \(cask)", "application \(name), not opened for \(days) days, installed by homebrew", "applications"))
			} else if access(app, W_OK) == 0 {
				emit(row("redundant", k, "rm", app, "application \(name), not opened for \(days) days", "applications"))
			} else {
				emit(row("redundant", k, "run", "sudo rm -rf \"\(app)\"", "application \(name), not opened for \(days) days, owned by root", "applications"))
			}
		}

		let gits = lines(sh("find", [projects, "-maxdepth", "3", "-name", ".git", "-prune", "-print"]).out)
		for g in ranked(gits.map { "\($0.utf8.count)\t\($0)" }).map({ String($0[$0.index(after: $0.firstIndex(of: "\t")!)...]) }) {
			let d = dirname(g)
			if listed.contains(where: { starts(d + "/", $0 + "/") }) { continue }
			if inuse(d) { continue }
			let k = cached(d)
			guard k > 102400 else { continue }
			if !sh("find", ["-E", d, "(", "-type", "d", "-regex", ".*/(\(Work.artifacts))", "-prune", ")", "-o", "-type", "f", "-newer", ref, "-print", "-quit"], limit: limit).out.isEmpty { continue }
			listed.append(d)
			if !git(d, ["remote"]).out.isEmpty, git(d, ["status", "--porcelain"]).out.isEmpty,
				git(d, ["log", "--branches", "--not", "--remotes", "-1", "--format=%h"]).out.isEmpty, git(d, ["stash", "list"]).out.isEmpty {
				emit(row("redundant", "\(k)", "rm", d, "project folder untouched for \(stale) days, clean and every commit is on its remote", "projects"))
			} else {
				emit(row("data", "\(k)", "rm", d, "project folder untouched for \(stale) days, holds work that is on no remote", "unpushed projects"))
			}
		}

		for p in ["\(home)/Documents", "\(home)/Desktop", "\(home)/Downloads"] {
			for l in under(p, 1) {
				let v = fields(l, 1)
				let d = v[1]
				guard folder(d), whole(v[0]) > 102400 else { continue }
				if inuse(d) { continue }
				if !sh("find", [d, "-type", "f", "!", "-name", ".DS_Store", "(", "-newer", ref, "-o", "-atime", "-\(stale)", ")", "-print", "-quit"], limit: limit).out.isEmpty { continue }
				listed.append(d)
				emit(row("data", v[0], "rm", d, "folder with no file opened or changed for \(stale) days", "folders"))
			}
		}

		let found = sh("find", [
			home, "-xdev", "(", "-path", "\(home)/Library", "-o", "-name", ".?*", "-o", "-path", "\(home)/OrbStack", "-o", "-path", projects, "-o", "-name", "node_modules",
			"-o", "-name", "*.app", "-o", "-name", "*.photoslibrary", ")", "-prune", "-o", "-type", "f", "-size", "+100M", "-mtime", "+\(stale)", "-atime", "+\(stale)", "-print0",
		], limit: limit).out
		for l in files(found) {
			let t = cut(l, by: 9, keep: false)
			let d = t.dropFirst().joined(separator: "\t")
			if listed.contains(where: { starts(d, $0 + "/") }) { continue }
			if inuse(dirname(d)) { continue }
			emit(row("data", at(t, 0), "rm", d, "file over 100M not opened or changed for \(stale) days", "files"))
		}
	}
}
