import Foundation

// MARK: - Dialog

/// Everything needed to describe one swiftDialog invocation.
public struct DialogSpec: Codable, Equatable {
    /// Enabled options keyed by long name. A flag is stored with an empty value.
    public var options: [String: String]
    /// Repeatable content keyed by `ItemSchema.key`.
    public var items: [String: [DialogItem]]
    /// Raw arguments appended verbatim, for anything the builder does not model.
    public var extraArguments: String
    /// "" (single dialog), "wizard" or "navigation".
    public var cardStyle: String
    /// Pages of a multi-page dialog. Options set here act as defaults for every card.
    public var cards: [DialogCard]

    public init(options: [String: String] = [:], items: [String: [DialogItem]] = [:],
                extraArguments: String = "", cardStyle: String = "", cards: [DialogCard] = []) {
        self.options = options
        self.items = items
        self.extraArguments = extraArguments
        self.cardStyle = cardStyle
        self.cards = cards
    }

    private enum CodingKeys: String, CodingKey {
        case options, items, extraArguments, cardStyle, cards
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        options = try container.decodeIfPresent([String: String].self, forKey: .options) ?? [:]
        items = try container.decodeIfPresent([String: [DialogItem]].self, forKey: .items) ?? [:]
        extraArguments = try container.decodeIfPresent(String.self, forKey: .extraArguments) ?? ""
        cardStyle = try container.decodeIfPresent(String.self, forKey: .cardStyle) ?? ""
        cards = try container.decodeIfPresent([DialogCard].self, forKey: .cards) ?? []
    }

    public func has(_ option: String) -> Bool {
        options[option] != nil
    }

    public func value(_ option: String) -> String {
        options[option] ?? ""
    }

    public func items(_ schema: ItemSchema) -> [DialogItem] {
        items[schema.key] ?? []
    }

    public var usesCards: Bool { !cards.isEmpty }

    /// True when this dialog runs as a notification rather than a window.
    public var isNotification: Bool { has("notification") }

    /// The spec plus the spec of every card.
    public var allPages: [DialogSpec] {
        [self] + cards.map { $0.spec }
    }
}

/// One page of a cards-mode dialog.
public struct DialogCard: Codable, Identifiable, Equatable {
    public var id: UUID
    /// Stable identifier passed to `--onadvance` commands.
    public var cardId: String
    /// Navigation style: sidebar section heading.
    public var section: String
    /// Navigation style: sidebar label (defaults to the card's title).
    public var sidebarTitle: String
    /// Ends the workflow after this card regardless of remaining cards.
    public var finalPage: Bool
    public var spec: DialogSpec

    public init(id: UUID = UUID(), cardId: String = "", section: String = "", sidebarTitle: String = "",
                finalPage: Bool = false, spec: DialogSpec = DialogSpec()) {
        self.id = id
        self.cardId = cardId
        self.section = section
        self.sidebarTitle = sidebarTitle
        self.finalPage = finalPage
        self.spec = spec
    }

    private enum CodingKeys: String, CodingKey {
        case id, cardId, section, sidebarTitle, finalPage, spec
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        cardId = try container.decodeIfPresent(String.self, forKey: .cardId) ?? ""
        section = try container.decodeIfPresent(String.self, forKey: .section) ?? ""
        sidebarTitle = try container.decodeIfPresent(String.self, forKey: .sidebarTitle) ?? ""
        finalPage = try container.decodeIfPresent(Bool.self, forKey: .finalPage) ?? false
        spec = try container.decodeIfPresent(DialogSpec.self, forKey: .spec) ?? DialogSpec()
    }
}

// MARK: - Flow

public enum StepKind: String, Codable, CaseIterable, Identifiable {
    /// Show a dialog, wait for the user, capture input and branch on the exit code.
    case dialog
    /// Show a dialog and drive it through the command file while tasks run.
    case progress
    /// Send a notification and carry on.
    case notification
    /// Run a Jamf binary action.
    case jamf
    /// Run arbitrary shell.
    case script

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .dialog: return "Dialog"
        case .progress: return "Progress"
        case .notification: return "Notification"
        case .jamf: return "Jamf action"
        case .script: return "Shell script"
        }
    }

    public var symbol: String {
        switch self {
        case .dialog: return "macwindow"
        case .progress: return "list.bullet.clipboard"
        case .notification: return "bell.badge"
        case .jamf: return "server.rack"
        case .script: return "terminal"
        }
    }
}

public enum OutcomeAction: String, Codable, CaseIterable, Identifiable {
    case next
    case goto
    case retry
    case exit

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .next: return "Continue to next step"
        case .goto: return "Go to step…"
        case .retry: return "Show this dialog again"
        case .exit: return "Exit script"
        }
    }
}

/// What the script does for a given swiftDialog exit code.
public struct ExitOutcome: Codable, Identifiable, Equatable {
    public var id: UUID
    /// swiftDialog exit code, or -1 for "anything else".
    public var code: Int
    public var action: OutcomeAction
    /// Target for `.goto`.
    public var targetStep: UUID?
    /// Script exit status for `.exit`.
    public var exitStatus: Int
    /// Optional shell run before the action.
    public var command: String

    public static let anyOtherCode = -1

    public init(id: UUID = UUID(), code: Int, action: OutcomeAction = .next, targetStep: UUID? = nil,
                exitStatus: Int = 0, command: String = "") {
        self.id = id
        self.code = code
        self.action = action
        self.targetStep = targetStep
        self.exitStatus = exitStatus
        self.command = command
    }

    private enum CodingKeys: String, CodingKey {
        case id, code, action, targetStep, exitStatus, command
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        code = try container.decodeIfPresent(Int.self, forKey: .code) ?? 0
        action = try container.decodeIfPresent(OutcomeAction.self, forKey: .action) ?? .next
        targetStep = try container.decodeIfPresent(UUID.self, forKey: .targetStep)
        exitStatus = try container.decodeIfPresent(Int.self, forKey: .exitStatus) ?? 0
        command = try container.decodeIfPresent(String.self, forKey: .command) ?? ""
    }

    public static func describe(code: Int) -> String {
        switch code {
        case anyOtherCode: return "Any other exit code"
        case 0: return "0 – Button 1"
        case 2: return "2 – Button 2"
        case 3: return "3 – Info button"
        case 4: return "4 – Timer expired"
        case 5: return "5 – Quit via command file"
        case 10: return "10 – Quit with ⌘Q"
        case 15: return "15 – Window close button"
        case 20: return "20 – Timeout exceeded"
        case 30: return "30 – Authorisation key required"
        case 40: return "40 – Calling process ended"
        case 201: return "201 – Image not found"
        case 202: return "202 – File not found"
        case 203: return "203 – Invalid colour"
        default: return String(code)
        }
    }

    public static let knownCodes: [Int] = [0, 2, 3, 4, 5, 10, 15, 20, 30, 40, 201, 202, 203, anyOtherCode]

    public static var defaults: [ExitOutcome] {
        [
            ExitOutcome(code: 0, action: .next),
            ExitOutcome(code: 2, action: .exit, exitStatus: 0),
            ExitOutcome(code: anyOtherCode, action: .exit, exitStatus: 1)
        ]
    }
}

public enum TaskActionKind: String, Codable, CaseIterable, Identifiable {
    case policyEvent
    case policyID
    case command
    case waitForPath
    case pause

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .policyEvent: return "Jamf policy (custom event)"
        case .policyID: return "Jamf policy (ID)"
        case .command: return "Shell command"
        case .waitForPath: return "Wait for file or app"
        case .pause: return "Pause (seconds)"
        }
    }

    public var valuePrompt: String {
        switch self {
        case .policyEvent: return "installChrome"
        case .policyID: return "42"
        case .command: return "/usr/sbin/softwareupdate --install-rosetta --agree-to-license"
        case .waitForPath: return "/Applications/Google Chrome.app"
        case .pause: return "5"
        }
    }
}

/// One row of a progress step: a list item plus the work that completes it.
public struct ProgressTask: Codable, Identifiable, Equatable {
    public var id: UUID
    public var title: String
    public var subtitle: String
    public var icon: String
    public var action: TaskActionKind
    public var value: String
    /// Progress text shown while the task runs. Defaults to the title.
    public var progressText: String
    /// Optional path that must exist afterwards for the task to count as successful.
    public var successPath: String
    /// Optional path; when it already exists the task is skipped and marked done.
    public var skipIfPath: String

    public init(id: UUID = UUID(), title: String = "", subtitle: String = "", icon: String = "",
                action: TaskActionKind = .policyEvent, value: String = "", progressText: String = "",
                successPath: String = "", skipIfPath: String = "") {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.icon = icon
        self.action = action
        self.value = value
        self.progressText = progressText
        self.successPath = successPath
        self.skipIfPath = skipIfPath
    }

    private enum CodingKeys: String, CodingKey {
        case id, title, subtitle, icon, action, value, progressText, successPath, skipIfPath
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        title = try container.decodeIfPresent(String.self, forKey: .title) ?? ""
        subtitle = try container.decodeIfPresent(String.self, forKey: .subtitle) ?? ""
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? ""
        action = try container.decodeIfPresent(TaskActionKind.self, forKey: .action) ?? .policyEvent
        value = try container.decodeIfPresent(String.self, forKey: .value) ?? ""
        progressText = try container.decodeIfPresent(String.self, forKey: .progressText) ?? ""
        successPath = try container.decodeIfPresent(String.self, forKey: .successPath) ?? ""
        skipIfPath = try container.decodeIfPresent(String.self, forKey: .skipIfPath) ?? ""
    }
}

public enum ProgressCompletion: String, Codable, CaseIterable, Identifiable {
    case waitForButton
    case autoClose

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .waitForButton: return "Enable Button 1 and wait for the user"
        case .autoClose: return "Close automatically"
        }
    }
}

public enum JamfActionKind: String, Codable, CaseIterable, Identifiable {
    case policyEvent
    case policyID
    case recon
    case manage
    case selfService

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .policyEvent: return "Run policy by custom event"
        case .policyID: return "Run policy by ID"
        case .recon: return "Update inventory (recon)"
        case .manage: return "Enforce management framework"
        case .selfService: return "Open Self Service URL"
        }
    }
}

public struct FlowStep: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var kind: StepKind
    public var enabled: Bool
    /// Optional shell test; the step is skipped when it fails, e.g. `[[ ! -d "/Applications/Slack.app" ]]`.
    public var condition: String

    // dialog / progress / notification
    public var dialog: DialogSpec
    // dialog
    public var outcomes: [ExitOutcome]
    // progress
    public var tasks: [ProgressTask]
    public var completion: ProgressCompletion
    public var completionText: String
    public var completionButtonText: String
    public var autoCloseDelay: Int
    public var stopOnFailure: Bool
    // jamf
    public var jamfAction: JamfActionKind
    public var jamfValue: String
    public var jamfArguments: String
    // script
    public var script: String

    public init(id: UUID = UUID(), name: String, kind: StepKind, dialog: DialogSpec = DialogSpec()) {
        self.id = id
        self.name = name
        self.kind = kind
        self.enabled = true
        self.condition = ""
        self.dialog = dialog
        self.outcomes = kind == .dialog ? ExitOutcome.defaults : []
        self.tasks = []
        self.completion = .waitForButton
        self.completionText = "All done"
        self.completionButtonText = "Done"
        self.autoCloseDelay = 5
        self.stopOnFailure = false
        self.jamfAction = .policyEvent
        self.jamfValue = ""
        self.jamfArguments = ""
        self.script = ""
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, kind, enabled, condition, dialog, outcomes, tasks, completion, completionText
        case completionButtonText, autoCloseDelay, stopOnFailure, jamfAction, jamfValue, jamfArguments, script
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Step"
        kind = try container.decodeIfPresent(StepKind.self, forKey: .kind) ?? .dialog
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        condition = try container.decodeIfPresent(String.self, forKey: .condition) ?? ""
        dialog = try container.decodeIfPresent(DialogSpec.self, forKey: .dialog) ?? DialogSpec()
        outcomes = try container.decodeIfPresent([ExitOutcome].self, forKey: .outcomes) ?? []
        tasks = try container.decodeIfPresent([ProgressTask].self, forKey: .tasks) ?? []
        completion = try container.decodeIfPresent(ProgressCompletion.self, forKey: .completion) ?? .waitForButton
        completionText = try container.decodeIfPresent(String.self, forKey: .completionText) ?? ""
        completionButtonText = try container.decodeIfPresent(String.self, forKey: .completionButtonText) ?? ""
        autoCloseDelay = try container.decodeIfPresent(Int.self, forKey: .autoCloseDelay) ?? 5
        stopOnFailure = try container.decodeIfPresent(Bool.self, forKey: .stopOnFailure) ?? false
        jamfAction = try container.decodeIfPresent(JamfActionKind.self, forKey: .jamfAction) ?? .policyEvent
        jamfValue = try container.decodeIfPresent(String.self, forKey: .jamfValue) ?? ""
        jamfArguments = try container.decodeIfPresent(String.self, forKey: .jamfArguments) ?? ""
        script = try container.decodeIfPresent(String.self, forKey: .script) ?? ""
    }

    /// Whether this step shows swiftDialog UI.
    public var usesDialog: Bool {
        kind == .dialog || kind == .progress || kind == .notification
    }
}

/// A Jamf Pro script parameter ($4 – $11) exposed as a named variable.
public struct JamfParameter: Codable, Identifiable, Equatable {
    public var id: UUID
    /// 4 … 11
    public var index: Int
    /// Label shown in the Jamf Pro policy UI.
    public var label: String
    /// Shell variable the script assigns it to.
    public var variable: String
    public var defaultValue: String

    public init(id: UUID = UUID(), index: Int, label: String, variable: String, defaultValue: String = "") {
        self.id = id
        self.index = index
        self.label = label
        self.variable = variable
        self.defaultValue = defaultValue
    }
}

public enum InstallMethod: String, Codable, CaseIterable, Identifiable {
    case none
    case github
    case jamfPolicy

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .none: return "Don't install – exit with an error"
        case .github: return "Download the latest release from GitHub"
        case .jamfPolicy: return "Run a Jamf policy (custom event)"
        }
    }
}

public struct ScriptSettings: Codable, Equatable {
    public var dialogPath: String
    public var installMethod: InstallMethod
    public var installPolicyEvent: String
    public var minimumVersion: String
    /// Wait for a user to be logged in (Finder and Dock running) before starting.
    public var waitForUser: Bool
    /// Launch swiftDialog in the logged-in user's context instead of as root.
    public var runAsUser: Bool
    /// Keep the Mac awake while the script runs.
    public var caffeinate: Bool
    public var logFile: String
    public var organisation: String

    public init() {
        dialogPath = "/usr/local/bin/dialog"
        installMethod = .github
        installPolicyEvent = "installSwiftDialog"
        minimumVersion = "2.5.0"
        waitForUser = true
        runAsUser = false
        caffeinate = false
        logFile = "/var/log/dialogforge.log"
        organisation = ""
    }

    private enum CodingKeys: String, CodingKey {
        case dialogPath, installMethod, installPolicyEvent, minimumVersion, waitForUser, runAsUser
        case caffeinate, logFile, organisation
    }

    public init(from decoder: Decoder) throws {
        let defaults = ScriptSettings()
        let container = try decoder.container(keyedBy: CodingKeys.self)
        dialogPath = try container.decodeIfPresent(String.self, forKey: .dialogPath) ?? defaults.dialogPath
        installMethod = try container.decodeIfPresent(InstallMethod.self, forKey: .installMethod) ?? defaults.installMethod
        installPolicyEvent = try container.decodeIfPresent(String.self, forKey: .installPolicyEvent) ?? defaults.installPolicyEvent
        minimumVersion = try container.decodeIfPresent(String.self, forKey: .minimumVersion) ?? defaults.minimumVersion
        waitForUser = try container.decodeIfPresent(Bool.self, forKey: .waitForUser) ?? defaults.waitForUser
        runAsUser = try container.decodeIfPresent(Bool.self, forKey: .runAsUser) ?? defaults.runAsUser
        caffeinate = try container.decodeIfPresent(Bool.self, forKey: .caffeinate) ?? defaults.caffeinate
        logFile = try container.decodeIfPresent(String.self, forKey: .logFile) ?? defaults.logFile
        organisation = try container.decodeIfPresent(String.self, forKey: .organisation) ?? defaults.organisation
    }
}

/// A saved DialogForge document.
public struct FlowProject: Codable, Equatable {
    public static let currentFormat = 1

    public var format: Int
    public var name: String
    public var notes: String
    public var settings: ScriptSettings
    public var parameters: [JamfParameter]
    public var steps: [FlowStep]

    public init(name: String = "Untitled Flow", steps: [FlowStep] = []) {
        self.format = FlowProject.currentFormat
        self.name = name
        self.notes = ""
        self.settings = ScriptSettings()
        self.parameters = []
        self.steps = steps
    }

    private enum CodingKeys: String, CodingKey {
        case format, name, notes, settings, parameters, steps
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        format = try container.decodeIfPresent(Int.self, forKey: .format) ?? 1
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Untitled Flow"
        notes = try container.decodeIfPresent(String.self, forKey: .notes) ?? ""
        settings = try container.decodeIfPresent(ScriptSettings.self, forKey: .settings) ?? ScriptSettings()
        parameters = try container.decodeIfPresent([JamfParameter].self, forKey: .parameters) ?? []
        steps = try container.decodeIfPresent([FlowStep].self, forKey: .steps) ?? []
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> FlowProject {
        try JSONDecoder().decode(FlowProject.self, from: data)
    }

    /// Default values for the Jamf parameters, keyed by variable name. Used for previews.
    public var previewVariables: [String: String] {
        var values: [String: String] = [:]
        for parameter in parameters where !parameter.variable.isEmpty {
            values[parameter.variable] = parameter.defaultValue
        }
        return values
    }
}
