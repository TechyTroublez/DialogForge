import Foundation

/// How an option is edited and emitted.
public enum OptionKind: Equatable {
    /// Present or absent, takes no value (`--blurscreen`).
    case flag
    /// Single-line text.
    case text
    /// Multi-line text / markdown.
    case multiline
    /// Numeric value.
    case number
    /// One of a fixed set of values.
    case choice
    /// A file path, URL, SF Symbol or other resource reference.
    case resource
    /// A switch that may also carry a value (`--timer` or `--timer 300`).
    case optionalValue
}

public enum OptionCategory: String, CaseIterable, Identifiable {
    case content = "Content"
    case icon = "Icon"
    case banner = "Banner & Background"
    case buttons = "Buttons"
    case inputs = "Inputs"
    case list = "List"
    case media = "Media"
    case progress = "Progress & Timer"
    case window = "Window"
    case notification = "Notification"
    case advanced = "Advanced"

    public var id: OptionCategory { self }

    public var symbol: String {
        switch self {
        case .content: return "text.alignleft"
        case .icon: return "app.badge"
        case .banner: return "photo"
        case .buttons: return "rectangle.and.hand.point.up.left"
        case .inputs: return "character.cursor.ibeam"
        case .list: return "list.bullet"
        case .media: return "play.rectangle"
        case .progress: return "timer"
        case .window: return "macwindow"
        case .notification: return "bell"
        case .advanced: return "gearshape.2"
        }
    }
}

public struct OptionDefinition: Identifiable, Equatable {
    /// The long option name, also the JSON key.
    public let name: String
    public let short: String
    public let label: String
    public let kind: OptionKind
    public let category: OptionCategory
    public let help: String
    public let placeholder: String
    public let choices: [String]
    /// For `.choice`: free-form values are also accepted (e.g. position "100,200").
    public let allowsCustom: Bool

    public var id: String { name }

    init(_ name: String, _ label: String, _ kind: OptionKind, _ category: OptionCategory,
         help: String = "", placeholder: String = "", choices: [String] = [],
         allowsCustom: Bool = false, short: String = "") {
        self.name = name
        self.short = short
        self.label = label
        self.kind = kind
        self.category = category
        self.help = help
        self.placeholder = placeholder
        self.choices = choices
        self.allowsCustom = allowsCustom
    }
}

/// Every swiftDialog option the builder knows about, modelled on swiftDialog 3.x's
/// `CommandLineArguments`. Anything newer can still be passed via "Extra arguments".
public enum OptionCatalog {
    private static let positions = ["topleft", "left", "bottomleft", "top", "center", "bottom",
                                    "topright", "right", "bottomright"]
    private static let iconHelp = "File path, app path, URL, SF=symbol.name[,colour=…,weight=…], qr=text, or info | caution | warning. Append :dark=<value> for a dark-mode alternate."
    private static let fontHelp = "Comma separated: colour=#hex|name, size=<n>, name=<font>, weight=thin|light|regular|medium|heavy|bold, alignment=left|right, shadow=true"
    private static let symbolHelp = "SF Symbol name, optionally followed by position (leading|trailing|top|bottom), rendering mode, size=<n>, color=<name|hex>"

    public static let all: [OptionDefinition] = [
        // MARK: Content
        OptionDefinition("title", "Title", .text, .content,
                         help: "Window title. Use \"none\" to remove the title area.", short: "t"),
        OptionDefinition("titlefont", "Title font", .text, .content,
                         help: fontHelp, placeholder: "colour=#00A4C7,weight=light,size=32"),
        OptionDefinition("message", "Message", .multiline, .content,
                         help: "Plain text or GitHub-flavoured Markdown. A path or URL to a .md file loads its contents.", short: "m"),
        OptionDefinition("messagefont", "Message font", .text, .content,
                         help: "Comma separated: colour=…, size=…, name=…", placeholder: "size=16"),
        OptionDefinition("messagealignment", "Message alignment", .choice, .content,
                         choices: ["left", "centre", "right"]),
        OptionDefinition("messageposition", "Message vertical position", .choice, .content,
                         choices: ["top", "centre", "bottom"]),
        OptionDefinition("style", "Preset style", .choice, .content,
                         help: "Window presets (presentation, mini, centered, alert, caution, warning) or, with Notification enabled, the notification style (banner, alert, pseudo, pseudo-banner, pseudo-alert).",
                         choices: ["presentation", "mini", "centered", "alert", "caution", "warning",
                                   "banner", "pseudo", "pseudo-banner", "pseudo-alert"]),
        OptionDefinition("eula", "EULA mode", .flag, .content,
                         help: "Shows the message in a monospaced, scrollable area suited to licence text."),
        OptionDefinition("webcontent", "Web content", .text, .content,
                         help: "Render a web page in the message area. Use file:///path for local HTML.", placeholder: "https://…"),
        OptionDefinition("displaylog", "Display log file", .resource, .content,
                         help: "Tail a file and show its contents as it is written.", placeholder: "/var/log/jamf.log"),
        OptionDefinition("loghistory", "Log history lines", .number, .content,
                         help: "Lines of existing log to show with Display log file (default 100)."),
        OptionDefinition("infobox", "Info box", .multiline, .content,
                         help: "Markdown shown under the icon when the icon is on the left."),
        OptionDefinition("infoboxwidth", "Info box width", .number, .content),
        OptionDefinition("infotext", "Info text", .optionalValue, .content,
                         help: "Text shown in place of the info button. Empty shows the swiftDialog version."),
        OptionDefinition("helpmessage", "Help message", .multiline, .content,
                         help: "Adds a help button; the Markdown appears when it is clicked."),
        OptionDefinition("helpimage", "Help image", .resource, .content,
                         help: "Image or icon shown beside the help message."),
        OptionDefinition("helpalignment", "Help alignment", .choice, .content,
                         choices: ["left", "centre", "right"]),
        OptionDefinition("helpsheetbuttontext", "Help sheet button text", .text, .content, placeholder: "OK"),
        OptionDefinition("vieworder", "View order", .text, .content,
                         help: "Order of content types or named inputs, with optional [Group] headings. A JSON object allows group descriptions and footers.",
                         placeholder: "[Account],fullname,email,[Preferences],checkbox"),

        // MARK: Icon
        OptionDefinition("icon", "Icon", .resource, .icon, help: iconHelp,
                         placeholder: "SF=laptopcomputer,colour=accent", short: "i"),
        OptionDefinition("iconsize", "Icon size", .number, .icon, help: "Default 150.", placeholder: "150"),
        OptionDefinition("iconalpha", "Icon opacity", .number, .icon, help: "0.0 – 1.0", placeholder: "1.0"),
        OptionDefinition("iconalttext", "Icon accessibility label", .text, .icon),
        OptionDefinition("overlayicon", "Overlay icon", .resource, .icon, help: iconHelp, short: "y"),
        OptionDefinition("hideicon", "Hide icon", .flag, .icon,
                         help: "Removes the icon, giving the message more room.", short: "h"),
        OptionDefinition("centreicon", "Centre icon", .flag, .icon,
                         help: "Places the icon between the title and the message."),

        // MARK: Banner & background
        OptionDefinition("bannerimage", "Banner image", .resource, .banner,
                         help: "Full-width image across the top (850×150 suits the default window). colour=<name|#hex> or gradient=<colours> draws a banner without an image. Implies Hide icon.",
                         short: "n"),
        OptionDefinition("bannertitle", "Title in banner", .optionalValue, .banner,
                         help: "Draws the title on top of the banner image."),
        OptionDefinition("bannertext", "Banner text", .text, .banner,
                         help: "Shorthand for Title in banner plus a title."),
        OptionDefinition("bannerheight", "Banner height", .number, .banner),
        OptionDefinition("background", "Window background image", .resource, .banner,
                         help: "Watermark image behind the dialog content.", short: "bg"),
        OptionDefinition("bgalpha", "Background opacity", .number, .banner,
                         help: "0 – 1, default 0.5", short: "ba"),
        OptionDefinition("bgposition", "Background position", .choice, .banner, choices: positions, short: "bp"),
        OptionDefinition("bgfill", "Background fill", .choice, .banner, choices: ["fill", "fit"], short: "bf"),
        OptionDefinition("bgscale", "Background scale", .choice, .banner, choices: ["fill", "fit"], short: "bs"),
        OptionDefinition("screenbackground", "Screen background image", .resource, .banner,
                         help: "Shows an image full screen behind the dialog and blocks other apps."),

        // MARK: Buttons
        OptionDefinition("button1text", "Button 1 label", .text, .buttons,
                         help: "Default button (Return key, exit code 0). \"none\" hides it.", placeholder: "OK"),
        OptionDefinition("button1action", "Button 1 action", .text, .buttons,
                         help: "URL to open when clicked.", placeholder: "https://… or jamfselfservice://…"),
        OptionDefinition("button1shellaction", "Button 1 shell action", .text, .buttons,
                         help: "Shell command run through /bin/zsh when Button 1 is clicked."),
        OptionDefinition("button1symbol", "Button 1 symbol", .text, .buttons, help: symbolHelp),
        OptionDefinition("button1disabled", "Start with Button 1 disabled", .flag, .buttons,
                         help: "Re-enable with the command file: button1: enable"),
        OptionDefinition("button2", "Show Button 2", .flag, .buttons,
                         help: "Shows Button 2 with its default label (Escape key, exit code 2).", short: "2"),
        OptionDefinition("button2text", "Button 2 label", .text, .buttons, placeholder: "Cancel"),
        OptionDefinition("button2action", "Button 2 action", .text, .buttons,
                         help: "URL or command; used by notifications."),
        OptionDefinition("button2symbol", "Button 2 symbol", .text, .buttons, help: symbolHelp),
        OptionDefinition("button2disabled", "Start with Button 2 disabled", .flag, .buttons),
        OptionDefinition("infobutton", "Show info button", .flag, .buttons,
                         help: "Shows the info button with its default label (exit code 3).", short: "3"),
        OptionDefinition("infobuttontext", "Info button label", .text, .buttons, placeholder: "More Information"),
        OptionDefinition("infobuttonaction", "Info button action", .text, .buttons,
                         help: "URL to open. Setting this stops the info button closing the dialog."),
        OptionDefinition("infobuttonsymbol", "Info button symbol", .text, .buttons, help: symbolHelp),
        OptionDefinition("quitoninfo", "Quit when info button clicked", .flag, .buttons),
        OptionDefinition("buttonstyle", "Button layout", .choice, .buttons,
                         help: "center puts buttons bottom-centre; stack shows full-width stacked buttons. Timer and info button are unavailable.",
                         choices: ["center", "stack"]),
        OptionDefinition("buttonsize", "Button size", .choice, .buttons,
                         choices: ["mini", "small", "regular", "large"]),
        OptionDefinition("buttontextsize", "Button text size", .number, .buttons),
        OptionDefinition("hidedefaultkeyboardaction", "Require ⌘⇧ for Return / Esc", .flag, .buttons,
                         help: "Stops Return and Escape from triggering the buttons by accident."),

        // MARK: Inputs
        OptionDefinition("checkboxstyle", "Checkbox style", .text, .inputs,
                         help: "checkbox or switch, optionally followed by a size: mini | small | regular | large",
                         placeholder: "switch,regular"),
        OptionDefinition("selectstyle", "Select list style", .choice, .inputs,
                         help: "Applies to every select list; individual lists can override it.",
                         choices: ["list", "radio", "searchable", "multiselect"]),
        OptionDefinition("textfieldlivevalidation", "Live regex validation", .flag, .inputs,
                         help: "Shows a green/red indicator while typing in fields with a regex."),
        OptionDefinition("alwaysreturninput", "Return input on any exit code", .flag, .inputs,
                         help: "By default input is only returned when Button 1 is clicked."),

        // MARK: List
        OptionDefinition("liststyle", "List style", .choice, .list, choices: ["expanded", "compact"]),
        OptionDefinition("enablelistselect", "Selectable list items", .flag, .list,
                         help: "Lets users select list rows; the selection is returned in the output."),

        // MARK: Media
        OptionDefinition("video", "Video", .resource, .media,
                         help: "File or URL. youtube=<id> and vimeo=<id> are accepted as shortcuts."),
        OptionDefinition("videocaption", "Video caption", .text, .media),
        OptionDefinition("autoplay", "Autoplay", .optionalValue, .media,
                         help: "Starts video automatically. With an image carousel, the seconds between images.",
                         placeholder: "seconds"),
        OptionDefinition("hidetimer", "Hide carousel timer", .flag, .media),
        OptionDefinition("sound", "Play sound on launch", .resource, .media,
                         placeholder: "/System/Library/Sounds/Glass.aiff"),
        OptionDefinition("showsoundcontrols", "Show sound controls", .flag, .media),

        // MARK: Progress & timer
        OptionDefinition("progress", "Progress bar", .optionalValue, .progress,
                         help: "Shows a progress bar with the given number of steps. Drive it with the command file: progress: <n>",
                         placeholder: "steps"),
        OptionDefinition("progresstext", "Progress text", .text, .progress,
                         help: "Initial text under the progress bar."),
        OptionDefinition("progresstextalignment", "Progress text alignment", .choice, .progress,
                         choices: ["left", "right"]),
        OptionDefinition("timer", "Countdown timer", .optionalValue, .progress,
                         help: "Closes the dialog with exit code 4 when the countdown ends (default 10 seconds).",
                         placeholder: "seconds"),
        OptionDefinition("hidetimerbar", "Hide timer bar", .flag, .progress,
                         help: "Keeps the timeout but shows the normal button instead of the bar."),

        // MARK: Window
        OptionDefinition("width", "Width", .number, .window, help: "Window width in points (default 820).", placeholder: "820"),
        OptionDefinition("height", "Height", .number, .window, help: "Window height in points (default 380).", placeholder: "380"),
        OptionDefinition("position", "Position", .choice, .window,
                         help: "A keyword, or precise x,y coordinates.", choices: positions, allowsCustom: true),
        OptionDefinition("positionoffset", "Position offset", .number, .window, help: "Distance from the screen edge (default 16)."),
        OptionDefinition("small", "Small (-25%)", .flag, .window, short: "s"),
        OptionDefinition("big", "Big (+25%)", .flag, .window, short: "b"),
        OptionDefinition("fullscreen", "Full screen", .flag, .window,
                         help: "Only banner, title, icon and message are shown. No buttons.", short: "f"),
        OptionDefinition("mini", "Mini mode", .flag, .window,
                         help: "Compact fixed-size window: title, icon and a two-line message."),
        OptionDefinition("presentation", "Presentation mode", .flag, .window,
                         help: "Output-only layout for showing a long-running process."),
        OptionDefinition("moveable", "Moveable", .flag, .window, short: "o"),
        OptionDefinition("ontop", "Always on top", .flag, .window, short: "p"),
        OptionDefinition("resizable", "Resizable", .flag, .window),
        OptionDefinition("showonallscreens", "Show on all screens", .flag, .window),
        OptionDefinition("windowbuttons", "Window buttons", .optionalValue, .window,
                         help: "Enables close, minimise and zoom. Optionally limit to a subset.", placeholder: "close,min,max"),
        OptionDefinition("appearance", "Appearance", .choice, .window, choices: ["light", "dark"]),
        OptionDefinition("blurscreen", "Blur screen", .flag, .window,
                         help: "Blurs everything behind the dialog and blocks other apps."),
        OptionDefinition("hideotherapps", "Hide other apps", .flag, .window),
        OptionDefinition("loginwindow", "Show at login window", .flag, .window,
                         help: "Requires a LaunchAgent with LimitLoadToSessionType = LoginWindow."),
        OptionDefinition("showdockicon", "Show Dock icon", .flag, .window),
        OptionDefinition("dockicon", "Dock icon", .resource, .window),
        OptionDefinition("dockiconbadge", "Dock icon badge", .text, .window),
        OptionDefinition("quitkey", "Quit key", .text, .window,
                         help: "Character used with ⌘ to quit instead of q (exit code 10). A capital adds ⇧.", placeholder: "q"),

        // MARK: Notification
        OptionDefinition("notification", "Send as notification", .flag, .notification,
                         help: "Sends a notification instead of showing a window. Uses title, subtitle, message, icon, image, buttons and Preset style."),
        OptionDefinition("subtitle", "Subtitle", .text, .notification),
        OptionDefinition("identifier", "Identifier", .text, .notification,
                         help: "Reusing an identifier replaces the earlier notification; also used with Remove.", short: "id"),
        OptionDefinition("remove", "Remove notification", .flag, .notification,
                         help: "Removes the notification with the given identifier (or all of that style)."),
        OptionDefinition("enablenotificationsounds", "Notification sound", .flag, .notification),
        OptionDefinition("ignorednd", "Ignore Do Not Disturb", .flag, .notification, short: "d"),

        // MARK: Advanced
        OptionDefinition("json", "JSON output", .flag, .advanced,
                         help: "Print results as JSON. Generated scripts add this automatically when they capture input.", short: "j"),
        OptionDefinition("commandfile", "Command file", .resource, .advanced,
                         help: "File swiftDialog watches for update commands (default /var/tmp/dialog.log). Generated scripts manage this for progress steps.",
                         placeholder: "/var/tmp/dialog.log"),
        OptionDefinition("key", "Authorisation key", .text, .advanced,
                         help: "Secret phrase whose SHA256 must match the AuthorisationKey preference in au.csiro.dialog.", short: "k"),
        OptionDefinition("nextbuttontext", "Cards: Next button label", .text, .advanced, placeholder: "Next"),
        OptionDefinition("previousbuttontext", "Cards: Previous button label", .text, .advanced, placeholder: "Previous"),
        OptionDefinition("onadvance", "Cards: on-advance command", .text, .advanced,
                         help: "Shell command run when moving to the next card. Receives the card's input as JSON on stdin; a non-zero exit blocks the move and shows its output."),
        OptionDefinition("published-sessions-dir", "Published sessions directory", .text, .advanced,
                         help: "Where running dialogs publish <pid>.json for discovery. \"none\" disables."),
        OptionDefinition("inspect-mode", "Inspect mode", .flag, .advanced,
                         help: "Launches the inspect-mode dashboards, which use their own config schema."),
        OptionDefinition("inspect-config", "Inspect config file", .resource, .advanced),
        OptionDefinition("verbose", "Verbose logging", .flag, .advanced, short: "vvv"),
        OptionDefinition("debug", "Debug mode", .optionalValue, .advanced,
                         help: "Extra logging and window metrics. A colour value outlines the content areas.", placeholder: "colour")
    ]

    private static let byName: [String: OptionDefinition] = {
        var map: [String: OptionDefinition] = [:]
        for option in all { map[option.name] = option }
        return map
    }()

    private static let aliases: [String: String] = {
        var map: [String: String] = [
            "alignment": "messagealignment",
            "centericon": "centreicon",
            "buttons": "button"
        ]
        for option in all where !option.short.isEmpty { map[option.short] = option.name }
        return map
    }()

    public static func definition(_ name: String) -> OptionDefinition? {
        byName[name]
    }

    /// Resolves a long name, short name or alias to the canonical long name.
    public static func canonicalName(_ name: String) -> String {
        if byName[name] != nil { return name }
        return aliases[name] ?? name
    }

    public static func options(in category: OptionCategory) -> [OptionDefinition] {
        all.filter { $0.category == category }
    }
}
