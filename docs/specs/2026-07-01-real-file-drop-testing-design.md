# Real Cross-Process File Drop for AutoPilot (macOS) — Design Spec

**Date:** 2026-07-01
**Status:** Approved (brainstorm) — ready for implementation plan
**Repos touched:** `autopilot-core`, `autopilot-macos`, `medit`
(NOT `autopilot-ios` / `autopilot-android` — see §3 non-goals: neither conforms to core's
Swift `AppDriver` protocol today, so there is nothing to stub there.)
**Transient:** delete this spec after the implementation plan lands (git history is the archive — per no-historical-docs-in-tree rule).

---

## 1. Problem

AutoPilot cannot currently reproduce a **file drag-and-drop** in a test. The plan schema
already has the field for it — `ActionArgs.toFiles: [String]?`, used by the `drag` action —
but execution is **stubbed out**. `autopilot-core`'s `PlanRunner` rejects any `drag` step
carrying `toFiles` at runtime:

> `"file drag-and-drop is not supported via synthesized events; open files with
> target.launchFiles instead, or test the drop handler headlessly"`

This forces consumers (e.g. **medit**) to cover file-drop only via a launch hook
(`--open-files`) and a unit hook (`performFileDropForTesting`) — both of which exercise the
app's `openFiles(at:)` **logic** but **never the real cross-process OS drop**. That gap is
not hypothetical: medit shipped a bug (single-file drops worked, multi-file drops fired no
events at all — only `public.file-url` was registered, not `NSFilenamesPboardType`) that
**only a real cross-process drop would catch**, because it lives in the OS drag-routing
layer, not in `openFiles(at:)`.

## 2. Why the stub's premise is wrong

The stub assumes a file drop requires *injecting mouse events at the drag source* (Finder),
which synthetic `CGEvent`s cannot do. That is true **but avoidable**. Mechanical fact that
governs all macOS drag automation:

> A file drop fires **only** when a **source application voluntarily calls**
> `NSView.beginDraggingSession(with:event:source:)`. That call allocates the cross-process
> drag pasteboard and writes the payload (`public.file-url` / `NSFilenamesPboardType`). The
> OS never starts a drag on its own, and the drag pasteboard **cannot** be primed from
> outside. So the only question is: **who is the source, and did it really start a session?**

You cannot make **Finder** the source via injected events (proven unautomatable — Finder does
not reliably begin a session off synthetic input; no public/private API forces it). But
**AutoPilot can be the source itself.** When AP calls `beginDraggingSession`, the destination
receives a genuine cross-process drop. This is the maximally-real approach that actually works
deterministically — validated against `natestedman/drag` (public-domain reference),
Hammerspoon maintainers' analysis, and the `adamwulf/mouseup-nsdraggingsession` behavior notes.

## 3. Goal & non-goals

**Goal:** Implement the existing `drag` + `toFiles` path so it performs a **real
cross-process file drop** on macOS — the destination's real AppKit handlers
(`draggingEntered:` / `performDragOperation:`) fire with a real drag pasteboard carrying
**both** `public.file-url` **and** `NSFilenamesPboardType`. First consumer: medit.

**Non-goals:**
- No new plan action, no schema bump. `drag` + `toFiles` already models this; stays
  `schemaVersion "1.1"`. (Decision: reuse existing field, do not add `dragFiles`.)
- Not making Finder the literal source app — provably unautomatable; out of scope forever.
- **No iOS/Android work at all.** Verified 2026-07-01: `autopilot-ios` does **not** consume
  `autopilot-core` yet — it *mirrors* the schema with its own `PlanModel.swift`
  ("Future versions will consume autopilot-core directly"). `autopilot-android` is **Kotlin**,
  fully separate. Neither conforms to core's Swift `AppDriver` protocol, so adding a method to
  that protocol touches **only** `MacOSDriver` (the sole conformer today). No stubs needed;
  those repos are out of scope. (If/when iOS adopts core as a dependency, it implements
  `performFileDrag` then — a future concern, not this change.)

## 4. What "real" means here (honesty contract)

- **The drop is genuinely real.** Destination receives a true `NSDraggingSession` +
  real cross-process drag pasteboard; its real drop handlers fire. Not a mocked handler call.
  This is the layer that catches the medit-class bug.
- **The steering is real HID, synthetic origin.** The same `CGEvent(.cghidEventTap)` path AP
  already uses for every `click`/`drag`/`scroll`. The OS processes these as genuine HID mouse
  input. What is synthetic is that **AP** is the source app, not Finder. This is not a
  weakening of the drop's realness — it is the only reliable path.

## 5. Architecture

```
PlanRunner (core)
  case .drag, args.toFiles present:
    resolve step.target -> drop Point            (existing target resolution)
    driver.performFileDrag(files:, to: point)    <- NEW AppDriver method
        |- MacOSDriver -> FileDragSource          <- NEW (all AppKit)
        |- iOSDriver / AndroidDriver -> throw "unsupported on <platform>"  <- NEW stubs
```

### 5.1 macOS drag-source mechanism (inline — no separate helper binary)

The AP binary already calls `CGEventPost(.cghidEventTap)` for click/drag/scroll, which
**proves it runs non-sandboxed and Accessibility-trusted**. Therefore `beginDraggingSession`
works **inline in the driver** — no separate helper app or bundled binary needed.

Mechanism (`FileDragSource`):
1. AP owns a tiny **borderless, transparent, on-demand `NSWindow`** (off-screen or ~1px) with
   a custom source `NSView`.
2. Post a synthetic `CGEvent` **mouse-down onto that window** so the view receives a genuine
   `mouseDown:` `NSEvent`. (This is the **seed event** — see §5.2 risk.)
3. From that real event, call `beginDraggingSession(with:event:source:)` with one
   `NSDraggingItem` whose `NSPasteboardItem` declares **both** `public.file-url` and
   `NSFilenamesPboardType` (single- and multi-file drops both covered — the exact axis of the
   medit bug).
4. Source delegate conforms to `NSDraggingSource`, returns `.copy` for
   `NSDraggingContextOutsideApplication` (the flag that lets the drop cross app boundaries).
5. CGEvent `mouseMoved` / `leftMouseDragged` **steer** the OS-tracked cursor from the source
   window to the resolved drop `Point`; a final `mouseUp` releases → destination's real drop
   handlers fire.
6. Do **not** rely on a `mouseUp:` callback in the source view — the active drag loop consumes
   `leftMouseUp` (proven by `adamwulf/mouseup-nsdraggingsession`). Completion is detected via
   the `NSDraggingSession` end / delegate, not a mouse-up handler.

### 5.2 Known risk — the seed event (spike first)

`beginDraggingSession` requires a genuine mouse-type `NSEvent` as its `event:` argument.
Whether a **fully fabricated** `NSEvent.mouseEvent(...)` is accepted is the **one unverified
link**, and it **cannot be validated headless in CI** (needs a real display/session).

**Mitigation — the plan's Task 1 is a hardware proof-of-concept** that stands up only the drag
source + a throwaway destination and confirms a real drop fires **before** any core/schema
plumbing is built. **Safe pattern to implement first:** post a synthetic `CGEvent` mouse-down
onto AP's *own* source window, catch the resulting real `mouseDown:` NSEvent, and pass **that**
into `beginDraggingSession`. (A fabricated-`NSEvent` shortcut may be spiked as an optimization,
but the design does not depend on it.)

## 6. File-by-file plan

### `autopilot-macos` (all AppKit; built & proven first)
- **New:** `Sources/MacOSDriver/Actions/FileDragSource.swift` — the source window +
  `NSDraggingSession` + seed-event + CGEvent steering; writes both pasteboard types.
- **Modify:** `Sources/MacOSDriver/MacOSDriver.swift` — implement `performFileDrag(files:to:)`
  by delegating to `FileDragSource`. (Reuse existing `point(for:)` resolution.)
- **Modify:** `docs/AUTHORING.md` (~line 136, `drag` row + worked examples) — flip the
  "file drag-drop not supported" note to documented, with a `toFiles` worked example.

### `autopilot-core` (no macOS APIs — library-only)
- **Modify:** `Sources/AutopilotCore/Driver/AppDriver.swift` — add
  `func performFileDrag(files: [String], to: Point) throws`.
- **Modify:** `Sources/AutopilotCore/Runner/PlanRunner.swift` — replace the `toFiles`
  rejection with: resolve `step.target` -> `Point` -> `driver.performFileDrag(files:to:)`.
- **Verify:** `Sources/AutopilotCore/Plan/PlanLinter.swift` — `drag` already lints; confirm a
  `drag` + `toFiles` step (no `to`) does not spuriously warn. `PlanParser` already accepts
  `drag` with `toFiles` (validation: `to == nil && toFiles == nil` -> error), so no parser
  change.

**Sole `AppDriver` conformer is `MacOSDriver`.** iOS mirrors the schema (no core dependency
yet) and Android is Kotlin — adding a protocol method touches neither. No iOS/Android tasks.

### `medit` (first consumer)
- **New:** an **XCUITest** that: launches non-sandboxed **Debug** medit; computes the editor
  drop `Point`; drives the new AP capability; asserts **both** tabs open for a **multi-file**
  drop and one for a **single-file** drop; plus a payload sanity check that the received
  pasteboard carried `public.file-url` + `NSFilenamesPboardType`.
  (Debug build is sandbox-OFF per `medit-debug.entitlements` — required so the drop's file
  URLs are readable.)

## 7. Verification

- **Task 1 (POC):** on real hardware, a throwaway destination logs a real
  `performDragOperation:` with file URLs. Gate: if the seed trick needs adjustment, it is
  found here, before three repos are wired.
- **macOS unit/integration:** `FileDragSource` drives a drop onto an in-repo test destination
  view; assert both pasteboard types present and handler fired. (GUI test — must run against a
  real display, never headless; poll + skip-when-headless per existing AP CI convention.)
- **core:** unit test that a `drag` + `toFiles` step routes to `performFileDrag` (fake driver
  records the call) instead of erroring.
- **medit:** the XCUITest above — single- and multi-file, the exact bug axis.

## 8. Task order (for the implementation plan)

1. **macOS POC spike** — drag source + throwaway destination; confirm a real drop fires on
   hardware (de-risks the seed event before any plumbing).
2. **macOS `FileDragSource`** + `MacOSDriver.performFileDrag` + macOS integration test.
3. **core** — add `performFileDrag` to `AppDriver`; route `.drag`+`toFiles` in `PlanRunner`;
   core routing unit test (fake driver records the call). (No iOS/Android — not conformers.)
4. **AUTHORING.md** — document `toFiles` + worked example.
5. **medit consumer XCUITest** — single + multi-file real-drop coverage.

## 9. Constraints (verbatim, bind every task)

- **Schema stays `"1.1"`** — no new action, no schema bump.
- **`autopilot-core` is library-only, platform-agnostic** — **zero** macOS/AppKit APIs in
  core. All AppKit lives in `autopilot-macos`.
- **macOS binary must remain non-sandboxed + Accessibility-trusted** (already true; required
  for both `CGEventPost` and `beginDraggingSession`-as-source).
- Pasteboard must carry **BOTH** `public.file-url` AND `NSFilenamesPboardType` (single- and
  multi-file drops).
- GUI tests run against a **real display, never headless**; poll + skip-when-headless, no
  fixed sleeps.
- medit drop tests run against the **non-sandboxed Debug** build; Release stays sandboxed.
- Do not attempt to make Finder the source — out of scope, unautomatable.
