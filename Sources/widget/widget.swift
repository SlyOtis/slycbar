import SwiftUI
import WidgetKit

struct Reading: Decodable {
	struct Session: Decodable {
		let pid: Int
		let name: String?
		let dir: String
		let status: String?
		let since: Double
		let cpu: Double
		let kb: Double
	}
	struct Check: Decodable {
		let name: String
		let value: Double
		let limit: Double
		let over: Bool
	}
	struct Row: Decodable {
		let group: String?
		let target: String?
		let why: String?
		let kb: Double?
		let cpu: Double?
	}
	struct Resources: Decodable {
		let check: [Check]
		let rows: [Row]
	}
	struct Slot: Decodable {
		let pct: Double?
	}
	struct Account: Decodable {
		let active: Bool
		let five: Slot?
		let seven: Slot?
		let fable: Slot?
	}
	let sessions: [Session]?
	let resources: Resources?
	let accounts: [Account]?
}

enum Tone: Int {
	case rogue, wait, busy, idle

	var color: Color {
		switch self {
		case .rogue: return Color(red: 1, green: 0.49, blue: 0.43)
		case .wait: return Color(red: 0.92, green: 0.74, blue: 0.33)
		case .busy: return Color(red: 0.95, green: 0.65, blue: 0.42)
		case .idle: return Color.white.opacity(0.72)
		}
	}

	var label: String {
		switch self {
		case .rogue: return "rogue"
		case .wait: return "waiting"
		case .busy: return "busy"
		case .idle: return "idle"
		}
	}
}

let calm = Color(red: 0.42, green: 0.78, blue: 0.56)

func level(_ part: Double, over: Bool = false) -> Color {
	over || part >= 0.9 ? Tone.rogue.color : part >= 0.7 ? Tone.wait.color : calm
}

struct Line: Identifiable {
	let id: Int
	let tone: Tone
	let word: String
	let name: String
	let place: String
	let since: Double
	let cpu: Int
	let mem: String
}

struct Gauge: Identifiable {
	let id: String
	let value: String
	let note: String
	let part: Double
	let color: Color
}

struct Proc: Identifiable {
	let id: String
	let cpu: Int
	let kb: Double
}

struct Entry: TimelineEntry {
	let date: Date
	let lines: [Line]
	let gauges: [Gauge]
	let procs: [Proc]
	let limits: [Gauge]
	let read: Bool
}

func size(_ kb: Double) -> String {
	kb >= 1048576 ? String(format: "%.1fG", kb / 1048576) : kb >= 1024 ? "\(Int((kb / 1024).rounded()))M" : ""
}

func ago(_ s: Double) -> String {
	s >= 86400 ? "\(Int(s / 86400))d" : s >= 3600 ? "\(Int(s / 3600))h" : s >= 60 ? "\(Int(s / 60))m" : "now"
}

func named(_ row: Reading.Row) -> String {
	let why = row.why ?? ""
	if row.group == "cpu" { return why }
	if let at = why.range(of: ": ", options: .backwards) {
		let first = why[at.upperBound...].split(separator: " ").first.map(String.init) ?? ""
		return first.split(separator: "/").last.map(String.init) ?? first
	}
	return why.components(separatedBy: ", ").first ?? why
}

func entry(at date: Date) -> Entry {
	let home = String(cString: getpwuid(getuid()).pointee.pw_dir)
	guard let data = FileManager.default.contents(atPath: home + "/.cache/slycbar/tray/state.json"),
		let reading = try? JSONDecoder().decode(Reading.self, from: data) else {
		return Entry(date: date, lines: [], gauges: [], procs: [], limits: [], read: false)
	}
	let rows = reading.resources?.rows ?? []
	var rogue: [String: String] = [:]
	for row in rows where row.group == "rogue sessions" {
		guard let target = row.target else { continue }
		var from = ""
		if let why = row.why, let a = why.range(of: "started from "), let b = why.range(of: ", not from", range: a.upperBound..<why.endIndex) {
			from = String(why[a.upperBound..<b.lowerBound])
		}
		rogue[target] = from
	}
	let lines = (reading.sessions ?? []).map { s -> Line in
		var parts = s.dir.replacingOccurrences(of: home, with: "~").split(separator: "/").map(String.init)
		let name = parts.popLast() ?? s.name ?? ""
		let from = rogue[String(s.pid)]
		let tone: Tone = from != nil ? .rogue : s.status == "busy" ? .busy : s.status == "idle" || s.status == nil ? .idle : .wait
		return Line(id: s.pid, tone: tone, word: from != nil ? "rogue" : s.status ?? "idle", name: name,
			place: from.map { $0.isEmpty ? "" : "from " + $0 } ?? parts.joined(separator: "/"),
			since: s.since, cpu: Int(s.cpu), mem: size(s.kb))
	}.sorted { $0.tone.rawValue != $1.tone.rawValue ? $0.tone.rawValue < $1.tone.rawValue : $0.since > $1.since }
	let checks = reading.resources?.check ?? []
	let disk = try? FileManager.default.attributesOfFileSystem(forPath: home)
	let gauges = ["cpu", "mem", "disk"].compactMap { name -> Gauge? in
		guard let c = checks.first(where: { $0.name == name }) else { return nil }
		if name == "disk" {
			let all = (disk?[.systemSize] as? NSNumber)?.doubleValue ?? 0
			let part = all > 0 ? max(0, 1 - c.value * 1048576 / all) : 0
			return Gauge(id: name, value: "\(Int((c.value / 1024).rounded()))G", note: "free", part: part, color: level(0, over: c.over))
		}
		return Gauge(id: name, value: "\(Int(c.value))%", note: "", part: min(1, c.value / 100), color: level(c.value / max(1, c.limit) * 0.9, over: c.over))
	}
	var seen: [String: Proc] = [:]
	for row in rows where !(row.group ?? "").contains("sessions") {
		let name = named(row)
		guard !name.isEmpty else { continue }
		let proc = Proc(id: name, cpu: Int(row.cpu ?? 0), kb: row.kb ?? 0)
		if let old = seen[name], old.cpu > proc.cpu || (old.cpu == proc.cpu && old.kb >= proc.kb) { continue }
		seen[name] = proc
	}
	let procs = seen.values.sorted { $0.cpu != $1.cpu ? $0.cpu > $1.cpu : $0.kb > $1.kb }
	var limits: [Gauge] = []
	if let active = reading.accounts?.first(where: { $0.active }) {
		for (label, slot) in [("5h", active.five), ("7d", active.seven), ("fable", active.fable)] {
			guard let pct = slot?.pct else { continue }
			limits.append(Gauge(id: label, value: "\(Int(pct.rounded()))%", note: "", part: min(1, pct / 100), color: level(pct / 100)))
		}
	}
	return Entry(date: date, lines: lines, gauges: gauges, procs: Array(procs.prefix(4)), limits: limits, read: true)
}

struct Provider: TimelineProvider {
	func placeholder(in context: Context) -> Entry {
		Entry(date: Date(), lines: [], gauges: [], procs: [], limits: [], read: true)
	}

	func getSnapshot(in context: Context, completion: @escaping (Entry) -> Void) {
		completion(entry(at: Date()))
	}

	func getTimeline(in context: Context, completion: @escaping (Timeline<Entry>) -> Void) {
		let now = Date()
		let first = entry(at: now)
		let entries = (0..<15).map { Entry(date: now.addingTimeInterval(Double($0) * 60), lines: first.lines, gauges: first.gauges, procs: first.procs, limits: first.limits, read: first.read) }
		completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(900))))
	}
}

struct Mark: View {
	let tone: Tone

	var body: some View {
		Group {
			switch tone {
			case .idle: Circle().strokeBorder(Color.white.opacity(0.56), lineWidth: 1.5)
			case .rogue: RoundedRectangle(cornerRadius: 1.5).fill(tone.color).rotationEffect(.degrees(45)).scaleEffect(0.82)
			default: Circle().fill(tone.color)
			}
		}
		.frame(width: 7, height: 7)
	}
}

struct Ring: View {
	let gauge: Gauge

	var body: some View {
		VStack(spacing: 4) {
			ZStack {
				Circle().stroke(Color.white.opacity(0.12), lineWidth: 5)
				Circle().trim(from: 0, to: max(0.001, gauge.part)).stroke(gauge.color, style: StrokeStyle(lineWidth: 5, lineCap: .round)).rotationEffect(.degrees(-90))
				Text(gauge.id == "disk" ? "\(Int((gauge.part * 100).rounded()))%" : gauge.value).font(.system(size: 14, weight: .semibold)).foregroundStyle(.white)
			}
			.frame(width: 44, height: 44)
			Text(gauge.id == "disk" ? "disk · \(gauge.value) free" : gauge.id).font(.system(size: 12)).foregroundStyle(Color.white.opacity(0.72))
		}
		.frame(maxWidth: .infinity)
	}
}

struct Bar: View {
	let part: Double
	let color: Color

	var body: some View {
		GeometryReader { box in
			ZStack(alignment: .leading) {
				Capsule().fill(Color.white.opacity(0.12))
				Capsule().fill(color).frame(width: max(3, box.size.width * part))
			}
		}
		.frame(height: 4)
	}
}

struct Face: View {
	@Environment(\.widgetFamily) var family
	let entry: Entry

	var dim: Color { Color.white.opacity(0.72) }
	var faint: Color { Color.white.opacity(0.56) }
	var rule: some View { Rectangle().fill(Color.white.opacity(0.1)).frame(height: 1) }

	func sessions(_ most: Int) -> some View {
		VStack(alignment: .leading, spacing: 9) {
			HStack(alignment: .firstTextBaseline, spacing: 10) {
				(Text("\(entry.lines.count)").fontWeight(.semibold).foregroundColor(.white)
					+ Text(entry.lines.count == 1 ? " Claude session" : " Claude sessions").foregroundColor(dim))
				ForEach([Tone.rogue, .wait, .busy, .idle], id: \.rawValue) { tone in
					let count = entry.lines.filter { $0.tone == tone }.count
					if count > 0 {
						HStack(alignment: .firstTextBaseline, spacing: 4) {
							Mark(tone: tone).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 2 }
							(Text("\(count)").fontWeight(.semibold).foregroundColor(.white)
								+ Text(" " + tone.label).foregroundColor(dim))
						}
					}
				}
				Spacer(minLength: 0)
			}
			.lineLimit(1)
			.minimumScaleFactor(0.8)
			if !entry.read {
				Text("Open slycbar for the first reading").foregroundStyle(dim)
			} else if entry.lines.isEmpty {
				Text("No Claude session running").foregroundStyle(dim)
			} else {
				VStack(spacing: 5) {
					ForEach(entry.lines.prefix(most)) { line in
						HStack(alignment: .firstTextBaseline, spacing: 8) {
							Mark(tone: line.tone).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 2 }
							Text(line.name).fontWeight(.semibold).foregroundStyle(.white).layoutPriority(2)
							Text(line.place).font(.system(size: 12)).foregroundStyle(faint).truncationMode(.middle)
							Spacer(minLength: 4)
							(Text(line.word).fontWeight(.semibold).foregroundColor(line.tone == .idle ? .white : line.tone.color)
								+ Text(" " + ago(max(0, entry.date.timeIntervalSince1970 - line.since))).foregroundColor(dim))
								.layoutPriority(3)
							Text("\(line.cpu)%").foregroundStyle(line.cpu > 0 ? dim : faint).frame(minWidth: 30, alignment: .trailing).layoutPriority(3)
							Text(line.mem).foregroundStyle(dim).frame(minWidth: 40, alignment: .trailing).layoutPriority(3)
						}
						.lineLimit(1)
					}
				}
				if entry.lines.count > most {
					Text("and \(entry.lines.count - most) more").foregroundStyle(dim)
				}
			}
		}
		.padding(EdgeInsets(top: 13, leading: 16, bottom: 10, trailing: 16))
	}

	var strip: some View {
		HStack(spacing: 0) {
			ForEach(Array(entry.gauges.enumerated()), id: \.element.id) { at, gauge in
				HStack(alignment: .firstTextBaseline, spacing: 5) {
					Text(gauge.id).foregroundStyle(dim)
					Text(gauge.value).fontWeight(.semibold).foregroundStyle(gauge.color == calm ? Color.white.opacity(0.94) : gauge.color)
					if !gauge.note.isEmpty {
						Text(gauge.note).foregroundStyle(dim)
					}
				}
				.frame(maxWidth: .infinity, alignment: at == 0 ? .leading : at == entry.gauges.count - 1 ? .trailing : .center)
			}
		}
		.padding(EdgeInsets(top: 9, leading: 16, bottom: 11, trailing: 16))
		.background(Color.black.opacity(0.2))
	}

	func heavy(_ count: Int) -> some View {
		let most = max(1, entry.procs.map(\.kb).max() ?? 1)
		return VStack(spacing: 5) {
			HStack {
				Text("Heaviest").foregroundStyle(dim)
				Spacer()
				Text("cpu").foregroundStyle(faint).frame(width: 44, alignment: .trailing)
				Text("mem").foregroundStyle(faint).frame(width: 96, alignment: .trailing)
			}
			.font(.system(size: 12))
			ForEach(entry.procs.prefix(count)) { proc in
				HStack(spacing: 8) {
					Text(proc.id).foregroundStyle(.white).lineLimit(1).truncationMode(.middle)
					Spacer(minLength: 4)
					Text("\(proc.cpu)%").foregroundStyle(proc.cpu >= 50 ? Tone.wait.color : proc.cpu > 0 ? dim : faint).fixedSize().frame(width: 44, alignment: .trailing)
					Bar(part: proc.kb / most, color: Color(red: 0.45, green: 0.62, blue: 0.95)).frame(width: 44)
					Text(size(proc.kb)).foregroundStyle(dim).frame(width: 44, alignment: .trailing)
				}
			}
		}
		.padding(EdgeInsets(top: 8, leading: 16, bottom: 7, trailing: 16))
	}

	var caps: some View {
		HStack(spacing: 14) {
			Text("Limits").foregroundStyle(dim)
			ForEach(entry.limits) { limit in
				HStack(spacing: 7) {
					Text(limit.id).foregroundStyle(dim)
					Bar(part: limit.part, color: limit.color)
					Text(limit.value).fontWeight(.semibold).foregroundStyle(.white)
				}
			}
		}
		.padding(EdgeInsets(top: 9, leading: 16, bottom: 11, trailing: 16))
		.background(Color.black.opacity(0.2))
	}

	func large(_ count: Int) -> some View {
		VStack(spacing: 0) {
			sessions(3)
			if !entry.gauges.isEmpty {
				rule
				HStack(spacing: 0) {
					ForEach(entry.gauges) { Ring(gauge: $0) }
				}
				.padding(.vertical, 8)
				.background(Color.black.opacity(0.12))
			}
			if count > 0 && !entry.procs.isEmpty {
				rule
				heavy(count)
			}
			Spacer(minLength: 0)
			if !entry.limits.isEmpty {
				rule
				caps
			}
		}
	}

	var body: some View {
		VStack(spacing: 0) {
			if family == .systemLarge {
				ViewThatFits(in: .vertical) {
					large(4)
					large(3)
					large(2)
					large(1)
					large(0)
				}
			} else {
				sessions(3)
				Spacer(minLength: 0)
				if !entry.gauges.isEmpty {
					rule
					strip
				}
			}
		}
		.font(.system(size: 13))
		.monospacedDigit()
		.widgetURL(URL(string: "slycbar://open"))
		.containerBackground(for: .widget) {
			LinearGradient(colors: [Color(red: 0.13, green: 0.19, blue: 0.3), Color(red: 0.1, green: 0.15, blue: 0.25)], startPoint: .top, endPoint: .bottom)
		}
	}
}

@main
struct Sessions: Widget {
	var body: some WidgetConfiguration {
		StaticConfiguration(kind: "sessions", provider: Provider()) { entry in
			Face(entry: entry)
		}
		.configurationDisplayName("Claude sessions")
		.description("Every running Claude session and how it is doing, with cpu, memory and free disk.")
		.supportedFamilies([.systemMedium, .systemLarge])
		.contentMarginsDisabled()
	}
}
