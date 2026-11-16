import Foundation

public struct ValidationIssue: Identifiable, Equatable {
    public enum Severity: String {
        case error
        case warning
        case info
    }

    public let severity: Severity
    public let message: String
    /// The step the issue belongs to, or nil for project-level issues.
    public let stepID: UUID?

    public var id: String { (stepID?.uuidString ?? "project") + severity.rawValue + message }

    public init(_ severity: Severity, _ message: String, stepID: UUID? = nil) {
        self.severity = severity
        self.message = message
        self.stepID = stepID
    }
}

/// Catches combinations swiftDialog silently ignores, and flow mistakes that would only
/// show up on a managed Mac.
public enum Validator {
    public static func issues(for project: FlowProject) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        let enabled = project.steps.filter { $0.enabled }
        if enabled.isEmpty {
            issues.append(ValidationIssue(.warning, "The flow has no enabled steps."))
        }

        var seenIndexes: Set<Int> = []
        var seenVariables: Set<String> = []
        for parameter in project.parameters {
            if !(4...11).contains(parameter.index) {
                issues.append(ValidationIssue(.error, "Jamf parameter \(parameter.index) is out of range; Jamf Pro provides parameters 4 to 11."))
            }
            if !seenIndexes.insert(parameter.index).inserted {
                issues.append(ValidationIssue(.error, "Jamf parameter \(parameter.index) is defined more than once."))
            }
            if !Shell.isValidVariableName(parameter.variable) {
                issues.append(ValidationIssue(.error, "\"\(parameter.variable)\" is not a valid shell variable name (parameter \(parameter.index))."))
            } else if Shell.reservedVariableNames.contains(parameter.variable) {
                issues.append(ValidationIssue(.error, "\"\(parameter.variable)\" is reserved by zsh or the generated script (parameter \(parameter.index))."))
            } else if !seenVariables.insert(parameter.variable).inserted {
                issues.append(ValidationIssue(.error, "Variable \"\(parameter.variable)\" is used by more than one Jamf parameter."))
            }
        }

        if project.settings.installMethod == .jamfPolicy && project.settings.installPolicyEvent.isEmpty {
            issues.append(ValidationIssue(.error, "swiftDialog is installed by Jamf policy, but no custom event is set."))
        }

        var capturedBy: [String: String] = [:]
        for step in enabled {
            issues += stepIssues(step, in: project)
            guard step.kind == .dialog else { continue }
            for capture in DialogBuilder.captures(for: step.dialog) {
                if let other = capturedBy[capture.variable], other != step.name {
                    issues.append(ValidationIssue(.info, "Variable $\(capture.variable) is set by both \"\(other)\" and \"\(step.name)\"; the later step wins.", stepID: step.id))
                }
                if seenVariables.contains(capture.variable) {
                    issues.append(ValidationIssue(.warning, "Input \"\(capture.outputKey)\" overwrites the Jamf parameter variable $\(capture.variable).", stepID: step.id))
                }
                capturedBy[capture.variable] = step.name
            }
        }
        return issues
    }

    private static func stepIssues(_ step: FlowStep, in project: FlowProject) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        func add(_ severity: ValidationIssue.Severity, _ message: String) {
            issues.append(ValidationIssue(severity, "\(step.name): \(message)", stepID: step.id))
        }

        switch step.kind {
        case .dialog:
            issues += dialogIssues(step.dialog, stepName: step.name, stepID: step.id)
            let enabledIDs = Set(project.steps.filter { $0.enabled }.map { $0.id })
            for outcome in step.outcomes where outcome.action == .goto {
                if let target = outcome.targetStep, enabledIDs.contains(target) { continue }
                add(.error, "exit code \(ExitOutcome.describe(code: outcome.code)) goes to a step that is missing or disabled.")
            }
            let codes = step.outcomes.map { $0.code }
            if Set(codes).count != codes.count {
                add(.warning, "an exit code is handled more than once; only the first is used.")
            }
            if step.dialog.has("timer") && !codes.contains(4) && !codes.contains(ExitOutcome.anyOtherCode) {
                add(.info, "has a timer but no outcome for exit code 4 (timer expired).")
            }
            if (step.dialog.has("button2") || !step.dialog.value("button2text").isEmpty)
                && !codes.contains(2) && !codes.contains(ExitOutcome.anyOtherCode) {
                add(.info, "shows Button 2 but has no outcome for exit code 2.")
            }
        case .progress:
            issues += dialogIssues(step.dialog, stepName: step.name, stepID: step.id)
            if step.tasks.isEmpty { add(.warning, "has no tasks.") }
            for task in step.tasks {
                if task.title.isEmpty { add(.warning, "a task has no title.") }
                if task.value.trimmingCharacters(in: .whitespaces).isEmpty {
                    add(.error, "task \"\(task.title)\" has no \(task.action.label.lowercased()) value.")
                }
                if task.action == .policyID && Int(task.value.trimmingCharacters(in: .whitespaces)) == nil
                    && !task.value.contains("$") {
                    add(.error, "task \"\(task.title)\" needs a numeric policy ID.")
                }
            }
            if !step.dialog.items(ItemCatalog.listItem).isEmpty {
                add(.info, "list items are generated from the tasks; the dialog's own list items are replaced.")
            }
            if step.dialog.usesCards { add(.warning, "cards are not used by progress steps.") }
        case .notification:
            if step.dialog.value("title").isEmpty && step.dialog.value("message").isEmpty {
                add(.warning, "the notification has no title or message.")
            }
            if !project.settings.runAsUser {
                add(.info, "system notifications are delivered to the logged-in user; consider enabling \"Run swiftDialog as the logged-in user\".")
            }
        case .jamf:
            let needsValue = step.jamfAction == .policyEvent || step.jamfAction == .policyID
            if needsValue && step.jamfValue.trimmingCharacters(in: .whitespaces).isEmpty {
                add(.error, "no policy \(step.jamfAction == .policyID ? "ID" : "event") is set.")
            }
        case .script:
            if step.script.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { add(.warning, "the script is empty.") }
        }
        return issues
    }

    public static func dialogIssues(_ spec: DialogSpec, stepName: String = "Dialog", stepID: UUID? = nil) -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        func add(_ severity: ValidationIssue.Severity, _ message: String) {
            issues.append(ValidationIssue(severity, "\(stepName): \(message)", stepID: stepID))
        }

        for (pageIndex, page) in spec.allPages.enumerated() {
            let where_ = pageIndex == 0 ? "" : "card \(pageIndex): "
            let inputs = [ItemCatalog.textField, ItemCatalog.checkbox, ItemCatalog.select, ItemCatalog.slider, ItemCatalog.stepper]
                .flatMap { page.items($0) }
            let style = page.value("style")

            if page.has("fullscreen") && !inputs.isEmpty {
                add(.warning, where_ + "full screen shows only the banner, title, icon and message; inputs will not appear.")
            }
            if (page.has("mini") || style == "mini") && (!inputs.isEmpty || !page.items(ItemCatalog.listItem).isEmpty) {
                add(.warning, where_ + "mini mode shows only the title, icon and a two-line message.")
            }
            if (page.has("presentation") || style == "presentation") && !inputs.isEmpty {
                add(.warning, where_ + "presentation mode is output only; inputs will not appear.")
            }
            if !page.value("buttonstyle").isEmpty && page.has("timer") {
                add(.warning, where_ + "the timer is not available with a centred or stacked button layout.")
            }
            if page.value("buttonstyle") == "stack" && (page.has("infobutton") || !page.value("infobuttontext").isEmpty) {
                add(.warning, where_ + "the info button is not available with stacked buttons.")
            }
            if !page.value("infobox").isEmpty && (page.has("hideicon") || page.has("centreicon") || !page.value("bannerimage").isEmpty) {
                add(.warning, where_ + "the info box only shows when the icon is displayed on the left.")
            }
            if page.has("ontop") && page.has("blurscreen") {
                add(.info, where_ + "blur screen already keeps the dialog in front; Always on top is redundant.")
            }
            if page.has("button1disabled") && !page.items(ItemCatalog.checkbox).contains(where: { $0.bool("enableButton1") })
                && !page.has("commandfile") && !page.has("timer") {
                add(.warning, where_ + "Button 1 starts disabled and nothing re-enables it (a checkbox with \"Enables Button 1\", a timer, or a command file).")
            }
            if page.value("button1text").lowercased() == "none" && !page.has("button2") && page.value("button2text").isEmpty
                && !page.has("timer") && !page.has("commandfile") && !page.has("fullscreen") {
                add(.warning, where_ + "Button 1 is hidden and there is no other way to close the dialog.")
            }
            for field in page.items(ItemCatalog.textField) {
                if field.bool("secure") && !field["prompt"].isEmpty {
                    add(.warning, where_ + "secure text field \"\(field["title"])\" cannot show a prompt.")
                }
                if !field["regexerror"].isEmpty && field["regex"].isEmpty {
                    add(.info, where_ + "text field \"\(field["title"])\" has a regex error message but no regex.")
                }
                if !field["mintime"].isEmpty && field.bool("date") {
                    add(.info, where_ + "text field \"\(field["title"])\": earliest/latest time is ignored when a date is also picked.")
                }
            }
            for select in page.items(ItemCatalog.select) {
                let values = select.list("values")
                if values.isEmpty {
                    add(.error, where_ + "select list \"\(select["title"])\" has no values.")
                } else if !select["default"].isEmpty && !values.contains(select["default"]) && !select["default"].contains("$") {
                    add(.warning, where_ + "select list \"\(select["title"])\": the default \"\(select["default"])\" is not one of its values.")
                }
            }
            if page.isNotification {
                if !inputs.isEmpty { add(.warning, where_ + "notifications cannot show inputs.") }
            } else if ["banner", "pseudo", "pseudo-banner", "pseudo-alert"].contains(style) {
                add(.warning, where_ + "style \"\(style)\" is a notification style; enable \"Send as notification\" or pick a window style.")
            }
            if !page.value("subtitle").isEmpty && !page.isNotification {
                add(.info, where_ + "subtitle is only used by notifications.")
            }
            if page.has("loginwindow") {
                add(.info, where_ + "login window dialogs need a LaunchAgent with LimitLoadToSessionType = LoginWindow; a Jamf policy script alone cannot show them.")
            }
            if !page.items(ItemCatalog.image).isEmpty && !page.value("webcontent").isEmpty {
                add(.info, where_ + "images and web content compete for the same area.")
            }
        }

        if spec.usesCards {
            if spec.cardStyle == "navigation" && !spec.value("infobox").isEmpty {
                add(.warning, "the info box is not available with a navigation sidebar.")
            }
            let ids = spec.cards.map { $0.cardId }.filter { !$0.isEmpty }
            if Set(ids).count != ids.count { add(.warning, "two cards share the same card ID.") }
        } else if !spec.value("onadvance").isEmpty {
            add(.info, "the on-advance command only runs in a dialog with cards.")
        }
        return issues
    }
}
