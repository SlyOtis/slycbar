import Foundation

enum Table {
	typealias Bytes = [UInt8]

	struct Cell {
		var label: [Bytes]
		var value: [Bytes]
		var colour: Bytes
		var left: Bool
		var link: Bytes
	}

	static let esc: Bytes = [27]
	static let bar = Bytes("─".utf8)
	static let wall = Bytes("│".utf8)
	static let down = Bytes("┬".utf8)
	static let up = Bytes("┴".utf8)
	static let cross = Bytes("┼".utf8)
	static let dots = Bytes("…".utf8)
	static let reset = esc + Bytes("[0m".utf8)
	static let osc = esc + Bytes("]8;;".utf8)

	static func plain(_ s: Bytes) -> Bytes {
		if !s.contains(27) {
			return s
		}
		let link: Bytes = [27, 93, 56, 59, 59]
		var mid = Bytes()
		var i = 0
		while i < s.count {
			if s[i...].starts(with: link) {
				var j = i + 5
				while j < s.count && s[j] != 27 {
					j += 1
				}
				if j + 1 < s.count && s[j + 1] == 92 {
					i = j + 2
					continue
				}
			}
			mid.append(s[i])
			i += 1
		}
		var out = Bytes()
		i = 0
		while i < mid.count {
			if mid[i] == 27 && i + 1 < mid.count && mid[i + 1] == 91 {
				var j = i + 2
				while j < mid.count && ((mid[j] >= 48 && mid[j] <= 57) || mid[j] == 59) {
					j += 1
				}
				if j < mid.count && mid[j] == 109 {
					i = j + 1
					continue
				}
			}
			out.append(mid[i])
			i += 1
		}
		return out
	}

	static func cw(_ cp: Int) -> Int {
		if cp == 0 || (cp >= 768 && cp <= 879) || cp == 8203 || cp == 8205 || (cp >= 65024 && cp <= 65039) {
			return 0
		}
		if (cp >= 4352 && cp <= 4447) || (cp >= 11904 && cp <= 42191) || (cp >= 44032 && cp <= 55203) ||
			(cp >= 63744 && cp <= 64255) || (cp >= 65040 && cp <= 65049) || (cp >= 65072 && cp <= 65135) ||
			(cp >= 65280 && cp <= 65376) || (cp >= 65504 && cp <= 65510) ||
			(cp >= 127744 && cp <= 129791) || (cp >= 131072 && cp <= 262141) {
			return 2
		}
		return 1
	}

	static func chars(_ s: Bytes) -> [(text: Bytes, wide: Int)] {
		var out: [(text: Bytes, wide: Int)] = []
		var i = 0
		func at(_ j: Int) -> Int {
			j < s.count ? Int(s[j]) : 0
		}
		while i < s.count {
			let b = Int(s[i])
			var k = 1
			var cp = b
			if b >= 240 {
				k = 4
				cp = (b - 240) * 262144 + (at(i + 1) - 128) * 4096 + (at(i + 2) - 128) * 64 + at(i + 3) - 128
			} else if b >= 224 {
				k = 3
				cp = (b - 224) * 4096 + (at(i + 1) - 128) * 64 + at(i + 2) - 128
			} else if b >= 192 {
				k = 2
				cp = (b - 192) * 64 + at(i + 1) - 128
			} else if b >= 128 {
				cp = 65533
			}
			out.append((Bytes(s[i..<min(i + k, s.count)]), cw(cp)))
			i += k
		}
		return out
	}

	static func vis(_ s: Bytes) -> Int {
		chars(plain(s)).reduce(0) { $0 + $1.wide }
	}

	static func head(_ s: Bytes, _ w: Int) -> Bytes {
		var out = Bytes()
		var t = 0
		for c in chars(s) {
			if t + c.wide > w {
				break
			}
			out += c.text
			t += c.wide
		}
		return out
	}

	static func tail(_ s: Bytes, _ w: Int) -> Bytes {
		var out = Bytes()
		var t = 0
		for c in chars(s).reversed() {
			if t + c.wide > w {
				break
			}
			out = c.text + out
			t += c.wide
		}
		return out
	}

	static func cut(_ v: Bytes, _ n: Int, _ left: Bool) -> Bytes {
		let v = plain(v)
		if vis(v) <= n {
			return v
		}
		if n <= 1 {
			return n == 1 ? dots : []
		}
		return left ? dots + tail(v, n - 1) : head(v, n - 1) + dots
	}

	static func dim(_ s: Bytes) -> Bytes {
		esc + Bytes("[2m".utf8) + s
	}

	static func val(_ s: Bytes, _ c: Bytes) -> Bytes {
		esc + Bytes("[22m".utf8) + esc + Bytes("[38;5;".utf8) + c + Bytes("m".utf8) + s + esc + Bytes("[39m".utf8)
	}

	static func kv(_ l: Bytes, _ v: Bytes, _ c: Bytes, _ room: Int, _ left: Bool) -> Bytes {
		let lw = vis(l)
		if lw >= room {
			return dim(head(l, room))
		}
		return dim(l) + [32] + val(cut(v, room - lw - 1, left), c)
	}

	static func sep(_ above: Set<Int>, _ below: Set<Int>, _ w: Int) -> Bytes {
		var out = Bytes()
		var x = 1
		while x < w - 1 {
			let a = above.contains(x)
			let b = below.contains(x)
			out += a && b ? cross : a ? up : b ? down : bar
			x += 1
		}
		return dim(out) + reset
	}

	static func parse(_ rows: Bytes) -> [[Cell]] {
		var table: [[Cell]] = []
		for line in rows.split(10) {
			let f = line.split(9)
			func at(_ i: Int) -> Bytes {
				i < f.count ? f[i] : []
			}
			if at(0) == [82] {
				table.append([])
			} else if at(0) == [67] && !table.isEmpty {
				table[table.count - 1].append(Cell(label: [at(1), at(5)], value: [at(2), at(6)], colour: at(3), left: at(4) == [76], link: at(7)))
			}
		}
		return table
	}

	static func render(_ rows: Bytes, _ width: Int) -> Bytes {
		let w = max(width, 8) + 2
		var lines: [Bytes] = []
		var marks: [Set<Int>] = []
		for cells in parse(rows) where !cells.isEmpty {
			let n = cells.count
			var tot = n + 1
			for c in cells {
				tot += vis(c.label[0]) + vis(c.value[0]) + 3
			}
			let short = tot > w ? 1 : 0
			let need = cells.map { vis($0.label[short]) + vis($0.value[short]) + 3 }
			let per = max((w - 1) / 10, 1)
			var parts = (n + per - 1) / per
			while parts < n {
				var fits = true
				var c = 0
				for p in 0..<parts {
					let k = n / parts + (p < n % parts ? 1 : 0)
					var t = k + 1
					for i in 0..<k {
						t += need[c + i]
					}
					c += k
					if t > w {
						fits = false
					}
				}
				if fits {
					break
				}
				parts += 1
			}
			var idx = 0
			for p in 0..<parts {
				let k = n / parts + (p < n % parts ? 1 : 0)
				var rem = w - k - 1
				var left = k
				var ws = [Int](repeating: 0, count: k)
				var changed = true
				repeat {
					changed = false
					for i in 0..<k where ws[i] == 0 && left > 0 && need[idx + i] * left <= rem {
						ws[i] = need[idx + i]
						rem -= ws[i]
						left -= 1
						changed = true
					}
				} while changed && left > 0
				if left > 0 {
					let share = rem / left
					var extra = rem - share * left
					for i in 0..<k where ws[i] == 0 {
						ws[i] = share + (extra > 0 ? 1 : 0)
						extra -= 1
					}
				} else {
					let share = rem / k
					let extra = rem - share * k
					for i in 0..<k {
						ws[i] += share + (i < extra ? 1 : 0)
					}
				}
				var o = Bytes()
				var x = 0
				var mark = Set<Int>()
				for i in 0..<k {
					let c = cells[idx + i]
					var txt: Bytes = i > 0 ? [32] : []
					txt += kv(c.label[short], c.value[short], c.colour, ws[i] - (i > 0 ? 2 : 1), c.left)
					if !c.link.isEmpty {
						let open: Bytes = osc + c.link + esc + [92]
						let shut: Bytes = osc + esc + [92]
						txt = open + txt + shut
					}
					o += txt
					o += Bytes(repeating: 32, count: max(ws[i] - vis(txt), 0))
					if i < k - 1 {
						o += dim(wall)
					}
					x += ws[i] + 1
					if i < k - 1 {
						mark.insert(x)
					}
				}
				lines.append(o + reset)
				marks.append(mark)
				idx += k
			}
		}
		var out = Bytes()
		for r in 0..<lines.count {
			if r > 0 {
				out += sep(marks[r - 1], marks[r], w) + [10]
			}
			out += lines[r] + [10]
		}
		return out
	}
}
