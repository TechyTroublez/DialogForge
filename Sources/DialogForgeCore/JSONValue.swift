import Foundation

/// A small JSON tree with ordered object keys, so generated configs read in a
/// sensible order (title first) and are byte-for-byte deterministic.
public enum JSONValue: Equatable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case object([JSONMember])

    public var stringValue: String? {
        switch self {
        case .string(let value): return value
        case .int(let value): return String(value)
        case .double(let value): return JSONValue.format(value)
        case .bool(let value): return value ? "true" : "false"
        default: return nil
        }
    }

    public var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let value) = self { return value }
        return nil
    }

    public var objectValue: [JSONMember]? {
        if case .object(let value) = self { return value }
        return nil
    }

    public subscript(key: String) -> JSONValue? {
        guard case .object(let members) = self else { return nil }
        return members.first(where: { $0.key == key })?.value
    }

    /// Converts a stored string into the most natural JSON scalar.
    public static func number(from text: String) -> JSONValue {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if let value = Int(trimmed) { return .int(value) }
        if let value = Double(trimmed), value.isFinite { return .double(value) }
        return .string(text)
    }

    static func format(_ value: Double) -> String {
        if value == value.rounded(), abs(value) < 1e15 { return String(Int(value)) }
        return String(value)
    }

    // MARK: Serialising

    public func serialized(pretty: Bool = true) -> String {
        var out = ""
        write(to: &out, indent: 0, pretty: pretty)
        return out
    }

    private func write(to out: inout String, indent: Int, pretty: Bool) {
        let pad = pretty ? String(repeating: "  ", count: indent + 1) : ""
        let closePad = pretty ? String(repeating: "  ", count: indent) : ""
        let newline = pretty ? "\n" : ""
        switch self {
        case .null: out += "null"
        case .bool(let value): out += value ? "true" : "false"
        case .int(let value): out += String(value)
        case .double(let value): out += JSONValue.format(value)
        case .string(let value): out += JSONValue.quote(value)
        case .array(let values):
            if values.isEmpty { out += "[]"; return }
            let scalarsOnly = values.allSatisfy { value in
                if case .array = value { return false }
                if case .object = value { return false }
                return true
            }
            if scalarsOnly {
                out += "["
                for (index, value) in values.enumerated() {
                    if index > 0 { out += pretty ? ", " : "," }
                    value.write(to: &out, indent: indent, pretty: pretty)
                }
                out += "]"
                return
            }
            out += "[" + newline
            for (index, value) in values.enumerated() {
                out += pad
                value.write(to: &out, indent: indent + 1, pretty: pretty)
                if index < values.count - 1 { out += "," }
                out += newline
            }
            out += closePad + "]"
        case .object(let members):
            if members.isEmpty { out += "{}"; return }
            out += "{" + newline
            for (index, member) in members.enumerated() {
                out += pad + JSONValue.quote(member.key) + (pretty ? ": " : ":")
                member.value.write(to: &out, indent: indent + 1, pretty: pretty)
                if index < members.count - 1 { out += "," }
                out += newline
            }
            out += closePad + "}"
        }
    }

    static func quote(_ text: String) -> String {
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
                    let hex = String(scalar.value, radix: 16)
                    out += "\\u" + String(repeating: "0", count: 4 - hex.count) + hex
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        return out + "\""
    }

    // MARK: Parsing

    public static func parse(_ text: String) throws -> JSONValue {
        try JSONDecoder().decode(JSONValue.self, from: Data(text.utf8))
    }
}

public struct JSONMember: Equatable {
    public var key: String
    public var value: JSONValue

    public init(_ key: String, _ value: JSONValue) {
        self.key = key
        self.value = value
    }
}

extension JSONValue: Decodable {
    private struct AnyKey: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }

    public init(from decoder: Decoder) throws {
        if let keyed = try? decoder.container(keyedBy: AnyKey.self) {
            var members: [JSONMember] = []
            for key in keyed.allKeys {
                members.append(JSONMember(key.stringValue, try keyed.decode(JSONValue.self, forKey: key)))
            }
            // Decoder key order is not guaranteed; sort for stable behaviour.
            self = .object(members.sorted { $0.key < $1.key })
            return
        }
        if var unkeyed = try? decoder.unkeyedContainer() {
            var values: [JSONValue] = []
            while !unkeyed.isAtEnd { values.append(try unkeyed.decode(JSONValue.self)) }
            self = .array(values)
            return
        }
        let single = try decoder.singleValueContainer()
        if single.decodeNil() { self = .null; return }
        if let value = try? single.decode(Bool.self) { self = .bool(value); return }
        if let value = try? single.decode(Int.self) { self = .int(value); return }
        if let value = try? single.decode(Double.self) { self = .double(value); return }
        self = .string(try single.decode(String.self))
    }
}
