import AppKit
import DialogForgeCore
import SwiftUI

/// An approximate, non-interactive sketch of a dialog. It is a layout aid, not a
/// pixel-accurate rendering: use "Run in swiftDialog" for the real window.
@MainActor
struct DialogPreview: View {
    let spec: DialogSpec
    let variables: [String: String]

    /// The page being sketched: the first card (over the shared defaults) when cards are used.
    private var page: DialogSpec {
        guard let card = spec.cards.first else { return spec }
        var merged = spec
        merged.cards = []
        for (key, value) in card.spec.options { merged.options[key] = value }
        for (key, items) in card.spec.items { merged.items[key] = items }
        return merged
    }

    private func text(_ option: String) -> String {
        Shell.substitute(page.value(option), variables: variables)
            .replacingOccurrences(of: "\\n", with: "\n")
    }

    private func resolved(_ value: String) -> String {
        Shell.substitute(value, variables: variables)
    }

    var body: some View {
        if page.isNotification {
            notification
        } else {
            window
        }
    }

    // MARK: Notification

    private var notification: some View {
        HStack(alignment: .top, spacing: 10) {
            IconSketch(value: resolved(page.value("icon")), size: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(text("title").isEmpty ? "Title" : text("title"))
                    .fontWeight(.semibold)
                if !text("subtitle").isEmpty {
                    Text(text("subtitle"))
                        .font(.callout)
                }
                Text(text("message"))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 340, alignment: .leading)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.secondary.opacity(0.3)))
    }

    // MARK: Window

    private var windowSize: CGSize {
        var width = Double(resolved(page.value("width"))) ?? 820
        var height = Double(resolved(page.value("height"))) ?? 380
        let style = page.value("style")
        if page.has("mini") || style == "mini" { width = 540; height = 120 }
        if ["alert", "caution", "warning"].contains(style) { width = 300; height = 300 }
        if page.has("small") { width *= 0.75; height *= 0.75 }
        if page.has("big") { width *= 1.25; height *= 1.25 }
        if spec.cardStyle == "navigation" && !spec.cards.isEmpty {
            width = max(width, 900)
            height = max(height, 600)
        }
        // Sketched at 70% so it fits beside the editor.
        return CGSize(width: max(width, 200) * 0.7, height: max(height, 90) * 0.7)
    }

    private var iconOnLeft: Bool {
        !page.has("hideicon") && !page.has("centreicon") && page.value("bannerimage").isEmpty
            && page.value("icon") != "none" && !["centered", "alert", "caution", "warning"].contains(page.value("style"))
    }

    private var window: some View {
        HStack(spacing: 0) {
            if spec.cardStyle == "navigation" && !spec.cards.isEmpty {
                cardSidebar
                Divider()
            }
            VStack(spacing: 0) {
                if !page.value("bannerimage").isEmpty {
                    banner
                } else if text("title") != "none" {
                    Text(text("title").isEmpty ? "An Important Message" : text("title"))
                        .font(.system(size: 17, weight: .bold))
                        .lineLimit(1)
                        .padding(.top, 12)
                        .padding(.horizontal, 12)
                }
                HStack(alignment: .top, spacing: 14) {
                    if iconOnLeft {
                        VStack(spacing: 8) {
                            IconSketch(value: resolved(page.value("icon")), size: 84)
                            if !text("infobox").isEmpty {
                                Text(markdown(text("infobox")))
                                    .font(.system(size: 9))
                                    .frame(width: 90, alignment: .leading)
                            }
                        }
                    }
                    contentColumn
                }
                .padding(14)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                footer
            }
        }
        .frame(width: windowSize.width, height: windowSize.height)
        .background(Color(nsColor: .windowBackgroundColor))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.secondary.opacity(0.35)))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 5)
    }

    private var cardSidebar: some View {
        VStack(alignment: .leading, spacing: 5) {
            ForEach(Array(spec.cards.enumerated()), id: \.element.id) { index, card in
                Text(card.sidebarTitle.isEmpty ? (card.spec.value("title").isEmpty ? card.cardId : card.spec.value("title")) : card.sidebarTitle)
                    .font(.system(size: 10, weight: index == 0 ? .semibold : .regular))
                    .lineLimit(1)
            }
            Spacer()
        }
        .padding(10)
        .frame(width: 130, alignment: .leading)
        .background(Color.secondary.opacity(0.08))
    }

    private var banner: some View {
        ZStack {
            LinearGradient(colors: [Color.accentColor.opacity(0.8), Color.accentColor.opacity(0.4)],
                           startPoint: .leading, endPoint: .trailing)
            if page.has("bannertitle") || !page.value("bannertext").isEmpty {
                Text(text("bannertext").isEmpty ? text("title") : text("bannertext"))
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(.white)
            } else {
                Text("banner image")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.8))
            }
        }
        .frame(height: 70)
    }

    private var contentColumn: some View {
        VStack(alignment: .leading, spacing: 7) {
            if page.has("centreicon") && !page.has("hideicon") {
                IconSketch(value: resolved(page.value("icon")), size: 60)
                    .frame(maxWidth: .infinity)
            }
            if !text("message").isEmpty {
                Text(markdown(text("message")))
                    .font(.system(size: 11))
                    .frame(maxWidth: .infinity, alignment: messageAlignment)
                    .multilineTextAlignment(textAlignment)
            }
            Group {
                ForEach(page.items(ItemCatalog.image)) { image in
                    placeholder("photo", resolved(image["imagename"]))
                }
                if !page.value("video").isEmpty { placeholder("play.rectangle", resolved(page.value("video"))) }
                if !page.value("webcontent").isEmpty { placeholder("globe", resolved(page.value("webcontent"))) }
            }
            ForEach(page.items(ItemCatalog.listItem)) { item in
                HStack(spacing: 6) {
                    if !item["icon"].isEmpty { IconSketch(value: resolved(item["icon"]), size: 16) }
                    Text(resolved(item["title"])).font(.system(size: 11))
                    Spacer()
                    Text(resolved(item["statustext"])).font(.system(size: 9)).foregroundStyle(.secondary)
                    Image(systemName: statusSymbol(item["status"]))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
            ForEach(page.items(ItemCatalog.checkbox)) { item in
                HStack(spacing: 6) {
                    Image(systemName: item.bool("checked") ? "checkmark.square.fill" : "square")
                    Text(resolved(item["label"]))
                }
                .font(.system(size: 11))
            }
            ForEach(page.items(ItemCatalog.textField)) { item in
                inputRow(resolved(item["title"]) + (item.bool("required") ? " *" : ""),
                         value: item.bool("secure") ? "••••••" : resolved(item["value"].isEmpty ? item["prompt"] : item["value"]),
                         dimmed: item["value"].isEmpty)
            }
            ForEach(page.items(ItemCatalog.select)) { item in
                inputRow(resolved(item["title"]) + (item.bool("required") ? " *" : ""),
                         value: (item["default"].isEmpty ? (item.list("values").first ?? "") : resolved(item["default"])) + "  ⌄",
                         dimmed: false)
            }
            ForEach(page.items(ItemCatalog.slider) + page.items(ItemCatalog.stepper)) { item in
                inputRow(resolved(item["title"]), value: (item["value"].isEmpty ? item["min"] : item["value"]) + " " + item["unit"], dimmed: false)
            }
            ForEach(page.items(ItemCatalog.pageButton)) { item in
                Text(resolved(item["label"].isEmpty ? item["name"] : item["label"]))
                    .font(.system(size: 10))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }

    private var messageAlignment: Alignment {
        switch page.value("messagealignment") {
        case "centre", "center": return .center
        case "right": return .trailing
        default: return page.value("style") == "centered" ? .center : .leading
        }
    }

    private var textAlignment: TextAlignment {
        switch messageAlignment {
        case .center: return .center
        case .trailing: return .trailing
        default: return .leading
        }
    }

    private var footer: some View {
        VStack(spacing: 6) {
            if page.has("progress") {
                ProgressView(value: 0.35)
                    .padding(.horizontal, 14)
                if !text("progresstext").isEmpty {
                    Text(text("progresstext")).font(.system(size: 9)).foregroundStyle(.secondary)
                }
            }
            if !page.has("fullscreen") {
                HStack(spacing: 8) {
                    if page.has("infobutton") || !page.value("infobuttontext").isEmpty {
                        sketchButton(text("infobuttontext").isEmpty ? "More Information" : text("infobuttontext"), prominent: false)
                    } else if page.has("infotext") {
                        Text(text("infotext").isEmpty ? "swiftDialog" : text("infotext"))
                            .font(.system(size: 9))
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if !page.value("helpmessage").isEmpty {
                        Image(systemName: "questionmark.circle").foregroundStyle(.secondary)
                    }
                    if page.has("button2") || !page.value("button2text").isEmpty {
                        sketchButton(text("button2text").isEmpty ? "Cancel" : text("button2text"), prominent: false)
                    }
                    if page.has("timer") && page.value("button1text").isEmpty {
                        ProgressView(value: 0.6).frame(width: 120)
                    } else if text("button1text").lowercased() != "none" {
                        sketchButton(text("button1text").isEmpty ? "OK" : text("button1text"), prominent: !page.has("button1disabled"))
                    }
                }
                .padding(.horizontal, 14)
            }
        }
        .padding(.bottom, 12)
    }

    private func sketchButton(_ title: String, prominent: Bool) -> some View {
        Text(title)
            .font(.system(size: 11))
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .foregroundStyle(prominent ? Color.white : Color.primary)
            .background(prominent ? Color.accentColor : Color.secondary.opacity(0.2), in: RoundedRectangle(cornerRadius: 5))
    }

    private func inputRow(_ label: String, value: String, dimmed: Bool) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 11))
                .frame(width: 110, alignment: .trailing)
            Text(value.isEmpty ? " " : value)
                .font(.system(size: 11))
                .foregroundStyle(dimmed ? Color.secondary : Color.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color(nsColor: .textBackgroundColor), in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.secondary.opacity(0.3)))
        }
    }

    private func placeholder(_ symbol: String, _ caption: String) -> some View {
        HStack {
            Image(systemName: symbol)
            Text(caption).lineLimit(1).truncationMode(.middle)
        }
        .font(.system(size: 10))
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, minHeight: 44)
        .background(Color.secondary.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
    }

    private func statusSymbol(_ status: String) -> String {
        switch status {
        case "success": return "checkmark.circle.fill"
        case "fail": return "xmark.circle.fill"
        case "error": return "exclamationmark.circle.fill"
        case "wait": return "arrow.triangle.2.circlepath"
        case "pending": return "ellipsis.circle"
        default: return "circle"
        }
    }

    private func markdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }
}

/// Draws a swiftDialog icon value: SF Symbols, app and image paths, and the built-in keywords.
@MainActor
struct IconSketch: View {
    let value: String
    let size: CGFloat

    var body: some View {
        Group {
            if let symbol = symbolName {
                Image(systemName: symbol)
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(symbolColor)
            } else if let image = fileImage {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "bubble.left.and.text.bubble.right.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(Color.accentColor)
            }
        }
        .frame(width: size, height: size)
    }

    /// The light-mode part of a `value:dark=other` pair.
    private var primary: String {
        value.components(separatedBy: ":dark=").first ?? value
    }

    private var parts: [String] {
        primary.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
    }

    private var symbolName: String? {
        switch primary.lowercased() {
        case "info": return "info.circle.fill"
        case "caution": return "exclamationmark.triangle.fill"
        case "warning": return "exclamationmark.octagon.fill"
        default: break
        }
        guard let first = parts.first, first.lowercased().hasPrefix("sf=") else { return nil }
        return String(first.dropFirst(3))
    }

    private var symbolColor: Color {
        for part in parts {
            let lower = part.lowercased()
            guard lower.hasPrefix("colour=") || lower.hasPrefix("color=") else { continue }
            let name = String(lower.split(separator: "=", maxSplits: 1).last ?? "")
            switch name {
            case "accent": return .accentColor
            case "black": return .black
            case "blue": return .blue
            case "gray", "grey": return .gray
            case "green": return .green
            case "orange": return .orange
            case "pink": return .pink
            case "purple": return .purple
            case "red": return .red
            case "white": return .white
            case "yellow": return .yellow
            case "mint": return .mint
            case "cyan": return .cyan
            case "indigo": return .indigo
            case "teal": return .teal
            default: return .primary
            }
        }
        return .primary
    }

    private var fileImage: NSImage? {
        let path = (primary as NSString).expandingTildeInPath
        guard path.hasPrefix("/"), FileManager.default.fileExists(atPath: path) else { return nil }
        if path.hasSuffix(".app") { return NSWorkspace.shared.icon(forFile: path) }
        return NSImage(contentsOfFile: path)
    }
}
