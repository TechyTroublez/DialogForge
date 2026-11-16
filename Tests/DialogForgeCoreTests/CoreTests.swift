import XCTest
@testable import DialogForgeCore

final class ShellTests: XCTestCase {
    func testQuoteLeavesSafeValuesBare() {
        XCTAssertEqual(Shell.quote("--title"), "--title")
        XCTAssertEqual(Shell.quote("/usr/local/bin/dialog"), "/usr/local/bin/dialog")
    }

    func testQuoteKeepsVariablesLiveAndEscapesSpecials() {
        XCTAssertEqual(Shell.quote("Welcome to ${orgName}"), "\"Welcome to ${orgName}\"")
        XCTAssertEqual(Shell.quote("say \"hi\""), "\"say \\\"hi\\\"\"")
        XCTAssertEqual(Shell.quote("line one\\nline two"), "\"line one\\\\nline two\"")
        XCTAssertEqual(Shell.quote("costs \\$5"), "\"costs \\$5\"")
        XCTAssertEqual(Shell.quote(""), "\"\"")
    }

    func testTokenizeRoundTripsQuotedValues() {
        for value in ["plain", "two words", "say \"hi\"", "a\\nb", "it's", "costs \\$5 for ${name}", "tick `x`"] {
            XCTAssertEqual(Shell.tokenize("dialog --message " + Shell.quote(value)), ["dialog", "--message", value])
        }
    }

    func testTokenizeHandlesContinuationsAndSingleQuotes() {
        let command = "/usr/local/bin/dialog \\\n  --title 'My Title' \\\n  --small # comment\n"
        XCTAssertEqual(Shell.tokenize(command), ["/usr/local/bin/dialog", "--title", "My Title", "--small"])
    }

    func testVariableNames() {
        XCTAssertEqual(Shell.variableName(from: "Asset Tag"), "assetTag")
        XCTAssertEqual(Shell.variableName(from: "assetTag"), "assetTag")
        XCTAssertEqual(Shell.variableName(from: "2nd choice"), "_2ndChoice")
        XCTAssertEqual(Shell.variableName(from: "!!!", fallback: "input"), "input")
        XCTAssertTrue(Shell.isValidVariableName("orgName"))
        XCTAssertFalse(Shell.isValidVariableName("org name"))
        XCTAssertFalse(Shell.isValidVariableName("4x"))
    }

    func testSubstitute() {
        XCTAssertEqual(Shell.substitute("Hi ${name}, $name! \\$5", variables: ["name": "Sam"]), "Hi Sam, Sam! $5")
    }
}

final class BuilderTests: XCTestCase {
    func testFlagsValuesAndOrdering() {
        let spec = DialogSpec(options: ["message": "Hello", "title": "Hi", "blurscreen": "", "timer": "", "progress": "5",
                                        "button1text": ""])
        XCTAssertEqual(DialogBuilder.arguments(for: spec),
                       ["--title", "Hi", "--message", "Hello", "--progress", "5", "--timer", "--blurscreen"])
    }

    func testLegacyItemSyntax() {
        var spec = DialogSpec()
        spec.items["textfield"] = [DialogItem(fields: ["title": "Asset Tag", "required": "true", "prompt": "AC-1"])]
        spec.items["checkbox"] = [DialogItem(fields: ["label": "Agree", "checked": "true", "enableButton1": "true"])]
        spec.items["listitem"] = [DialogItem(fields: ["title": "Chrome", "status": "wait"])]
        XCTAssertEqual(DialogBuilder.arguments(for: spec), [
            "--textfield", "Asset Tag,required,prompt=AC-1",
            "--checkbox", "Agree,checked,enableButton1",
            "--listitem", "Chrome,status=wait"
        ])
    }

    func testItemsFallBackToJSONWhenLegacySyntaxIsUnsafe() {
        var spec = DialogSpec()
        spec.items["textfield"] = [DialogItem(fields: ["title": "Name", "prompt": "Last, First"])]
        XCTAssertEqual(DialogBuilder.arguments(for: spec),
                       ["--textfield", "{\"title\":\"Name\",\"prompt\":\"Last, First\"}"])
    }

    func testSelectLists() {
        var spec = DialogSpec()
        spec.items["selectitems"] = [DialogItem(fields: ["title": "Dept", "values": "A\nB", "default": "B",
                                                         "style": "radio", "required": "true", "name": "dept"])]
        XCTAssertEqual(DialogBuilder.arguments(for: spec), [
            "--selecttitle", "Dept,radio,required,name=dept", "--selectvalues", "A,B", "--selectdefault", "B"
        ])
        spec.items["selectitems"]?.append(DialogItem(fields: ["title": "Other", "values": "X\nY"]))
        let mixed = DialogBuilder.arguments(for: spec)
        XCTAssertEqual(mixed.filter { $0 == "--selectitem" }.count, 2, "mixed defaults must not rely on positional pairing")
    }

    func testImagesWithCaptions() {
        var spec = DialogSpec()
        spec.items["image"] = [DialogItem(fields: ["imagename": "/tmp/a.png", "caption": "A"]),
                               DialogItem(fields: ["imagename": "/tmp/b.png"])]
        XCTAssertEqual(DialogBuilder.arguments(for: spec),
                       ["--image", "/tmp/a.png", "--imagecaption", "A", "--image", "/tmp/b.png"])
    }

    func testJSONConfig() throws {
        var spec = DialogSpec(options: ["title": "Hi", "width": "900", "ontop": "", "timer": "", "checkboxstyle": "switch,large"])
        spec.items["checkbox"] = [DialogItem(fields: ["label": "A", "checked": "true"])]
        spec.items["selectitems"] = [DialogItem(fields: ["title": "S", "values": "1\n2"])]
        let config = DialogBuilder.jsonConfig(for: spec)
        XCTAssertEqual(config.extraArguments, [["--timer"]])
        let json = try JSONValue.parse(config.json.serialized())
        XCTAssertEqual(json["title"], .string("Hi"))
        XCTAssertEqual(json["width"], .int(900))
        XCTAssertEqual(json["ontop"], .bool(true))
        XCTAssertNil(json["timer"])
        XCTAssertEqual(json["checkboxstyle"]?["size"], .string("large"))
        XCTAssertEqual(json["checkbox"]?.arrayValue?.first?["checked"], .bool(true))
        XCTAssertEqual(json["selectitems"]?.arrayValue?.first?["values"], .array([.string("1"), .string("2")]))
    }

    func testCardsBecomeJSON() throws {
        var spec = DialogSpec(options: ["title": "Setup"])
        spec.cardStyle = "navigation"
        spec.cards = [DialogCard(cardId: "one", section: "Start", spec: DialogSpec(options: ["message": "Hello"]))]
        let arguments = DialogBuilder.arguments(for: spec)
        XCTAssertEqual(arguments.first, "--jsonstring")
        let json = try JSONValue.parse(arguments[1])
        XCTAssertEqual(json["cardstyle"], .string("navigation"))
        XCTAssertEqual(json["cards"]?.arrayValue?.first?["cardId"], .string("one"))
        XCTAssertEqual(json["cards"]?.arrayValue?.first?["message"], .string("Hello"))
    }

    func testCapturesAvoidReservedAndDuplicateNames() {
        var spec = DialogSpec()
        spec.items["textfield"] = [DialogItem(fields: ["title": "Status"]), DialogItem(fields: ["title": "Name"]),
                                   DialogItem(fields: ["title": "Name"])]
        XCTAssertEqual(DialogBuilder.captures(for: spec).map { $0.variable }, ["statusValue", "name", "name2"])
    }

    func testJSONStringEscaping() {
        XCTAssertEqual(JSONValue.string("a\"b\\c\nd").serialized(), "\"a\\\"b\\\\c\\nd\"")
    }
}

final class ImporterTests: XCTestCase {
    func testCommandRoundTrip() {
        var spec = DialogSpec(options: ["title": "Welcome to ${orgName}", "message": "Line one\\nLine \"two\"",
                                        "icon": "SF=gear,colour=blue", "ontop": "", "timer": "30", "progress": ""])
        spec.items["textfield"] = [DialogItem(fields: ["title": "Asset Tag", "required": "true", "prompt": "AC-1"]),
                                   DialogItem(fields: ["title": "Name", "prompt": "Last, First"])]
        spec.items["checkbox"] = [DialogItem(fields: ["label": "Agree", "enableButton1": "true"])]
        spec.items["selectitems"] = [DialogItem(fields: ["title": "Dept", "values": "A\nB", "default": "A", "required": "true"])]
        spec.items["image"] = [DialogItem(fields: ["imagename": "/tmp/a.png", "caption": "Cap"])]

        let command = DialogBuilder.renderCommand(binary: "/usr/local/bin/dialog", groups: DialogBuilder.argumentGroups(for: spec))
        let imported = DialogImporter.importCommand(command)
        XCTAssertEqual(imported.options, spec.options)
        XCTAssertEqual(DialogBuilder.arguments(for: imported), DialogBuilder.arguments(for: spec))
    }

    func testImportsShortOptionsAndUnknowns() {
        let spec = DialogImporter.importCommand("dialog -t Hello -m 'A message' -o -p --futureoption value --small")
        XCTAssertEqual(spec.value("title"), "Hello")
        XCTAssertEqual(spec.value("message"), "A message")
        XCTAssertTrue(spec.has("moveable"))
        XCTAssertTrue(spec.has("ontop"))
        XCTAssertTrue(spec.has("small"))
        XCTAssertEqual(spec.extraArguments, "--futureoption value")
    }

    func testImportsJSONWithCards() throws {
        let text = """
        {
          "cardstyle": "navigation", "title": "Setup", "moveable": true, "blurscreen": false, "width": 900,
          "checkboxstyle": {"style": "switch", "size": "regular"},
          "cards": [
            {"cardId": "a", "section": "S", "title": "One",
             "textfield": [{"title": "Full Name", "name": "fullname", "required": true}, "Plain"],
             "selectitems": [{"title": "Team", "values": ["X", "Y"], "default": "X"}]}
          ]
        }
        """
        let spec = try DialogImporter.importText(text)
        XCTAssertEqual(spec.cardStyle, "navigation")
        XCTAssertEqual(spec.value("width"), "900")
        XCTAssertTrue(spec.has("moveable"))
        XCTAssertFalse(spec.has("blurscreen"))
        XCTAssertEqual(spec.value("checkboxstyle"), "switch,regular")
        XCTAssertEqual(spec.cards.count, 1)
        let card = spec.cards[0]
        XCTAssertEqual(card.cardId, "a")
        XCTAssertEqual(card.spec.items["textfield"]?.map { $0["title"] }, ["Full Name", "Plain"])
        XCTAssertTrue(card.spec.items["textfield"]?.first?.bool("required") ?? false)
        XCTAssertEqual(card.spec.items["selectitems"]?.first?.list("values"), ["X", "Y"])
    }
}

final class ScriptTests: XCTestCase {
    func testEveryTemplateGeneratesAndPassesValidation() throws {
        for template in Templates.all {
            let project = template.make()
            let script = ScriptGenerator.script(for: project)
            XCTAssertTrue(script.hasPrefix("#!/bin/zsh"), template.name)
            XCTAssertTrue(script.contains("step_1() {"), template.name)
            XCTAssertFalse(script.contains("\u{E000}") || script.contains("\u{E001}"), "\(template.name) leaked a marker")
            let errors = Validator.issues(for: project).filter { $0.severity == .error }
            XCTAssertEqual(errors.map { $0.message }, [], template.name)
            // Projects survive a save and reopen unchanged.
            XCTAssertEqual(try FlowProject.decode(project.encoded()), project, template.name)
        }
    }

    /// Runs `zsh -n` over every template's script, so a generator change cannot emit invalid shell.
    func testGeneratedScriptsAreValidZsh() throws {
        let candidates = ["/bin/zsh", "/usr/bin/zsh"]
        guard let zsh = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) }) else {
            throw XCTSkip("zsh is not installed")
        }
        for template in Templates.all {
            let url = FileManager.default.temporaryDirectory.appendingPathComponent("dialogforge-\(template.id).zsh")
            try ScriptGenerator.script(for: template.make()).write(to: url, atomically: true, encoding: .utf8)
            defer { try? FileManager.default.removeItem(at: url) }
            let process = Process()
            process.executableURL = URL(fileURLWithPath: zsh)
            process.arguments = ["-n", url.path]
            let errors = Pipe()
            process.standardError = errors
            try process.run()
            let message = String(decoding: errors.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            process.waitUntilExit()
            XCTAssertEqual(process.terminationStatus, 0, "\(template.name): \(message)")
        }
    }

    func testDialogStepCapturesInputAndBranches() {
        let project = Templates.inventory()
        let script = ScriptGenerator.script(for: project)
        XCTAssertTrue(script.contains("orgName=\"${4}\""))
        XCTAssertTrue(script.contains("if [[ -z \"$orgName\" ]]; then orgName=\"Acme Corp\"; fi"))
        XCTAssertTrue(script.contains("        --title \"Register this Mac\""))
        XCTAssertTrue(script.contains("        --json"))
        XCTAssertTrue(script.contains("        assetTag=\"$(json_value \"$output\" assetTag)\""))
        XCTAssertTrue(script.contains("        0)\n            nextStep=\"step_2\""))
        XCTAssertTrue(script.contains("\"$jamfBinary\" recon -assetTag \"${assetTag}\" -email \"${email}\" -department \"${department}\""))
    }

    func testProgressStepDrivesCommandFile() {
        let script = ScriptGenerator.script(for: Templates.enrolment())
        XCTAssertTrue(script.contains("--commandfile \"${commandFile}\""))
        XCTAssertTrue(script.contains("--progress 5"))
        XCTAssertTrue(script.contains("--listitem \"Google Chrome,icon=/Applications/Google Chrome.app,status=pending\""))
        XCTAssertTrue(script.contains("run_task 1 \"Installing Google Chrome…\" \"/Applications/Google Chrome.app\" \"/Applications/Google Chrome.app\" \\\n        \"$jamfBinary\" policy -event installChrome || failures=$((failures + 1))"))
        XCTAssertTrue(script.contains("dialog_update \"button1: enable\""))
    }

    func testCardsUseAnUnindentedHeredoc() {
        let script = ScriptGenerator.script(for: Templates.onboarding())
        XCTAssertTrue(script.contains("<<DIALOGFORGE_JSON\n{\n"))
        XCTAssertTrue(script.contains("\nDIALOGFORGE_JSON\n"))
        XCTAssertTrue(script.contains("\"title\": \"${orgName} Setup\""))
        XCTAssertTrue(script.contains("    if ! {\n        [[ \"$installSlack\" == \"true\" ]]\n    }; then"))
    }

    func testGotoRetryAndDisabledSteps() {
        var first = FlowStep(name: "First", kind: .dialog, dialog: DialogSpec(options: ["title": "One"]))
        var skipped = FlowStep(name: "Skipped", kind: .script)
        skipped.enabled = false
        skipped.script = "echo never"
        var last = FlowStep(name: "Last", kind: .script)
        last.script = "cat <<EOF\nhello\nEOF"
        first.outcomes = [ExitOutcome(code: 0, action: .goto, targetStep: last.id),
                          ExitOutcome(code: 2, action: .retry),
                          ExitOutcome(code: -1, action: .exit, exitStatus: 3)]
        let script = ScriptGenerator.script(for: FlowProject(name: "T", steps: [first, skipped, last]))
        XCTAssertFalse(script.contains("echo never"))
        XCTAssertTrue(script.contains("        0)\n            nextStep=\"step_2\""))
        XCTAssertTrue(script.contains("        2)\n            nextStep=\"step_1\""))
        XCTAssertTrue(script.contains("            exit 3"))
        XCTAssertTrue(script.contains("\ncat <<EOF\nhello\nEOF\n"), "here-documents in user scripts must not be indented")
        XCTAssertTrue(script.contains("    nextStep=\"\"\ncat <<EOF"), "nextStep is set before user script so it can be overridden")
    }

    func testValidationFlagsProblems() {
        var spec = DialogSpec(options: ["fullscreen": "", "button1disabled": ""])
        spec.items["textfield"] = [DialogItem(fields: ["title": "Password", "secure": "true", "prompt": "x"])]
        spec.items["selectitems"] = [DialogItem(fields: ["title": "Empty"])]
        var step = FlowStep(name: "Bad", kind: .dialog, dialog: spec)
        step.outcomes = [ExitOutcome(code: 0, action: .goto, targetStep: UUID())]
        var project = FlowProject(name: "T", steps: [step])
        project.parameters = [JamfParameter(index: 12, label: "x", variable: "path")]
        let messages = Validator.issues(for: project).map { $0.message }.joined(separator: "\n")
        for expected in ["out of range", "reserved", "full screen", "cannot show a prompt", "has no values",
                         "missing or disabled", "nothing re-enables"] {
            XCTAssertTrue(messages.contains(expected), "missing: \(expected)")
        }
    }

    func testJamfPayload() throws {
        let project = Templates.enrolment()
        let payload = JamfAPI.scriptPayload(project: project, name: "Enrolment")
        XCTAssertEqual(payload["parameter4"], .string("Organisation name"))
        XCTAssertEqual(payload["priority"], .string("AFTER"))
        XCTAssertEqual(payload["scriptContents"]?.stringValue, ScriptGenerator.script(for: project))
        XCTAssertEqual(JamfAPI.baseURL(from: "acme.jamfcloud.com/")?.absoluteString, "https://acme.jamfcloud.com")
        XCTAssertEqual(JamfAPI.scriptSearchPath(name: "My Script"),
                       "/api/v1/scripts?page=0&page-size=10&filter=name%3D%3D%22My%20Script%22")
        let response = try JSONValue.parse("{\"totalCount\":1,\"results\":[{\"id\":\"42\",\"name\":\"x\"}]}")
        XCTAssertEqual(JamfAPI.firstScriptID(in: response), "42")
    }
}
