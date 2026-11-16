import Foundation

/// Turns a `DialogSpec` into swiftDialog command line arguments or a JSON config.
public enum DialogBuilder {

    // MARK: Command line

    /// Arguments grouped per option (`["--title", "Hello"]`), ready to be rendered one per line.
    ///
    /// A dialog that uses cards can only be expressed as JSON, so it becomes a single
    /// `--jsonstring` group; use `jsonConfig(for:)` when you want to place the JSON yourself.
    public static func argumentGroups(for spec: DialogSpec) -> [[String]] {
        if spec.usesCards {
            let config = jsonConfig(for: spec)
            return [["--jsonstring", config.json.serialized(pretty: false)]] + config.extraArguments
        }
        var groups: [[String]] = []
        for option in OptionCatalog.all {
            guard let value = spec.options[option.name] else { continue }
            switch option.kind {
            case .flag:
                groups.append(["--" + option.name])
            case .optionalValue:
                groups.append(value.isEmpty ? ["--" + option.name] : ["--" + option.name, value])
            default:
                if !value.isEmpty { groups.append(["--" + option.name, value]) }
            }
        }
        for schema in ItemCatalog.all {
            groups += itemGroups(spec.items(schema), schema: schema)
        }
        groups += extraGroups(spec.extraArguments)
        return groups
    }

    public static func arguments(for spec: DialogSpec) -> [String] {
        argumentGroups(for: spec).flatMap { $0 }
    }

    /// Renders a copy-and-paste command, one option per line.
    public static func renderCommand(binary: String, groups: [[String]]) -> String {
        var lines = [Shell.quote(binary)]
        for group in groups {
            lines.append("    " + group.map { Shell.quote($0) }.joined(separator: " "))
        }
        return lines.joined(separator: " \\\n")
    }

    /// Replaces `${variable}` references with preview values, for running outside a script.
    public static func resolve(_ arguments: [String], variables: [String: String]) -> [String] {
        arguments.map { Shell.substitute($0, variables: variables) }
    }

    private static func extraGroups(_ text: String) -> [[String]] {
        var groups: [[String]] = []
        for token in Shell.tokenize(text) {
            if token.hasPrefix("-") || groups.isEmpty {
                groups.append([token])
            } else {
                groups[groups.count - 1].append(token)
            }
        }
        return groups
    }

    private static func usableItems(_ items: [DialogItem], schema: ItemSchema) -> [DialogItem] {
        items.filter { item in
            if schema.key == ItemCatalog.pageButton.key {
                return !item["label"].isEmpty || !item["symbol"].isEmpty || !item["image"].isEmpty
            }
            return !item[schema.primaryField].isEmpty
        }
    }

    private static func itemGroups(_ allItems: [DialogItem], schema: ItemSchema) -> [[String]] {
        let items = usableItems(allItems, schema: schema)
        guard !items.isEmpty else { return [] }

        if schema.key == ItemCatalog.image.key {
            return items.flatMap { item -> [[String]] in
                var groups = [["--image", item["imagename"]]]
                if !item["caption"].isEmpty { groups.append(["--imagecaption", item["caption"]]) }
                return groups
            }
        }

        if schema.key == ItemCatalog.select.key {
            return selectGroups(items)
        }

        return items.map { item in
            if let legacy = legacyArgument(for: item, schema: schema) {
                return ["--" + schema.option, legacy]
            }
            return ["--" + schema.option, jsonObject(for: item, schema: schema).serialized(pretty: false)]
        }
    }

    private static func selectGroups(_ items: [DialogItem]) -> [[String]] {
        let schema = ItemCatalog.select
        let withDefault = items.filter { !$0["default"].isEmpty }.count
        let uniformDefaults = withDefault == 0 || withDefault == items.count
        let allSimple = items.allSatisfy { item in
            legacyArgument(for: item, schema: schema) != nil
                && !item.list("values").contains(where: { $0.contains(",") })
                && !item.list("values").isEmpty
        }
        guard uniformDefaults && allSimple else {
            return items.map { ["--selectitem", jsonObject(for: $0, schema: schema).serialized(pretty: false)] }
        }
        var groups: [[String]] = []
        for item in items {
            var title = item["title"]
            if !item["style"].isEmpty { title += "," + item["style"] }
            if item.bool("required") { title += ",required" }
            for key in ["name", "detail", "enabledif", "visibleif"] where !item[key].isEmpty {
                title += "," + key + "=" + item[key]
            }
            groups.append(["--selecttitle", title])
            groups.append(["--selectvalues", item.list("values").joined(separator: ",")])
            if !item["default"].isEmpty { groups.append(["--selectdefault", item["default"]]) }
        }
        return groups
    }

    /// The classic comma separated form (`Label,required,prompt=Text`), which works on every
    /// swiftDialog version. Returns nil when a value could not survive that syntax, in which
    /// case the item is emitted as a JSON object instead.
    static func legacyArgument(for item: DialogItem, schema: ItemSchema) -> String? {
        let primary = item[schema.primaryField]
        guard !primary.isEmpty, !primary.contains(","), !primary.contains("="), !primary.contains("\"") else {
            return nil
        }
        var parts = [primary]
        for field in schema.fields where field.key != schema.primaryField {
            let value = item[field.key]
            guard !value.isEmpty else { continue }
            // "values" and "default" of a select list travel in their own options.
            if schema.key == ItemCatalog.select.key && ["values", "default", "style", "required", "name",
                                                         "detail", "enabledif", "visibleif"].contains(field.key) {
                if value.contains(",") && field.key != "values" { return nil }
                continue
            }
            switch field.kind {
            case .bool:
                if value == "true" { parts.append(field.key) }
            case .multiline, .list:
                return nil
            default:
                if value.contains(",") || value.contains("\"") || value.contains("\n") { return nil }
                // Text fields are split on `,word=`, so an embedded key=value would be misread.
                if schema.key == ItemCatalog.textField.key && value.contains("=") { return nil }
                parts.append(field.key + "=" + value)
            }
        }
        return parts.joined(separator: ",")
    }

    // MARK: JSON

    public static func jsonObject(for item: DialogItem, schema: ItemSchema) -> JSONValue {
        var members: [JSONMember] = []
        for field in schema.fields {
            let value = item[field.key]
            guard !value.isEmpty else { continue }
            switch field.kind {
            case .bool:
                if value == "true" { members.append(JSONMember(field.key, .bool(true))) }
            case .number:
                members.append(JSONMember(field.key, JSONValue.number(from: value)))
            case .list:
                members.append(JSONMember(field.key, .array(item.list(field.key).map { .string($0) })))
            case .choice where field.choices == ["true", "false"]:
                members.append(JSONMember(field.key, .bool(value == "true")))
            default:
                members.append(JSONMember(field.key, .string(value)))
            }
        }
        return .object(members)
    }

    /// A complete JSON config for `--jsonfile` / `--jsonstring`.
    ///
    /// `extraArguments` holds anything JSON cannot carry (switches with an optional value that
    /// were left empty, and the free-form extra arguments); pass them on the command line too.
    public static func jsonConfig(for spec: DialogSpec) -> (json: JSONValue, extraArguments: [[String]]) {
        var extra: [[String]] = []
        var members = pageMembers(for: spec, extra: &extra)
        if spec.usesCards {
            if !spec.cardStyle.isEmpty { members.insert(JSONMember("cardstyle", .string(spec.cardStyle)), at: 0) }
            var cards: [JSONValue] = []
            for card in spec.cards {
                var cardMembers: [JSONMember] = []
                if !card.cardId.isEmpty { cardMembers.append(JSONMember("cardId", .string(card.cardId))) }
                if !card.section.isEmpty { cardMembers.append(JSONMember("section", .string(card.section))) }
                if !card.sidebarTitle.isEmpty { cardMembers.append(JSONMember("sidebartitle", .string(card.sidebarTitle))) }
                if card.finalPage { cardMembers.append(JSONMember("finalpage", .bool(true))) }
                cardMembers += pageMembers(for: card.spec, extra: &extra)
                cards.append(.object(cardMembers))
            }
            members.append(JSONMember("cards", .array(cards)))
        }
        extra += extraGroups(spec.extraArguments)
        return (.object(members), extra)
    }

    private static func pageMembers(for spec: DialogSpec, extra: inout [[String]]) -> [JSONMember] {
        var members: [JSONMember] = []
        for option in OptionCatalog.all {
            guard let value = spec.options[option.name] else { continue }
            switch option.kind {
            case .flag:
                members.append(JSONMember(option.name, .bool(true)))
            case .optionalValue:
                if value.isEmpty {
                    // swiftDialog ignores `true` for options that expect a value.
                    extra.append(["--" + option.name])
                } else {
                    members.append(JSONMember(option.name, JSONValue.number(from: value)))
                }
            case .number:
                if !value.isEmpty { members.append(JSONMember(option.name, JSONValue.number(from: value))) }
            default:
                guard !value.isEmpty else { continue }
                if option.name == "checkboxstyle" {
                    members.append(JSONMember(option.name, checkboxStyleObject(value)))
                } else if option.name == "vieworder", value.hasPrefix("{"), let parsed = try? JSONValue.parse(value) {
                    members.append(JSONMember(option.name, parsed))
                } else {
                    members.append(JSONMember(option.name, .string(value)))
                }
            }
        }
        for schema in ItemCatalog.all {
            let items = usableItems(spec.items(schema), schema: schema)
            guard !items.isEmpty else { continue }
            members.append(JSONMember(schema.key, .array(items.map { jsonObject(for: $0, schema: schema) })))
        }
        return members
    }

    private static func checkboxStyleObject(_ value: String) -> JSONValue {
        let parts = value.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
        var members = [JSONMember("style", .string(parts.first ?? "checkbox"))]
        if parts.count > 1 { members.append(JSONMember("size", .string(parts[1]))) }
        return .object(members)
    }

    // MARK: Output

    /// The values a dialog returns, and the shell variable each is captured into.
    public struct Capture: Equatable, Identifiable {
        /// Key in swiftDialog's JSON output.
        public let outputKey: String
        public let variable: String
        public let kind: String

        public var id: String { variable + "|" + outputKey }
    }

    public static func captures(for spec: DialogSpec) -> [Capture] {
        var captures: [Capture] = []
        var used: Set<String> = []
        for page in spec.allPages {
            for schema in ItemCatalog.all where schema.producesOutput {
                for item in usableItems(page.items(schema), schema: schema) {
                    let key = item["name"].isEmpty ? item[schema.primaryField] : item["name"]
                    var variable = Shell.variableName(from: key, fallback: "input")
                    if Shell.reservedVariableNames.contains(variable) { variable += "Value" }
                    var suffix = 2
                    let base = variable
                    while used.contains(variable) {
                        variable = base + String(suffix)
                        suffix += 1
                    }
                    used.insert(variable)
                    captures.append(Capture(outputKey: key, variable: variable, kind: schema.singular))
                }
            }
        }
        return captures
    }
}
