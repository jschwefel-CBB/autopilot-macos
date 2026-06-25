# AutoPilot User Manual

This manual takes you from zero to a working test plan. Read it once, front to back. For exhaustive field-by-field reference, see [docs/AUTHORING.md](AUTHORING.md). For the quick-reference card, see the [README](../README.md).

---

## Table of Contents

1. [Introduction](#1-introduction)
2. [Installation and First Run](#2-installation-and-first-run)
3. [How a Plan Works](#3-how-a-plan-works)
4. [Finding Element Identifiers](#4-finding-element-identifiers)
5. [The Full Action Set](#5-the-full-action-set)
6. [Assertions](#6-assertions)
7. [Selectors: Targeting Elements](#7-selectors-targeting-elements)
8. [Screenshots and Failure Artifacts](#8-screenshots-and-failure-artifacts)
9. [Plans at Scale: Includes and Suites](#9-plans-at-scale-includes-and-suites)
10. [The MCP Server](#10-the-mcp-server)
11. [Troubleshooting](#11-troubleshooting)
12. [Reference Links](#12-reference-links)

---

## 1. Introduction

AutoPilot is a declarative macOS GUI testing tool. You write a JSON file that describes a sequence of UI interactions and assertions, hand it to AutoPilot, and it drives the target app through the macOS Accessibility API and reports pass or fail.

**The motivating problem:** you want to verify that your app's Save dialog appears, fills the filename field, and commits — without shipping test code inside the app, without a recording tool that breaks on every UI change, and without an AI that guesses what the screen looks like at runtime. You want a deterministic contract: same plan, same app build, same result, every time.

**What AutoPilot is:**
- A CLI tool that reads a JSON plan and drives a macOS app via the Accessibility API.
- A deterministic executor — no LLM is in the execution path. Plans are reproduced exactly.
- A reporting tool that tells you, per step, what passed, what failed, and why.
- A **declarative GUI automation engine**, not only a test runner. The `assert` steps are optional: a plan made only of actions (`click`, `type`, `menu`, `waitFor`, `drag`, …) is an automation script that drives an app to *accomplish* a task. With `target.attach: true` it drives an already-running app from its current state. Testing is the flagship use; automating repeatable Mac workflows is the same engine with the assertions left out.

**What AutoPilot is not:**
- Not a recorder. You write plans by hand (or with an agent). Recording produces brittle coordinate-based scripts; AutoPilot uses stable AX identifiers.
- Not AI-driven at runtime. The LLM workflow (via the MCP server) happens at plan-authoring time, not during execution.
- Not a web testing tool. AutoPilot targets macOS native apps only — it drives the Accessibility API, which is a macOS concept.

---

## 2. Installation and First Run

### Install via Homebrew

```bash
brew tap jschwefel-CBB/autopilot
brew install autopilot
```

This installs two binaries: `autopilot` (the CLI) and `AutopilotMCP` (the MCP server for AI agent integration).

### Grant Accessibility permission

AutoPilot drives other apps by reading and interacting with their AX trees. macOS requires explicit permission for this.

1. Open **System Settings → Privacy & Security → Accessibility**.
2. Add Terminal (or iTerm2, or whichever app runs the `autopilot` command). The permission must be granted to the process that actually executes the binary — not just the binary itself.

### Verify with `autopilot doctor`

```bash
autopilot doctor
```

Expected output when both permissions are in order:

```
Accessibility:    OK
Screen Recording: OK
```

`doctor` checks both Accessibility (required for all plans) and Screen Recording (required for visual actions like screenshots and pixel assertions). If either shows MISSING, follow the link printed to System Settings.

### Run the Calculator quick start

Save this plan as `calculator-smoke.json`:

```json
{
  "schemaVersion": "1.0",
  "name": "calculator-smoke",
  "target": { "bundleId": "com.apple.calculator" },
  "steps": [
    { "id": "wait-window", "action": "waitFor",
      "target": { "role": "AXWindow" } },
    { "id": "press-1",   "action": "click",
      "target": { "identifier": "One" } },
    { "id": "press-plus","action": "click",
      "target": { "identifier": "Add" } },
    { "id": "press-2",   "action": "click",
      "target": { "identifier": "Two" } },
    { "id": "press-eq",  "action": "click",
      "target": { "identifier": "Equals" } },
    { "id": "check-result", "action": "assert",
      "target": { "role": "AXStaticText", "within": { "identifier": "StandardResultView" } },
      "assert": { "property": "value", "op": "equals", "expected": "3" } },
    { "id": "done", "action": "terminate" }
  ]
}
```

Run it:

```bash
autopilot run calculator-smoke.json --artifacts /tmp/autopilot-demo
```

Expected output:

```
RESULT pass 7/7
```

**If it fails:**
- `error: Accessibility permission not granted` — you must grant Accessibility to the terminal app running the command, not just allow it in a dialog. Open System Settings → Privacy & Security → Accessibility and add the correct app.
- Element not found on `press-1` — Calculator's button identifiers (`"One"`, `"Add"`, `"Equals"`) are correct for macOS 14+. On older versions the identifiers may differ. Run `autopilot dump-axtree com.apple.calculator` with Calculator open to see the actual identifiers.

**The `target.attach` option:** if you need to drive an already-running app instance without relaunching it (for example, to capture a specific UI state you set up manually), add `"attach": true` to the `target` block. AutoPilot attaches to the frontmost matching instance and fails immediately if none is running.

---

## 3. How a Plan Works

A plan is a JSON file that describes a sequence of steps to perform against a target macOS app. AutoPilot reads the plan, launches the app (unless `attach: true`), runs each step in order, and writes a report.

### The mental model

```
You write  ──▶  plan.json  ──fed to──▶  autopilot run  ──drives via AX──▶  the target app
                                               │
                                               └──▶  report.json + artifacts
```

The executor knows nothing about your app beyond what the plan and the live AX tree tell it. It does not infer intent, does not retry differently on failure, and does not adapt — that is the feature: the result is predictable and reproducible.

**The first failure stops the run** (unless you pass `--keep-going`). This is intentional: a failed assertion usually means subsequent steps would be operating on wrong state.

### Walking through the Calculator plan

```json
{
  "schemaVersion": "1.0",
  "name": "calculator-smoke",
  "target": { "bundleId": "com.apple.calculator" },
  "steps": [...]
}
```

- `schemaVersion` must be `"1.0"` — any other value is rejected.
- `name` appears in reports. Make it descriptive.
- `target.bundleId` tells AutoPilot which app to launch. You can also use `target.path` with an absolute `.app` path instead.

```json
{ "id": "wait-window", "action": "waitFor",
  "target": { "role": "AXWindow" } }
```

- Every plan should start with `waitFor` on `{ "role": "AXWindow" }`. AutoPilot launches the app and needs to wait for its window before sending input. Skipping this causes intermittent first-step failures.
- `id` must be unique within the plan. It appears in the report and in artifact filenames.
- `role` is the AX role — `AXWindow` matches the app's main window.

```json
{ "id": "press-1", "action": "click",
  "target": { "identifier": "One" } }
```

- `action: "click"` sends a single left click to the element's center.
- `target.identifier` matches the element's `AXIdentifier`. This is the preferred, most stable way to target elements — it is set in the app's source code and does not change when the UI is restyled.

```json
{ "id": "check-result", "action": "assert",
  "target": { "role": "AXStaticText", "within": { "identifier": "StandardResultView" } },
  "assert": { "property": "value", "op": "equals", "expected": "3" } }
```

- `action: "assert"` reads a property from the element and compares it.
- `assert.property`: `"value"` reads the element's text value.
- `assert.op`: `"equals"` requires an exact match.
- `assert.expected`: the string you expect.
- If the actual value does not match, the step fails and AutoPilot writes the actual value to the report so you can see what the app produced.

```json
{ "id": "done", "action": "terminate" }
```

- Always end with `terminate`. Without it, the app stays running and can pollute the next run.

**Every step polls** up to `timeoutMs` (default 5000 ms, configurable in `defaults` or per-step). You never need to insert manual delays — AutoPilot waits for the element to appear, the value to update, etc.

---

## 4. Finding Element Identifiers

You cannot write good selectors without knowing what the app exposes. AutoPilot provides three CLI commands for this.

### `autopilot dump-axtree`

Dumps the entire AX tree of a running app to stdout:

```bash
autopilot dump-axtree com.apple.calculator
```

Or, for an app at a specific path:

```bash
autopilot dump-axtree /Applications/MyApp.app
```

The output lists every node's role, identifier, title, and value. Use this when you don't know what to look for — it gives you the full picture.

### `autopilot find`

Resolves a specific selector and tells you how many elements match:

```bash
autopilot find com.apple.calculator --identifier add
```

Use `find` first when you already have a candidate identifier. It confirms whether the selector resolves to exactly one element (good), zero (identifier doesn't exist or is wrong), or many (ambiguous — you need to narrow it down with `role`, `title`, or `within`).

### `autopilot suggest`

Suggests the best selector for each interactive element:

```bash
autopilot suggest com.apple.calculator
```

This scans the AX tree for buttons, text fields, and other interactive controls, and proposes a selector for each — prioritizing stable `identifier`-based selectors over fragile `title`-based ones. Use `suggest` when starting a plan for an app you haven't worked with before.

**All three commands attach to the already-running instance** — they do not relaunch the app. If no matching instance is running, they report that directly. Launch the app before running them.

**Recommended workflow:** run `suggest` first for a quick overview, then use `find` to verify specific selectors as you write your plan. Fall back to `dump-axtree` when you need to understand the complete tree structure.

---

## 5. The Full Action Set

### Navigation: `click`, `doubleClick`, `rightClick`, `press`

```json
{ "id": "open", "action": "click",       "target": { "identifier": "openButton" } }
{ "id": "edit", "action": "doubleClick", "target": { "identifier": "fileRow" } }
{ "id": "ctx",  "action": "rightClick",  "target": { "identifier": "fileRow" } }
{ "id": "chk",  "action": "press",       "target": { "identifier": "flagCheckbox" } }
```

Prefer `press` over `click` for buttons, checkboxes, and toggles. `press` performs the AX press action rather than a coordinate click, so it works even when the element has no clickable frame or when the click would miss a small hit area.

### Menus: `menu`

```json
{ "id": "wrap", "action": "menu", "args": { "menuPath": ["View", "Wrap Lines"] } }
```

`menu` is the only reliable way to trigger a menu command that has no keyboard shortcut. A `click` cannot open a closed menu bar item. `menuPath` is an array of titles walking the menu hierarchy.

### Text input: `type`, `setValue`, `keyPress`

```json
{ "id": "search",  "action": "type",
  "target": { "identifier": "searchField" },
  "args": { "text": "query", "focus": false } }

{ "id": "rename",  "action": "type",
  "target": { "identifier": "renameField" },
  "args": { "text": "newname.txt", "clear": true, "commit": true } }

{ "id": "fill",    "action": "setValue",
  "target": { "identifier": "nameField" },
  "args": { "text": "draft" } }

{ "id": "save",    "action": "keyPress",
  "target": { "identifier": "editorTextView" },
  "args": { "keys": "cmd+s" } }
```

- `type` clicks to focus, then sends keystrokes. Use `clear: true` to select-all and delete first. Use `commit: true` to press Return after typing (needed for inline-rename fields). Use `focus: false` when the app already has focus on the field — a focus click would drop it.
- `setValue` sets the element's AX value directly, bypassing keystrokes. It is fast but does not fire the control's end-editing action. Use `type` with `commit: true` when the commit matters.
- `keyPress` sends a key chord. Modifiers: `cmd`, `shift`, `opt`/`alt`, `ctrl`. Example: `"shift+cmd+a"`, `"cmd+,"`. The `+` key is spelled `plus` (it is the chord separator).

### Waiting: `waitFor`, `wait`

```json
{ "id": "sheet-open",  "action": "waitFor",
  "target": { "identifier": "saveSheet" }, "args": { "present": true } }

{ "id": "sheet-close", "action": "waitFor",
  "target": { "identifier": "saveSheet" }, "args": { "present": false } }
```

`waitFor` polls until the element appears (`present: true`, the default) or disappears (`present: false`). Use it to gate on UI transitions before sending input.

`wait` adds a fixed delay in seconds (`"args": { "seconds": 1 }`). Use it only as a last resort when polling isn't possible — fixed delays make plans slow and fragile.

### Visual capture: `screenshot`, `assertPixel`, `assertRegion`, `snapshot`

```json
{ "id": "state",   "action": "screenshot" }
{ "id": "toolbar", "action": "screenshot",
  "args": { "atX": 0, "atY": 0, "width": 800, "height": 44 } }
{ "id": "gutter",  "action": "assertPixel",
  "args": { "atX": 30, "atY": 200, "color": "#2B2B2B", "tolerance": 16 } }
```

These actions require Screen Recording permission (checked by `autopilot doctor`). See Chapter 8 for full detail.

### Flow: `launch`, `terminate`

```json
{ "id": "start", "action": "launch" }
{ "id": "quit",  "action": "terminate" }
```

`launch` is a no-op marker — the app is always launched automatically before step 1. It is useful as a visual separator in long plans. `terminate` quits the app. Always include it as your last step.

---

## 6. Assertions

Every `assert` step has an `assert` block with three fields: `property`, `op`, and (usually) `expected`.

### Properties

| Property | What it reads |
|---|---|
| `value` | The element's text value (`AXValue`) |
| `title` | The element's visible label (`AXTitle`) |
| `enabled` | Whether the element is enabled (`"true"` / `"false"`) |
| `focused` | Whether the element has keyboard focus |
| `count` | The number of elements matching the selector — for collections |
| `marked` | Menu item checkmark state (`"true"` / `"false"`) |

### Operators

| Operator | Meaning | Requires `expected`? |
|---|---|---|
| `equals` | Exact string match | yes |
| `notEquals` | Not equal | yes |
| `contains` | Substring | yes |
| `matches` | NSRegularExpression pattern | yes |
| `greaterThan` | Numeric `>` (parsed as Double) | yes |
| `lessThan` | Numeric `<` | yes |
| `exists` | Element resolves in the AX tree | no |
| `notExists` | Element does not resolve | no |

### Examples

```json
{ "id": "label-check",   "action": "assert",
  "target": { "identifier": "statusLabel" },
  "assert": { "property": "value", "op": "equals", "expected": "Ready" } }

{ "id": "row-count",     "action": "assert",
  "target": { "role": "AXRow" },
  "assert": { "property": "count", "op": "greaterThan", "expected": "0" } }

{ "id": "panel-gone",    "action": "assert",
  "target": { "identifier": "findBar" },
  "assert": { "property": "value", "op": "notExists" } }

{ "id": "version-match", "action": "assert",
  "target": { "identifier": "versionLabel" },
  "assert": { "property": "value", "op": "matches", "expected": "^\\d+\\.\\d+" } }
```

**Notes:**
- `count` with `greaterThan`/`lessThan` is the right way to assert that a list has items. Do not try to assert `notExists` on a collection when you mean "at least one exists."
- `matches` takes a Swift `NSRegularExpression` pattern (not PCRE). Most common syntax works the same, but possessive quantifiers and some PCRE extensions are not supported.
- `exists` / `notExists` check element presence in the AX tree. They do not read a property value — the `property` field is ignored when using these operators.
- `marked` reflects menu item checkmark state, but the state is only populated after the menu has been opened and validated by AppKit. If you need to verify a toggle's state, prefer asserting the visible side effect (a label change, a panel appearing) rather than the checkmark.

---

## 7. Selectors: Targeting Elements

A selector is a set of predicates that must all match, narrowed to exactly one element. If zero elements match or multiple elements match, the step fails immediately (ambiguity is a plan bug, not a runtime condition to handle).

### What works

| Field | Status | Notes |
|---|---|---|
| `identifier` | Preferred | Matches `AXIdentifier`. Stable because it is set in code. |
| `role` | Works | AX role: `AXButton`, `AXTextField`, `AXTextArea`, `AXStaticText`, `AXWindow`, etc. |
| `title` | Works | Matches `AXTitle` — the visible label. |
| `value` | Works | Matches `AXValue` — the element's current text. |
| `index` | Disambiguator | When predicates match multiple elements, pick the nth (0-based). Last resort — prefer `identifier`. |
| `within` | Scoping | Search inside a separately-resolved parent element. Useful when the same identifier appears in multiple panels. |
| `vision.image` | Fallback | Template-match a PNG against the screen when no AX element is available. See below. |

### What does NOT work

| Field | Status | Why |
|---|---|---|
| `label` | Rejected | Hard parse error. `label` never matched any element. Use `title` or `identifier`. |
| `path` | Rejected | Hard parse error. `path` as a selector is never consulted. Use `identifier`/`role`/`title`/`within`. |

### Examples

```json
{ "identifier": "okButton" }
{ "role": "AXButton", "title": "OK" }
{ "role": "AXRow", "within": { "identifier": "fileList" }, "index": 0 }
```

### `within` for disambiguation

When the same identifier appears in multiple panels, scope the search:

```json
{ "identifier": "nameField", "within": { "identifier": "savePanel" } }
```

### `index` for nth-match

```json
{ "role": "AXRow", "index": 2 }
```

This selects the third `AXRow` (0-based). Use `identifier` or `within` first — `index` is brittle if rows are added or reordered.

### Vision fallback for custom-drawn controls

Some controls are drawn entirely in pixels with no AX element. For these, use a template image:

```json
"target": {
  "vision": { "image": "templates/play-icon.png", "confidence": 0.9 }
}
```

Vision fires only after AX resolution fails. It finds a screen point — you can click at it, but you cannot read AX properties from it (no `assert` on a vision-only match). The template must have internal contrast; solid-color images will not match. Use this as a fallback, not a first choice — adding an `AXIdentifier` in the app's source is always preferable.

---

## 8. Screenshots and Failure Artifacts

### What AutoPilot writes on failure

When a step fails, AutoPilot writes two files to the artifacts directory:

- `<step-id>.png` — a full-display screenshot at the moment of failure
- `<step-id>.axtree.json` — the AX tree AutoPilot saw when the failure occurred

These are your primary debugging surface. Read the `actual` value in the report, look at the screenshot, and compare the AX tree to what you expected.

### The `screenshot` action

Three modes:

```json
{ "id": "full",    "action": "screenshot" }
{ "id": "element", "action": "screenshot",
  "target": { "identifier": "saveSheet" }, "args": { "padding": 16 } }
{ "id": "region",  "action": "screenshot",
  "args": { "atX": 0, "atY": 0, "width": 800, "height": 44 } }
```

- No target: captures the full display.
- With target: crops to the element's AX frame plus `padding` points on each side.
- With `atX/atY/width/height`: captures an absolute screen region.

Requires Screen Recording permission. Without it, `screenshot` steps succeed but write nothing — they do not error. Use `autopilot doctor` to check.

### `captureTarget: true` — visual logging without extra steps

Add `"captureTarget": true` to any step that has a `target`. AutoPilot saves a cropped screenshot of that element as `<step-id>-target.png` on every run, pass or fail:

```json
{ "id": "check-label", "action": "assert",
  "target": { "identifier": "statusLabel" },
  "assert": { "property": "value", "op": "equals", "expected": "Ready" },
  "captureTarget": true }
```

`captureTarget` silently skips if Screen Recording is not granted, or if the target resolves only via vision (no AX element). Default padding is 8 points.

### Where artifacts go

By default, artifacts go in `./artifacts`. Override with `--artifacts <dir>`:

```bash
autopilot run my-plan.json --artifacts /tmp/my-results
```

Each plan's artifacts are namespaced in a subdirectory: `<artifacts-root>/<plan-name-slug>/`.

### PNG metadata

Every AutoPilot screenshot embeds `tEXt` metadata chunks:

| Key | Value |
|---|---|
| `autopilot-step` | Step ID |
| `autopilot-plan` | Plan name |
| `autopilot-action` | Action name |
| `autopilot-result` | `pass` or `fail` |

This metadata persists even when the PNG is moved away from its `report.json`.

---

## 9. Plans at Scale: Includes and Suites

### Shared setup with `include`

Factor common setup steps (launching the app, waiting for the window, resetting state) into a separate file and include it in every test plan:

`setups/launch.json`:
```json
{
  "schemaVersion": "1.0",
  "name": "launch clean",
  "target": { "bundleId": "com.example.myapp", "launchArgs": ["--reset-state"] },
  "defaults": { "timeoutMs": 6000, "retryIntervalMs": 100 },
  "steps": [
    { "id": "wait-window", "action": "waitFor",
      "target": { "role": "AXWindow" }, "args": { "present": true } }
  ]
}
```

`tests/my-feature.json`:
```json
{
  "schemaVersion": "1.0",
  "name": "my feature test",
  "include": ["../setups/launch.json"],
  "target": { "bundleId": "com.example.myapp", "launchArgs": ["--reset-state"] },
  "defaults": { "timeoutMs": 6000, "retryIntervalMs": 100 },
  "steps": [
    { "id": "do-thing", "action": "click", "target": { "identifier": "featureButton" } },
    { "id": "quit", "action": "terminate" }
  ]
}
```

Include paths resolve relative to the plan file. Included steps are prepended before the host plan's steps. The host plan's `target` and `defaults` win if they differ from the included file.

### Running a suite

Point `autopilot run` at a directory to run every `*.json` plan under it:

```bash
autopilot run tests/ --artifacts ./out
```

- Plans run sequentially (macOS has a single keyboard/mouse focus; parallel runs would conflict).
- Files under a `setups/` directory are treated as include-only fragments and are skipped as standalone plans.
- Each plan's artifacts go in `./out/<plan-slug>/`. An aggregate `out/suite.json` is written, and a `SUITE pass N/M` line goes to stderr.

### Exit codes

| Code | Meaning |
|---|---|
| `0` | All steps passed |
| `1` | One or more test steps failed |
| `2` | Plan or parse error (malformed JSON, rejected field) |
| `3` | Accessibility permission missing |

Use exit code 2 to distinguish infrastructure problems from test failures in CI.

---

## 10. The MCP Server

AutoPilot ships `AutopilotMCP`, an MCP server that exposes the test engine to AI agents (such as Claude).

### Adding it to Claude Desktop

Add this to `~/Library/Application Support/Claude/claude_desktop_config.json`:

```json
{
  "mcpServers": {
    "autopilot": {
      "command": "/usr/local/bin/AutopilotMCP"
    }
  }
}
```

If you installed via Homebrew, the binary is at `/usr/local/bin/AutopilotMCP` on Intel Macs and `/opt/homebrew/bin/AutopilotMCP` on Apple Silicon. Restart Claude Desktop after editing the config.

### The 6 tools

| Tool | What it does |
|---|---|
| `run_plan` | Run a JSON plan (inline or from a file path) and return structured results |
| `get_report` | Fetch the last run's report JSON, including per-step outcomes and artifact paths |
| `dump_axtree` | Dump an app's AX tree so an agent can discover element selectors |
| `find_element` | Resolve a specific selector against a running app and report what it matches |
| `suggest_selectors` | Suggest the best selector for each interactive element in a running app |
| `lint_plan` | Static-check a plan for non-functional selectors, missing terminate, and missing required args |

### Typical agent workflow

1. **Explore:** call `suggest_selectors` or `dump_axtree` to discover what elements the target app exposes.
2. **Draft:** write a plan using the discovered selectors.
3. **Check:** call `lint_plan` to catch obvious problems before running.
4. **Run:** call `run_plan` to execute the plan.
5. **Debug:** call `get_report` to inspect per-step outcomes and artifact paths when something fails.

The MCP tools need the same Accessibility permission as the CLI. Run `autopilot doctor` from the terminal to verify permissions before starting an agent session.

---

## 11. Troubleshooting

| Symptom | Likely cause | Fix |
|---|---|---|
| `error: Accessibility permission not granted` | Accessibility not granted to the terminal running `autopilot` | Open System Settings → Privacy & Security → Accessibility and add the correct terminal app (Terminal, iTerm2, etc.) |
| `error: Screen Recording permission not granted` (on visual assert steps) | Screen Recording not granted | Open System Settings → Privacy & Security → Screen Recording and add your terminal. Note: `screenshot` and `captureTarget` silently produce nothing when Screen Recording is absent (they do not error); only visual *assert* steps (`assertPixel`, `assertRegion`, `snapshot`) produce a hard error |
| Element not found / `No element matched selector` | Wrong identifier, or element not yet in the AX tree | Use `autopilot find com.example.myapp --identifier YOUR_IDENTIFIER_HERE` to check; also try `autopilot dump-axtree com.example.myapp` to see the full tree |
| Step times out waiting for element | The timeout is too short, or the app is slow to render | Increase `timeoutMs` in the plan's `defaults` block, or add a per-step `"timeoutMs"` field |
| `captureTarget` wrote nothing | Screen Recording not granted, or target resolves only via vision (not AX) | Verify Screen Recording with `autopilot doctor`; confirm the target has an AX element (not just a vision match) |
| App launched but first click fails intermittently | AutoPilot acted before the window was ready | Add a `waitFor` step on `{ "role": "AXWindow" }` as the first step; do not click before the window exists |
| `autopilot doctor` says OK but tests still fail | Accessibility was granted to the wrong process (e.g. Terminal.app but you are running from iTerm2, or granted to the system `autopilot` binary instead of the terminal) | The permission must be on the process that spawns `autopilot`. Check System Settings → Accessibility and confirm the listed app matches what you are actually running |

---

## 12. Reference Links

- **Full action, selector, and assertion reference:** [docs/AUTHORING.md](AUTHORING.md)
- **Plan JSON schema (editor autocomplete):** [schema/plan.schema.json](../schema/plan.schema.json)
- **GitHub repository:** [https://github.com/jschwefel-CBB/autopilot-macos](https://github.com/jschwefel-CBB/autopilot-macos)
- **Filing issues:** [https://github.com/jschwefel-CBB/autopilot-macos/issues](https://github.com/jschwefel-CBB/autopilot-macos/issues)
