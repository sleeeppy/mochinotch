import Foundation

/// 사용자 설정 파일을 고칠 때 키 순서와 숫자 표기를 그대로 둔다. `JSONSerialization`은 키 순서를 섞는다.
indirect enum OrderedJSON: Equatable {
    case object([(key: String, value: OrderedJSON)])
    case array([OrderedJSON])
    case string(String)
    /// 원래 표기 그대로.
    case number(String)
    case bool(Bool)
    case null

    static func == (lhs: OrderedJSON, rhs: OrderedJSON) -> Bool {
        lhs.text(indent: nil) == rhs.text(indent: nil)
    }

    subscript(key: String) -> OrderedJSON? {
        get {
            guard case .object(let members) = self else { return nil }
            return members.first(where: { $0.key == key })?.value
        }
        set {
            guard case .object(var members) = self else { return }
            if let index = members.firstIndex(where: { $0.key == key }) {
                if let newValue {
                    members[index].value = newValue
                } else {
                    members.remove(at: index)
                }
            } else if let newValue {
                members.append((key, newValue))
            }
            self = .object(members)
        }
    }

    var arrayValue: [OrderedJSON]? {
        if case .array(let items) = self { return items }
        return nil
    }

    var stringValue: String? {
        if case .string(let text) = self { return text }
        return nil
    }

    /// 안에 들어 있는 모든 `"command"` 문자열.
    var commands: [String] {
        switch self {
        case .object(let members):
            return members.flatMap { member in
                member.key == "command" ? [member.value.stringValue].compactMap { $0 } : member.value.commands
            }
        case .array(let items):
            return items.flatMap(\.commands)
        default:
            return []
        }
    }

    // MARK: 쓰기

    func text(indent: Int? = 2) -> String {
        var out = ""
        write(into: &out, indent: indent, level: 0)
        return out
    }

    private func write(into out: inout String, indent: Int?, level: Int) {
        let newline = indent == nil ? "" : "\n"
        func pad(_ depth: Int) -> String {
            String(repeating: " ", count: (indent ?? 0) * depth)
        }
        switch self {
        case .object(let members):
            if members.isEmpty { out += "{}"; return }
            out += "{" + newline
            for (index, member) in members.enumerated() {
                out += pad(level + 1) + Self.quoted(member.key) + (indent == nil ? ":" : ": ")
                member.value.write(into: &out, indent: indent, level: level + 1)
                out += (index < members.count - 1 ? "," : "") + newline
            }
            out += pad(level) + "}"
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "[" + newline
            for (index, item) in items.enumerated() {
                out += pad(level + 1)
                item.write(into: &out, indent: indent, level: level + 1)
                out += (index < items.count - 1 ? "," : "") + newline
            }
            out += pad(level) + "]"
        case .string(let text):
            out += Self.quoted(text)
        case .number(let raw):
            out += raw
        case .bool(let flag):
            out += flag ? "true" : "false"
        case .null:
            out += "null"
        }
    }

    private static func quoted(_ text: String) -> String {
        var out = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    // MARK: 읽기

    struct ParseError: Error {}

    static func parse(_ text: String) throws -> OrderedJSON {
        var parser = Parser(scalars: Array(text.unicodeScalars))
        parser.skipSpace()
        let value = try parser.value()
        parser.skipSpace()
        guard parser.atEnd else { throw ParseError() }
        return value
    }

    private struct Parser {
        let scalars: [Unicode.Scalar]
        var index = 0

        var atEnd: Bool { index >= scalars.count }

        mutating func skipSpace() {
            while !atEnd, [" ", "\n", "\r", "\t"].contains(scalars[index]) { index += 1 }
        }

        mutating func expect(_ scalar: Unicode.Scalar) throws {
            guard !atEnd, scalars[index] == scalar else { throw ParseError() }
            index += 1
        }

        mutating func literal(_ word: String) throws {
            for scalar in word.unicodeScalars { try expect(scalar) }
        }

        mutating func value() throws -> OrderedJSON {
            guard !atEnd else { throw ParseError() }
            switch scalars[index] {
            case "{":
                index += 1
                var members: [(key: String, value: OrderedJSON)] = []
                skipSpace()
                if !atEnd, scalars[index] == "}" { index += 1; return .object(members) }
                while true {
                    skipSpace()
                    let key = try string()
                    skipSpace()
                    try expect(":")
                    skipSpace()
                    members.append((key, try value()))
                    skipSpace()
                    guard !atEnd else { throw ParseError() }
                    if scalars[index] == "," { index += 1; continue }
                    try expect("}")
                    return .object(members)
                }
            case "[":
                index += 1
                var items: [OrderedJSON] = []
                skipSpace()
                if !atEnd, scalars[index] == "]" { index += 1; return .array(items) }
                while true {
                    skipSpace()
                    items.append(try value())
                    skipSpace()
                    guard !atEnd else { throw ParseError() }
                    if scalars[index] == "," { index += 1; continue }
                    try expect("]")
                    return .array(items)
                }
            case "\"":
                return .string(try string())
            case "t":
                try literal("true")
                return .bool(true)
            case "f":
                try literal("false")
                return .bool(false)
            case "n":
                try literal("null")
                return .null
            default:
                let start = index
                while !atEnd, "+-0123456789.eE".unicodeScalars.contains(scalars[index]) { index += 1 }
                guard index > start else { throw ParseError() }
                var raw = ""
                raw.unicodeScalars.append(contentsOf: scalars[start..<index])
                guard Double(raw) != nil else { throw ParseError() }
                return .number(raw)
            }
        }

        mutating func string() throws -> String {
            try expect("\"")
            var out = String.UnicodeScalarView()
            while !atEnd {
                let scalar = scalars[index]
                index += 1
                switch scalar {
                case "\"":
                    return String(out)
                case "\\":
                    guard !atEnd else { throw ParseError() }
                    let escape = scalars[index]
                    index += 1
                    switch escape {
                    case "\"": out.append("\"")
                    case "\\": out.append("\\")
                    case "/": out.append("/")
                    case "b": out.append("\u{08}")
                    case "f": out.append("\u{0C}")
                    case "n": out.append("\n")
                    case "r": out.append("\r")
                    case "t": out.append("\t")
                    case "u":
                        var code = try hex4()
                        if (0xD800...0xDBFF).contains(code) {
                            try literal("\\u")
                            let low = try hex4()
                            guard (0xDC00...0xDFFF).contains(low) else { throw ParseError() }
                            code = 0x10000 + ((code - 0xD800) << 10) + (low - 0xDC00)
                        }
                        guard let decoded = Unicode.Scalar(code) else { throw ParseError() }
                        out.append(decoded)
                    default:
                        throw ParseError()
                    }
                default:
                    out.append(scalar)
                }
            }
            throw ParseError()
        }

        mutating func hex4() throws -> UInt32 {
            guard index + 4 <= scalars.count else { throw ParseError() }
            var raw = ""
            raw.unicodeScalars.append(contentsOf: scalars[index..<(index + 4)])
            index += 4
            guard let code = UInt32(raw, radix: 16) else { throw ParseError() }
            return code
        }
    }
}
