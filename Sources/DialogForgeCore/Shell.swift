import Foundation

/// Shell quoting and tokenising helpers used by the generators and importers.
public enum Shell {
    private static let dollarPlaceholder = "\u{E000}"

    /// Characters that never need quoting.
    private static let safeCharacters = CharacterSet(charactersIn:
        "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-./:=@%+,")

    /// Quotes a value for use in a zsh/bash script.
    ///
    /// Values are double-quoted so that `${variables}` and `$(commands)` typed into a
    /// field expand at run time. Write `\$` for a literal dollar sign.
    public static func quote(_ value: String) -> String {
        if !value.isEmpty, value.unicodeScalars.allSatisfy({ safeCharacters.contains($0) }) {
            return value
        }
        var text = value.replacingOccurrences(of: "\\$", with: dollarPlaceholder)
        text = text.replacingOccurrences(of: "\\", with: "\\\\")
        text = text.replacingOccurrences(of: "\"", with: "\\\"")
        text = text.replacingOccurrences(of: "`", with: "\\`")
        text = text.replacingOccurrences(of: dollarPlaceholder, with: "\\$")
        return "\"" + text + "\""
    }

    /// Escapes text for an unquoted here-document (`<<EOF`), keeping `${variables}` live.
    public static func escapeForHeredoc(_ value: String) -> String {
        // In JSON a user-typed `\$` has already become `\\$`.
        var text = value.replacingOccurrences(of: "\\\\$", with: dollarPlaceholder)
        text = text.replacingOccurrences(of: "\\", with: "\\\\")
        text = text.replacingOccurrences(of: "`", with: "\\`")
        text = text.replacingOccurrences(of: dollarPlaceholder, with: "\\$")
        return text
    }

    /// Resolves `${name}` / `$name` references and `\$` escapes the way the script
    /// would, using the supplied values. Used when previewing outside a script.
    public static func substitute(_ value: String, variables: [String: String]) -> String {
        guard value.contains("$") else { return value }
        var text = value.replacingOccurrences(of: "\\$", with: dollarPlaceholder)
        // Longest names first so `$user` does not clobber `$username`.
        for name in variables.keys.sorted(by: { $0.count > $1.count }) {
            let replacement = variables[name] ?? ""
            text = text.replacingOccurrences(of: "${" + name + "}", with: replacement)
            text = text.replacingOccurrences(of: "$" + name, with: replacement)
        }
        return text.replacingOccurrences(of: dollarPlaceholder, with: "$")
    }

    /// Makes a string safe to use as a shell variable name.
    public static func variableName(from text: String, fallback: String = "value") -> String {
        var words: [String] = []
        var current = ""
        for scalar in text.unicodeScalars {
            let isAlnum = (scalar.value < 128) && CharacterSet.alphanumerics.contains(scalar)
            if isAlnum {
                current.unicodeScalars.append(scalar)
            } else if !current.isEmpty {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        guard !words.isEmpty else { return fallback }
        var name = ""
        for (index, word) in words.enumerated() {
            if index == 0 {
                // Keep an existing camelCase name intact; lower-case only the first letter.
                name += word.prefix(1).lowercased() + String(word.dropFirst())
            } else {
                name += word.prefix(1).uppercased() + String(word.dropFirst())
            }
        }
        if let first = name.unicodeScalars.first, CharacterSet.decimalDigits.contains(first) {
            name = "_" + name
        }
        return name
    }

    /// Names zsh reserves or ties to special behaviour (`path` is `$PATH`, `status` is read-only).
    public static let reservedVariableNames: Set<String> = [
        "status", "path", "argv", "pipestatus", "options", "functions", "commands", "aliases",
        "signals", "history", "fpath", "cdpath", "manpath", "mailpath", "prompt", "psvar", "watch",
        "parameters", "modules", "builtins", "dirstack", "funcstack", "functrace", "errnos",
        "terminfo", "termcap", "userdirs", "nameddirs", "jobdirs", "jobstates", "jobtexts",
        "module_path", "histchars", "widgets", "keymaps", "reswords", "galiases", "saliases",
        // Used by generated scripts.
        "scriptName", "scriptLog", "dialogBinary", "minimumDialogVersion", "runDialogAsUser",
        "jamfBinary", "commandFile", "temporaryFiles", "loggedInUser", "loggedInUserID",
        "nextStep", "currentStep", "output", "exitCode", "dialogArgs", "dialogPID", "failures",
        "jsonFile"
    ]

    public static func isValidVariableName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first else { return false }
        let letters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_")
        let rest = letters.union(.decimalDigits)
        guard letters.contains(first) else { return false }
        return name.unicodeScalars.allSatisfy { $0.value < 128 && rest.contains($0) }
    }

    /// Splits a command line into arguments, honouring quotes, backslash escapes,
    /// line continuations and `#` comments. Variables are left untouched.
    public static func tokenize(_ command: String) -> [String] {
        var tokens: [String] = []
        var current = ""
        var hasToken = false
        var quote: Character? = nil
        var iterator = command.makeIterator()
        var pending: Character? = nil

        func next() -> Character? {
            if let character = pending { pending = nil; return character }
            return iterator.next()
        }

        while let character = next() {
            if let active = quote {
                if character == active {
                    quote = nil
                } else if character == "\\" && active == "\"" {
                    if let following = next() {
                        if following == "\"" || following == "\\" || following == "`" {
                            current.append(following)
                        } else if following == "$" {
                            current.append("\\$")
                        } else if following == "\n" {
                            // line continuation inside double quotes
                        } else {
                            current.append(character)
                            current.append(following)
                        }
                    }
                } else {
                    current.append(character)
                }
                continue
            }
            switch character {
            case "'", "\"":
                quote = character
                hasToken = true
            case "\\":
                if let following = next() {
                    if following != "\n" {
                        current.append(following)
                        hasToken = true
                    }
                }
            case " ", "\t", "\n", "\r":
                if hasToken || !current.isEmpty {
                    tokens.append(current)
                    current = ""
                    hasToken = false
                }
            case "#" where current.isEmpty && !hasToken:
                // Skip a comment through to the end of the line.
                while let skipped = next() {
                    if skipped == "\n" { break }
                }
            default:
                current.append(character)
                hasToken = true
            }
        }
        if hasToken || !current.isEmpty { tokens.append(current) }
        return tokens
    }
}
