import Foundation

extension Work {
	func mem() {
		section("pressure")
		put(sh("sysctl", ["-n", "vm.swapusage"]).out)
		if let l = lines(sh("memory_pressure", []).out).last { put(l + "\n") }
		for l in lines(sh("top", ["-l", "1", "-n", "0"]).out) where l.contains("Load Avg") || l.contains("CPU usage") || l.contains("PhysMem") {
			put(l + "\n")
		}

		section("top 15 by cpu")
		for (i, l) in lines(sh("ps", ["-Aceo", "pid,pcpu,rss,etime,comm", "-r"]).out).prefix(16).enumerated() {
			if i == 0 {
				put(l + "\n")
				continue
			}
			let w = words(l)
			let name = w.count > 4 ? l.range(of: w[4], options: .literal).map { String(l[$0.lowerBound...]) } ?? "" : l
			put(left(at(w, 0), 7) + " " + right(at(w, 1), 6) + " " + f("%7.0fM ", num(at(w, 2)) / 1024) + right(at(w, 3), 12) + "  " + name + "\n")
		}

		section("processes over \(rss)M, by memory")
		let heavy = lines(sh("ps", ["-axo", "pid=,ppid=,rss=,pcpu=,etime=,command="]).out).filter { num(at(words($0), 2)) > Double(rss * 1024) }
		for l in ranked(heavy, down: true, by: third).prefix(30) {
			let w = words(l)
			put(left(at(w, 0), 7) + " ppid " + left(at(w, 1), 7) + " " + f("%7.0fM ", num(at(w, 2)) / 1024) + right(at(w, 3), 5) + "% " + right(at(w, 4), 12) + "  "
				+ clip(w.dropFirst(5).joined(separator: " "), 150) + "\n")
		}

		section("by app, summed")
		var apps: [String: Double] = [:]
		for l in lines(sh("ps", ["-axo", "rss=,comm="]).out) {
			let w = words(l)
			var n = w.dropFirst().joined(separator: " ")
			if let r = n.range(of: ".app/", options: .literal) { n = String(n[..<r.lowerBound]) }
			if let r = n.range(of: "/", options: [.literal, .backwards]) { n = String(n[r.upperBound...]) }
			apps[n, default: 0] += num(at(w, 0))
		}
		for l in ranked(apps.map { f("%d", Int($0.value)) + "\t" + $0.key }, down: true).prefix(15) {
			let t = tabs(l)
			put(f("%7.0fM  ", num(at(t, 0)) / 1024) + at(t, 1) + "\n")
		}

		section("dev servers, browsers and tools")
		let all = lines(sh("ps", ["-axo", "pid=,ppid=,rss=,etime=,command="]).out)
		let dev = re(Work.dev)
		let own = re("space.sh")
		let tools = all.filter { hit(dev, $0) && !$0.contains("grep") && !hit(own, $0) && !$0.contains(" Helper") }
		for l in ranked(tools, down: true, by: third).prefix(40) {
			let w = words(l)
			put(left(at(w, 0), 7) + " ppid " + left(at(w, 1), 7) + " " + f("%6.0fM ", num(at(w, 2)) / 1024) + right(at(w, 3), 12) + "  "
				+ clip(w.dropFirst(4).joined(separator: " "), 140) + "\n")
		}

		section("orphans, parent is launchd")
		let lost = re(Work.dev + "|node|claude")
		var n = 0
		var sum = 0.0
		for l in lines(sh("ps", ["-axo", "pid=,ppid=,rss=,etime=,command="]).out) {
			let w = words(l)
			guard num(at(w, 1)) == 1, hit(lost, l), !l.contains("grep"), !l.contains("/System/"), !l.contains("/usr/libexec") else { continue }
			n += 1
			sum += num(at(w, 2))
			put(left(at(w, 0), 7) + " " + f("%6.0fM ", num(at(w, 2)) / 1024) + right(at(w, 3), 12) + "  " + clip(w.dropFirst(4).joined(separator: " "), 120) + "\n")
		}
		put(f("%d orphans, %.0fM\n", n, sum / 1024))

		section("claude sessions with their whole process tree")
		var par: [String: String] = [:]
		var size: [String: Double] = [:]
		for l in lines(sh("ps", ["-axo", "pid=,ppid=,rss="]).out) {
			let w = words(l)
			par[at(w, 0)] = at(w, 1)
			size[at(w, 0)] = num(at(w, 2))
		}
		let ids = Set(words(sh("pgrep", ["-x", "claude"]).out.replacingOccurrences(of: "\n", with: " ")) + words(sh("pgrep", ["-f", "^(/opt/homebrew/bin/)?claude( |$)"]).out.replacingOccurrences(of: "\n", with: " ")))
		var out: [String] = []
		for c in ids.sorted(by: before) {
			let total = Int(below([c], par).reduce(0.0) { $0 + (size[$1] ?? 0) } / 1024)
			let time = sh("ps", ["-o", "etime=", "-p", c]).out.filter { $0 != " " && $0 != "\n" }
			out.append(left(c, 7) + " " + right(time, 12) + " " + right("\(total)", 6) + "M  " + cwd(c))
		}
		for l in ranked(out, down: true, by: third) { put(l + "\n") }
	}
}
