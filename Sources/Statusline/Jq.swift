import Foundation

enum Jq {
	struct Bad: Error {}

	static func parse(_ bytes: [UInt8]) -> Any? {
		if let value = try? JSONSerialization.jsonObject(with: Data(bytes), options: .fragmentsAllowed) {
			return value
		}
		guard let fixed = mend(bytes) else {
			return nil
		}
		return try? JSONSerialization.jsonObject(with: Data(fixed), options: .fragmentsAllowed)
	}

	static func mend(_ bytes: [UInt8]) -> [UInt8]? {
		var b = bytes
		var i = 0
		var hit = false
		func unit(_ at: Int) -> Int? {
			guard at + 6 <= b.count, b[at] == 92, b[at + 1] == 117 else {
				return nil
			}
			return Int(String(decoding: b[(at + 2)..<(at + 6)], as: UTF8.self), radix: 16)
		}
		while i < b.count {
			if b[i] != 92 {
				i += 1
				continue
			}
			guard let u = unit(i) else {
				i += 2
				continue
			}
			if u >= 0xD800 && u < 0xDC00, let v = unit(i + 6), v >= 0xDC00 && v < 0xE000 {
				i += 12
				continue
			}
			if u >= 0xD800 && u < 0xDC00 {
				return nil
			}
			if u >= 0xDC00 && u < 0xE000 {
				b.replaceSubrange((i + 2)..<(i + 6), with: Array("fffd".utf8))
				hit = true
			}
			i += 6
		}
		return hit ? b : nil
	}

	static func flag(_ v: Any?) -> Bool? {
		guard let n = v as? NSNumber, CFGetTypeID(n) == CFBooleanGetTypeID() else {
			return nil
		}
		return n.boolValue
	}

	static func truthy(_ v: Any?) -> Bool {
		guard let v, !(v is NSNull) else {
			return false
		}
		return flag(v) ?? true
	}

	static func number(_ v: Any?) -> Double? {
		guard let n = v as? NSNumber, flag(v) == nil else {
			return nil
		}
		return n.doubleValue
	}

	static func at(_ v: Any?, _ path: [String]) throws -> Any? {
		var cur = v
		for key in path {
			guard let now = cur, !(now is NSNull) else {
				return nil
			}
			guard let map = now as? NSDictionary else {
				throw Bad()
			}
			cur = map[key]
		}
		return cur
	}

	static func num(_ d: Double) -> String {
		d == d.rounded() && abs(d) < 1e17 ? String(Int64(d)) : "\(d)"
	}

	static func quote(_ s: String) -> String {
		var out = "\""
		for c in s.unicodeScalars {
			switch c.value {
			case 34: out += "\\\""
			case 92: out += "\\\\"
			case 10: out += "\\n"
			case 9: out += "\\t"
			case 13: out += "\\r"
			case 8: out += "\\b"
			case 12: out += "\\f"
			case 0..<32, 127: out += String(format: "\\u%04x", c.value)
			default: out.unicodeScalars.append(c)
			}
		}
		return out + "\""
	}

	static func json(_ v: Any?) -> String {
		guard let v, !(v is NSNull) else {
			return "null"
		}
		if let b = flag(v) {
			return b ? "true" : "false"
		}
		if let n = v as? NSNumber {
			return CFNumberIsFloatType(n) ? "\(n.doubleValue)" : n.stringValue
		}
		if let s = v as? String {
			return quote(s)
		}
		if let list = v as? [Any] {
			return "[" + list.map { json($0) }.joined(separator: ",") + "]"
		}
		if let map = v as? NSDictionary {
			return "{" + map.map { quote("\($0.key)") + ":" + json($0.value) }.joined(separator: ",") + "}"
		}
		return "null"
	}

	static func text(_ v: Any?) -> String {
		(v as? String) ?? json(v)
	}
}
