# AutoPilot

A deterministic, app-agnostic macOS GUI test driver. It executes declarative
JSON test plans against any Mac app via the Accessibility API — no LLM in the
execution path, so the same plan + same app build produces the same result
every run.

> The product is **AutoPilot**. The CLI binary, Swift targets, and repository
> use lowercase/`Autopilot` spellings (`autopilot`, `AutopilotCore`,
> `AutopilotMCP`) — those are technical identifiers and are intentionally left
> as-is.

## What it does

- Drives any macOS app: launch, click, **press**, **menu**, type, key chords,
  **drag**, scroll, wait, assert.
- **Plan-as-contract:** an offline author (agent or human) writes a JSON plan;
  the executor runs it mechanically and reports structured results + failure
  artifacts (screenshots, AX-tree snapshots).
- **AX-first targeting** with a deterministic vision fallback (normalized
  cross-correlation template match) for custom-drawn controls.
- **Pixel-color assertions** for visual features the Accessibility API can't see
  (syntax colors, rainbow brackets, gutters).
- **Menu-bar navigation** drives commands with no key equivalent; reads menu
  checkmark state.
- Value assertions **poll** until they match (no flaky one-shot reads); the app
  is **activated** before input so keystrokes aren't dropped.
- Two front-ends over one shared core: a **CLI** and an **MCP server**
  (`run_plan`, `get_report`, `dump_axtree`).
- Plan composition via `include`; per-plan artifact namespacing.

## Layout

```
Sources/
  AutopilotCore/      engine: plan parser, targeting, actions, assertions, reporter
  autopilot/          CLI executable
  AutopilotMCP/       MCP server (run_plan, get_report, dump_axtree)
Tests/AutopilotCoreTests/
Fixtures/TestHostApp/  tiny AppKit app with known AX identifiers, for self-testing
```

## Quick start

```bash
swift build
.build/debug/autopilot doctor          # check Accessibility permission
.build/debug/autopilot run plan.json --artifacts ./artifacts
```

Exit codes: `0` pass, `1` test failure, `2` plan/parse error, `3` permission missing.

**Writing plans:** see **[docs/AUTHORING.md](docs/AUTHORING.md)** — the complete
plan-authoring guide (actions, assertions, selectors, discovery, hygiene
patterns, and a worked end-to-end example). Written to be usable by both an
AI agent and a human.

## Plan example

```json
{
  "schemaVersion": "1.0",
  "name": "click OK and verify count",
  "target": { "bundleId": "com.example.app" },
  "defaults": { "timeoutMs": 4000, "retryIntervalMs": 100 },
  "steps": [
    { "id": "click", "action": "click", "target": { "identifier": "okButton" } },
    { "id": "check", "action": "assert", "target": { "identifier": "countLabel" },
      "assert": { "property": "value", "op": "contains", "expected": "count: 1" } },
    { "id": "quit", "action": "terminate" }
  ]
}
```

## Requirements

macOS 14+, Swift 6 toolchain, and Accessibility permission granted to the
process (or terminal) running `autopilot` — `autopilot doctor` checks this.

## Design

See the design spec and implementation plan in the companion `medit` repo
(`docs/specs/2026-06-16-gui-test-driver-design.md`,
`docs/plans/2026-06-16-autopilot.md`).
