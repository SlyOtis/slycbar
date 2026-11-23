import Foundation

enum Accounts {
	static func secret(_ service: String, _ account: String? = nil) -> String? {
		let found = Base.run("/usr/bin/security", ["find-generic-password", "-s", service] + (account.map { ["-a", $0] } ?? []) + ["-w"])
		return found.code == 0 ? found.out.trimmingCharacters(in: .newlines) : nil
	}

	static func keep(_ service: String, _ account: String, _ value: String) {
		let hex = Data(value.utf8).map { String(format: "%02x", $0) }.joined()
		Base.run("/usr/bin/security", ["-i"], input: "add-generic-password -U -a \"\(account)\" -s \"\(service)\" -X \(hex)\n")
	}

	static func owner() -> String {
		for line in Base.run("/usr/bin/security", ["find-generic-password", "-s", Base.main]).out.split(separator: "\n") {
			let text = line.trimmingCharacters(in: .whitespaces)
			if text.hasPrefix("\"acct\"<blob>=\""), text.hasSuffix("\"") {
				return String(text.dropFirst(14).dropLast())
			}
		}
		return ""
	}

	static func active() -> String {
		(Base.json(Base.config)["oauthAccount"] as? Json)?["emailAddress"] as? String ?? ""
	}

	static func name(_ email: String) -> String {
		(Base.json(Base.tray + "/accounts.json")[email] as? Json)?["name"] as? String ?? email
	}

	static func mark(_ email: String) {
		Base.write(Base.tray + "/active", name(email) + "\n" + email + "\n")
	}

	static func remember(_ email: String, _ oauth: Json, _ account: Json) {
		keep(Base.store, email, Base.text(["claudeAiOauth": oauth, "oauthAccount": account]))
		Base.edit(Base.tray + "/accounts.json") {
			$0[email] = ["name": account["displayName"] as? String ?? account["fullName"] as? String ?? email,
				"org": account["organizationName"] as? String ?? "", "plan": account["planDisplayName"] as? String ?? ""]
		}
	}

	static func switched(_ email: String) {
		guard !email.isEmpty else { return }
		let path = Base.tray + "/switches"
		let last = Base.read(path).split(separator: "\n").last.map(String.init) ?? ""
		if last.split(separator: " ", maxSplits: 1).dropFirst().first.map(String.init) != email {
			Base.write(path, Base.read(path) + "\(Int(Base.now)) \(email)\n")
		}
	}

	static func ask(_ path: String, _ token: String) -> (code: Int, text: String) {
		Base.get(Base.api + "/" + path, headers: ["Authorization": "Bearer " + token, "anthropic-beta": "oauth-2025-04-20"])
	}

	static func profile(_ token: String) -> Json? {
		let reply = ask("profile", token)
		guard reply.code == 200, let all = Base.parse(reply.text) else { return nil }
		let account = all["account"] as? Json ?? [:]
		let org = all["organization"] as? Json ?? [:]
		return ["accountUuid": account["uuid"] ?? NSNull(), "emailAddress": account["email"] ?? NSNull(), "displayName": account["display_name"] ?? NSNull(),
			"fullName": account["full_name"] ?? NSNull(), "organizationUuid": org["uuid"] ?? NSNull(), "organizationName": org["name"] ?? NSNull(),
			"planDisplayName": org["plan_display_name"] ?? NSNull()]
	}

	static func save() -> String {
		guard let oauth = secret(Base.main).flatMap(Base.parse)?["claudeAiOauth"] as? Json else { return "" }
		var email = active()
		var fresh = ""
		let known = (secret(Base.store, email).flatMap(Base.parse)?["claudeAiOauth"] as? Json)?["refreshToken"] as? String ?? ""
		if email.isEmpty || known != oauth["refreshToken"] as? String {
			var account = profile(oauth["accessToken"] as? String ?? "")
			if account == nil {
				guard !known.isEmpty, let stored = Base.json(Base.config)["oauthAccount"] as? Json else { return "" }
				account = stored
			}
			if account?["emailAddress"] as? String == email, let stored = Base.json(Base.config)["oauthAccount"] as? Json {
				account = stored
			}
			guard let account, let found = account["emailAddress"] as? String else { return "" }
			email = found
			remember(email, oauth, account)
			fresh = email
		}
		switched(email)
		mark(email)
		return fresh
	}

	static func usage(_ email: String, _ change: (inout Json) -> Void) {
		Base.edit(Base.tray + "/usage.json") {
			var row = $0[email] as? Json ?? [:]
			change(&row)
			$0[email] = row
		}
	}

	static func token(_ email: String) -> String? {
		guard let text = secret(Base.store, email), var stored = Base.parse(text), var oauth = stored["claudeAiOauth"] as? Json else { return nil }
		let now = Base.now
		let exp = oauth["expiresAt"] as? Double ?? 0
		let access = oauth["accessToken"] as? String
		if exp > (now + 1800) * 1000 {
			usage(email) { $0["due"] = Int(exp / 1000 - 1800) }
			return access
		}
		let row = Base.json(Base.tray + "/usage.json")[email] as? Json ?? [:]
		if (row["retry"] as? Double ?? 0) > now {
			return exp > now * 1000 ? access : nil
		}
		let body = Base.text(["grant_type": "refresh_token", "refresh_token": oauth["refreshToken"] ?? "", "client_id": Base.client])
		let reply = Base.get(Base.token, headers: ["Content-Type": "application/json"], body: Data(body.utf8))
		guard reply.code == 200, let fresh = Base.parse(reply.text), let next = fresh["access_token"] as? String else {
			usage(email) {
				let wait = min(($0["wait"] as? Double ?? 150) * 2, 3600)
				$0["wait"] = Int(wait)
				$0["retry"] = Int(now + wait)
				$0["error"] = reply.code == 400 || reply.code == 401 ? "login" : "token"
			}
			return exp > now * 1000 ? access : nil
		}
		oauth["accessToken"] = next
		oauth["refreshToken"] = fresh["refresh_token"] ?? oauth["refreshToken"] ?? NSNull()
		let expires = (now.rounded(.down) + (fresh["expires_in"] as? Double ?? 0)) * 1000
		oauth["expiresAt"] = Int(expires)
		stored["claudeAiOauth"] = oauth
		keep(Base.store, email, Base.text(stored))
		usage(email) {
			$0["retry"] = nil
			$0["wait"] = nil
			$0["due"] = Int(expires / 1000 - 1800)
		}
		return next
	}

	static func stamp(_ value: Any?) -> Any {
		guard var text = value as? String else { return NSNull() }
		if let dot = text.firstIndex(of: "."), let zone = text[dot...].firstIndex(where: { $0 == "+" || $0 == "Z" || $0 == "-" }) {
			text.removeSubrange(dot..<zone)
		}
		let format = ISO8601DateFormatter()
		return format.date(from: text).map { Int($0.timeIntervalSince1970) as Any } ?? NSNull()
	}

	static func slot(_ value: Any?, _ key: String) -> Any {
		guard let all = value as? Json else { return NSNull() }
		return ["pct": all[key] ?? NSNull(), "reset": stamp(all["resets_at"])] as Json
	}

	static func poll(_ email: String) {
		let token = email == active() ? (secret(Base.main).flatMap(Base.parse)?["claudeAiOauth"] as? Json)?["accessToken"] as? String : Accounts.token(email)
		guard let token, !token.isEmpty else {
			usage(email) { $0["error"] = $0["error"] as? String ?? "token" }
			return
		}
		let reply = ask("usage", token)
		guard reply.code == 200, let all = Base.parse(reply.text) else {
			usage(email) { $0["error"] = "http \(reply.code)" }
			return
		}
		let scoped = (all["limits"] as? [Json] ?? []).first { ((($0["scope"] as? Json)?["model"] as? Json)?["display_name"] as? String) == "Fable" }
		var credits: Any = NSNull()
		if let extra = all["extra_usage"] as? Json, extra["is_enabled"] as? Bool == true {
			credits = ["pct": extra["utilization"] ?? NSNull(), "used": extra["used_credits"] ?? NSNull(), "limit": extra["monthly_limit"] ?? NSNull(),
				"currency": extra["currency"] as? String ?? "USD", "places": extra["decimal_places"] ?? 2] as Json
		}
		usage(email) {
			$0 = ["five": slot(all["five_hour"], "utilization"), "seven": slot(all["seven_day"], "utilization"), "fable": slot(scoped, "percent"),
				"credits": credits, "at": Int(Base.now), "error": NSNull(), "retry": $0["retry"] ?? NSNull(), "wait": $0["wait"] ?? NSNull(), "due": $0["due"] ?? NSNull()]
		}
	}

	static func sync() {
		guard Base.lock(wait: false) else { return }
		let email = save()
		if !email.isEmpty {
			poll(email)
		}
		Base.unlock()
	}

	static func refresh(_ only: String) -> Int32 {
		_ = Base.lock(wait: true)
		defer { Base.unlock() }
		_ = save()
		for email in only.isEmpty ? Base.json(Base.tray + "/accounts.json").keys.sorted() : [only] {
			poll(email)
		}
		return 0
	}

	static func use(_ email: String) -> Int32 {
		_ = Base.lock(wait: true)
		defer { Base.unlock() }
		guard let stored = secret(Base.store, email).flatMap(Base.parse) else { return Base.fail("no stored login for \(email)") }
		if email == active() {
			return 0
		}
		_ = save()
		var main = secret(Base.main).flatMap(Base.parse) ?? [:]
		main["claudeAiOauth"] = stored["claudeAiOauth"] ?? NSNull()
		let user = owner()
		keep(Base.main, user.isEmpty ? NSUserName() : user, Base.text(main))
		Base.edit(Base.config) { $0["oauthAccount"] = stored["oauthAccount"] ?? NSNull() }
		switched(email)
		mark(email)
		poll(email)
		return 0
	}

	static func items() -> Set<String> {
		var found: Set<String> = []
		for line in Base.run("/usr/bin/security", ["dump-keychain"]).out.split(separator: "\n") {
			let text = line.trimmingCharacters(in: .whitespaces)
			if text.hasPrefix("\"svce\"<blob>=\"Claude Code-credentials-"), text.hasSuffix("\"") {
				found.insert(String(text.dropFirst(14).dropLast()))
			}
		}
		return found
	}

	static func login() -> Int32 {
		let dir = Base.tray + "/login"
		try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
		let before = items()
		let main = secret(Base.main)
		var env = Base.tools()
		env["CLAUDE_CONFIG_DIR"] = dir
		let task = Process()
		task.executableURL = URL(fileURLWithPath: "/usr/bin/env")
		task.arguments = ["claude", "auth", "login", "--claudeai"]
		task.environment = env
		try? task.run()
		task.waitUntilExit()
		let item = items().subtracting(before).sorted().first
		var stored: Json?
		if FileManager.default.fileExists(atPath: dir + "/.credentials.json") {
			stored = Base.json(dir + "/.credentials.json")
		} else if let item {
			stored = secret(item).flatMap(Base.parse)
		} else if let now = secret(Base.main), Base.text(Base.parse(now)?["claudeAiOauth"] ?? NSNull()) != Base.text(main.flatMap(Base.parse)?["claudeAiOauth"] ?? NSNull()) {
			stored = Base.parse(now)
			if let main {
				keep(Base.main, owner(), main)
			}
		}
		guard let oauth = stored?["claudeAiOauth"] as? Json else { return Base.fail("the login wrote no credentials slycbar can find") }
		var account = Base.json(dir + "/.claude.json")["oauthAccount"] as? Json
		if account == nil {
			account = profile(oauth["accessToken"] as? String ?? "")
		}
		guard let account, let email = account["emailAddress"] as? String else { return Base.fail("profile lookup failed") }
		_ = Base.lock(wait: true)
		defer { Base.unlock() }
		remember(email, oauth, account)
		if let item {
			Base.run("/usr/bin/security", ["delete-generic-password", "-s", item])
		}
		Base.write(dir + "/.claude.json", "{}")
		try? FileManager.default.removeItem(atPath: dir + "/.credentials.json")
		poll(email)
		Base.say("added \(email)")
		return 0
	}

	static func forget(_ email: String) -> Int32 {
		_ = Base.lock(wait: true)
		defer { Base.unlock() }
		if email == active() {
			return Base.fail("switch away from \(email) before forgetting it")
		}
		Base.run("/usr/bin/security", ["delete-generic-password", "-s", Base.store, "-a", email])
		Base.edit(Base.tray + "/accounts.json") { $0[email] = nil }
		Base.edit(Base.tray + "/usage.json") { $0[email] = nil }
		return 0
	}
}
