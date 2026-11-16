import Foundation

public enum FieldKind: Equatable {
    case text
    case multiline
    case bool
    case number
    case choice
    /// One value per line; emitted as a JSON array / CSV.
    case list
}

public struct FieldDefinition: Identifiable, Equatable {
    public let key: String
    public let label: String
    public let kind: FieldKind
    public let help: String
    public let choices: [String]

    public var id: String { key }

    init(_ key: String, _ label: String, _ kind: FieldKind = .text, help: String = "", choices: [String] = []) {
        self.key = key
        self.label = label
        self.kind = kind
        self.help = help
        self.choices = choices
    }
}

/// Describes one kind of repeatable content (text fields, checkboxes, list items…).
public struct ItemSchema: Identifiable, Equatable {
    /// Key used in a swiftDialog JSON config, and to store the items in a `DialogSpec`.
    public let key: String
    /// Command line option that adds one item.
    public let option: String
    public let singular: String
    public let plural: String
    public let category: OptionCategory
    public let symbol: String
    /// The field shown as the item's heading and used as its bare CLI value.
    public let primaryField: String
    /// Whether the item produces a value in swiftDialog's output.
    public let producesOutput: Bool
    public let fields: [FieldDefinition]

    public var id: String { key }

    public func field(_ key: String) -> FieldDefinition? {
        fields.first { $0.key == key }
    }
}

public enum ItemCatalog {
    private static let dependencyHelp = "Condition using other inputs' names, e.g. useproxy, channel=Phone or \"volume>50 && !mute\""

    private static let dependencyFields: [FieldDefinition] = [
        FieldDefinition("enabledif", "Enabled if", help: dependencyHelp),
        FieldDefinition("visibleif", "Visible if", help: dependencyHelp)
    ]

    public static let textField = ItemSchema(
        key: "textfield", option: "textfield", singular: "Text field", plural: "Text fields",
        category: .inputs, symbol: "character.cursor.ibeam", primaryField: "title", producesOutput: true,
        fields: [
            FieldDefinition("title", "Label"),
            FieldDefinition("name", "Output name", help: "Key used in the output instead of the label."),
            FieldDefinition("required", "Required", .bool),
            FieldDefinition("secure", "Secure (password)", .bool, help: "Cannot be combined with a prompt."),
            FieldDefinition("prompt", "Placeholder prompt"),
            FieldDefinition("value", "Initial value"),
            FieldDefinition("detail", "Detail text", help: "Subtext shown under the label."),
            FieldDefinition("regex", "Validation regex"),
            FieldDefinition("regexerror", "Regex error message"),
            FieldDefinition("confirm", "Confirm by typing twice", .bool),
            FieldDefinition("editor", "Multi-line editor", .bool),
            FieldDefinition("fileselect", "File picker", .bool),
            FieldDefinition("filetype", "Allowed file extensions", help: "Space separated, e.g. jpg png pdf"),
            FieldDefinition("path", "File picker start path"),
            FieldDefinition("date", "Date picker", .bool, help: "Returns yyyy-MM-dd."),
            FieldDefinition("time", "Time picker", .bool, help: "Returns HH:mm. Combine with Date picker for both."),
            FieldDefinition("mindate", "Earliest date", help: "YYYYMMDD"),
            FieldDefinition("maxdate", "Latest date", help: "YYYYMMDD"),
            FieldDefinition("mintime", "Earliest time", help: "e.g. 9am or 16:30 (time-only fields)"),
            FieldDefinition("maxtime", "Latest time"),
            FieldDefinition("format", "Date output format", help: "strftime syntax, e.g. +%s for epoch")
        ] + dependencyFields)

    public static let checkbox = ItemSchema(
        key: "checkbox", option: "checkbox", singular: "Checkbox", plural: "Checkboxes",
        category: .inputs, symbol: "checkmark.square", primaryField: "label", producesOutput: true,
        fields: [
            FieldDefinition("label", "Label"),
            FieldDefinition("name", "Output name"),
            FieldDefinition("checked", "Checked by default", .bool),
            FieldDefinition("disabled", "Disabled", .bool),
            FieldDefinition("enableButton1", "Enables Button 1 when ticked", .bool,
                            help: "Combine with \"Start with Button 1 disabled\" for an \"I agree\" gate."),
            FieldDefinition("icon", "Icon", help: "Shown with the switch style."),
            FieldDefinition("detail", "Detail text")
        ] + dependencyFields)

    public static let select = ItemSchema(
        key: "selectitems", option: "selectitem", singular: "Select list", plural: "Select lists",
        category: .inputs, symbol: "list.bullet.rectangle", primaryField: "title", producesOutput: true,
        fields: [
            FieldDefinition("title", "Label"),
            FieldDefinition("name", "Output name"),
            FieldDefinition("values", "Values", .list, help: "One per line. A line of --- inserts a divider."),
            FieldDefinition("default", "Default value"),
            FieldDefinition("style", "Style", .choice, choices: ["radio", "searchable", "multiselect"]),
            FieldDefinition("required", "Required", .bool),
            FieldDefinition("detail", "Detail text")
        ] + dependencyFields)

    public static let slider = ItemSchema(
        key: "slider", option: "slider", singular: "Slider", plural: "Sliders",
        category: .inputs, symbol: "slider.horizontal.3", primaryField: "title", producesOutput: true,
        fields: [
            FieldDefinition("title", "Label"),
            FieldDefinition("name", "Output name"),
            FieldDefinition("min", "Minimum", .number),
            FieldDefinition("max", "Maximum", .number),
            FieldDefinition("step", "Step", .number),
            FieldDefinition("value", "Initial value", .number),
            FieldDefinition("unit", "Unit", help: "Text shown after the value, e.g. %"),
            FieldDefinition("minlabel", "Left label"),
            FieldDefinition("maxlabel", "Right label"),
            FieldDefinition("showvalue", "Show value", .choice, choices: ["true", "false"]),
            FieldDefinition("detail", "Detail text")
        ] + dependencyFields)

    public static let stepper = ItemSchema(
        key: "stepper", option: "stepper", singular: "Stepper", plural: "Steppers",
        category: .inputs, symbol: "plusminus", primaryField: "title", producesOutput: true,
        fields: [
            FieldDefinition("title", "Label"),
            FieldDefinition("name", "Output name"),
            FieldDefinition("min", "Minimum", .number),
            FieldDefinition("max", "Maximum", .number),
            FieldDefinition("step", "Step", .number),
            FieldDefinition("value", "Initial value", .number),
            FieldDefinition("unit", "Unit"),
            FieldDefinition("detail", "Detail text")
        ] + dependencyFields)

    public static let pageButton = ItemSchema(
        key: "button", option: "button", singular: "Page button", plural: "Page buttons",
        category: .inputs, symbol: "button.programmable", primaryField: "label", producesOutput: false,
        fields: [
            FieldDefinition("label", "Label"),
            FieldDefinition("name", "Name"),
            FieldDefinition("symbol", "SF Symbol"),
            FieldDefinition("image", "Image"),
            FieldDefinition("display", "Display", .choice, choices: ["both", "symbol", "label"]),
            FieldDefinition("url", "Open URL"),
            FieldDefinition("shell", "Run command", help: "Runs in the background; the dialog stays open."),
            FieldDefinition("sheet", "Show sheet", .multiline, help: "Markdown, or a path to a .md file."),
            FieldDefinition("confirm", "Confirmation prompt"),
            FieldDefinition("disabled", "Disabled", .bool),
            FieldDefinition("detail", "Detail text")
        ] + dependencyFields)

    public static let listItem = ItemSchema(
        key: "listitem", option: "listitem", singular: "List item", plural: "List items",
        category: .list, symbol: "list.bullet", primaryField: "title", producesOutput: false,
        fields: [
            FieldDefinition("title", "Title"),
            FieldDefinition("subtitle", "Subtitle"),
            FieldDefinition("icon", "Icon"),
            FieldDefinition("status", "Status", .choice,
                            help: "Or an SF Symbol with a colour, e.g. lock.shield.fill-green",
                            choices: ["pending", "wait", "success", "fail", "error"]),
            FieldDefinition("statustext", "Status text"),
            FieldDefinition("action", "Click action URL")
        ])

    public static let image = ItemSchema(
        key: "image", option: "image", singular: "Image", plural: "Images",
        category: .media, symbol: "photo.on.rectangle", primaryField: "imagename", producesOutput: false,
        fields: [
            FieldDefinition("imagename", "File or URL"),
            FieldDefinition("caption", "Caption")
        ])

    public static let all: [ItemSchema] = [textField, checkbox, select, slider, stepper, pageButton, listItem, image]

    public static func schema(_ key: String) -> ItemSchema? {
        all.first { $0.key == key }
    }

    public static func schemas(in category: OptionCategory) -> [ItemSchema] {
        all.filter { $0.category == category }
    }
}

/// One repeatable element. Values are stored as strings keyed by the schema's field keys,
/// which keeps saved projects forward compatible as swiftDialog grows new properties.
public struct DialogItem: Codable, Identifiable, Equatable {
    public var id: UUID
    public var fields: [String: String]

    public init(id: UUID = UUID(), fields: [String: String] = [:]) {
        self.id = id
        self.fields = fields
    }

    public subscript(key: String) -> String {
        get { fields[key] ?? "" }
        set {
            if newValue.isEmpty { fields.removeValue(forKey: key) } else { fields[key] = newValue }
        }
    }

    public func bool(_ key: String) -> Bool {
        fields[key] == "true"
    }

    /// The lines of a `.list` field, trimmed, without blanks.
    public func list(_ key: String) -> [String] {
        self[key].split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
