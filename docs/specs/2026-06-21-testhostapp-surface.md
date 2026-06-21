# TestHostApp UI Surface Specification

**Version:** 1.0  
**Applies to:** `autopilot-macos`, `autopilot-ios` (planned), `autopilot-android` (planned)

---

## Purpose

Every AutoPilot platform ships a `TestHostApp` — a minimal native app that exposes a fixed, well-known UI surface. A single canonical test plan (`Fixtures/TestHostApp/test-all-capabilities.json`) runs against all three apps unchanged. The runner for each platform translates each plan step into the platform's native mechanism; the plan itself contains no platform-specific knowledge.

This document is the authoritative contract between the test plan and every `TestHostApp` implementation. When you add a new platform, build a `TestHostApp` that satisfies every element in the **Element Surface** table and every **Implementation Notes** section below.

---

## Design Principles

1. **One plan, all platforms.** The JSON plan is the single source of truth. Runners translate; the plan does not branch.
2. **Minimize platform-only steps.** If an action genuinely has no cross-platform equivalent (e.g. `assertPixel` requires screen-capture permission that doesn't exist on Android), the step is skipped by the runner — not removed from the plan. The plan remains unified.
3. **Stable identifiers.** Every interactive element has a fixed `identifier` string. Identifiers are the primary selector in the test plan. Role/title selectors are secondary, used only when a platform's accessibility system doesn't support identifier lookup.
4. **Extend, don't break.** New elements and steps may be added to future versions of this spec. Existing identifiers and step IDs are never renamed or removed — only added to.

---

## Element Surface

Every `TestHostApp` implementation must expose the following elements with these exact identifiers, roles, and behaviors. The "Plan selector" column shows how the test plan targets each element.

| # | Identifier | Role (AX / iOS / Android) | Type | Behavior | Plan selector |
|---|---|---|---|---|---|
| 1 | `nameField` | `AXTextField` / `TextField` / `EditText` | Text input | Displays typed text; live-updates `statusLabel` on every keystroke | `{"identifier":"nameField"}` |
| 2 | `statusLabel` | `AXStaticText` / `Label` / `TextView` | Read-only label | Reflects: `"status: <nameField value>"`, `"status: flag=true/false"`, `"status: context-tapped"` | `{"identifier":"statusLabel"}` |
| 3 | `countLabel` | `AXStaticText` / `Label` / `TextView` | Read-only label | Shows `"count: N"` where N increments each time `okButton` is activated | `{"identifier":"countLabel"}` |
| 4 | `dblLabel` | `AXStaticText` / `Label` / `TextView` | Read-only label | Shows `"dbl: N"` where N increments each time `dblButton` receives a double-tap/double-click | `{"identifier":"dblLabel"}` |
| 5 | `okButton` | `AXButton` / `Button` / `Button` | Button | Single click/tap increments `countLabel` | `{"identifier":"okButton"}` |
| 6 | `dblButton` | `AXButton` / `Button` / `Button` | Double-click/tap target | Double-click or double-tap increments `dblLabel` | `{"identifier":"dblButton"}` |
| 7 | `flagCheckbox` | `AXCheckBox` / `Switch` / `CheckBox` | Toggle | Starts unchecked (value `"0"`/`"false"`); toggling changes value to `"1"`/`"true"` | `{"identifier":"flagCheckbox"}` |
| 8 | `colorSwatch` | `AXGroup` / `View` / `View` | Solid-color view | Filled with exactly `#3478F6` (sRGB 52, 120, 246). Used for `assertPixel`, `assertRegion`, `snapshot`, `screenshot` | `{"identifier":"colorSwatch"}` |
| 9 | `searchField` | `AXTextField` / `SearchField` / `SearchView` | Search input | Made first responder on launch; used to test keycode-based type and `focused` property | `{"identifier":"searchField"}` |
| 10 | `scrollView` | `AXScrollArea` / `ScrollView` / `ScrollView` | Scrollable container | Contains items `item-0` … `item-8` and `scroll-end`; `scroll-end` is off-screen initially | `{"identifier":"scrollView"}` |
| 11 | `scroll-end` | `AXStaticText` / `Label` / `TextView` | Label at bottom of scroll | Becomes visible after scrolling down; used to verify `scroll` action | `{"identifier":"scroll-end"}` |
| 12 | `slider` | `AXSlider` / `Slider` / `SeekBar` | Continuous slider | Range 0–100, starts at 0; drag/swipe right increases value | `{"identifier":"slider"}` |
| 13 | `sliderValueLabel` | `AXStaticText` / `Label` / `TextView` | Read-only label | Shows `"slider: N"` where N is the current integer slider value | `{"identifier":"sliderValueLabel"}` |
| 14 | `rightClickTarget` | `AXGroup` / `View` / `View` | Context-menu trigger | Right-click (macOS), long-press (iOS/Android) reveals a context menu with item `"ContextAction"` | `{"identifier":"rightClickTarget"}` |
| 15 | `ContextAction` | `AXMenuItem` / `Button` / `MenuItem` | Context menu item | Selecting it sets `statusLabel` to `"status: context-tapped"` | `{"role":"AXMenuItem","title":"ContextAction"}` (macOS) / `{"identifier":"contextAction"}` (iOS/Android) |
| 16 | `Toggle Flag` | `AXMenuItem` / — / — | Menu bar item (macOS) / nav action (iOS) / overflow item (Android) | Toggles `flagOn`; checkmark visible when on; maps to `menu` action | `{"role":"AXMenuItem","title":"Toggle Flag"}` |

> **Note on `Toggle Flag` / menu action:** On macOS this lives in the `View` menu bar. On iOS it maps to a navigation bar button or action sheet. On Android it maps to an options menu item. The plan uses `"action":"menu"` with `"menuPath":["View","Toggle Flag"]`; each runner translates the path to its platform's menu navigation mechanism.

---

## Unified Test Plan

`Fixtures/TestHostApp/test-all-capabilities.json`

This plan exercises every AutoPilot capability in sequence. The `target` field is intentionally left with a placeholder bundle ID — each platform's test harness substitutes the correct value (or the runner resolves it by path). Steps are ordered to build on each other; the app is launched once and terminated at the end.

```json
{
  "schemaVersion": "1.0",
  "name": "testhostapp-all-capabilities",
  "target": { "bundleId": "com.autopilot.testhostapp" },
  "defaults": { "timeoutMs": 5000, "retryIntervalMs": 100 },
  "steps": [

    { "id": "wait-window",
      "action": "waitFor",
      "target": { "role": "AXWindow" },
      "args": { "present": true } },

    { "id": "type-name",
      "action": "type",
      "target": { "identifier": "nameField" },
      "args": { "text": "Ada", "clear": true } },

    { "id": "assert-status-name",
      "action": "assert",
      "target": { "identifier": "statusLabel" },
      "assert": { "property": "value", "op": "contains", "expected": "Ada" } },

    { "id": "set-value",
      "action": "setValue",
      "target": { "identifier": "nameField" },
      "args": { "text": "Zed-42" } },

    { "id": "assert-set-value",
      "action": "assert",
      "target": { "identifier": "nameField" },
      "assert": { "property": "value", "op": "matches", "expected": "Zed-\\d+" } },

    { "id": "click-ok",
      "action": "click",
      "target": { "identifier": "okButton" } },

    { "id": "assert-count-1",
      "action": "assert",
      "target": { "identifier": "countLabel" },
      "assert": { "property": "value", "op": "equals", "expected": "count: 1" } },

    { "id": "assert-ok-title",
      "action": "assert",
      "target": { "identifier": "okButton" },
      "assert": { "property": "title", "op": "equals", "expected": "OK" } },

    { "id": "assert-ok-enabled",
      "action": "assert",
      "target": { "identifier": "okButton" },
      "assert": { "property": "enabled", "op": "equals", "expected": "true" } },

    { "id": "press-ok",
      "action": "press",
      "target": { "identifier": "okButton" } },

    { "id": "assert-count-2",
      "action": "assert",
      "target": { "identifier": "countLabel" },
      "assert": { "property": "value", "op": "equals", "expected": "count: 2" } },

    { "id": "double-click",
      "action": "doubleClick",
      "target": { "identifier": "dblButton" } },

    { "id": "assert-dbl-1",
      "action": "assert",
      "target": { "identifier": "dblLabel" },
      "assert": { "property": "value", "op": "equals", "expected": "dbl: 1" } },

    { "id": "check-flag",
      "action": "press",
      "target": { "identifier": "flagCheckbox" } },

    { "id": "assert-checked",
      "action": "assert",
      "target": { "identifier": "flagCheckbox" },
      "assert": { "property": "value", "op": "equals", "expected": "1" } },

    { "id": "assert-search-focused",
      "action": "assert",
      "target": { "identifier": "searchField" },
      "assert": { "property": "focused", "op": "equals", "expected": "true" } },

    { "id": "type-search",
      "action": "type",
      "target": { "identifier": "searchField" },
      "args": { "text": "Query 9", "focus": false } },

    { "id": "assert-search-value",
      "action": "assert",
      "target": { "identifier": "searchField" },
      "assert": { "property": "value", "op": "equals", "expected": "Query 9" } },

    { "id": "keypress-select-all",
      "action": "keyPress",
      "target": { "identifier": "nameField" },
      "args": { "keys": "cmd+a" } },

    { "id": "scroll-down",
      "action": "scroll",
      "target": { "identifier": "scrollView" },
      "args": { "deltaY": -300 } },

    { "id": "assert-scroll-end-visible",
      "action": "waitFor",
      "target": { "identifier": "scroll-end" },
      "args": { "present": true } },

    { "id": "assert-slider-zero",
      "action": "assert",
      "target": { "identifier": "sliderValueLabel" },
      "assert": { "property": "value", "op": "equals", "expected": "slider: 0" } },

    { "id": "drag-slider",
      "action": "drag",
      "target": { "identifier": "slider" },
      "args": { "to": { "identifier": "sliderValueLabel" } } },

    { "id": "assert-slider-moved",
      "action": "assert",
      "target": { "identifier": "sliderValueLabel" },
      "assert": { "property": "value", "op": "notEquals", "expected": "slider: 0" } },

    { "id": "right-click-target",
      "action": "rightClick",
      "target": { "identifier": "rightClickTarget" } },

    { "id": "press-context-item",
      "action": "press",
      "target": { "role": "AXMenuItem", "title": "ContextAction" } },

    { "id": "assert-context-tapped",
      "action": "assert",
      "target": { "identifier": "statusLabel" },
      "assert": { "property": "value", "op": "contains", "expected": "context-tapped" } },

    { "id": "menu-toggle-flag",
      "action": "menu",
      "args": { "menuPath": ["View", "Toggle Flag"] } },

    { "id": "assert-flag-status",
      "action": "assert",
      "target": { "identifier": "statusLabel" },
      "assert": { "property": "value", "op": "contains", "expected": "flag=true" } },

    { "id": "assert-menu-marked",
      "action": "assert",
      "target": { "role": "AXMenuItem", "title": "Toggle Flag" },
      "assert": { "property": "marked", "op": "equals", "expected": "true" } },

    { "id": "assert-count-gt-1",
      "action": "assert",
      "target": { "role": "AXButton" },
      "assert": { "property": "count", "op": "greaterThan", "expected": "1" } },

    { "id": "assert-colorSwatch-position",
      "action": "assert",
      "target": { "identifier": "colorSwatch" },
      "assert": { "property": "position", "op": "contains", "expected": "," } },

    { "id": "assert-colorSwatch-size",
      "action": "assert",
      "target": { "identifier": "colorSwatch" },
      "assert": { "property": "size", "op": "contains", "expected": "," } },

    { "id": "assert-pixel",
      "action": "assertPixel",
      "target": { "identifier": "colorSwatch" },
      "args": { "color": "#3478F6", "tolerance": 16 } },

    { "id": "assert-region",
      "action": "assertRegion",
      "target": { "identifier": "colorSwatch" },
      "args": { "color": "#3478F6", "width": 12, "height": 12, "mode": "dominant", "tolerance": 16 } },

    { "id": "snapshot-swatch",
      "action": "snapshot",
      "target": { "identifier": "colorSwatch" },
      "args": { "reference": "ref/swatch.png", "width": 30, "height": 30 } },

    { "id": "screenshot-swatch",
      "action": "screenshot",
      "target": { "identifier": "colorSwatch" },
      "args": { "padding": 4 } },

    { "id": "explicit-wait",
      "action": "wait",
      "args": { "seconds": 0.05 } },

    { "id": "assert-not-equals",
      "action": "assert",
      "target": { "identifier": "nameField" },
      "assert": { "property": "value", "op": "notEquals", "expected": "Ada" } },

    { "id": "assert-exists",
      "action": "assert",
      "target": { "identifier": "okButton" },
      "assert": { "property": "value", "op": "exists" } },

    { "id": "assert-not-exists",
      "action": "assert",
      "target": { "identifier": "okButton", "within": { "role": "AXMenuBar" } },
      "assert": { "property": "value", "op": "notExists" } },

    { "id": "terminate",
      "action": "terminate" }
  ]
}
```

---

## Capability Coverage Map

| Step ID | Action | Assert property / op | Capability exercised |
|---|---|---|---|
| `wait-window` | `waitFor` | — | Element presence wait |
| `type-name` | `type` | — | Text input with `clear` |
| `assert-status-name` | `assert` | `value` / `contains` | Live label update; `contains` op |
| `set-value` | `setValue` | — | Direct AX/a11y value write |
| `assert-set-value` | `assert` | `value` / `matches` | Regex match op |
| `click-ok` | `click` | — | Coordinate click |
| `assert-count-1` | `assert` | `value` / `equals` | Exact value match |
| `assert-ok-title` | `assert` | `title` / `equals` | Title property |
| `assert-ok-enabled` | `assert` | `enabled` / `equals` | Enabled property |
| `press-ok` | `press` | — | AX press action |
| `assert-count-2` | `assert` | `value` / `equals` | Cumulative state |
| `double-click` | `doubleClick` | — | Double-click / double-tap |
| `assert-dbl-1` | `assert` | `value` / `equals` | Double-click result |
| `check-flag` | `press` | — | Toggle via press |
| `assert-checked` | `assert` | `value` / `equals` | Checkbox numeric value |
| `assert-search-focused` | `assert` | `focused` / `equals` | Focused property |
| `type-search` | `type` | — | Type with `focus: false` (keycode path) |
| `assert-search-value` | `assert` | `value` / `equals` | Search field value |
| `keypress-select-all` | `keyPress` | — | Chord key synthesis |
| `scroll-down` | `scroll` | — | Scroll action |
| `assert-scroll-end-visible` | `waitFor` | — | Post-scroll presence |
| `assert-slider-zero` | `assert` | `value` / `equals` | Initial slider state |
| `drag-slider` | `drag` | — | Drag gesture |
| `assert-slider-moved` | `assert` | `value` / `notEquals` | Drag result; `notEquals` op |
| `right-click-target` | `rightClick` | — | Right-click / long-press |
| `press-context-item` | `press` | — | Context menu item press |
| `assert-context-tapped` | `assert` | `value` / `contains` | Context action result |
| `menu-toggle-flag` | `menu` | — | Menu bar / nav menu navigation |
| `assert-flag-status` | `assert` | `value` / `contains` | Menu action result |
| `assert-menu-marked` | `assert` | `marked` / `equals` | Menu item checkmark |
| `assert-count-gt-1` | `assert` | `count` / `greaterThan` | Multi-element count |
| `assert-colorSwatch-position` | `assert` | `position` / `contains` | Position property |
| `assert-colorSwatch-size` | `assert` | `size` / `contains` | Size property |
| `assert-pixel` | `assertPixel` | — | Pixel color sampling |
| `assert-region` | `assertRegion` | — | Region color (dominant mode) |
| `snapshot-swatch` | `snapshot` | — | Visual regression reference |
| `screenshot-swatch` | `screenshot` | — | Element screenshot capture |
| `explicit-wait` | `wait` | — | Fixed delay |
| `assert-not-equals` | `assert` | `value` / `notEquals` | Negative value match |
| `assert-exists` | `assert` | `value` / `exists` | Existence check |
| `assert-not-exists` | `assert` | `value` / `notExists` | Scoped non-existence |
| `terminate` | `terminate` | — | App termination |

---

## Implementation Notes per Element

For each element, the notes show what you need to wire up in a new platform's `TestHostApp`. Code snippets are minimal — just enough to satisfy the test plan's expectations.

---

### 1. `nameField` — Text input

**Plan exercises:** `type`, `setValue`, `assert value`, `assert notEquals`, `keyPress` (target for select-all)

**What it must do:**
- Accept text input
- On every keystroke update `statusLabel` to `"status: <current text>"`

**macOS (AppKit)**
```swift
let nameField = NSTextField(frame: ...)
nameField.setAccessibilityIdentifier("nameField")
nameField.delegate = self          // controlTextDidChange fires on every keystroke
// In delegate:
func controlTextDidChange(_ obj: Notification) {
    statusLabel.stringValue = "status: \(nameField.stringValue)"
}
```

**iOS (UIKit)**
```swift
let nameField = UITextField()
nameField.accessibilityIdentifier = "nameField"
nameField.addTarget(self, action: #selector(nameChanged), for: .editingChanged)
@objc func nameChanged() {
    statusLabel.text = "status: \(nameField.text ?? "")"
}
```

**Android (XML + Kotlin)**
```xml
<EditText android:id="@+id/nameField"
          android:contentDescription="nameField" />
```
```kotlin
nameField.addTextChangedListener { statusLabel.text = "status: ${it}" }
```

---

### 2. `statusLabel` — Status display

**Plan exercises:** `assert value contains`, `assert value notEquals`

**What it must do:**
- Start as `"status: "` (empty)
- Be updated by: `nameField` keystrokes, `flagCheckbox` toggle (via menu), context menu selection

**macOS:** `NSTextField(labelWithString: "status: ")` with `setAccessibilityIdentifier("statusLabel")`  
**iOS:** `UILabel()` with `accessibilityIdentifier = "statusLabel"`  
**Android:** `<TextView android:contentDescription="statusLabel" />`

---

### 3. `countLabel` — Click counter display

**Plan exercises:** `assert value equals` (verifies `click` and `press` both fired)

**What it must do:**
- Start as `"count: 0"`
- Increment to `"count: 1"` after first `okButton` click, `"count: 2"` after `press`

**macOS:**
```swift
var count = 0
@objc func okTapped() { count += 1; countLabel.stringValue = "count: \(count)" }
```
**iOS:**
```swift
@objc func okTapped() { count += 1; countLabel.text = "count: \(count)" }
```
**Android:**
```kotlin
okButton.setOnClickListener { countLabel.text = "count: ${++count}" }
```

---

### 4. `dblLabel` — Double-click/tap counter

**Plan exercises:** `doubleClick`

**What it must do:**
- Start as `"dbl: 0"`
- Increment to `"dbl: 1"` on the first double-click or double-tap of `dblButton`

**macOS:** Custom `NSView` subclass; detect `event.clickCount == 2` in `mouseDown`.  
**iOS:** `UITapGestureRecognizer` with `numberOfTapsRequired = 2`.  
```swift
let dbl = UITapGestureRecognizer(target: self, action: #selector(doubleTapped))
dbl.numberOfTapsRequired = 2
dblButton.addGestureRecognizer(dbl)
@objc func doubleTapped() { dblCount += 1; dblLabel.text = "dbl: \(dblCount)" }
```
**Android:** `GestureDetector.OnDoubleTapListener`.
```kotlin
val detector = GestureDetector(context, object : GestureDetector.SimpleOnGestureListener() {
    override fun onDoubleTap(e: MotionEvent): Boolean {
        dblLabel.text = "dbl: ${++dblCount}"; return true
    }
})
dblButton.setOnTouchListener { _, e -> detector.onTouchEvent(e); true }
```

---

### 5. `okButton` — Primary button

**Plan exercises:** `click`, `press`, `assert title`, `assert enabled`, `assert exists`, `assert count > 1`

**What it must do:**
- Title/label exactly `"OK"`
- Enabled at all times
- Single click or press increments `countLabel`

**macOS:** `NSButton(title: "OK", ...)` with `setAccessibilityIdentifier("okButton")`  
**iOS:** `UIButton`; `setTitle("OK", for: .normal)`; `accessibilityIdentifier = "okButton"`  
**Android:** `<Button android:text="OK" android:contentDescription="okButton" />`

---

### 6. `dblButton` — Double-click/tap target

**Plan exercises:** `doubleClick`

**What it must do:**
- Exposed as a button in the accessibility tree (so the runner can resolve it by identifier)
- Respond to double-click/double-tap by incrementing `dblLabel`
- Single click does nothing (prevents accidental counter increment from the first half of a double-click)

**macOS:**
```swift
// NSView subclass; must call setAccessibilityElement(true) or it won't appear in AX tree
dblButton.setAccessibilityElement(true)
dblButton.setAccessibilityRole(.button)
dblButton.setAccessibilityIdentifier("dblButton")
```
**iOS:** Any `UIView`; set `isAccessibilityElement = true`, `accessibilityTraits = .button`, `accessibilityIdentifier = "dblButton"`.  
**Android:** `<View android:contentDescription="dblButton" android:focusable="true" />`

---

### 7. `flagCheckbox` — Toggle / checkbox

**Plan exercises:** `press` (toggle), `assert value equals "0"` / `"1"`

**What it must do:**
- Start unchecked; AX value `"0"` when off, `"1"` when on
- Toggled by `press` action (AX press, not coordinate click)

**macOS:** `NSButton(checkboxWithTitle: "Flag", ...)` — AX value is `NSNumber` `0`/`1`.  
**iOS:** `UISwitch`; `accessibilityValue` returns `"0"`/`"1"` based on `isOn`. Override if needed:
```swift
override var accessibilityValue: String? {
    get { isOn ? "1" : "0" }
    set { }
}
```
**Android:** `<CheckBox>`; `contentDescription = "flagCheckbox"`; override `getAccessibilityNodeInfo` or use `ViewCompat.setAccessibilityDelegate` to expose `"0"`/`"1"` as state text.

---

### 8. `colorSwatch` — Solid-color reference view

**Plan exercises:** `assertPixel`, `assertRegion`, `snapshot`, `screenshot`, `assert position`, `assert size`

**What it must do:**
- Fill solidly with `#3478F6` (sRGB: R=52, G=120, B=246)
- Be at least 60×60 pts/dp so region sampling and snapshot have sufficient area
- Exposed as an accessibility element with a position and size the runner can read

**macOS:**
```swift
swatch.wantsLayer = true
swatch.layer?.backgroundColor = NSColor(srgbRed: 52/255, green: 120/255,
                                         blue: 246/255, alpha: 1).cgColor
swatch.setAccessibilityElement(true)
swatch.setAccessibilityRole(.group)
swatch.setAccessibilityIdentifier("colorSwatch")
```
**iOS:**
```swift
swatch.backgroundColor = UIColor(red: 52/255, green: 120/255, blue: 246/255, alpha: 1)
swatch.isAccessibilityElement = true
swatch.accessibilityIdentifier = "colorSwatch"
```
**Android:**
```xml
<View android:id="@+id/colorSwatch"
      android:contentDescription="colorSwatch"
      android:background="#3478F6"
      android:minWidth="60dp" android:minHeight="60dp" />
```

> **Color precision:** The value `#3478F6` is the sRGB target. Wide-gamut displays may render it slightly outside the standard gamut; the test plan uses `tolerance: 16` to accommodate display-pipeline rounding.

---

### 9. `searchField` — Search / focused input

**Plan exercises:** `type` with `focus: false`, `assert focused`

**What it must do:**
- Be made first responder immediately on launch (before any user interaction)
- Accept text input via the keycode/virtual-key path (not unicode string injection)
- Report `focused = true` while it holds first responder

**macOS:** `NSSearchField`; `window.makeFirstResponder(search)` in a `DispatchQueue.main.async` block so it runs after the window is visible.  
**iOS:** Call `searchField.becomeFirstResponder()` in `viewDidAppear`.  
**Android:** `requestFocus()` in `onResume`; or set `android:focusableInTouchMode="true"` and `requestFocus()` in layout.

---

### 10–11. `scrollView` + `scroll-end` — Scrollable content

**Plan exercises:** `scroll`, `waitFor` post-scroll

**What it must do:**
- `scrollView`: a clipping scroll container; vertically scrollable
- Contains at least 10 items (`item-0` … `item-8`, `scroll-end`)
- `scroll-end` must be **off-screen** in the initial viewport
- After `"deltaY": -300` (scroll down), `scroll-end` must become visible in the accessibility tree

**macOS:** `NSScrollView` with a tall `documentView` (height > 3× clip height); `scroll-end` label at the bottom.  
**iOS:**
```swift
// UIScrollView with contentSize.height > frame.height * 3
// Place scroll-end label at bottom; set accessibilityIdentifier = "scroll-end"
scrollEnd.accessibilityIdentifier = "scroll-end"
```
**Android:**
```xml
<ScrollView android:id="@+id/scrollView"
            android:contentDescription="scrollView">
  <!-- 10 TextViews; last one: -->
  <TextView android:contentDescription="scroll-end" android:text="scroll-end" />
</ScrollView>
```

> **Runner note on `deltaY`:** On macOS `deltaY = -300` scroll-wheel units scrolls down. iOS/Android runners translate this to a swipe-up gesture or programmatic scroll offset proportional to `deltaY`. The exact pixel mapping is runner-defined; the contract is that `scroll-end` becomes visible.

---

### 12–13. `slider` + `sliderValueLabel` — Drag target

**Plan exercises:** `drag`, `assert value notEquals`, `assert value equals "slider: 0"` (initial state)

**What it must do:**
- `slider`: horizontal, range 0–100, initial value 0
- `sliderValueLabel`: displays `"slider: N"` (integer) updating as the slider moves
- A drag from `slider` (center) to `sliderValueLabel` (to its right) must move the slider thumb far enough to produce a value > 0

**macOS:**
```swift
let slider = NSSlider(value: 0, minValue: 0, maxValue: 100,
                      target: self, action: #selector(sliderMoved(_:)))
slider.setAccessibilityIdentifier("slider")
@objc func sliderMoved(_ s: NSSlider) {
    sliderValueLabel.stringValue = "slider: \(Int(s.doubleValue))"
}
```
**iOS:**
```swift
let slider = UISlider()
slider.minimumValue = 0; slider.maximumValue = 100; slider.value = 0
slider.accessibilityIdentifier = "slider"
slider.addTarget(self, action: #selector(sliderMoved), for: .valueChanged)
@objc func sliderMoved() {
    sliderValueLabel.text = "slider: \(Int(slider.value))"
}
```
**Android:**
```xml
<SeekBar android:id="@+id/slider"
         android:contentDescription="slider"
         android:max="100" android:progress="0" />
<TextView android:id="@+id/sliderValueLabel"
          android:contentDescription="sliderValueLabel"
          android:text="slider: 0" />
```
```kotlin
slider.setOnSeekBarChangeListener(object : SeekBar.OnSeekBarChangeListener {
    override fun onProgressChanged(sb: SeekBar, progress: Int, fromUser: Boolean) {
        sliderValueLabel.text = "slider: $progress"
    }
    override fun onStartTrackingTouch(sb: SeekBar) {}
    override fun onStopTrackingTouch(sb: SeekBar) {}
})
```

> **Drag destination:** `sliderValueLabel` is placed to the right of `slider`. The runner resolves both elements, extracts their screen-space centers, and synthesizes a drag from slider-center to label-center. The label must be positioned far enough right that the drag reliably moves the thumb past zero.

---

### 14–15. `rightClickTarget` + `ContextAction` — Context menu

**Plan exercises:** `rightClick`, `press` on context menu item, `assert value contains "context-tapped"`

**What it must do:**
- `rightClickTarget`: right-click (macOS) or long-press (iOS/Android) opens a context menu
- Context menu contains exactly one item: `"ContextAction"`
- Selecting it sets `statusLabel` to `"status: context-tapped"`

**macOS:**
```swift
// NSView subclass
override func rightMouseDown(with event: NSEvent) {
    let menu = NSMenu(); let item = NSMenuItem(title: "ContextAction", ...)
    NSMenu.popUpContextMenu(menu, with: event, for: self)
}
```
**iOS:** `UIContextMenuInteraction` (iOS 13+):
```swift
let interaction = UIContextMenuInteraction(delegate: self)
rightClickTarget.addInteraction(interaction)
// UIContextMenuInteractionDelegate:
func contextMenuInteraction(...) -> UIContextMenuConfiguration? {
    UIContextMenuConfiguration(actionProvider: { _ in
        UIMenu(children: [UIAction(title: "ContextAction") { _ in
            self.statusLabel.text = "status: context-tapped"
        }])
    })
}
```
**Android:** `registerForContextMenu` + `onCreateContextMenu`:
```kotlin
registerForContextMenu(rightClickTarget)
override fun onCreateContextMenu(menu: ContextMenu, v: View, info: ContextMenu.ContextMenuInfo?) {
    menu.add(0, 1, 0, "ContextAction")
}
override fun onContextItemSelected(item: MenuItem): Boolean {
    if (item.itemId == 1) { statusLabel.text = "status: context-tapped"; return true }
    return super.onContextItemSelected(item)
}
```

> **Selector note:** On macOS the context menu item is resolved as `{"role":"AXMenuItem","title":"ContextAction"}`. On iOS/Android the runner must expose the menu item with `accessibilityIdentifier = "contextAction"` (lowercase) or resolve it by label text. The test plan currently uses the macOS selector; iOS/Android runners should add identifier-based fallback resolution.

---

### 16. `Toggle Flag` — Menu / nav action

**Plan exercises:** `menu`, `assert value contains "flag=true"`, `assert marked equals "true"`

**What it must do:**
- Toggles a boolean flag
- When on: `statusLabel` contains `"flag=true"`; the menu item itself reports `marked = true` (checkmark present)
- Accessible via `menu` action with path `["View", "Toggle Flag"]`

**macOS:** `NSMenuItem` in the `View` submenu of the main menu bar; set `state = .on/.off` to control the checkmark.

**iOS:** No persistent menu bar. Map `["View", "Toggle Flag"]` to a `UIBarButtonItem` or `UIAlertController` action sheet. The runner's `menu` implementation for iOS traverses navigation elements by path. The `marked` property maps to whether the button's image or title indicates the "on" state (runner-defined mapping).

**Android:** Options menu item in the `View` group. `menu` path `["View","Toggle Flag"]` maps to `R.id.action_toggle_flag`. `marked` maps to `item.isChecked`.

---

## Platform-Runner Mapping Table

Actions where the platform runner must translate the plan concept into a different native mechanism:

| Plan action | macOS implementation | iOS implementation | Android implementation |
|---|---|---|---|
| `click` | CGEvent left mouse down/up | `XCUIElement.tap()` / touch event | Appium `tap` |
| `doubleClick` | CGEvent clickCount=2 | `XCUIElement.doubleTap()` | Appium `doubleTap` |
| `rightClick` | CGEvent right mouse down/up | Long-press gesture (triggers context menu) | Long-press event |
| `press` | AX `kAXPressAction` | `XCUIElement.tap()` on button | Appium `tap` |
| `type` | CGEvent keyboard + unicode fallback | `XCUIElement.typeText()` | Appium `sendKeys` |
| `keyPress` | CGEvent virtual key + modifiers | `XCUIElement.typeText()` with special chars | Appium key events |
| `setValue` | AX `kAXValueAttribute` write | `XCUIElement.adjust(toNormalizedSliderPosition:)` or direct value | Appium `setValue` |
| `scroll` | CGEvent scroll wheel | `XCUIElement.swipeUp/Down()` | Appium `scroll` |
| `drag` | CGEvent mouse-down + drag + up | `XCUIElement.press(forDuration:thenDragTo:)` | Appium `dragAndDrop` |
| `menu` | Walk `NSMenu` / `AXMenuBar` by path | Find bar button / action sheet by path | Find options menu item by path |
| `assertPixel` | ScreenCaptureKit pixel sample | XCTest screenshot + pixel read | Appium screenshot + pixel read |
| `assertRegion` | ScreenCaptureKit region sample | XCTest screenshot + region average | Appium screenshot + region average |
| `snapshot` | ScreenCaptureKit element crop + NCC diff | XCTest screenshot crop + NCC diff | Appium screenshot crop + NCC diff |
| `screenshot` | ScreenCaptureKit element/display capture | XCTest `screenshot()` | Appium `getScreenshot` |
| `waitFor` | AX tree polling | XCTest `waitForExistence(timeout:)` | Appium `waitForElement` |
| `assert value` | `kAXValueAttribute` string | `XCUIElement.value` | Appium `getAttribute("text")` |
| `assert title` | `kAXTitleAttribute` string | `XCUIElement.label` | Appium `getAttribute("content-desc")` |
| `assert enabled` | `kAXEnabledAttribute` bool | `XCUIElement.isEnabled` | Appium `isEnabled()` |
| `assert focused` | `kAXFocusedAttribute` bool | `XCUIElement.hasFocus` | Appium `isFocused()` |
| `assert marked` | `kAXMenuItemMarkChar` non-empty | `XCUIElement.value == "1"` (switch) / custom | `MenuItem.isChecked` |
| `assert position` | `kAXPositionAttribute` CGPoint | `XCUIElement.frame.origin` | Appium `getLocation()` |
| `assert size` | `kAXSizeAttribute` CGSize | `XCUIElement.frame.size` | Appium `getSize()` |
| `assert count` | AX tree count query | XCTest query count | Appium `findElements().size()` |
| `terminate` | `NSRunningApplication.terminate()` | `XCUIApplication.terminate()` | Appium `closeApp()` |
| `wait` | `Thread.sleep` | `Thread.sleep` | `Thread.sleep` |
| `launch` | `NSWorkspace.openApplication` | `XCUIApplication.launch()` | Appium `launchApp()` |
