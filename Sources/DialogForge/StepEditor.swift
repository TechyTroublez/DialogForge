import DialogForgeCore
import SwiftUI

/// Editor for one step of the flow.
@MainActor
struct StepEditor: View {
    @Binding var step: FlowStep
    @State private var tab = "main"

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(16)
            Divider()
            content
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: step.kind.symbol)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                TextField("Step name", text: $step.name)
                    .textFieldStyle(.roundedBorder)
                    .font(.title3)
                Toggle("Enabled", isOn: $step.enabled)
            }
            HStack {
                Text("Only run if")
                    .foregroundStyle(.secondary)
                TextField("optional shell test, e.g. [[ ! -d \"/Applications/Slack.app\" ]]", text: $step.condition)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
            }
            if tabs.count > 1 {
                Picker("", selection: $tab) {
                    ForEach(tabs) { item in
                        Text(item.title).tag(item.id)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
        }
    }

    private struct TabItem: Identifiable {
        let id: String
        let title: String
    }

    private var tabs: [TabItem] {
        switch step.kind {
        case .dialog:
            return [TabItem(id: "main", title: "Dialog"),
                    TabItem(id: "cards", title: "Cards (\(step.dialog.cards.count))"),
                    TabItem(id: "outcomes", title: "Outcomes")]
        case .progress:
            return [TabItem(id: "main", title: "Tasks (\(step.tasks.count))"),
                    TabItem(id: "dialog", title: "Dialog")]
        case .notification, .jamf, .script:
            return [TabItem(id: "main", title: "Main")]
        }
    }

    @ViewBuilder
    private var content: some View {
        switch step.kind {
        case .dialog:
            switch tab {
            case "cards": CardsEditor(spec: $step.dialog)
            case "outcomes": OutcomesEditor(step: $step)
            default: DialogEditor(spec: $step.dialog)
            }
        case .progress:
            if tab == "dialog" {
                DialogEditor(spec: $step.dialog, hiddenSchemas: [ItemCatalog.listItem.key],
                             hiddenOptions: ["progress", "commandfile", "button1disabled", "notification"])
            } else {
                TasksEditor(step: $step)
            }
        case .notification:
            DialogEditor(spec: $step.dialog, hiddenOptions: ["notification"])
        case .jamf:
            JamfStepEditor(step: $step)
        case .script:
            ScriptStepEditor(step: $step)
        }
    }
}

// MARK: - Cards

@MainActor
struct CardsEditor: View {
    @Binding var spec: DialogSpec
    @State private var selectedCard: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Cards turn this dialog into several pages in one window. Options on the Dialog tab act as defaults for every card. Cards are sent to swiftDialog as JSON and need swiftDialog 3 or later.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Picker("Style", selection: $spec.cardStyle) {
                        Text("Wizard (Next / Previous)").tag("")
                        Text("Navigation sidebar").tag("navigation")
                    }
                    .frame(maxWidth: 320)
                    Spacer()
                    Button {
                        let card = DialogCard(cardId: "card\(spec.cards.count + 1)",
                                              spec: DialogSpec(options: ["title": "Page \(spec.cards.count + 1)", "message": ""]))
                        spec.cards.append(card)
                        selectedCard = card.id
                    } label: {
                        Label("Add Card", systemImage: "plus")
                    }
                }
                if !spec.cards.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(Array(spec.cards.enumerated()), id: \.element.id) { index, card in
                                Button {
                                    selectedCard = card.id
                                } label: {
                                    Text("\(index + 1). " + cardTitle(card))
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 5)
                                        .background(currentCardID == card.id ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12),
                                                    in: RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
            .padding(16)
            Divider()
            if let index = currentIndex {
                CardEditor(card: $spec.cards[index],
                           showsNavigationFields: spec.cardStyle == "navigation",
                           onMove: { offset in move(index, by: offset) },
                           onDelete: { delete(index) })
                    .id(spec.cards[index].id)
            } else {
                Text("No cards. This step shows a single dialog.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private var currentCardID: UUID? {
        if let id = selectedCard, spec.cards.contains(where: { $0.id == id }) { return id }
        return spec.cards.first?.id
    }

    private var currentIndex: Int? {
        guard let id = currentCardID else { return nil }
        return spec.cards.firstIndex { $0.id == id }
    }

    private func cardTitle(_ card: DialogCard) -> String {
        if !card.sidebarTitle.isEmpty { return card.sidebarTitle }
        let title = card.spec.value("title")
        if !title.isEmpty { return title }
        return card.cardId.isEmpty ? "Card" : card.cardId
    }

    private func move(_ index: Int, by offset: Int) {
        let target = index + offset
        guard spec.cards.indices.contains(target) else { return }
        spec.cards.swapAt(index, target)
    }

    private func delete(_ index: Int) {
        guard spec.cards.indices.contains(index) else { return }
        selectedCard = nil
        spec.cards.remove(at: index)
    }
}

@MainActor
struct CardEditor: View {
    @Binding var card: DialogCard
    let showsNavigationFields: Bool
    let onMove: (Int) -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                TextField("Card ID", text: $card.cardId)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 160)
                    .help("Stable identifier passed to the on-advance command")
                if showsNavigationFields {
                    TextField("Sidebar section", text: $card.section)
                        .textFieldStyle(.roundedBorder)
                    TextField("Sidebar title", text: $card.sidebarTitle)
                        .textFieldStyle(.roundedBorder)
                } else {
                    Toggle("Final page", isOn: $card.finalPage)
                        .help("Ends the workflow after this card")
                }
                Spacer()
                Button { onMove(-1) } label: { Image(systemName: "chevron.left") }
                    .help("Move earlier")
                Button { onMove(1) } label: { Image(systemName: "chevron.right") }
                    .help("Move later")
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .help("Delete card")
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            Divider()
            DialogEditor(spec: $card.spec, hiddenOptions: ["notification", "json", "commandfile"])
        }
    }
}

// MARK: - Outcomes

@MainActor
struct OutcomesEditor: View {
    @EnvironmentObject private var model: AppModel
    @Binding var step: FlowStep

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                GroupBox {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach($step.outcomes) { $outcome in
                            OutcomeRow(outcome: $outcome, steps: otherSteps) {
                                step.outcomes.removeAll { $0.id == outcome.id }
                            }
                            Divider()
                        }
                        Menu {
                            ForEach(unusedCodes, id: \.self) { code in
                                Button(ExitOutcome.describe(code: code)) {
                                    step.outcomes.append(ExitOutcome(code: code))
                                }
                            }
                        } label: {
                            Label("Add Outcome", systemImage: "plus")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                } label: {
                    Label("When the dialog closes", systemImage: "arrow.triangle.branch")
                        .font(.headline)
                }

                GroupBox {
                    VStack(alignment: .leading, spacing: 6) {
                        let captures = DialogBuilder.captures(for: step.dialog)
                        if captures.isEmpty {
                            Text("This dialog has no inputs. Add text fields, checkboxes, select lists, sliders or steppers to capture values.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("Each input is stored in a shell variable that later steps can use, e.g. in a Jamf recon argument or a message.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                            ForEach(captures) { capture in
                                HStack {
                                    Text("${" + capture.variable + "}")
                                        .font(.system(.body, design: .monospaced))
                                        .textSelection(.enabled)
                                    Text("← \(capture.kind) “\(capture.outputKey)”")
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(4)
                } label: {
                    Label("Captured variables", systemImage: "curlybraces")
                        .font(.headline)
                }
            }
            .padding(16)
        }
    }

    private var otherSteps: [FlowStep] {
        model.project.steps.filter { $0.enabled }
    }

    private var unusedCodes: [Int] {
        let used = Set(step.outcomes.map { $0.code })
        return ExitOutcome.knownCodes.filter { !used.contains($0) }
    }
}

@MainActor
struct OutcomeRow: View {
    @Binding var outcome: ExitOutcome
    let steps: [FlowStep]
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(ExitOutcome.describe(code: outcome.code))
                    .fontWeight(.medium)
                    .frame(minWidth: 190, alignment: .leading)
                Picker("", selection: $outcome.action) {
                    ForEach(OutcomeAction.allCases) { action in
                        Text(action.label).tag(action)
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 220)
                if outcome.action == .goto {
                    Picker("", selection: $outcome.targetStep) {
                        Text("Choose a step").tag(UUID?.none)
                        ForEach(steps) { step in
                            Text(step.name).tag(UUID?.some(step.id))
                        }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }
                if outcome.action == .exit {
                    Text("status")
                        .foregroundStyle(.secondary)
                    TextField("0", value: $outcome.exitStatus, format: .number)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 56)
                }
                Spacer()
                Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    .buttonStyle(.borderless)
            }
            TextField("Optional shell to run first, e.g. log \"User deferred\"", text: $outcome.command, axis: .vertical)
                .textFieldStyle(.roundedBorder)
                .font(.system(.body, design: .monospaced))
                .lineLimit(1...5)
        }
    }
}

// MARK: - Progress tasks

@MainActor
struct TasksEditor: View {
    @Binding var step: FlowStep

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Each task becomes a row in the dialog's list. The script runs them in order, updating the status icon and progress bar through swiftDialog's command file.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach($step.tasks) { $task in
                    TaskEditor(task: $task,
                               onMoveUp: { move(task.id, by: -1) },
                               onMoveDown: { move(task.id, by: 1) },
                               onDelete: { step.tasks.removeAll { $0.id == task.id } })
                }
                Button {
                    step.tasks.append(ProgressTask(title: "New task"))
                } label: {
                    Label("Add Task", systemImage: "plus")
                }

                GroupBox {
                    Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                        GridRow {
                            Text("When finished").gridColumnAlignment(.trailing)
                            Picker("", selection: $step.completion) {
                                ForEach(ProgressCompletion.allCases) { option in
                                    Text(option.label).tag(option)
                                }
                            }
                            .labelsHidden()
                        }
                        GridRow {
                            Text("Finished text")
                            TextField("All done", text: $step.completionText)
                                .textFieldStyle(.roundedBorder)
                        }
                        if step.completion == .waitForButton {
                            GridRow {
                                Text("Button label")
                                TextField("Done", text: $step.completionButtonText)
                                    .textFieldStyle(.roundedBorder)
                            }
                        } else {
                            GridRow {
                                Text("Close after (seconds)")
                                TextField("5", value: $step.autoCloseDelay, format: .number)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 70)
                            }
                        }
                        GridRow {
                            Text("Failures")
                            Toggle("Exit the script with an error if any task fails", isOn: $step.stopOnFailure)
                        }
                    }
                    .padding(4)
                } label: {
                    Label("Completion", systemImage: "flag.checkered")
                        .font(.headline)
                }
            }
            .padding(16)
        }
    }

    private func move(_ id: UUID, by offset: Int) {
        guard let index = step.tasks.firstIndex(where: { $0.id == id }) else { return }
        let target = index + offset
        guard step.tasks.indices.contains(target) else { return }
        step.tasks.swapAt(index, target)
    }
}

@MainActor
struct TaskEditor: View {
    @Binding var task: ProgressTask
    let onMoveUp: () -> Void
    let onMoveDown: () -> Void
    let onDelete: () -> Void

    var body: some View {
        GroupBox {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 6) {
                GridRow {
                    Text("Title").gridColumnAlignment(.trailing)
                    HStack {
                        TextField("Google Chrome", text: $task.title)
                            .textFieldStyle(.roundedBorder)
                        Button(action: onMoveUp) { Image(systemName: "chevron.up") }
                        Button(action: onMoveDown) { Image(systemName: "chevron.down") }
                        Button(role: .destructive, action: onDelete) { Image(systemName: "trash") }
                    }
                    .buttonStyle(.borderless)
                }
                GridRow {
                    Text("Action")
                    HStack {
                        Picker("", selection: $task.action) {
                            ForEach(TaskActionKind.allCases) { kind in
                                Text(kind.label).tag(kind)
                            }
                        }
                        .labelsHidden()
                        .frame(maxWidth: 230)
                        TextField(task.action.valuePrompt, text: $task.value)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(.body, design: .monospaced))
                    }
                }
                GridRow {
                    Text("Icon")
                    HStack {
                        TextField("App path, image, URL or SF=symbol", text: $task.icon)
                            .textFieldStyle(.roundedBorder)
                        Button("Choose…") {
                            if let path = FilePicker.choose() { task.icon = path }
                        }
                    }
                }
                GridRow {
                    Text("Subtitle")
                    TextField("Optional", text: $task.subtitle)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Progress text")
                    TextField("Defaults to the title", text: $task.progressText)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Skip if exists")
                    TextField("Optional path – the task is marked done without running", text: $task.skipIfPath)
                        .textFieldStyle(.roundedBorder)
                }
                GridRow {
                    Text("Verify exists")
                    TextField("Optional path – must exist afterwards or the task fails", text: $task.successPath)
                        .textFieldStyle(.roundedBorder)
                }
            }
            .padding(4)
        }
    }
}

// MARK: - Jamf and script steps

@MainActor
struct JamfStepEditor: View {
    @Binding var step: FlowStep

    var body: some View {
        Form {
            Picker("Action", selection: $step.jamfAction) {
                ForEach(JamfActionKind.allCases) { action in
                    Text(action.label).tag(action)
                }
            }
            switch step.jamfAction {
            case .policyEvent:
                TextField("Custom event", text: $step.jamfValue, prompt: Text("installChrome"))
            case .policyID:
                TextField("Policy ID", text: $step.jamfValue, prompt: Text("42"))
            case .selfService:
                TextField("URL", text: $step.jamfValue, prompt: Text("jamfselfservice://content?entity=policy&id=42&action=view"))
            case .recon, .manage:
                EmptyView()
            }
            if step.jamfAction != .selfService {
                TextField("Extra arguments", text: $step.jamfArguments,
                          prompt: Text("-assetTag \"${assetTag}\" -endUsername \"${email}\""), axis: .vertical)
                    .font(.system(.body, design: .monospaced))
                    .lineLimit(1...4)
                Text("Arguments are added to the jamf command as typed. Use variables captured by earlier dialogs or Jamf parameters, quoted as in the example.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

@MainActor
struct ScriptStepEditor: View {
    @Binding var step: FlowStep

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Runs as part of the generated zsh script. Helpers available: log \"text\", run_as_user <command>, dialog_update \"<command>\", json_value \"$output\" <key>. Set nextStep=\"\" to end the flow early.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $step.script)
                .font(.system(.body, design: .monospaced))
                .border(Color.secondary.opacity(0.25))
        }
        .padding(16)
    }
}
