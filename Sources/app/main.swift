import AppKit
import WidgetKit

final class Launcher: NSObject, NSApplicationDelegate {
	var asked = false

	func tray() {
		guard let script = Bundle.main.object(forInfoDictionaryKey: "SlycbarCli") as? String else { return }
		let task = Process()
		task.executableURL = URL(fileURLWithPath: script)
		task.arguments = ["open"]
		task.standardOutput = FileHandle.nullDevice
		task.standardError = FileHandle.nullDevice
		try? task.run()
	}

	func leave() {
		DispatchQueue.main.asyncAfter(deadline: .now() + 1) { NSApp.terminate(nil) }
	}

	func application(_ application: NSApplication, open urls: [URL]) {
		asked = true
		if urls.contains(where: { $0.host == "reload" }) {
			WidgetCenter.shared.reloadAllTimelines()
		} else {
			tray()
		}
		leave()
	}

	func applicationDidFinishLaunching(_ notification: Notification) {
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
			guard !self.asked else { return }
			self.tray()
			self.leave()
		}
	}
}

let launcher = Launcher()
NSApplication.shared.delegate = launcher
NSApplication.shared.run()
