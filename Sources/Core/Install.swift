import Foundation

enum Install {
	static func info(_ fields: [(String, String)]) -> String {
		var body = ""
		for (key, value) in fields {
			body += "  <key>\(key)</key>" + (value.hasPrefix("<") ? value : "<string>\(value)</string>") + "\n"
		}
		return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" \"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\n<plist version=\"1.0\"><dict>\n" + body + "</dict></plist>\n"
	}

	static func common(_ id: String, _ name: String, _ exe: String, _ type: String) -> [(String, String)] {
		[("CFBundleIdentifier", id), ("CFBundleName", name), ("CFBundleExecutable", exe), ("CFBundlePackageType", type), ("CFBundleShortVersionString", "1.0"),
			("CFBundleVersion", String(Int(Base.now))), ("CFBundleInfoDictionaryVersion", "6.0"), ("LSMinimumSystemVersion", "14.0")]
	}

	static func place(_ product: String, _ target: String) -> Bool {
		let fm = FileManager.default
		try? fm.createDirectory(atPath: (target as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
		try? fm.removeItem(atPath: target)
		return (try? fm.copyItem(atPath: Base.here + "/.build/release/" + product, toPath: target)) != nil
	}

	static func install() -> Int32 {
		let fm = FileManager.default
		var given: [String: String] = [:]
		for line in Base.read(Base.here + "/.env").split(separator: "\n") {
			let pair = line.split(separator: "=", maxSplits: 1).map(String.init)
			if pair.count == 2, !pair[0].hasPrefix("#"), !pair[1].isEmpty {
				given[pair[0]] = pair[1]
			}
		}
		let sign = "slyed"
		guard Base.run("/usr/bin/security", ["find-identity", "-p", "codesigning"]).out.contains("\"" + sign + "\"") else { return Base.fail("no code signing identity named " + sign + " in the keychain") }
		let carried = given.keys.sorted().map { "<key>" + $0 + "</key><string>" + (given[$0] ?? "") + "</string>" }.joined()
		let schemes = { (names: [String]) in "<array>" + names.map { "<dict><key>CFBundleURLName</key><string>\($0)</string><key>CFBundleURLSchemes</key><array><string>\($0)</string></array></dict>" }.joined() + "</array>" }
		guard Base.run("/usr/bin/swift", ["build", "-c", "release"], dir: Base.here, quiet: false).code == 0 else { return Base.fail("the build failed") }
		guard Base.run("pnpm", ["--version"]).code == 0 else { return Base.fail("pnpm is missing, the editor page needs it") }

		try? fm.removeItem(atPath: Base.editApp)
		let ext = Base.editApp + "/Contents/PlugIns/widget.appex"
		guard place("widget", ext + "/Contents/MacOS/widget"), place("slyed", Base.editApp + "/Contents/MacOS/slyed") else { return Base.fail("a built product is missing under .build/release") }
		Base.write(ext + "/Contents/Info.plist", info(common("slycbar.slyed.widget", "Slyed", "widget", "XPC!") + [("CFBundleDisplayName", "Slyed"),
			("NSExtension", "<dict><key>NSExtensionPointIdentifier</key><string>com.apple.widgetkit-extension</string></dict>")]))
		let types = "<array>\n    <dict><key>CFBundleTypeName</key><string>Text</string><key>CFBundleTypeRole</key><string>Editor</string><key>LSHandlerRank</key><string>Default</string>\n      <key>LSItemContentTypes</key><array><string>public.text</string><string>public.source-code</string><string>public.script</string><string>public.json</string><string>public.xml</string><string>public.yaml</string></array></dict>\n    <dict><key>CFBundleTypeName</key><string>File</string><key>CFBundleTypeRole</key><string>Editor</string><key>LSHandlerRank</key><string>Alternate</string>\n      <key>LSItemContentTypes</key><array><string>public.data</string><string>public.folder</string></array></dict>\n  </array>"
		Base.write(Base.editApp + "/Contents/Info.plist", info(common("slycbar.slyed", "Slyed", "slyed", "APPL") + [("SlycbarCli", Base.bin), ("LSUIElement", "<true/>"), ("LSEnvironment", "<dict>" + carried + "</dict>"), ("CFBundleURLTypes", schemes(["slyed", "slycbar"])),
			("NSHighResolutionCapable", "<true/>"), ("CFBundleIconFile", "icon"), ("CFBundleDocumentTypes", types)]))

		try? fm.createDirectory(atPath: Base.editApp + "/Contents/Resources", withIntermediateDirectories: true)
		for name in ["warp.html", "celery.html", "celery.m4a", "editor/icon.png", "editor/tray.svg"] {
			try? fm.copyItem(atPath: Base.here + "/" + name, toPath: Base.editApp + "/Contents/Resources/" + (name as NSString).lastPathComponent)
		}

		let build = Base.cache + "/editor/build"
		try? fm.createDirectory(atPath: build, withIntermediateDirectories: true)
		for name in ["package.json", "pnpm-lock.yaml", "pnpm-workspace.yaml", "vite.config.js", "index.html", "main.js", "icon.svg"] {
			Base.write(build + "/" + name, Base.read(Base.here + "/editor/" + name))
		}
		try? fm.removeItem(atPath: build + "/components-nimtech")
		try? fm.copyItem(atPath: Base.here + "/editor/components-nimtech", toPath: build + "/components-nimtech")
		try? fm.removeItem(atPath: build + "/fonts")
		try? fm.copyItem(atPath: Base.here + "/editor/fonts", toPath: build + "/fonts")
		guard Base.run("pnpm", ["install", "--frozen-lockfile"], dir: build).code == 0, Base.run("pnpm", ["build"], dir: build).code == 0 else { return Base.fail("the editor page did not build") }
		try? fm.copyItem(atPath: build + "/dist", toPath: Base.editApp + "/Contents/Resources/editor")
		try? fm.copyItem(atPath: Base.here + "/editor/servers.json", toPath: Base.editApp + "/Contents/Resources/editor/servers.json")
		let set = Base.cache + "/icon.iconset"
		try? fm.removeItem(atPath: set)
		try? fm.createDirectory(atPath: set, withIntermediateDirectories: true)
		for size in [16, 32, 128, 256, 512] {
			Base.run("/usr/bin/sips", ["-z", String(size), String(size), Base.here + "/editor/icon.png", "--out", set + "/icon_\(size)x\(size).png"])
			Base.run("/usr/bin/sips", ["-z", String(size * 2), String(size * 2), Base.here + "/editor/icon.png", "--out", set + "/icon_\(size)x\(size)@2x.png"])
		}
		Base.run("/usr/bin/iconutil", ["-c", "icns", set, "-o", Base.editApp + "/Contents/Resources/icon.icns"])

		let rights = Base.cache + "/widget.entitlements"
		Base.write(rights, info([("com.apple.security.app-sandbox", "<true/>"), ("com.apple.security.temporary-exception.files.home-relative-path.read-only", "<array><string>/.cache/slycbar/</string></array>")]))
		Base.run("/usr/bin/codesign", ["-f", "-s", sign, "--entitlements", rights, ext])
		Base.run("/usr/bin/codesign", ["-f", "-s", sign, Base.editApp])
		let register = "/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister"
		Base.run(register, ["-f", Base.editApp])
		Base.run("/usr/bin/pluginkit", ["-a", ext])
		Base.run(Base.editApp + "/Contents/MacOS/slyed", ["default"], quiet: false)

		try? fm.createDirectory(atPath: (Base.bin as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
		try? fm.removeItem(atPath: Base.bin)
		try? fm.createSymbolicLink(atPath: Base.bin, withDestinationPath: Base.here + "/.build/release/slybar")
		try? fm.createDirectory(atPath: Base.home + "/.slycbar", withIntermediateDirectories: true)
		Base.write(Base.home + "/.slycbar/home", Base.here + "\n")

		try? fm.createDirectory(atPath: (Base.plist as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
		Base.write(Base.plist, info([("Label", Base.agent),
			("ProgramArguments", "<array><string>\(Base.editApp)/Contents/MacOS/slyed</string><string>tray</string></array>"),
			("EnvironmentVariables", "<dict><key>PATH</key><string>\(Base.tools()["PATH"] ?? "")</string>" + carried + "</dict>"), ("RunAtLoad", "<true/>"),
			("KeepAlive", "<dict><key>SuccessfulExit</key><false/></dict>"), ("LimitLoadToSessionType", "Aqua"), ("ProcessType", "Interactive"),
			("StandardOutPath", Base.tray + "/tray.log"), ("StandardErrorPath", Base.tray + "/tray.log")]))
		let domain = "gui/\(getuid())"
		Base.run("/bin/launchctl", ["bootout", domain + "/" + Base.agent])
		if let pid = pid_t(Base.read(Base.tray + "/pid").trimmingCharacters(in: .whitespacesAndNewlines)), Tools.running() {
			kill(pid, SIGTERM)
		}
		for _ in 0..<50 where Base.run("/bin/launchctl", ["print", domain + "/" + Base.agent]).code == 0 {
			Thread.sleep(forTimeInterval: 0.2)
		}
		Base.run("/bin/launchctl", ["bootstrap", domain, Base.plist])
		Base.say("installed \(Base.editApp), \(Base.bin) and \(Base.plist)")
		return 0
	}
}
