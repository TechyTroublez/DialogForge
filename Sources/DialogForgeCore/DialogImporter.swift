import Foundation

/// Reads existing swiftDialog commands and JSON configs back into a `DialogSpec`,
/// so scripts you already have can be opened in the builder.
public enum DialogImporter {
    public enum ImportError: Error, LocalizedError {
        case notAnObject

        public var errorDescription: String? {
            "The JSON is not a swiftDialog configuration object."
        }
    }

    private static let cardKeys = ["workflow", "cards", "stack", "block", "pages", "deck"]

    /// Accepts either a JSON config or a `dialog …` command line.
    public static func importText(_ text: String) throws -> DialogSpec {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("{") {
            return try importJSON(trimmed)
        }
        return importCommand(trimmed)
    }

    // MARK: JSON

    public static func importJSON(_ text: String) throws -> DialogSpec {
        let json = try JSONValue.parse(text)
        guard let members = json.objectValue else { throw ImportError.notAnObject }
        return spec(from: members)
    }

    private static func spec(from members: [JSONMember]) -> DialogSpec {
        var spec = DialogSpec()
        var extras: [String] = []
        var legacySelect = DialogItem()

        for member in members {
            let key = member.key
            let value = member.value

            if cardKeys.contains(key), let cards = value.arrayValue {
                spec.cards = cards.compactMap { card(from: $0) }
                continue
            }
            if key == "cardstyle" {
                spec.cardStyle = value.stringValue ?? ""
                continue
            }
            if let schema = ItemCatalog.schema(key) {
                let entries = value.arrayValue ?? [value]
                spec.items[schema.key, default: []] += entries.compactMap { item(from: $0, schema: schema) }
                continue
            }
            switch key {
            case "selecttitle":
                legacySelect["title"] = value.stringValue ?? ""
                continue
            case "selectvalues":
                if let values = value.arrayValue {
                    legacySelect["values"] = values.compactMap { $0.stringValue }.joined(separator: "\n")
                } else {
                    legacySelect["values"] = (value.stringValue ?? "").split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
                }
                continue
            case "selectdefault":
                legacySelect["default"] = value.stringValue ?? ""
                continue
            case "checkboxstyle":
                if value.objectValue != nil {
                    let style = value["style"]?.stringValue ?? "checkbox"
                    let size = value["size"]?.stringValue ?? ""
                    spec.options[key] = size.isEmpty ? style : style + "," + size
                    continue
                }
            case "vieworder":
                if value.objectValue != nil {
                    spec.options[key] = value.serialized(pretty: false)
                    continue
                }
            default:
                break
            }

            let name = OptionCatalog.canonicalName(key)
            if let definition = OptionCatalog.definition(name) {
                if let flag = value.boolValue {
                    // `false` simply means "not set"; `true` on a valued option is ignored by swiftDialog.
                    if flag && (definition.kind == .flag || definition.kind == .optionalValue) {
                        spec.options[name] = ""
                    }
                } else if definition.kind == .flag {
                    spec.options[name] = ""
                } else if let string = value.stringValue {
                    spec.options[name] = string
                } else {
                    spec.options[name] = value.serialized(pretty: false)
                }
            } else if let string = value.stringValue {
                extras.append("--" + key + (value.boolValue == nil ? " " + Shell.quote(string) : ""))
            }
        }

        if !legacySelect["values"].isEmpty {
            spec.items[ItemCatalog.select.key, default: []].append(legacySelect)
        }
        spec.extraArguments = extras.joined(separator: " ")
        return spec
    }

    private static func card(from value: JSONValue) -> DialogCard? {
        guard let members = value.objectValue else { return nil }
        var card = DialogCard()
        var rest: [JSONMember] = []
        for member in members {
            switch member.key {
            case "cardId": card.cardId = member.value.stringValue ?? ""
            case "section": card.section = member.value.stringValue ?? ""
            case "sidebartitle": card.sidebarTitle = member.value.stringValue ?? ""
            case "finalpage": card.finalPage = member.value.boolValue ?? false
            default: rest.append(member)
            }
        }
        card.spec = spec(from: rest)
        return card
    }

    private static func item(from value: JSONValue, schema: ItemSchema) -> DialogItem? {
        var item = DialogItem()
        guard let members = value.objectValue else {
            guard let string = value.stringValue, !string.isEmpty else { return nil }
            item[schema.primaryField] = string
            return item
        }
        for member in members {
            if let list = member.value.arrayValue {
                item[member.key] = list.compactMap { $0.stringValue }.joined(separator: "\n")
            } else if let flag = member.value.boolValue {
                let isTrueFalseChoice = schema.field(member.key)?.kind == .choice
                if flag || isTrueFalseChoice { item[member.key] = flag ? "true" : "false" }
            } else if let string = member.value.stringValue {
                item[member.key] = string
            } else if member.value.objectValue != nil {
                item[member.key] = member.value.serialized(pretty: false)
            }
        }
        return item
    }

    // MARK: Command line

    public static func importCommand(_ text: String) -> DialogSpec {
        var tokens = Shell.tokenize(text)
        // Drop the binary and anything else before the first option.
        while let first = tokens.first, !first.hasPrefix("-") { tokens.removeFirst() }

        var spec = DialogSpec()
        var extras: [String] = []
        var selectTitles: [String] = []
        var selectValues: [String] = []
        var selectDefaults: [String] = []
        var index = 0

        func peekValue() -> String? {
            guard index + 1 < tokens.count else { return nil }
            let next = tokens[index + 1]
            // "---" style values and negative numbers are values, not options.
            if next.hasPrefix("-") && !next.hasPrefix("---") && Double(next) == nil { return nil }
            return next
        }

        func takeValue() -> String? {
            guard let value = peekValue() else { return nil }
            index += 1
            return value
        }

        while index < tokens.count {
            let token = tokens[index]
            guard token.hasPrefix("-") else {
                extras.append(Shell.quote(token))
                index += 1
                continue
            }
            let raw = String(token.drop(while: { $0 == "-" }))
            let name = OptionCatalog.canonicalName(raw)

            switch name {
            case "textfield", "checkbox", "listitem", "slider", "stepper", "button", "selectitem":
                let schemaKey = name == "selectitem" ? ItemCatalog.select.key : name
                if let value = takeValue(), let schema = ItemCatalog.schema(schemaKey) {
                    spec.items[schema.key, default: []].append(parseItem(value, schema: schema))
                }
            case "image", "g":
                if let value = takeValue() {
                    spec.items[ItemCatalog.image.key, default: []].append(DialogItem(fields: ["imagename": value]))
                }
            case "imagecaption":
                if let value = takeValue(), var images = spec.items[ItemCatalog.image.key], !images.isEmpty {
                    images[images.count - 1]["caption"] = value
                    spec.items[ItemCatalog.image.key] = images
                }
            case "selecttitle":
                if let value = takeValue() {
                    if value.hasPrefix("{"), (try? JSONValue.parse(value)) != nil {
                        spec.items[ItemCatalog.select.key, default: []].append(parseItem(value, schema: ItemCatalog.select))
                    } else {
                        selectTitles.append(value)
                    }
                }
            case "selectvalues":
                if let value = takeValue() { selectValues.append(value) }
            case "selectdefault":
                if let value = takeValue() { selectDefaults.append(value) }
            case "jsonstring":
                if let value = takeValue(), let imported = try? importJSON(value) {
                    spec = merge(spec, imported)
                }
            default:
                if let definition = OptionCatalog.definition(name) {
                    switch definition.kind {
                    case .flag:
                        spec.options[name] = ""
                    case .optionalValue:
                        spec.options[name] = takeValue() ?? ""
                    default:
                        if let value = takeValue() { spec.options[name] = value }
                    }
                } else {
                    var extra = token
                    if let value = takeValue() { extra += " " + Shell.quote(value) }
                    extras.append(extra)
                }
            }
            index += 1
        }

        // Select lists are declared as parallel option lists matched by position.
        for (position, values) in selectValues.enumerated() {
            var item = DialogItem()
            if position < selectTitles.count {
                item = parseSelectTitle(selectTitles[position])
            }
            item["values"] = values.split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }.joined(separator: "\n")
            if position < selectDefaults.count { item["default"] = selectDefaults[position] }
            spec.items[ItemCatalog.select.key, default: []].append(item)
        }

        if !extras.isEmpty {
            spec.extraArguments = ([spec.extraArguments] + extras).filter { !$0.isEmpty }.joined(separator: " ")
        }
        return spec
    }

    private static func merge(_ base: DialogSpec, _ other: DialogSpec) -> DialogSpec {
        var result = base
        // Command line options win over JSON, as they do in swiftDialog.
        for (key, value) in other.options where result.options[key] == nil { result.options[key] = value }
        for (key, items) in other.items { result.items[key, default: []] += items }
        if result.cards.isEmpty { result.cards = other.cards }
        if result.cardStyle.isEmpty { result.cardStyle = other.cardStyle }
        if !other.extraArguments.isEmpty {
            result.extraArguments = [result.extraArguments, other.extraArguments]
                .filter { !$0.isEmpty }.joined(separator: " ")
        }
        return result
    }

    private static func unquote(_ text: String) -> String {
        var value = text.trimmingCharacters(in: .whitespaces)
        if value.count >= 2, value.hasPrefix("\""), value.hasSuffix("\"") {
            value = String(value.dropFirst().dropLast())
        }
        return value
    }

    /// Parses either a JSON object or the comma separated form (`Label,required,prompt=Text`).
    static func parseItem(_ text: String, schema: ItemSchema) -> DialogItem {
        if text.hasPrefix("{"), let json = try? JSONValue.parse(text), let parsed = item(from: json, schema: schema) {
            return parsed
        }
        var item = DialogItem()
        var lastKey: String? = nil
        let parts = text.components(separatedBy: ",")
        for (position, part) in parts.enumerated() {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if let separator = trimmed.firstIndex(of: "="), position > 0 || schema.field(String(trimmed[..<separator]).lowercased()) != nil {
                let rawKey = String(trimmed[..<separator])
                let value = unquote(String(trimmed[trimmed.index(after: separator)...]))
                let key = schema.fields.first(where: { $0.key.lowercased() == rawKey.lowercased() })?.key ?? rawKey.lowercased()
                item[key] = value
                lastKey = key
                continue
            }
            if let field = schema.fields.first(where: { $0.key.lowercased() == trimmed.lowercased() && $0.kind == .bool }),
               position > 0 {
                item[field.key] = "true"
                lastKey = nil
                continue
            }
            if item[schema.primaryField].isEmpty && lastKey == nil {
                item[schema.primaryField] = trimmed
            } else if let key = lastKey {
                // A comma inside a value, e.g. a prompt with a comma in it.
                item[key] = item[key] + "," + part
            }
        }
        return item
    }

    private static func parseSelectTitle(_ text: String) -> DialogItem {
        var item = DialogItem()
        for (position, part) in text.components(separatedBy: ",").enumerated() {
            let trimmed = part.trimmingCharacters(in: .whitespaces)
            if position == 0 {
                item["title"] = trimmed
                continue
            }
            switch trimmed.lowercased() {
            case "radio", "searchable", "multiselect":
                item["style"] = trimmed.lowercased()
            case "required":
                item["required"] = "true"
            default:
                if let separator = trimmed.firstIndex(of: "=") {
                    let key = String(trimmed[..<separator]).lowercased()
                    item[key] = unquote(String(trimmed[trimmed.index(after: separator)...]))
                }
            }
        }
        return item
    }
}
