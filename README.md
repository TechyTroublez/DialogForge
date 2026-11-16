# DialogForge

A native macOS app for building [swiftDialog](https://swiftdialog.app) flows without writing the
script by hand. You assemble a flow from steps in a GUI; DialogForge generates the swiftDialog
commands and a complete zsh script ready for a Jamf Pro policy.

> **Status: first cut, not yet compiled.** This was written in an environment without a Swift
> toolchain. Every file passes a Swift syntax parse and the logic is covered by unit tests, but
> nothing has been built or run yet. Expect to fix some compiler errors on the first
> `swift build`. See [First build](#first-build).

## What it does

**A flow is an ordered list of steps**

| Step | What it generates |
| --- | --- |
| Dialog | A swiftDialog window. Inputs are captured into shell variables; each exit code (Button 1, Button 2, info button, timer, ⌘Q …) can continue, jump to another step, show the dialog again, or exit the script. |
| Progress | A dialog driven through swiftDialog's command file while tasks run: Jamf policies by event or ID, shell commands, wait-for-file, pauses. Each task is a list row with live status and a progress bar. |
| Notification | A system or pseudo notification. |
| Jamf action | `jamf policy -event/-id`, `recon` (with arguments built from captured input), `manage`, or open a Self Service URL. |
| Shell script | Anything else. |

Any step can have a condition (`[[ ! -d "/Applications/Slack.app" ]]`).

**Every swiftDialog option, in a GUI.** Options are modelled on swiftDialog 3.x's own argument
table and grouped by category (content, icon, banner, buttons, inputs, list, media, progress and
timer, window, notification, advanced), each with its help text. Text fields, checkboxes, select
lists, sliders, steppers, page buttons, list items and images have structured editors, including
input dependencies (`enabledif` / `visibleif`). Cards (wizard and sidebar-navigation styles) are
supported. Anything newer than the app can be typed into *Extra arguments*.

**Jamf Pro integration**

- Script parameters 4–11 become named variables (`${orgName}`) you can use in any field, with
  defaults for when a policy leaves them blank. The labels are written to the script header and
  set on the script record when uploading.
- The generated script waits for a logged-in user, checks swiftDialog is present and new enough
  (installing the latest signed release from GitHub, or via a Jamf policy), can launch
  swiftDialog as the logged-in user, logs to a file, and cleans up after itself.
- *Upload to Jamf Pro* creates or updates the script through the Jamf Pro API using an API
  client (or a user account). The secret can be kept in your keychain.

**Output you can see while you edit**: an approximate sketch of the dialog, the equivalent
command line, the JSON config, the full script, and a list of issues (option combinations
swiftDialog silently ignores, broken jumps, invalid variable names, and so on).

**Run it for real.** With swiftDialog installed on your Mac, *Run in swiftDialog* launches the
actual window for the selected step, shows the exit code and output, and simulates progress
steps.

**Import.** Paste an existing `dialog …` command or JSON config to turn it into a step.

**Templates**: enrolment setup, inventory collection, update prompt with deferral, restart
countdown, notification, multi-page onboarding, and policy acceptance.

## First build

Requires macOS 13 or later and Xcode 15 or later.

```bash
swift test
```

```bash
swift run DialogForge
```

Or open `Package.swift` in Xcode and run the `DialogForge` scheme. To produce a `.app` bundle:

```bash
Scripts/build-app.sh
```

`.github/workflows/ci.yml` builds and tests on macOS, and tests the core library on Linux.

## Layout

```
Sources/DialogForgeCore   Foundation-only: models, option catalogue, command/JSON builders,
                          importer, script generator, validation, templates, Jamf payloads
Sources/DialogForge       The SwiftUI app (macOS only)
Tests/DialogForgeCoreTests
```

All generation logic lives in `DialogForgeCore` so it can be unit tested without the UI and
reused, for example from a command line tool.

## Notes on generated scripts

- Values are double-quoted so `${variables}` and `$(commands)` expand at run time. Write `\$`
  for a literal dollar sign.
- Simple inputs use swiftDialog's classic comma syntax (`--textfield "Asset Tag,required"`),
  which works on every version. Values that syntax cannot carry (commas, quotes) are passed as
  JSON objects, which needs a recent swiftDialog 3.x. Cards are always passed as a JSON file.
- Input is read from swiftDialog's `--json` output with a small JavaScript-for-Automation
  helper, so no extra tools are needed on the Mac.

## Not covered yet

- Inspect mode (`--inspect-mode`) has its own large config schema; the flags are available but
  there is no editor for the config.
- Card branching (`branch`, `nextpage`) is not editable; use `finalpage` or separate steps.
- Only Jamf Pro is integrated. The core has no Jamf dependency outside `JamfAPI.swift`, the
  Jamf step kinds and the script's `jamf` calls, so other MDMs can be added alongside.
