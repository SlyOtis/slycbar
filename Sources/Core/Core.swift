import Foundation

public enum Core {
	static let usage = "usage: slybar open|state|refresh [email]|use <email>|login|forget <email>|resources|scan|free <target>...|warp [email] [display]|changes <path> [display]|widget|edit <path> [line] [end]|server <path> [install]|plugin install|status|install|guard|statusline|space <command>"

	public static func run(_ args: [String]) -> Int32 {
		Base.prepare()
		let rest = Array(args.dropFirst())
		switch args.first ?? "" {
		case "open": return Tools.open()
		case "state": return State.state()
		case "refresh": return Accounts.refresh(rest.first ?? "")
		case "use": return rest.isEmpty ? Base.fail(usage, 2) : Accounts.use(rest[0])
		case "login": return Accounts.login()
		case "forget": return rest.isEmpty ? Base.fail(usage, 2) : Accounts.forget(rest[0])
		case "resources": return State.resources()
		case "scan": return State.space()
		case "free": return State.free(rest)
		case "warp": return Warp.warp(rest.first ?? "", rest.count > 1 ? rest[1] : "1")
		case "changes": return rest.isEmpty ? Base.fail(usage, 2) : Warp.changes(rest[0], rest.count > 1 ? rest[1] : "1")
		case "widget": return Tools.widget()
		case "edit": return Tools.edit(rest)
		case "server": return Tools.server(rest)
		case "plugin": return Tools.plugin(rest.first ?? "status")
		case "guard": return Guard.run()
		case "install": return Install.install()
		default: return Base.fail(usage, 2)
		}
	}
}
