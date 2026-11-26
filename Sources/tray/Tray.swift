import AppKit
import SwiftUI
import WebKit

struct Reading: Decodable {
	struct Slot: Decodable {
		let pct: Double?
		let reset: Double?
	}
	struct Credits: Decodable {
		let pct: Double?
		let used: Double?
		let limit: Double?
		let currency: String?
		let places: Double?
	}
	struct Account: Decodable, Identifiable {
		let email: String
		let name: String?
		let plan: String?
		let active: Bool
		let five: Slot?
		let seven: Slot?
		let fable: Slot?
		let credits: Credits?
		let at: Double?
		let error: String?
		let retry: Double?
		let due: Double?
		var id: String { email }
	}
	struct Last: Decodable {
		let dir: String?
		let model: String?
		let cost: Double?
		let ctx: Double?
	}
	struct Session: Decodable {
		let pid: Int
		let status: String?
	}
	struct Check: Decodable {
		let name: String
		let value: Double
		let limit: Double
		let over: Bool
	}
	struct Row: Decodable {
		let kb: Double?
		let action: String?
		let target: String?
		let why: String?
		let group: String?
		let cpu: Double?
	}
	struct Resources: Decodable {
		let check: [Check]
		let agents: Double?
		let rows: [Row]
	}
	struct Space: Decodable {
		let at: Double?
		let scanning: Bool?
		let rows: [Row]
	}
	let accounts: [Account]?
	let bar: Last?
	let sessions: [Session]?
	let resources: Resources?
	let space: Space?
}

enum Ask {
	case free([String]), space, use(String), forget(String), warp(String), celery, edit, login, refresh, fit
}

struct Tip: Equatable {
	let id: String
	let why: String
	let cmd: String
	let box: CGRect
}

final class Model: ObservableObject {
	@Published var reading = try! JSONDecoder().decode(Reading.self, from: Data("{}".utf8))
	@Published var activating = ""
	@Published var refreshing: Set<String> = []
	@Published var going: Set<String> = []
	@Published var closed: [String: Bool] = ["accounts": UserDefaults.standard.bool(forKey: "closed.accounts"), "resources": UserDefaults.standard.bool(forKey: "closed.resources")]
	@Published var tip: Tip?
	@Published var now = Date()
	@Published var height = 0.0
	var send: (Ask) -> Void = { _ in }

	func toggle(_ group: String) {
		closed[group] = !(closed[group] ?? false)
		UserDefaults.standard.set(closed[group], forKey: "closed." + group)
		send(.fit)
	}

	func free(_ targets: [String]) {
		going.formUnion(targets)
		send(.free(targets))
	}
}

enum Ink {
	static let fg = Color.white.opacity(0.92)
	static let dim = Color.white.opacity(0.66)
	static let line = Color.white.opacity(0.08)
	static let hover = Color.white.opacity(0.1)
	static let accent = Color(red: 0.706, green: 0.388, blue: 0.184)
	static let ok = Color(red: 0.247, green: 0.604, blue: 0.353)
	static let warn = Color(red: 0.788, green: 0.541, blue: 0.106)
	static let bad = Color(red: 0.788, green: 0.29, blue: 0.227)
}

func left(_ reset: Double, _ now: Date) -> String {
	let s = Int(max(0, reset - now.timeIntervalSince1970))
	let d = s / 86400, h = s % 86400 / 3600, m = s % 3600 / 60
	return d > 0 ? "\(d)d \(h)h" : "\(h)h \(m)m"
}

func ago(_ seconds: Double) -> String {
	let s = Int(max(0, seconds))
	return s >= 86400 ? "\(s / 86400)d \(s % 86400 / 3600)h" : s >= 3600 ? "\(s / 3600)h \(s % 3600 / 60)m" : "\(s / 60)m"
}

func when(_ reset: Double) -> String {
	let format = DateFormatter()
	format.setLocalizedDateFormatFromTemplate("EEE HH:mm")
	return format.string(from: Date(timeIntervalSince1970: reset))
}

func size(_ kb: Double) -> String {
	kb >= 1048576 ? String(format: "%.1fG", kb / 1048576) : kb >= 1024 ? "\(Int((kb / 1024).rounded()))M" : kb > 0 ? "\(Int(kb))k" : ""
}

func num(_ v: Double) -> String {
	v == v.rounded() ? String(Int(v)) : String(v)
}

func money(_ v: Double, _ c: Reading.Credits) -> String {
	let format = NumberFormatter()
	format.numberStyle = .currency
	format.currencyCode = c.currency ?? "USD"
	return format.string(from: NSNumber(value: v / pow(10, c.places ?? 2))) ?? ""
}

func tone(_ pct: Double?) -> Color? {
	guard let pct else { return nil }
	return pct >= 90 ? Ink.bad : pct >= 70 ? Ink.warn : nil
}

struct Hover<Content: View>: View {
	@State private var over = false
	@ViewBuilder let content: (Bool) -> Content

	var body: some View {
		content(over).onHover { over = $0 }
	}
}

struct Track: View {
	let part: Double
	let color: Color
	var faded = false

	var body: some View {
		GeometryReader { box in
			ZStack(alignment: .leading) {
				Capsule().fill(Ink.hover)
				Capsule().fill(color).opacity(faded ? 0.45 : 1).frame(width: box.size.width * min(1, max(0, part)))
			}
		}
		.frame(height: 5)
	}
}

struct Pill: View {
	let title: String
	let action: () -> Void

	var body: some View {
		Hover { over in
			Button(action: action) {
				Text(title)
					.foregroundStyle(over ? Ink.bad : Ink.dim)
					.padding(.horizontal, 8)
					.overlay(Capsule().strokeBorder(over ? Ink.bad : Ink.line, lineWidth: 1))
					.contentShape(Capsule())
			}
			.buttonStyle(.plain).focusable(false)
		}
		.fixedSize()
	}
}

struct Cross: View {
	let ask: String?
	let action: () -> Void

	var mark: some View {
		Hover { over in
			Text("×").font(.system(size: 13)).foregroundStyle(over ? Ink.bad : Ink.dim).padding(.horizontal, 2).contentShape(Rectangle())
				.onTapGesture(count: ask == nil ? 1 : 2, perform: action)
		}
		.fixedSize()
	}

	var body: some View {
		if let ask {
			mark.help(ask)
		} else {
			mark
		}
	}
}

struct Round<Mark: View>: View {
	let tint: Color
	let tip: String
	let action: () -> Void
	@ViewBuilder let mark: () -> Mark

	var body: some View {
		Hover { over in
			Button(action: action) {
				mark()
					.foregroundStyle(over ? tint : Ink.dim)
					.frame(width: 24, height: 24)
					.background(Circle().fill(over ? Ink.hover : Color.clear))
					.overlay(Circle().strokeBorder(Ink.line, lineWidth: 1))
					.contentShape(Circle())
			}
			.buttonStyle(.plain).focusable(false)
		}
		.help(tip)
	}
}

struct Dot: View {
	let on: Bool

	var body: some View {
		Circle().fill(on ? Ink.accent : Color.clear).overlay(Circle().strokeBorder(on ? Ink.accent : Ink.dim, lineWidth: 1.5)).frame(width: 8, height: 8)
	}
}

struct Shimmer: View {
	@State private var at = 0.0

	var body: some View {
		GeometryReader { box in
			LinearGradient(colors: [.clear, Ink.hover, .clear], startPoint: .leading, endPoint: .trailing)
				.offset(x: box.size.width * (2 * at - 1))
		}
		.onAppear {
			withAnimation(.linear(duration: 1.1).repeatForever(autoreverses: false)) { at = 1 }
		}
	}
}

struct Limit: Identifiable {
	let id: String
	let pct: Double?
	let note: String
}

struct Limits: View {
	let rows: [Limit]
	let stale: Bool

	var body: some View {
		Grid(alignment: .leading, horizontalSpacing: 7, verticalSpacing: 4) {
			ForEach(rows) { row in
				GridRow {
					Text(row.id).foregroundStyle(Ink.dim)
					Track(part: (row.pct ?? 0) / 100, color: tone(row.pct) ?? Ink.ok, faded: stale).frame(width: 224)
					Text(row.pct.map { "\(Int($0.rounded()))%" } ?? "–").fontWeight(.semibold).gridColumnAlignment(.trailing)
					Text(row.note).foregroundStyle(Ink.dim).lineLimit(1)
				}
			}
		}
		.monospacedDigit()
	}
}

struct Card: View {
	@ObservedObject var model: Model
	let account: Reading.Account
	@State private var over = false

	var age: Double { account.at.map { model.now.timeIntervalSince1970 - $0 } ?? 0 }

	var rows: [Limit] {
		func slot(_ label: String, _ s: Reading.Slot?) -> Limit {
			Limit(id: label, pct: s?.pct.map { $0.rounded() }, note: s?.reset.map { left($0, model.now) + " · " + when($0) } ?? "")
		}
		var rows = [slot("5h", account.five), slot("7d", account.seven)]
		if let fable = account.fable {
			rows.append(slot("fable", fable))
		}
		if let c = account.credits {
			rows.append(Limit(id: "cr", pct: c.pct.map { $0.rounded() }, note: money(c.used ?? 0, c) + (c.limit.map { " / " + money($0, c) } ?? "")))
		}
		return rows
	}

	var status: Text {
		guard account.error != nil || age > 600 else { return Text("all good") }
		let late = age > 600 ? "as of \(ago(age)) ago" : ""
		guard let error = account.error else { return Text(late) }
		return Text(error).foregroundColor(Ink.bad) + Text(late.isEmpty ? "" : " · " + late)
	}

	var body: some View {
		VStack(alignment: .leading, spacing: 4) {
			HStack(spacing: 7) {
				Dot(on: account.active)
				Text(account.name ?? account.email).fontWeight(.semibold).fixedSize()
				Text(account.email).foregroundStyle(Ink.dim).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
				if let plan = account.plan, !plan.isEmpty {
					Text(plan).font(.system(size: 10)).foregroundStyle(Ink.dim).fixedSize()
				}
				if !account.active {
					Cross(ask: nil) { model.send(.forget(account.email)) }.opacity(over ? 1 : 0).help("Forget")
				}
			}
			Limits(rows: rows, stale: age > 600)
			status.font(.system(size: 10)).foregroundStyle(Ink.dim).lineLimit(1)
		}
		.padding(EdgeInsets(top: 7, leading: 9, bottom: 7, trailing: 9))
		.background(RoundedRectangle(cornerRadius: 9).fill(account.active || over ? Ink.hover : Color.clear))
		.overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(account.active ? Ink.accent : Color.clear, lineWidth: 1))
		.overlay {
			if model.activating == account.email || model.refreshing.contains(account.email) {
				Shimmer().clipShape(RoundedRectangle(cornerRadius: 9))
			}
		}
		.contentShape(Rectangle())
		.onTapGesture {
			guard !account.active else { return }
			model.activating = account.email
			model.send(.use(account.email))
		}
		.onHover { over = $0 }
		.help(account.active ? "" : "Switch to \(account.email)")
	}
}

struct Slim: View {
	@ObservedObject var model: Model
	let account: Reading.Account
	@State private var over = false

	func val(_ label: String, _ pct: Double?) -> Text {
		let pct = pct.map { $0.rounded() }
		return Text(label + " ").foregroundColor(Ink.dim) + Text(pct.map { "\(Int($0))%" } ?? "–").fontWeight(.semibold).foregroundColor(tone(pct) ?? Ink.fg)
	}

	var body: some View {
		HStack(spacing: 8) {
			Dot(on: account.active)
			Text(account.email).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
			val("5h", account.five?.pct).fixedSize()
			val("7d", account.seven?.pct).fixedSize()
			if let credits = account.credits {
				val("cr", credits.pct).fixedSize()
			}
		}
		.monospacedDigit()
		.padding(EdgeInsets(top: 3.5, leading: 9, bottom: 3.5, trailing: 9))
		.background(RoundedRectangle(cornerRadius: 9).fill(account.active || over ? Ink.hover : Color.clear))
		.overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(account.active ? Ink.accent : Color.clear, lineWidth: 1))
		.overlay {
			if model.activating == account.email || model.refreshing.contains(account.email) {
				Shimmer().clipShape(RoundedRectangle(cornerRadius: 9))
			}
		}
		.contentShape(Rectangle())
		.onTapGesture {
			guard !account.active else { return }
			model.activating = account.email
			model.send(.use(account.email))
		}
		.onHover { over = $0 }
		.help(account.active ? "" : "Switch to \(account.email)")
	}
}

struct Panel<Icons: View, Content: View>: View {
	@ObservedObject var model: Model
	let id: String
	let title: String
	let panel: Color
	@ViewBuilder let icons: () -> Icons
	@ViewBuilder let content: () -> Content

	var body: some View {
		VStack(alignment: .leading, spacing: 6) {
			HStack(spacing: 5) {
				Text(model.closed[id] == true ? "▸" : "▾").foregroundStyle(Ink.dim).frame(width: 14, alignment: .leading)
				Text(title).font(.system(size: 15, weight: .semibold)).fixedSize()
				Spacer(minLength: 8)
				icons()
			}
			.padding(.horizontal, 2)
			.contentShape(Rectangle())
			.onTapGesture { model.toggle(id) }
			content()
		}
		.padding(7)
		.background(RoundedRectangle(cornerRadius: 13).fill(panel))
	}
}

struct Accounts: View {
	@ObservedObject var model: Model

	var body: some View {
		Panel(model: model, id: "accounts", title: "Claude accounts", panel: Ink.accent.opacity(0.13)) {
			Round(tint: Ink.fg, tip: "Refresh accounts", action: { model.send(.refresh) }) { Image(systemName: "arrow.clockwise").font(.system(size: 11)) }
			Round(tint: Ink.fg, tip: "Add account", action: { model.send(.login) }) { Text("+").font(.system(size: 16, weight: .medium)) }
		} content: {
			let accounts = model.reading.accounts ?? []
			if accounts.isEmpty {
				Text("No accounts yet").foregroundStyle(Ink.dim).frame(maxWidth: .infinity).padding(10)
			} else {
				VStack(spacing: 6) {
					ForEach(accounts) { account in
						if model.closed["accounts"] == true {
							Slim(model: model, account: account)
						} else {
							Card(model: model, account: account)
						}
					}
				}
			}
		}
	}
}

struct Tile: View {
	let check: Reading.Check

	var body: some View {
		let disk = check.name == "disk"
		VStack(spacing: 4) {
			HStack(alignment: .firstTextBaseline) {
				Text(disk ? "disk free" : check.name).foregroundStyle(Ink.dim)
				Spacer(minLength: 4)
				Text(disk ? "\(Int((check.value / 1024).rounded()))G" : num(check.value) + "%")
					.font(.system(size: 14, weight: .bold)).foregroundStyle(disk && check.over ? Ink.bad : Ink.fg)
			}
			if disk {
				Track(part: check.over ? 1 : 0, color: Ink.bad)
			} else {
				Track(part: check.value / 100, color: check.over ? Ink.bad : tone(check.value * 90 / max(1, check.limit)) ?? Ink.ok)
			}
		}
		.lineLimit(1)
		.monospacedDigit()
		.padding(EdgeInsets(top: 6, leading: 8, bottom: 6, trailing: 8))
		.background(RoundedRectangle(cornerRadius: 8).fill(Ink.hover))
		.frame(maxWidth: .infinity)
	}
}

struct Box: PreferenceKey {
	static var defaultValue = CGRect.zero
	static func reduce(value: inout CGRect, nextValue: () -> CGRect) { value = nextValue() }
}

struct High: PreferenceKey {
	static var defaultValue = 0.0
	static func reduce(value: inout Double, nextValue: () -> Double) { value = nextValue() }
}

func kind(_ group: String, _ space: Bool) -> String {
	space ? "space" : group == "cpu" ? "cpu" : group.contains("sessions") ? "session" : group == "open applications" ? "app" : "proc"
}

func named(_ row: Reading.Row, _ type: String) -> (String, String) {
	let why = row.why ?? ""
	let target = row.target ?? ""
	func tail(_ path: String, _ count: Int) -> String {
		path.split(separator: "/", omittingEmptySubsequences: false).suffix(count).joined(separator: "/")
	}
	if type == "session", let at = try? #/ in (\S+?), (.*)$/#.firstMatch(in: why) {
		let dir = String(at.1)
		return (tail(dir, 1), String(at.2) + " · " + dir.replacing(#/^/Users/[^/]+/#, with: "~"))
	}
	if type == "proc", let at = why.range(of: ": ", options: .backwards) {
		return (why[at.upperBound...].split(separator: " ", omittingEmptySubsequences: false).map { tail(String($0), 2) }.joined(separator: " "), String(why[..<at.lowerBound]))
	}
	if type == "space" && row.action == "rm" {
		return (tail(target, 2), why)
	}
	guard let at = why.range(of: ", ") else { return (why, "") }
	return (String(why[..<at.lowerBound]), String(why[at.upperBound...]))
}

struct Item: View {
	@ObservedObject var model: Model
	let row: Reading.Row
	let type: String
	let space: Bool
	let share: Double
	@State private var box = CGRect.zero

	var target: String { row.target ?? "" }

	var tint: Color {
		switch type {
		case "session": return Color(red: 0.604, green: 0.435, blue: 0.847)
		case "app": return Color(red: 0.31, green: 0.561, blue: 0.902)
		case "proc": return Color(red: 0.851, green: 0.541, blue: 0.227)
		case "cpu": return Ink.bad
		default: return Ink.ok
		}
	}

	var cmd: String {
		row.action == "kill" ? "kill -9 " + target : row.action == "rm" ? "rm -rf " + target : target
	}

	var pid: String {
		if row.action == "kill" { return target }
		guard type == "app" else { return "" }
		let name = named(row, type).0
		return NSWorkspace.shared.runningApplications.first { $0.localizedName == name }.map { String($0.processIdentifier) } ?? ""
	}

	var ask: String {
		"Double click to " + (row.action == "kill" ? "kill" : row.action == "rm" ? "remove" : type == "app" ? "quit" : "run")
	}

	func use(_ label: String, _ value: String, _ none: Bool) -> some View {
		(Text(label + " ").font(.system(size: 10)).foregroundColor(Ink.dim)
			+ Text(value).fontWeight(none ? .regular : .semibold).foregroundColor(none ? Ink.dim : Ink.fg))
			.frame(width: 64, alignment: .trailing)
	}

	var body: some View {
		let name = named(row, type)
		let mono = type == "proc" || type == "space"
		HStack(spacing: 10) {
			HStack(alignment: .firstTextBaseline, spacing: 7) {
				Text(name.0).font(mono ? .system(size: 11.5, weight: .semibold, design: .monospaced) : .system(size: 12, weight: .semibold)).layoutPriority(1)
				if !name.1.isEmpty {
					Text(name.1).font(.system(size: 11)).foregroundStyle(Ink.dim)
				}
			}
			.frame(maxWidth: .infinity, alignment: .leading)
			if !pid.isEmpty {
				Hover { over in
					Button {
						NSPasteboard.general.clearContents()
						NSPasteboard.general.setString(pid, forType: .string)
						model.tip = Tip(id: target, why: "Copied pid \(pid)", cmd: pid, box: box)
					} label: {
						Text(pid).font(.system(size: 10, design: .monospaced))
							.foregroundStyle(over ? Ink.fg : Ink.dim)
							.padding(.horizontal, 6)
							.overlay(Capsule().strokeBorder(over ? Ink.fg : Ink.line, lineWidth: 1))
							.contentShape(Capsule())
					}
					.buttonStyle(.plain).focusable(false)
				}
				.fixedSize()
				.help("Copy pid \(pid)")
			}
			HStack(spacing: 0) {
				if space {
					use("size", size(row.kb ?? 0).isEmpty ? "–" : size(row.kb ?? 0), size(row.kb ?? 0).isEmpty)
				} else {
					use("cpu", row.cpu.map { num($0) + "%" } ?? "–", (row.cpu ?? 0) == 0)
					use("mem", size(row.kb ?? 0).isEmpty ? "–" : size(row.kb ?? 0), false)
				}
			}
			Cross(ask: ask) {
				model.free([target])
			}
		}
		.lineLimit(1)
		.monospacedDigit()
		.padding(EdgeInsets(top: 4.5, leading: 9, bottom: 4.5, trailing: 6))
		.background(GeometryReader { g in
			ZStack(alignment: .leading) {
				Ink.hover
				tint.opacity(0.26).frame(width: g.size.width * share)
			}
			.preference(key: Box.self, value: g.frame(in: .named("tray")))
		})
		.clipShape(RoundedRectangle(cornerRadius: 8))
		.onPreferenceChange(Box.self) { box = $0 }
		.opacity(model.going.contains(target) ? 0.35 : 1)
		.allowsHitTesting(!model.going.contains(target))
		.onHover { on in
			if on {
				model.tip = Tip(id: target, why: row.why ?? "", cmd: cmd, box: box)
			} else if model.tip?.id == target {
				model.tip = nil
			}
		}
	}
}

struct Listed: View {
	@ObservedObject var model: Model
	let rows: [Reading.Row]
	let space: Bool

	struct Part: Identifiable {
		let id: String
		var rows: [Reading.Row]
	}

	var parts: [Part] {
		var parts: [Part] = []
		for row in rows {
			let name = row.group ?? ""
			if let at = parts.firstIndex(where: { $0.id == name }) {
				parts[at].rows.append(row)
			} else {
				parts.append(Part(id: name, rows: [row]))
			}
		}
		return parts
	}

	func section(_ part: Part) -> some View {
		let type = kind(part.id, space)
		let key: (Reading.Row) -> Double = { type == "cpu" ? $0.cpu ?? 0 : $0.kb ?? 0 }
		let rows = part.rows.sorted { key($0) > key($1) }
		let most = max(1, rows.first.map(key) ?? 0)
		let kb = size(rows.reduce(0) { $0 + ($1.kb ?? 0) })
		let cpu = rows.reduce(0) { $0 + ($1.cpu ?? 0) }
		let total = type == "cpu" ? "" : [space ? kb : kb.isEmpty ? "" : kb + " mem", !space && cpu != 0 ? num(cpu) + "% cpu" : ""].filter { !$0.isEmpty }.joined(separator: " · ")
		return VStack(spacing: 4) {
			HStack(spacing: 12) {
				Text((part.id + (total.isEmpty ? "" : " · " + total)).uppercased()).tracking(0.6).lineLimit(1)
				Spacer(minLength: 0)
				Hover { over in
					Image(systemName: "trash")
						.foregroundStyle(over ? Ink.bad : Ink.dim)
						.padding(.horizontal, 8)
						.overlay(Capsule().strokeBorder(over ? Ink.bad : Ink.line, lineWidth: 1))
						.contentShape(Capsule())
						.onTapGesture(count: 2) {
							let all = (model.reading.resources?.rows ?? []) + (model.reading.space?.rows ?? [])
							model.free(all.filter { $0.group == part.id }.compactMap { $0.target })
						}
				}
				.fixedSize()
				.help("Double click to free all \(rows.count)")
			}
			.font(.system(size: 10))
			.foregroundStyle(Ink.dim)
			.padding(.horizontal, 2)
			.padding(.top, 5)
			ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
				Item(model: model, row: row, type: type, space: space, share: (key(row) * 100 / most).rounded() / 100)
			}
		}
	}

	var body: some View {
		ForEach(parts) { part in
			section(part)
		}
	}
}

struct Resources: View {
	@ObservedObject var model: Model

	var body: some View {
		let space = model.reading.space
		Panel(model: model, id: "resources", title: "Resource management", panel: Color(red: 0.282, green: 0.463, blue: 0.839).opacity(0.13)) {
			Pill(title: space?.scanning == true ? "scanning…" : "scan space") { model.send(.space) }.help("Scan the disk for what can go")
		} content: {
			if model.closed["resources"] != true {
				VStack(alignment: .leading, spacing: 4) {
					if let r = model.reading.resources, !r.check.isEmpty {
						HStack(spacing: 5) {
							ForEach(["cpu", "mem", "disk"], id: \.self) { name in
								if let check = r.check.first(where: { $0.name == name }) {
									Tile(check: check)
								}
							}
						}
						let agents = Int(r.agents ?? 0)
						Text("\(agents) claude \(agents == 1 ? "session" : "sessions") running").font(.system(size: 10)).foregroundStyle(Ink.dim)
						Listed(model: model, rows: r.rows, space: false)
						if let space, !space.rows.isEmpty {
							Listed(model: model, rows: space.rows, space: true)
							Text("space scanned \(ago(model.now.timeIntervalSince1970 - (space.at ?? 0))) ago").font(.system(size: 10)).foregroundStyle(Ink.dim)
						}
					} else {
						Text("No reading yet").foregroundStyle(Ink.dim).frame(maxWidth: .infinity).padding(10)
					}
				}
			}
		}
	}
}

struct Ring: View {
	let label: String
	let value: String
	let part: Double
	let color: Color
	var faded = false

	var body: some View {
		VStack(spacing: 4) {
			ZStack {
				Circle().stroke(Ink.hover, lineWidth: 5)
				Circle().trim(from: 0, to: max(0.001, min(1, part))).stroke(color, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
				Text(value).font(.system(size: 12, weight: .semibold))
			}
			.frame(width: 44, height: 44)
			Text(label).font(.system(size: 10)).foregroundStyle(Ink.dim).lineLimit(2).multilineTextAlignment(.center).fixedSize()
		}
		.frame(maxWidth: .infinity)
		.opacity(faded ? 0.45 : 1)
	}
}

struct Top: View {
	@ObservedObject var model: Model

	struct Count: Identifiable {
		let id: String
		let count: Int
		let color: Color
	}

	var counts: [Count] {
		let rogue = Set((model.reading.resources?.rows ?? []).filter { $0.group == "rogue sessions" }.compactMap { $0.target })
		var by: [String: Int] = [:]
		for s in model.reading.sessions ?? [] {
			by[rogue.contains(String(s.pid)) ? "rogue" : s.status == "busy" ? "busy" : s.status == "idle" || s.status == nil ? "idle" : "waiting", default: 0] += 1
		}
		return [("rogue", Color(red: 1, green: 0.49, blue: 0.43)), ("waiting", Color(red: 0.92, green: 0.74, blue: 0.33)), ("busy", Color(red: 0.95, green: 0.65, blue: 0.42)), ("idle", Ink.dim)]
			.compactMap { name, color in by[name].map { Count(id: name, count: $0, color: color) } }
	}

	var busy: [Ring] {
		let sessions = model.reading.sessions ?? []
		guard !sessions.isEmpty else { return [] }
		let count = sessions.filter { $0.status == "busy" }.count
		return [Ring(label: "busy", value: "\(count)/\(sessions.count)", part: Double(count) / Double(sessions.count), color: Color(red: 0.95, green: 0.65, blue: 0.42))]
	}

	var gauges: [Ring] {
		let all = ((try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()))?[.systemSize] as? NSNumber)?.doubleValue ?? 0
		return ["cpu", "mem", "disk"].compactMap { name in
			guard let c = model.reading.resources?.check.first(where: { $0.name == name }) else { return nil }
			if name == "disk" {
				let part = all > 0 ? max(0, 1 - c.value * 1048576 / all) : 0
				return Ring(label: "disk\n\(Int((c.value / 1024).rounded()))G free", value: "\(Int((part * 100).rounded()))%", part: part, color: c.over ? Ink.bad : Ink.ok)
			}
			return Ring(label: name, value: num(c.value) + "%", part: c.value / 100, color: c.over ? Ink.bad : tone(c.value * 90 / max(1, c.limit)) ?? Ink.ok)
		}
	}

	var limits: [Ring] {
		guard let active = (model.reading.accounts ?? []).first(where: { $0.active }) else { return [] }
		return [("5h", active.five), ("7d", active.seven), ("fable", active.fable)].compactMap { label, slot in
			guard let pct = slot?.pct else { return label == "fable" ? Ring(label: label, value: "–", part: 0, color: Ink.dim, faded: true) : nil }
			return Ring(label: label, value: "\(Int(pct.rounded()))%", part: pct / 100, color: tone(pct) ?? Ink.ok)
		}
	}

	var body: some View {
		let sessions = model.reading.sessions?.count ?? 0
		VStack(spacing: 12) {
			HStack(alignment: .firstTextBaseline, spacing: 10) {
				Text("\(sessions) Claude \(sessions == 1 ? "session" : "sessions")").font(.system(size: 15, weight: .semibold))
				ForEach(counts) { count in
					HStack(alignment: .firstTextBaseline, spacing: 4) {
						Circle().fill(count.id == "idle" ? Color.clear : count.color).overlay(Circle().strokeBorder(count.color, lineWidth: 1.5)).frame(width: 7, height: 7)
							.alignmentGuide(.firstTextBaseline) { $0[.bottom] + 2 }
						Text("\(count.count)").fontWeight(.semibold) + Text(" " + count.id).foregroundColor(Ink.dim)
					}
				}
				Spacer(minLength: 0)
				Round(tint: Ink.ok, tip: "Open the editor", action: { model.send(.edit) }) { Image(systemName: "chevron.left.forwardslash.chevron.right").font(.system(size: 10)) }
				if let video = ProcessInfo.processInfo.environment["SLYCBAR_CELERY"], FileManager.default.fileExists(atPath: video), ["celery.html", "celery.m4a"].allSatisfy({ FileManager.default.fileExists(atPath: (Bundle.main.resourcePath ?? "") + "/" + $0) }) {
					Round(tint: Ink.ok, tip: "Celery Man", action: { model.send(.celery) }) { Image(systemName: "leaf").font(.system(size: 11)) }
				}
			}
			.lineLimit(1)
			.minimumScaleFactor(0.8)
			HStack(alignment: .top, spacing: 6) {
				ForEach(busy, id: \.label) { $0 }
				ForEach(gauges, id: \.label) { $0 }
				if !gauges.isEmpty && !limits.isEmpty {
					Rectangle().fill(Ink.line).frame(width: 1, height: 44).padding(.horizontal, 6)
				}
				ForEach(limits, id: \.label) { $0 }
			}
		}
		.monospacedDigit()
		.padding(EdgeInsets(top: 4, leading: 6, bottom: 6, trailing: 6))
	}
}

struct Face: View {
	@ObservedObject var model: Model
	let scroll: Bool
	@State private var high = 0.0

	var groups: some View {
		VStack(spacing: 8) {
			Accounts(model: model)
			Resources(model: model)
		}
	}

	var session: String {
		guard let bar = model.reading.bar else { return "" }
		var parts: [String] = []
		if let dir = bar.dir, !dir.isEmpty { parts.append(String(dir.split(separator: "/").last ?? "")) }
		if let name = bar.model, !name.isEmpty { parts.append(name) }
		if let ctx = bar.ctx { parts.append("ctx \(Int(ctx.rounded()))%") }
		if let cost = bar.cost { parts.append(String(format: "$%.2f", cost)) }
		return parts.joined(separator: " · ")
	}

	var body: some View {
		VStack(spacing: 6) {
			Top(model: model)
			if scroll {
				ScrollView { groups }.scrollIndicators(.never)
			} else {
				groups
			}
			HStack(spacing: 12) {
				Text(session).font(.system(size: 11)).foregroundStyle(Ink.dim).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
				Hover { over in
					Button(action: { model.send(.warp((model.reading.accounts ?? []).first { $0.active }?.email ?? "")) }) {
						Text("WARP").font(.custom("Impact", size: 11)).tracking(1.5).foregroundStyle(over ? Ink.fg : Ink.dim).contentShape(Rectangle())
					}
					.buttonStyle(.plain).focusable(false)
				}
				.help("Warp")
			}
			.padding(.horizontal, 2)
		}
		.padding(EdgeInsets(top: 10, leading: 10, bottom: 6, trailing: 10))
		.font(.system(size: 12))
		.foregroundStyle(Ink.fg)
		.background(Color(red: 0.031, green: 0.039, blue: 0.071).opacity(0.34))
		.coordinateSpace(name: "tray")
		.overlay(alignment: .topLeading) {
			if let tip = model.tip {
				VStack(alignment: .leading, spacing: 3) {
					Text(tip.why)
					Text(tip.cmd).font(.system(size: 11, design: .monospaced)).foregroundStyle(Color.white.opacity(0.6))
				}
				.font(.system(size: 12))
				.foregroundStyle(Ink.fg)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(EdgeInsets(top: 6, leading: 9, bottom: 6, trailing: 9))
				.background(RoundedRectangle(cornerRadius: 8).fill(Color(red: 0.078, green: 0.086, blue: 0.118).opacity(0.96)))
				.overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Ink.line, lineWidth: 1))
				.background(GeometryReader { g in Color.clear.preference(key: High.self, value: g.size.height) })
				.padding(.horizontal, 10)
				.offset(y: tip.box.maxY + 3 + high <= model.height ? tip.box.maxY + 3 : tip.box.minY - 3 - high)
				.allowsHitTesting(false)
			}
		}
		.onPreferenceChange(High.self) { high = $0 }
		.allowsHitTesting(model.activating.isEmpty)
	}
}

final class Keyed: NSPanel {
	override var canBecomeKey: Bool { true }
}

public final class Host: NSObject, NSWindowDelegate, WKScriptMessageHandler {
	let script: String
	let dir: String
	let show: Bool
	let model = Model()
	var item: NSStatusItem!
	var win: Keyed!
	var shown = ""
	var played = ""
	var last = ""
	var listed = ""
	var hiddenAt = Date.distantPast
	var shownAt = Date.distantPast
	var warpWin: Keyed?
	var warpWeb: WKWebView?
	var fading: Timer?
	var probing: Process?
	var scanning: Process?
	var polling: Process?
	var ticks = 0
	var accounts: [Reading.Account] = []
	var tried: [String: Double] = [:]
	var loading = false
	var again = false
	var waiting: [() -> Void] = []
	public var edit: () -> Void = {}

	public init(script: String, dir: String, show: Bool) {
		self.script = script
		self.dir = dir
		self.show = show
	}

	@discardableResult
	func shell(_ args: [String], done: ((String) -> Void)? = nil) -> Process {
		let task = Process()
		let pipe = Pipe()
		task.executableURL = URL(fileURLWithPath: script)
		task.arguments = args
		task.standardOutput = done == nil ? FileHandle.nullDevice : pipe
		task.standardError = FileHandle.nullDevice
		do {
			try task.run()
		} catch {
			done?("")
			return task
		}
		if let done {
			DispatchQueue.global().async {
				let data = pipe.fileHandleForReading.readDataToEndOfFile()
				task.waitUntilExit()
				DispatchQueue.main.async { done(String(data: data, encoding: .utf8) ?? "") }
			}
		}
		return task
	}

	func read(_ path: String) -> String {
		(try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
	}

	func bounds(_ on: NSScreen) -> (screen: NSRect, width: CGFloat, least: CGFloat, most: CGFloat) {
		let screen = on.visibleFrame
		return (screen, min(max(screen.width * 0.22, 380), 480), screen.height * 0.1, screen.height * 0.9)
	}

	func fit() {
		guard let on = win.screen ?? NSScreen.main else { return }
		let b = bounds(on)
		let far = CGSize(width: 100000, height: 100000)
		let wide = NSHostingController(rootView: Accounts(model: model).font(.system(size: 12)).fixedSize()).sizeThatFits(in: far).width + 20
		let width = min(max(wide.rounded(.up), b.width), b.screen.width * 0.5)
		let tall = NSHostingController(rootView: Face(model: model, scroll: false).frame(width: width).fixedSize(horizontal: false, vertical: true)).sizeThatFits(in: CGSize(width: width, height: far.height)).height
		let height = min(max(tall.rounded(.up), b.least), b.most)
		let frame = win.frame
		win.setFrame(NSRect(x: frame.maxX - width, y: frame.maxY - height, width: width, height: height), display: true, animate: false)
		model.height = height
	}

	func probe() {
		if probing?.isRunning == true {
			return
		}
		probing = shell(["resources"])
	}

	func take(_ text: String) {
		guard let reading = try? JSONDecoder().decode(Reading.self, from: Data(text.utf8)) else { return }
		accounts = reading.accounts ?? []
		let now = (reading.sessions ?? []).map { "\($0.pid) \($0.status ?? "")" }.joined(separator: ", ")
		if now != listed || ticks % 60 == 0 {
			listed = now
			shell(["widget"])
		}
		item.button?.title = accounts.first { $0.active }?.five?.pct.map { " \(Int($0.rounded()))%" } ?? ""
		let first = last.isEmpty
		if text != last {
			last = text
			try? text.write(toFile: dir + "/state.json", atomically: true, encoding: .utf8)
			model.reading = reading
			model.going.formIntersection(((reading.resources?.rows ?? []) + (reading.space?.rows ?? [])).compactMap { $0.target })
			if first || win.isVisible {
				fit()
			}
		}
	}

	func load(_ then: (() -> Void)? = nil) {
		if let then {
			waiting.append(then)
		}
		if loading {
			again = true
			return
		}
		loading = true
		shell(["state"]) { text in
			self.loading = false
			self.take(text)
			if self.again {
				self.again = false
				self.load()
				return
			}
			let run = self.waiting
			self.waiting = []
			run.forEach { $0() }
		}
	}

	func check() {
		if polling?.isRunning == true {
			return
		}
		let now = Date().timeIntervalSince1970
		var pick = ""
		var late = 0.0
		for a in accounts {
			let due = max(a.active ? (a.at ?? 0) + 180 : max(a.due ?? 0, a.retry ?? 0), (tried[a.email] ?? 0) + 180)
			if now >= due && now - due >= late {
				late = now - due
				pick = a.email
			}
		}
		if !pick.isEmpty {
			tried[pick] = now
			polling = shell(["refresh", pick])
		}
	}

	func screenAt() -> (screen: NSScreen, display: Int) {
		let mouse = NSEvent.mouseLocation
		var at = (NSScreen.main ?? NSScreen.screens[0], 1)
		for (i, screen) in NSScreen.screens.enumerated() where NSMouseInRect(mouse, screen.frame, false) {
			at = (screen, i + 1)
		}
		return at
	}

	public func reveal() {
		last = ""
		polling = shell(["refresh"])
		probe()
		load()
		let b = bounds(screenAt().screen)
		let frame = win.frame
		win.setFrame(NSRect(x: b.screen.maxX - frame.width - 16, y: b.screen.maxY - frame.height - 8, width: frame.width, height: frame.height), display: true)
		shownAt = Date()
		model.now = Date()
		win.alphaValue = 0
		win.makeKeyAndOrderFront(nil)
		win.orderFrontRegardless()
		NSAnimationContext.runAnimationGroup { context in
			context.duration = 0.25
			win.animator().alphaValue = 1
		}
	}

	func log(_ line: String) {
		guard let file = FileHandle(forWritingAtPath: dir + "/tray.log") else { return }
		file.seekToEndOfFile()
		file.write(Data((ISO8601DateFormatter().string(from: Date()) + " " + line + "\n").utf8))
		file.closeFile()
	}

	func overlay(_ screen: NSRect, _ page: String, _ query: String, _ clear: Bool) {
		fading?.invalidate()
		fading = nil
		if warpWin == nil {
			let config = WKWebViewConfiguration()
			config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
			config.mediaTypesRequiringUserActionForPlayback = []
			config.userContentController.add(self, name: "tray")
			let window = Keyed(contentRect: screen, styleMask: .borderless, backing: .buffered, defer: false)
			window.hidesOnDeactivate = false
			window.isReleasedWhenClosed = false
			window.hasShadow = false
			window.level = .screenSaver
			window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
			let web = WKWebView(frame: NSRect(origin: .zero, size: screen.size), configuration: config)
			web.setValue(false, forKey: "drawsBackground")
			web.autoresizingMask = [.width, .height]
			window.contentView = web
			warpWin = window
			warpWeb = web
		}
		guard let warpWin, let warpWeb else { return }
		warpWin.isOpaque = !clear
		warpWin.backgroundColor = clear ? .clear : .black
		warpWin.setFrame(screen, display: true)
		let file = URL(fileURLWithPath: Bundle.main.resourcePath ?? "").appendingPathComponent(page)
		if let url = URL(string: file.absoluteString + "?t=\(Int(Date().timeIntervalSince1970 * 1000))" + (query.isEmpty ? "" : "&" + query)) {
			warpWeb.loadFileURL(url, allowingReadAccessTo: URL(fileURLWithPath: "/"))
		}
		NSApp.activate(ignoringOtherApps: true)
		warpWin.alphaValue = 0
		warpWin.makeKeyAndOrderFront(nil)
	}

	func warp(_ email: String, changes: String = "") {
		guard CGPreflightScreenCaptureAccess() else {
			CGRequestScreenCaptureAccess()
			NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture")!)
			log("warp not started, screen recording is not allowed")
			return
		}
		let at = screenAt()
		shell(changes.isEmpty ? ["warp", email, String(at.display)] : ["changes", changes, String(at.display)]) { text in
			guard !text.isEmpty else {
				self.log("warp not started, nothing to show" + (changes.isEmpty ? "" : " for " + changes))
				return
			}
			try? text.write(toFile: self.dir + "/warp.json", atomically: true, encoding: .utf8)
			var plain = CharacterSet.alphanumerics
			plain.insert(charactersIn: "-_.!~*'()")
			self.overlay(at.screen.frame, "warp.html", "data=" + ((self.dir + "/warp.json").addingPercentEncoding(withAllowedCharacters: plain) ?? ""), false)
		}
	}

	func unwarp() {
		guard let warpWin, warpWin.isVisible, fading == nil else { return }
		fading = Timer.scheduledTimer(withTimeInterval: 1.0 / 60, repeats: true) { timer in
			warpWin.alphaValue = max(0, warpWin.alphaValue - 1.0 / 90)
			if warpWin.alphaValue > 0 {
				return
			}
			timer.invalidate()
			self.fading = nil
			self.warpWeb?.loadHTMLString("", baseURL: nil)
			warpWin.orderOut(nil)
			if self.win.isVisible {
				self.win.makeKeyAndOrderFront(nil)
			}
			self.log("warp closed")
		}
	}

	func dismiss() {
		if !win.isVisible || warpWin?.isVisible == true || Date().timeIntervalSince(shownAt) < 1 {
			return
		}
		hiddenAt = Date()
		win.orderOut(nil)
	}

	func ask(_ ask: Ask) {
		switch ask {
		case .edit:
			dismiss()
			edit()
		case .fit:
			DispatchQueue.main.async { self.fit() }
		case .free(let targets):
			shell(["free"] + targets) { _ in
				self.load()
				self.probe()
			}
		case .space:
			if scanning?.isRunning != true {
				scanning = shell(["scan"])
			}
		case .use(let email):
			shell(["use", email]) { _ in
				self.load { self.model.activating = "" }
			}
		case .forget(let email):
			shell(["forget", email]) { _ in self.load() }
		case .warp(let email):
			warp(email)
		case .celery:
			var plain = CharacterSet.alphanumerics
			plain.insert(charactersIn: "-_.!~*'()")
			overlay(screenAt().screen.frame, "celery.html", "video=" + ((ProcessInfo.processInfo.environment["SLYCBAR_CELERY"] ?? "").addingPercentEncoding(withAllowedCharacters: plain) ?? ""), true)
		case .login:
			shell(["login"])
		case .refresh:
			guard model.refreshing.isEmpty else { return }
			let emails = (model.reading.accounts ?? []).map(\.email)
			model.refreshing = Set(emails)
			refresh(emails)
		}
	}

	func refresh(_ emails: [String]) {
		guard let email = emails.first else { return }
		shell(["refresh", email]) { _ in
			self.load { self.model.refreshing.remove(email) }
			self.refresh(Array(emails.dropFirst()))
		}
	}

	public func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
		guard let body = message.body as? [String: Any] else { return }
		if body["ready"] != nil {
			warpWin?.alphaValue = 1
			log("warp shown")
		} else if body["close"] != nil {
			unwarp()
		} else if let line = body["log"] as? String {
			log(line)
		}
	}

	@objc func toggle(_ sender: Any?) {
		if win.isVisible {
			win.orderOut(nil)
		} else if Date().timeIntervalSince(hiddenAt) > 0.3 {
			reveal()
		}
	}

	public func windowDidResignKey(_ notification: Notification) {
		dismiss()
	}

	func tick() {
		load()
		check()
		ticks += 1
		if win.isVisible || ticks % 6 == 0 {
			probe()
		}
	}

	func watch() {
		let show = read(dir + "/show")
		if show != shown {
			shown = show
			reveal()
		}
		let play = read(dir + "/play")
		if play != played {
			played = play
			if play.hasPrefix("open") {
				let rows = play.split(separator: "\n").map(String.init)
				warp("", changes: rows.count > 1 && rows[1].hasPrefix("changes ") ? String(rows[1].dropFirst(8)) : "")
			} else {
				unwarp()
			}
		}
	}

	public func start() {
		shown = read(dir + "/show")
		played = read(dir + "/play")
		try? String(ProcessInfo.processInfo.processIdentifier).write(toFile: dir + "/pid", atomically: true, encoding: .utf8)
		model.send = { [unowned self] in self.ask($0) }

		item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
		let icon = NSImage(contentsOfFile: (Bundle.main.resourcePath ?? "") + "/tray.svg")
		icon?.size = NSSize(width: 25, height: 18)
		icon?.isTemplate = true
		item.button?.image = icon
		item.button?.target = self
		item.button?.action = #selector(toggle(_:))

		let b = bounds(NSScreen.main ?? NSScreen.screens[0])
		let frame = NSRect(x: 0, y: 0, width: b.width, height: b.least)
		win = Keyed(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
		win.hidesOnDeactivate = false
		win.title = "Slyed"
		win.isOpaque = false
		win.backgroundColor = .clear
		win.hasShadow = true
		win.isReleasedWhenClosed = false
		win.level = .floating
		win.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
		win.delegate = self
		NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [unowned self] _ in self.dismiss() }

		let glass = NSVisualEffectView(frame: frame)
		glass.material = .hudWindow
		glass.blendingMode = .behindWindow
		glass.state = .active
		glass.autoresizingMask = [.width, .height]
		let round = NSImage(size: NSSize(width: 25, height: 25), flipped: false) { rect in
			NSColor.black.setFill()
			NSBezierPath(roundedRect: rect, xRadius: 12, yRadius: 12).fill()
			return true
		}
		round.capInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
		round.resizingMode = .stretch
		glass.maskImage = round

		let face = NSHostingView(rootView: Face(model: model, scroll: true))
		face.sizingOptions = []
		face.frame = frame
		face.autoresizingMask = [.width, .height]
		glass.addSubview(face)
		win.contentView = glass

		polling = shell(["refresh"])
		probe()
		load()
		Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [unowned self] _ in self.tick() }
		Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [unowned self] _ in self.watch() }
		Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [unowned self] _ in
			if self.win.isVisible {
				self.model.now = Date()
			}
		}
		if show {
			Timer.scheduledTimer(withTimeInterval: 1, repeats: false) { [unowned self] _ in self.toggle(nil) }
		}
	}
}
