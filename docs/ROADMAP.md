# AutoPilot Roadmap

Candidate work for future versions, grounded in what's actually deferred or weak
in the current code — drawn from `review-findings.md` (A6), `feedback-response.md`
(deferred items across 3 consumer rounds), and the limitations documented in
`AUTHORING.md`. **Nothing here is committed work**; it's a prioritized backlog.

Each item notes **why** (the concrete friction it removes), rough **effort**
(S/M/L), and **risk**. Items are grouped into themed milestones; within a theme
they're ordered by value-per-effort.

> **Guiding principle (unchanged from v1):** deterministic, no LLM in the
> execution path, honest about limitations. Every new capability ships with a
> test against the `TestHostApp` fixture and a documented caveat where one
> applies.

---

## Status snapshot (what v1 already delivers)

So the roadmap isn't read in a vacuum — current capabilities:

- Actions: launch, terminate, click, doubleClick, rightClick, **press**, **menu**,
  type (+clear/commit/focus, keycode-based so search fields work), keyPress (full
  ANSI), setValue, scroll, **drag** (element→element), **assertPixel**, waitFor,
  screenshot, assert, wait.
- Polled property asserts; app activation before input; AX-first targeting with
  deterministic vision fallback; per-plan artifact namespacing; ambiguous-match
  listing; truncation signalling; error-vs-fail semantics; CLI + MCP front-ends;
  `include` composition.
- 65 tests; consumer-validated across 3 rounds (medit, 20 plans).

---

## Milestone A — Scale: parallel suite execution

The single biggest structural change. Today the core blocks on a
`DispatchSemaphore` + `Thread.sleep` (`AppLauncher.swift`, `Clock.swift`), so
plans run strictly one at a time and a consumer must shell-loop over a directory.
At medit's current 20 plans this is already the dominant wall-clock cost.

| # | Item | Why | Effort | Risk |
|---|---|---|---|---|
| A1 | **Async core** — convert launch + poll to async/await (`NSWorkspace.openApplication` has an async form; replace `Thread.sleep` with an async sleep; keep the `Clock` abstraction for deterministic tests) | Unblocks everything below; removes thread-blocking | **L** | Med — touches the hot path; needs careful test port |
| A2 | **Suite runner** — `autopilot run <dir>/` runs every `*.json` plan, each in its own per-plan artifact dir, with one **aggregate report** (`SUITE 18/20 passed`, per-plan rollup JSON) | Consumers stop hand-scripting loops; one exit code for CI | **M** | Low |
| A3 | **`--parallel N`** — run N plans concurrently against N app instances; cap by cores | Big wall-clock win for large suites | **M** (after A1) | Med — instance isolation, AX-tree cross-talk; must verify each plan still hits its own instance |
| A4 | **Per-run isolation guard** — ensure a plan only ever drives the instance it launched (track pid; scope AX queries to it), so parallel runs can't cross-talk | Correctness prerequisite for A3; also fixes the latent "leaked instance poisons resolution" class we hit in tests | **S–M** | Low |

**Order:** A1 → A4 → A2 → A3. A1 is the gate; A2 delivers value even before A3.

---

## Milestone B — Authoring & debugging ergonomics

Reduce the friction of *writing* and *fixing* plans — the time sink once the
capability set is broad enough (it now is).

| # | Item | Why | Effort | Risk |
|---|---|---|---|---|
| B1 | **`dump-axtree` CLI subcommand** | Today the tree dump is MCP-only; a `autopilot dump-axtree <bundleId>` (plain array, `--interactive-only`, `--window` filters) lets humans/scripts discover selectors without the JSON-RPC envelope that misled an early consumer | **S** | Low |
| B2 | **`nth` / `index` selector** — when a selector is intentionally ambiguous, pick the nth match (the ambiguity error already lists them) | Disambiguate without forcing the app author to add an `identifier` | **S** | Low |
| B3 | **`within` / parent scoping** — e.g. "the `AXStaticText` inside the `AXRow` at index 0" | Targets repeated structures (table rows, outline cells) that `role`+`value` can't uniquely hit | **M** | Med — selector grammar grows |
| B4 | **`find-element` helper** (CLI/MCP) — given a selector, return the matches with frames | Author a selector and instantly see what it resolves to | **S** | Low |
| B5 | **Plan linter** — `autopilot lint plan.json` validates schema + flags non-functional `label`/`path` selectors, missing `terminate`, missing window-wait | Catches the documented footguns before a run | **S** | Low |
| B6 | **Record-assist** (stretch) — observe a session and emit a draft plan / selector suggestions | Lowers the cost of the first plan for a new app | **L** | High — scope creep; keep deterministic, suggestions only |

**Order:** B1, B5 (cheap, high-value) → B2 → B4 → B3 → B6 (only if demand).

---

## Milestone C — Visual testing depth

`assertPixel` is reliable for solid fills but **fragile on thin anti-aliased
glyphs** (the medit rainbow-bracket color test was deliberately not shipped for
this reason — it remains a manual check). Close that gap.

| # | Item | Why | Effort | Risk |
|---|---|---|---|---|
| C1 | **Region color assertion** — assert the **average** or **dominant** color in a rectangle (not a single pixel), with tolerance | Makes glyph/region color tests robust enough to ship — the one medit gap still manual | **M** | Med — define "dominant" deterministically (e.g. modal bucket); document what it can't do |
| C2 | **Region snapshot/diff** — capture a named region and compare to a committed reference image with a pixel-diff threshold | Catches unintended visual regressions (theme, layout) without per-pixel asserts | **L** | Med — reference-image management, anti-alias noise; needs a sane default threshold |
| C3 | **Element-relative region helper** — express the rectangle relative to a resolved element's frame, not absolute screen coords | Plans survive window moves / different displays | **S** (with C1) | Low |

**Order:** C1 + C3 together → C2 if visual regression becomes a real need.

---

## Milestone D — Polish the documented rough edges

Small, bounded fixes to the limitations currently documented as caveats. Batch
them; none is individually large.

| # | Item | Why | Effort | Risk |
|---|---|---|---|---|
| D1 | **`marked` cold-read** — populate/validate the menu before reading `AXMenuItemMarkChar`, or auto-open the containing menu in the `marked` assertion | Today `marked` reads `false` until the menu is opened — a documented gotcha | **S–M** | Low |
| D2 | **Menu re-toggle reliability** — back-to-back invokes of the same menu item are flaky; add a settle/validation between presses | Consumer-reported P2 | **S** | Low |
| D3 | **`+` key in chords** — the `+` separator can't express `Cmd-+` (zoom); add an escape (e.g. `"plus"` alias, already partially mappable) | Documented limitation | **S** | Low |
| D4 | **`--settle-ms` / wait-for-prior-PID on relaunch** — **measure first**: app activation (v1) may already obviate the relaunch race. Only build if it still reproduces | Avoid building a flag for a fixed problem | **S** | Low |
| D5 | **Non-ANSI typing** — accented/emoji characters fall back to unicode-string and may be rejected by some field editors; investigate a layout-aware path | Edge case; document remains the honest answer until a real need | **M** | Med |

**Order:** D3, D2 (cheap) → D1 → D4 (measure) → D5 (only if needed).

---

## Milestone E — Distribution & adoption (optional)

If AutoPilot is meant to be used beyond this pair of repos:

| # | Item | Why | Effort |
|---|---|---|---|
| E1 | **`brew`-installable / release binaries** + tagged releases | One-command install for consumers | **S–M** |
| E2 | **JSON Schema for plans** (published) — editor autocomplete + validation in any editor | Authoring quality-of-life | **S** |
| E3 | **CI recipe** — a documented GitHub Actions job that runs a plan suite on a macOS runner (incl. the Accessibility-grant dance) | Makes AutoPilot usable in CI, not just locally | **M** | 

---

## Recommended first cut for "v2"

If picking a single coherent release rather than all of it:

**v2 = Milestone A (scale) + B1/B5 (cheap ergonomics) + C1/C3 (region color).**

Rationale: A is the structural unlock the growing suite needs; B1/B5 are
near-free authoring wins; C1/C3 close the one capability gap (visual color) that's
still manual. D and the rest of B/E are fast-follow once those land.

Everything here ships the v1 way: TestHostApp-backed tests, honest caveats, no
LLM in the execution path.
