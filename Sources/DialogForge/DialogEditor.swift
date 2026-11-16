import AppKit
import DialogForgeCore
import SwiftUI

// MARK: - Binding helpers

extension Binding where Value == [String: String] {
    /// Whether an option is switched on (present in the dictionary).
    func isPresent(_ key: String) -> Binding<Bool> {
        Binding<Bool>(
            get: { self.wrappedValue[key] != nil },
            set: { isOn in
                if isOn {
                    if self.wrappedValue[key] == nil { self.wrappedValue[key] = "" }
                } else {
                    self.wrappedValue.removeValue(forKey: key)
                }
            })
    }

    func text(_ key: String) -> Binding<String> {
        Binding<String>(
            get: { self.wrappedValue[key] ?? "" },
            set: { self.wrappedValue[key] = $0 })
    }
}

extension Binding where Value == DialogItem {
    func text(_ key: String) -> Binding<String> {
        Binding<String>(
            get: { self.wrappedValue[key] },
            set: { self.wrappedValue[key] = $0 })
    }

    func flag(_ key: String) -> Binding<Bool> {
        Binding<Bool>(
            get: { self.wrappedValue.bool(key) },
            set: { self.wrappedValue[key] = $0 ? "true" : "" })
    }
}

extension Binding where Value == DialogSpec {
    func itemList(_ schema: ItemSchema) -> Binding<[DialogItem]> {
        Binding<[DialogItem]>(
            get: { self.wrappedValue.items[schema.key] ?? [] },
            set: { self.wrappedValue.items[schema.key] = $0.isEmpty ? nil : $0 })
    }
}

enum FilePicker {
    @MainActor
    static func choose() -> String? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.treatsFilePackagesAsDirectories = false
        return panel.runModal() == .OK ? panel.url?.path : nil
    }
}

// MARK: - Dialog editor

/// Edits every option and repeatable item of one dialog, grouped by category.
@MainActor
struct DialogEditor: View {
    @Binding var spec: DialogSpec
    /// Hides content the surrounding step generates itself (e.g. list items of a progress step).
    var hiddenSchemas: Set<String> = []
    var hiddenOptions: Set<String> = []
    @State private var category: OptionCategory = .content
    @State private var search = ""

    var body: some View {
        HStack(spacing: 0) {
            categoryList
                .frame(width: 190)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    TextField("Filter options", text: $search)
                        .textFieldStyle(.roundedBorder)
                    if search.isEmpty {
                        categoryContent(category)
                    } else {
                        searchResults
                    }
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var categoryList: some View {
        List(OptionCategory.allCases, selection: categorySelection) { item in
            HStack {
                Label(item.rawValue, systemImage: item.symbol)
                Spacer()
                let count = activeCount(in: item)
                if count > 0 {
                    Text("\(count)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .tag(item)
        }
        .listStyle(.inset)
    }

    private var categorySelection: Binding<OptionCategory?> {
        Binding<OptionCategory?>(get: { category }, set: { if let value = $0 { category = value } })
    }

    private func visibleOptions(in category: OptionCategory) -> [OptionDefinition] {
        OptionCatalog.options(in: category).filter { !hiddenOptions.contains($0.name) }
    }

    private func visibleSchemas(in category: OptionCategory) -> [ItemSchema] {
        ItemCatalog.schemas(in: category).filter { !hiddenSchemas.contains($0.key) }
    }

    private func activeCount(in category: OptionCategory) -> Int {
        let options = visibleOptions(in: category).filter { spec.options[$0.name] != nil }.count
        let items = visibleSchemas(in: category).reduce(0) { $0 + spec.items($1).count }
        return options + items
    }

    @ViewBuilder
    private func categoryContent(_ category: OptionCategory) -> some View {
        ForEach(visibleSchemas(in: category)) { schema in
            ItemListEditor(schema: schema, items: $spec.itemList(schema))
        }
        ForEach(visibleOptions(in: category)) { option in
            OptionRow(definition: option, options: $spec.options)
        }
        if category == .advanced {
            VStack(alignment: .leading, spacing: 4) {
                Text("Extra arguments")
                    .font(.headline)
                TextField("--newoption value", text: $spec.extraArguments, axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                Text("Appended to the command as typed. Use this for options newer than this app.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private var searchResults: some View {
        let needle = search.lowercased()
        let matches = OptionCatalog.all.filter { option in
            !hiddenOptions.contains(option.name)
                && (option.name.contains(needle) || option.label.lowercased().contains(needle)
                    || option.help.lowercased().contains(needle))
        }
        if matches.isEmpty {
            Text("No options match “\(search)”.")
                .foregroundStyle(.secondary)
        }
        ForEach(matches) { option in
            OptionRow(definition: option, options: $spec.options)
        }
    }
}

// MARK: - Option row

@MainActor
struct OptionRow: View {
    let definition: OptionDefinition
    @Binding var options: [String: String]

    private var isOn: Bool { options[definition.name] != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Toggle(definition.label, isOn: $options.isPresent(definition.name))
                    .toggleStyle(.checkbox)
                Spacer()
                Text("--" + definition.name)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .textSelection(.enabled)
            }
            if isOn && definition.kind != .flag {
                control
                    .padding(.leading, 20)
            }
            if !definition.help.isEmpty && (isOn || definition.kind == .flag) {
                Text(definition.help)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.leading, 20)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .help(definition.help)
    }

    private var value: Binding<String> { $options.text(definition.name) }

    @ViewBuilder
    private var control: some View {
        switch definition.kind {
        case .flag:
            EmptyView()
        case .multiline:
            TextEditor(text: value)
                .font(.body)
                .frame(minHeight: 90, maxHeight: 220)
                .border(Color.secondary.opacity(0.25))
        case .choice:
            HStack {
                Picker("", selection: value) {
                    Text("Choose…").tag("")
                    ForEach(pickerChoices, id: \.self) { choice in
                        Text(choice).tag(choice)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
                if definition.allowsCustom {
                    TextField("or a custom value", text: value)
                        .textFieldStyle(.roundedBorder)
                }
            }
        case .resource:
            HStack {
                TextField(definition.placeholder, text: value)
                    .textFieldStyle(.roundedBorder)
                Button("Choose…") {
                    if let path = FilePicker.choose() { value.wrappedValue = path }
                }
            }
        case .text, .number, .optionalValue:
            TextField(definition.placeholder, text: value)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: definition.kind == .text ? .infinity : 220)
        }
    }

    /// The fixed choices, plus the current value when it is a custom one, so the picker can show it.
    private var pickerChoices: [String] {
        let current = value.wrappedValue
        if current.isEmpty || definition.choices.contains(current) { return definition.choices }
        return definition.choices + [current]
    }
}

// MARK: - Repeatable items

@MainActor
struct ItemListEditor: View {
    let schema: ItemSchema
    @Binding var items: [DialogItem]
    @State private var expanded: Set<UUID> = []

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 6) {
                if items.isEmpty {
                    Text("No \(schema.plural.lowercased()) yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ForEach($items) { $item in
                    ItemEditor(schema: schema, item: $item, isExpanded: expansion(for: item.id),
                               onMoveUp: { move(item.id, by: -1) },
                               onMoveDown: { move(item.id, by: 1) },
                               onDelete: { items.removeAll { $0.id == item.id } })
                    Divider()
                }
                Button {
                    let item = DialogItem()
                    items.append(item)
                    expanded.insert(item.id)
                } label: {
                    Label("Add \(schema.singular)", systemImage: "plus")
                }
                .buttonStyle(.borderless)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Label(schema.plural, systemImage: schema.symbol)
                .font(.headline)
        }
    }

    private func expansion(for id: UUID) -> Binding<Bool> {
        Binding<Bool>(
            get: { expanded.contains(id) },
            set: { isOpen in
                if isOpen { expanded.insert(id) } else { expanded.remove(id) }
            })
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard items.indices.contains(target) else { return }
        items.swapAt(index, target)
    }
}

@MainActor
struct ItemEditor: View {
    let schema: ItemSchema
    @Binding var item: DialogItem
    @Binding var isExpanded: Bool
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        DisclosureGroup(isExpanded: $isExpanded) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                ForEach(schema.fields.filter { $0.key != schema.primaryField }) { field in
                    GridRow {
                        Text(field.label)
                            .foregroundStyle(.secondary)
                            .gridColumnAlignment(.trailing)
                        fieldControl(field)
                    }
                }
            }
            .padding(.vertical, 6)
        } label: {
            HStack {
                TextField(primaryLabel, text: $item.text(schema.primaryField))
                    .textFieldStyle(.roundedBorder)
                Button(action: onMoveUp) { Image(systemName: "chevron.up") }
                    .help("Move up")
                Button(action: onMoveDown) { Image(systemName: "chevron.down") }
                    .help("Move down")
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .help("Remove")
            }
            .buttonStyle(.borderless)
        }
    }

    private var primaryLabel: String {
        schema.field(schema.primaryField)?.label ?? schema.singular
    }

    @ViewBuilder
    private func fieldControl(_ field: FieldDefinition) -> some View {
        switch field.kind {
        case .bool:
            Toggle("", isOn: $item.flag(field.key))
                .labelsHidden()
                .help(field.help)
        case .choice:
            Picker("", selection: $item.text(field.key)) {
                Text("Default").tag("")
                ForEach(choices(for: field), id: \.self) { choice in
                    Text(choice).tag(choice)
                }
            }
            .labelsHidden()
            .frame(maxWidth: 200)
            .help(field.help)
        case .list, .multiline:
            VStack(alignment: .leading, spacing: 2) {
                TextEditor(text: $item.text(field.key))
                    .font(.body)
                    .frame(minHeight: 70, maxHeight: 160)
                    .border(Color.secondary.opacity(0.25))
                if !field.help.isEmpty {
                    Text(field.help)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        case .text, .number:
            TextField(field.help, text: $item.text(field.key))
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: field.kind == .number ? 140 : .infinity)
                .help(field.help)
        }
    }

    private func choices(for field: FieldDefinition) -> [String] {
        let current = item[field.key]
        if current.isEmpty || field.choices.contains(current) { return field.choices }
        return field.choices + [current]
    }
}
