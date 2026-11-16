import Foundation

/// The commands a running dialog accepts through its command file
/// (`echo "<command>" >> /var/tmp/dialog.log`).
public struct CommandFileCommand: Identifiable, Equatable {
    public let template: String
    public let summary: String

    public var id: String { template }
}

public enum CommandFile {
    public static let defaultPath = "/var/tmp/dialog.log"

    public static let reference: [CommandFileCommand] = [
        CommandFileCommand(template: "title: <text>", summary: "Change the title"),
        CommandFileCommand(template: "message: <text>", summary: "Replace the message (prefix the text with + to append)"),
        CommandFileCommand(template: "alignment: left | center | right", summary: "Message alignment"),
        CommandFileCommand(template: "icon: <path | url | SF=symbol>", summary: "Change the icon"),
        CommandFileCommand(template: "icon: centre | left | default", summary: "Move the icon"),
        CommandFileCommand(template: "icon: size: <number>", summary: "Resize the icon"),
        CommandFileCommand(template: "iconalpha: <0.0 – 1.0>", summary: "Icon opacity"),
        CommandFileCommand(template: "overlayicon: <path | url | SF=symbol>", summary: "Change the overlay icon"),
        CommandFileCommand(template: "bannerimage: <path | url>", summary: "Change the banner image"),
        CommandFileCommand(template: "bannertext: enable | disable | shadow | <text>", summary: "Banner title"),
        CommandFileCommand(template: "image: <path | url>", summary: "Show an image"),
        CommandFileCommand(template: "image: show | hide | clear", summary: "Toggle the image area"),
        CommandFileCommand(template: "imagecaption: <text>", summary: "Image caption"),
        CommandFileCommand(template: "video: <path | url>", summary: "Show a video"),
        CommandFileCommand(template: "webcontent: <url>", summary: "Show a web page"),
        CommandFileCommand(template: "progress: <number>", summary: "Set the progress bar position"),
        CommandFileCommand(template: "progress: increment <number>", summary: "Advance the progress bar"),
        CommandFileCommand(template: "progress: complete", summary: "Fill the progress bar"),
        CommandFileCommand(template: "progress: reset", summary: "Return to an indeterminate bar"),
        CommandFileCommand(template: "progress: hide | show", summary: "Toggle the progress bar"),
        CommandFileCommand(template: "progresstext: <text>", summary: "Text under the progress bar"),
        CommandFileCommand(template: "list: <item>, <item>, …", summary: "Replace the list"),
        CommandFileCommand(template: "list: clear", summary: "Remove the list"),
        CommandFileCommand(template: "listitem: <title>: <status | text>", summary: "Update a list item (simple)"),
        CommandFileCommand(template: "listitem: title: <title>, status: <status>, statustext: <text>",
                           summary: "Update a list item by title"),
        CommandFileCommand(template: "listitem: index: <n>, status: <status>, statustext: <text>",
                           summary: "Update a list item by position (from 0)"),
        CommandFileCommand(template: "listitem: add, title: <text>, status: <status>, statustext: <text>",
                           summary: "Append a list item"),
        CommandFileCommand(template: "listitem: delete, title: <text>", summary: "Remove a list item"),
        CommandFileCommand(template: "button1: enable | disable", summary: "Enable or disable Button 1"),
        CommandFileCommand(template: "button2: enable | disable", summary: "Enable or disable Button 2"),
        CommandFileCommand(template: "button1text: <text>", summary: "Relabel Button 1"),
        CommandFileCommand(template: "button2text: <text>", summary: "Relabel Button 2"),
        CommandFileCommand(template: "buttonsize: mini | small | regular | large", summary: "Button size"),
        CommandFileCommand(template: "infobuttontext: <text>", summary: "Relabel the info button"),
        CommandFileCommand(template: "infotext: <text>", summary: "Change the info text"),
        CommandFileCommand(template: "infobox: <text>", summary: "Change the info box"),
        CommandFileCommand(template: "helpmessage: <text>", summary: "Change the help message"),
        CommandFileCommand(template: "width: <number>", summary: "Resize the window"),
        CommandFileCommand(template: "height: <number>", summary: "Resize the window"),
        CommandFileCommand(template: "position: <position>", summary: "Move the window"),
        CommandFileCommand(template: "blurscreen: enable | disable", summary: "Toggle the screen blur"),
        CommandFileCommand(template: "showdockicon: enable | disable", summary: "Toggle the Dock icon"),
        CommandFileCommand(template: "dockicon: <path | url>", summary: "Change the Dock icon"),
        CommandFileCommand(template: "dockiconbadge: <text>", summary: "Badge the Dock icon"),
        CommandFileCommand(template: "activate:", summary: "Bring the dialog to the front"),
        CommandFileCommand(template: "hide:", summary: "Hide the dialog"),
        CommandFileCommand(template: "show:", summary: "Show the dialog again"),
        CommandFileCommand(template: "quit:", summary: "Close the dialog (exit code 5)")
    ]
}
