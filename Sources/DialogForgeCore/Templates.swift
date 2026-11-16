import Foundation

public struct FlowTemplate: Identifiable {
    public let id: String
    public let name: String
    public let summary: String
    public let symbol: String
    public let make: () -> FlowProject
}

/// Starting points for the MDM workflows swiftDialog is most often used for.
public enum Templates {
    public static let all: [FlowTemplate] = [
        FlowTemplate(id: "blank", name: "Blank flow", summary: "A single empty dialog.",
                     symbol: "doc", make: blank),
        FlowTemplate(id: "enrolment", name: "Enrolment setup", summary: "Welcome, install apps by Jamf policy with live progress, then finish.",
                     symbol: "shippingbox", make: enrolment),
        FlowTemplate(id: "inventory", name: "Collect inventory details", summary: "Ask for asset tag and department, then submit them with recon.",
                     symbol: "barcode.viewfinder", make: inventory),
        FlowTemplate(id: "update", name: "Update prompt with deferral", summary: "Ask the user to update now or later, and trigger the update policy.",
                     symbol: "arrow.down.circle", make: updatePrompt),
        FlowTemplate(id: "restart", name: "Restart countdown", summary: "Warn about a restart with a countdown the user can bring forward.",
                     symbol: "restart.circle", make: restart),
        FlowTemplate(id: "notification", name: "Notification", summary: "Send a notification after a policy completes.",
                     symbol: "bell.badge", make: notification),
        FlowTemplate(id: "onboarding", name: "Multi-page onboarding", summary: "A sidebar-navigated set of cards that collects details in one window.",
                     symbol: "sidebar.left", make: onboarding),
        FlowTemplate(id: "agreement", name: "Policy acceptance", summary: "Show an acceptable-use policy that must be ticked before continuing.",
                     symbol: "checkmark.seal", make: agreement)
    ]

    private static func items(_ rows: [[String: String]]) -> [DialogItem] {
        rows.map { DialogItem(fields: $0) }
    }

    private static let organisation = JamfParameter(index: 4, label: "Organisation name", variable: "orgName",
                                                    defaultValue: "Acme Corp")
    private static let supportURL = JamfParameter(index: 5, label: "Support URL", variable: "supportURL",
                                                  defaultValue: "https://support.example.com")

    public static func blank() -> FlowProject {
        let spec = DialogSpec(options: [
            "title": "Hello",
            "message": "This is a swiftDialog window.",
            "icon": "SF=hand.wave.fill,colour=accent"
        ])
        return FlowProject(name: "Untitled Flow", steps: [FlowStep(name: "Dialog", kind: .dialog, dialog: spec)])
    }

    public static func enrolment() -> FlowProject {
        let welcome = DialogSpec(options: [
            "title": "Welcome to ${orgName}",
            "message": "We'll now set up your Mac with the apps and settings you need.\\n\\nThis takes around 10 minutes. Please keep your Mac connected to power and the network.",
            "icon": "SF=laptopcomputer.and.arrow.down,colour=accent",
            "button1text": "Get Started",
            "infobuttontext": "Need help?",
            "infobuttonaction": "${supportURL}",
            "ontop": "",
            "blurscreen": ""
        ])
        var welcomeStep = FlowStep(name: "Welcome", kind: .dialog, dialog: welcome)
        welcomeStep.outcomes = [
            ExitOutcome(code: 0, action: .next),
            ExitOutcome(code: ExitOutcome.anyOtherCode, action: .next)
        ]

        let progress = DialogSpec(options: [
            "title": "Setting up your Mac",
            "message": "Please wait while we install your apps.",
            "icon": "SF=gearshape.2.fill,colour=accent",
            "progresstext": "Starting…",
            "button1text": "Please wait",
            "height": "520",
            "ontop": "",
            "blurscreen": "",
            "quitkey": "X"
        ])
        var progressStep = FlowStep(name: "Install apps", kind: .progress, dialog: progress)
        progressStep.tasks = [
            ProgressTask(title: "Rosetta", icon: "SF=cpu", action: .command,
                         value: "[[ \"$(/usr/bin/arch)\" != \"arm64\" ]] || /usr/sbin/softwareupdate --install-rosetta --agree-to-license",
                         progressText: "Installing Rosetta…"),
            ProgressTask(title: "Google Chrome", icon: "/Applications/Google Chrome.app", action: .policyEvent,
                         value: "installChrome", progressText: "Installing Google Chrome…",
                         successPath: "/Applications/Google Chrome.app", skipIfPath: "/Applications/Google Chrome.app"),
            ProgressTask(title: "Microsoft Office", icon: "/Applications/Microsoft Word.app", action: .policyEvent,
                         value: "installOffice", progressText: "Installing Microsoft Office…",
                         successPath: "/Applications/Microsoft Word.app", skipIfPath: "/Applications/Microsoft Word.app"),
            ProgressTask(title: "Security settings", icon: "SF=lock.shield.fill", action: .policyEvent,
                         value: "applySecurity", progressText: "Applying security settings…"),
            ProgressTask(title: "Update inventory", icon: "SF=arrow.triangle.2.circlepath", action: .command,
                         value: "/usr/local/bin/jamf recon", progressText: "Updating inventory…")
        ]
        progressStep.completionText = "Your Mac is ready"
        progressStep.completionButtonText = "Finish"

        var project = FlowProject(name: "Enrolment Setup", steps: [welcomeStep, progressStep])
        project.parameters = [organisation, supportURL]
        project.settings.caffeinate = true
        return project
    }

    public static func inventory() -> FlowProject {
        var spec = DialogSpec(options: [
            "title": "Register this Mac",
            "message": "Please confirm a few details so ${orgName} IT can support you.",
            "icon": "SF=barcode.viewfinder,colour=accent",
            "button1text": "Submit",
            "button2text": "Not now",
            "textfieldlivevalidation": ""
        ])
        spec.items[ItemCatalog.textField.key] = items([
            ["title": "Asset Tag", "name": "assetTag", "required": "true", "prompt": "e.g. AC-012345",
             "regex": "^AC-[0-9]{6}$", "regexerror": "Asset tags look like AC-012345"],
            ["title": "Your email", "name": "email", "required": "true", "regex": ".+@.+",
             "regexerror": "Enter a valid email address"]
        ])
        spec.items[ItemCatalog.select.key] = items([
            ["title": "Department", "name": "department", "values": "Engineering\nFinance\nMarketing\nSales\nSupport",
             "required": "true"]
        ])
        let form = FlowStep(name: "Details", kind: .dialog, dialog: spec)

        var recon = FlowStep(name: "Submit to Jamf", kind: .jamf)
        recon.jamfAction = .recon
        recon.jamfArguments = "-assetTag \"${assetTag}\" -email \"${email}\" -department \"${department}\""

        let thanks = DialogSpec(options: [
            "title": "Thank you",
            "message": "Your details have been recorded.",
            "icon": "SF=checkmark.circle.fill,colour=green",
            "style": "mini",
            "timer": "8"
        ])
        var thanksStep = FlowStep(name: "Thanks", kind: .dialog, dialog: thanks)
        thanksStep.outcomes = [ExitOutcome(code: ExitOutcome.anyOtherCode, action: .next)]

        var project = FlowProject(name: "Collect Inventory Details", steps: [form, recon, thanksStep])
        project.parameters = [organisation]
        return project
    }

    public static func updatePrompt() -> FlowProject {
        let spec = DialogSpec(options: [
            "title": "macOS update required",
            "message": "A macOS update is ready to install. It takes about 30 minutes and your Mac will restart.\\n\\nPlease save your work before starting.",
            "icon": "SF=arrow.down.circle.fill,colour=accent",
            "overlayicon": "caution",
            "button1text": "Update now",
            "button2text": "Remind me later",
            "infobuttontext": "What's new",
            "infobuttonaction": "https://support.apple.com/macos",
            "moveable": "",
            "ontop": ""
        ])
        var prompt = FlowStep(name: "Prompt", kind: .dialog, dialog: spec)
        prompt.outcomes = [
            ExitOutcome(code: 0, action: .next),
            ExitOutcome(code: 2, action: .exit, exitStatus: 0, command: "log \"User deferred the update\""),
            ExitOutcome(code: ExitOutcome.anyOtherCode, action: .exit, exitStatus: 0)
        ]
        var policy = FlowStep(name: "Start update", kind: .jamf)
        policy.jamfAction = .policyEvent
        policy.jamfValue = "${updateEvent}"

        var project = FlowProject(name: "Update Prompt", steps: [prompt, policy])
        project.parameters = [JamfParameter(index: 4, label: "Update policy custom event", variable: "updateEvent",
                                            defaultValue: "runMacOSUpdate")]
        return project
    }

    public static func restart() -> FlowProject {
        let spec = DialogSpec(options: [
            "title": "Restart required",
            "message": "Your Mac needs to restart to finish installing updates.\\n\\nIt will restart automatically when the timer ends.",
            "icon": "SF=restart.circle.fill,colour=orange",
            "button1text": "Restart now",
            "timer": "${countdown}",
            "ontop": "",
            "position": "topright",
            "small": ""
        ])
        var prompt = FlowStep(name: "Countdown", kind: .dialog, dialog: spec)
        prompt.outcomes = [
            ExitOutcome(code: 0, action: .next),
            ExitOutcome(code: 4, action: .next),
            ExitOutcome(code: ExitOutcome.anyOtherCode, action: .next)
        ]
        var reboot = FlowStep(name: "Restart", kind: .script)
        reboot.script = "/sbin/shutdown -r +1 > /dev/null 2>&1 &"

        var project = FlowProject(name: "Restart Countdown", steps: [prompt, reboot])
        project.parameters = [JamfParameter(index: 4, label: "Countdown (seconds)", variable: "countdown",
                                            defaultValue: "300")]
        return project
    }

    public static func notification() -> FlowProject {
        let spec = DialogSpec(options: [
            "notification": "",
            "title": "${appName} installed",
            "subtitle": "${orgName} IT",
            "message": "${appName} is ready to use.",
            "icon": "SF=checkmark.seal.fill"
        ])
        var project = FlowProject(name: "Install Notification",
                                  steps: [FlowStep(name: "Notify", kind: .notification, dialog: spec)])
        project.parameters = [organisation,
                              JamfParameter(index: 5, label: "App name", variable: "appName", defaultValue: "Google Chrome")]
        project.settings.runAsUser = true
        return project
    }

    public static func onboarding() -> FlowProject {
        var spec = DialogSpec(options: [
            "title": "${orgName} Setup",
            "icon": "SF=building.2.fill,colour=accent",
            "button1text": "Done",
            "button2text": "Cancel"
        ])
        spec.cardStyle = "navigation"

        let welcome = DialogCard(cardId: "welcome", section: "Getting Started", spec: DialogSpec(options: [
            "title": "Welcome",
            "icon": "SF=hand.wave.fill",
            "message": "Welcome to your new Mac. Work through each page in the sidebar, in any order."
        ]))

        var accountSpec = DialogSpec(options: [
            "title": "Your Account",
            "icon": "SF=person.crop.circle.fill",
            "message": "Tell us who you are."
        ])
        accountSpec.items[ItemCatalog.textField.key] = items([
            ["title": "Full Name", "name": "fullName", "required": "true"],
            ["title": "Email", "name": "email", "required": "true", "regex": ".+@.+",
             "regexerror": "Enter a valid email address"]
        ])
        let account = DialogCard(cardId: "account", section: "Getting Started", spec: accountSpec)

        var teamSpec = DialogSpec(options: [
            "title": "Department",
            "icon": "SF=person.3.fill",
            "message": "Which team are you joining?"
        ])
        teamSpec.items[ItemCatalog.select.key] = items([
            ["title": "Department", "name": "department", "values": "Engineering\nSales\nSupport", "required": "true"]
        ])
        let team = DialogCard(cardId: "department", section: "Getting Started", sidebarTitle: "Team", spec: teamSpec)

        var appsSpec = DialogSpec(options: [
            "title": "Applications",
            "icon": "SF=square.grid.2x2.fill",
            "message": "Choose optional software.",
            "checkboxstyle": "switch,regular"
        ])
        appsSpec.items[ItemCatalog.checkbox.key] = items([
            ["label": "Slack", "name": "installSlack"],
            ["label": "Zoom", "name": "installZoom"]
        ])
        let apps = DialogCard(cardId: "apps", section: "Software", spec: appsSpec)

        spec.cards = [welcome, account, team, apps]
        let cardsStep = FlowStep(name: "Onboarding", kind: .dialog, dialog: spec)

        var slack = FlowStep(name: "Install Slack", kind: .jamf)
        slack.condition = "[[ \"$installSlack\" == \"true\" ]]"
        slack.jamfValue = "installSlack"
        var zoom = FlowStep(name: "Install Zoom", kind: .jamf)
        zoom.condition = "[[ \"$installZoom\" == \"true\" ]]"
        zoom.jamfValue = "installZoom"
        var recon = FlowStep(name: "Record details", kind: .jamf)
        recon.jamfAction = .recon
        recon.jamfArguments = "-realname \"${fullName}\" -email \"${email}\" -department \"${department}\""

        var project = FlowProject(name: "Onboarding", steps: [cardsStep, slack, zoom, recon])
        project.parameters = [organisation]
        project.settings.minimumVersion = "3.0.0"
        return project
    }

    public static func agreement() -> FlowProject {
        var spec = DialogSpec(options: [
            "title": "Acceptable Use Policy",
            "message": "## ${orgName} Acceptable Use Policy\\n\\nReplace this text with your policy, or set the message to the path or URL of a Markdown file.",
            "icon": "SF=checkmark.seal.fill,colour=accent",
            "button1text": "Continue",
            "button1disabled": "",
            "height": "500",
            "ontop": ""
        ])
        spec.items[ItemCatalog.checkbox.key] = items([
            ["label": "I have read and accept this policy", "name": "accepted", "enableButton1": "true"]
        ])
        var step = FlowStep(name: "Policy", kind: .dialog, dialog: spec)
        step.outcomes = [
            ExitOutcome(code: 0, action: .next,
                        command: "/usr/bin/defaults write /Library/Preferences/com.example.policy AcceptedDate -string \"$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)\""),
            ExitOutcome(code: ExitOutcome.anyOtherCode, action: .retry)
        ]
        var project = FlowProject(name: "Policy Acceptance", steps: [step])
        project.parameters = [organisation]
        return project
    }
}
