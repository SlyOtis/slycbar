import Foundation
import Space

enum Guard {
	static func run() -> Int32 {
		let input = Base.parse(String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self)) ?? [:]
		let event = input["hook_event_name"] as? String ?? ""
		let tool = input["tool_name"] as? String ?? ""
		let sid = input["session_id"] as? String ?? ""
		let cwd = input["cwd"] as? String ?? ""
		let fields = input["tool_input"] as? Json ?? [:]
		let path = fields["file_path"] as? String ?? fields["notebook_path"] as? String ?? ""
		var texts = [fields["content"], fields["new_string"], fields["new_source"]].compactMap { $0 as? String }
		texts += (fields["edits"] as? [Json] ?? []).compactMap { $0["new_string"] as? String }
		let bytes = texts.reduce(0) { $0 + $1.utf8.count }
		if event == "PreToolUse" {
			guard let checks = Space.check(path: path.isEmpty ? Base.home : path, bytes: bytes) else { return Base.fail("slybar guard: the machine could not be read") }
			let over = checks.filter { $0.over }.map { c in
				c.name == "disk" ? "disk \(c.value)M free (limit \(c.limit)M)" : "\(c.name) \(c.value)% used (limit \(c.limit)%)"
			}.joined(separator: ", ")
			if !over.isEmpty {
				if !path.isEmpty, checks.contains(where: { $0.name == "disk" && $0.over }) {
					let reason = "slybar guard: writing \(path) is refused, \(over). Nothing is written until space is freed: run slybar space candidates | slybar space free and hand its groups to the user."
					Base.say(Base.text(["hookSpecificOutput": ["hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": reason]] as Json))
					return 0
				}
				let told = (Base.env["TMPDIR"] ?? "/tmp") + "/space-n-resources.told." + (sid.isEmpty ? "none" : sid)
				let minutes = Double(Base.env["SPACE_TOLD_MIN"] ?? "") ?? 10
				if Base.now - Base.modified(told) > minutes * 60 {
					Base.write(told, "")
					let context = "slybar guard: the machine is over its limit, \(over). Before starting more work run slybar space running | slybar space free for what can be killed and slybar space candidates | slybar space free for what frees storage, and hand the groups to the user as the space-n-resources skill says."
					Base.say(Base.text(["hookSpecificOutput": ["hookEventName": "PreToolUse", "additionalContext": context]] as Json))
				}
			}
			if !path.isEmpty {
				return 0
			}
		}
		guard !sid.isEmpty else { return 0 }
		_ = Space.run(["log", event, tool.isEmpty ? "session" : tool, sid, cwd])
		return 0
	}
}
