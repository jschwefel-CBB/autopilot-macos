# CI & Distribution

## Continuous integration
`.github/workflows/ci.yml` has three jobs:

| Job | Runner | What it does |
|---|---|---|
| `build-and-test` | hosted `macos-15` | `swift build` + the full unit/integration test suite. |
| `lint-plans` | hosted `macos-15` | `swift build`, then lints the committed unified plan (`autopilot lint`). |
| `unified-plan` | **self-hosted macOS** | Runs the full 78-step `test-all-capabilities.json` plan end-to-end via the CLI against the `TestHostApp` fixture — the macOS analogue of the iOS XCUITest / Android instrumented run. Hard gate: any failing step fails the job. |

**Why a self-hosted runner for `unified-plan`.** Driving a real Mac app needs a
real, logged-in graphical session: synthesized clicks, menu tracking, and live
Accessibility reads. GitHub's hosted macOS runners are effectively headless
(`system_profiler` reports no display) and drop a small fraction of GUI
interactions at random, so a hosted GUI gate is flaky. On a real display the
plan passes reliably. The hosted runners still run everything that does **not**
need a display (`build-and-test`, `lint-plans`).

**Self-hosted runner setup (macOS).** Register a runner labeled
`[self-hosted, macOS]` on a Mac with a logged-in user. Two macOS-specific
requirements:
- **Run it inside a terminal app that has Screen Recording**, e.g. Ghostty or
  iTerm (System Settings → Privacy & Security → Screen Recording). macOS
  attributes Screen Recording to the nearest *app-bundle* ancestor of the
  process, and a LaunchAgent/LaunchDaemon has none — so the runner started by a
  LaunchAgent can never get Screen Recording. Launch `run.sh` from the granted
  terminal instead.
- **Grant Accessibility** to `/bin/bash` (and/or the runner's `Runner.Worker`)
  so synthesized input is allowed.
The `unified-plan` job runs an `autopilot doctor` step that prints the
Accessibility / Screen Recording status, so a missing grant fails loudly.

**Security (public repo).** The `unified-plan` job is gated so it runs only on
pushes to this repo and on pull requests from *same-repo* branches — never on
fork PRs — so an untrusted fork cannot execute code on the self-hosted machine.
The repo also requires workflow approval for all outside-collaborator PRs.

### Sibling repos
The iOS (`autopilot-ios`) and Android (`autopilot-android`) repos run the **same
unified plan** in their CI: iOS via XCUITest on a simulator, Android via an
instrumented test on an emulator (both fully on GitHub-hosted runners, since a
simulator/emulator brings its own rendering surface — the constraint that forces
a self-hosted runner is specific to native macOS). `autopilot-core` runs
`swift build` + a core-purity check + its unit tests on hosted `macos-15`.

## Releases
`scripts/release.sh <version>` produces a release build + a tarball under
`dist/`. It deliberately stops short of publishing (tagging / `gh release
create`) so nothing irreversible runs automatically — the printed next steps
show the manual publish commands and how to compute the sha256 for a Homebrew
formula.

## Release workflow (`.github/workflows/release.yml`)

Triggered by pushing a `v*` tag (e.g. `git tag v1.0.0 && git push origin v1.0.0`).

**What it does:**
1. Builds `autopilot` + `AutopilotMCP` on `macos-15` (arm64). The tap and releases are arm64-only.
2. Notarizes each tarball with Apple's `notarytool` (skipped if `APPLE_ID` secret is absent).
3. Creates a GitHub Release with both tarballs attached and auto-generated release notes.
4. Updates the Homebrew tap formula (`Formula/autopilot.rb` in the tap repo) with the new URLs and SHA-256 hashes.

**Required secrets** (Settings → Secrets → Actions):
| Secret | Purpose |
|---|---|
| `APPLE_ID` | Apple ID for notarization (optional — skip for ad-hoc signing only) |
| `APPLE_TEAM_ID` | Apple Team ID |
| `APPLE_APP_PASSWORD` | App-specific password from appleid.apple.com |
| `TAP_REPO` | HTTPS URL of `homebrew-autopilot` repo |
| `TAP_GITHUB_TOKEN` | GitHub PAT with `repo` write scope on the tap repo |

**Manual release** (without CI):
```bash
scripts/release.sh 1.0.0           # build + package
scripts/notarize.sh dist/*.tar.gz   # notarize (optional)
git tag v1.0.0 && git push origin v1.0.0
gh release create v1.0.0 dist/*.tar.gz --title "v1.0.0" --generate-notes
SHA=$(shasum -a 256 dist/autopilot-1.0.0-arm64.tar.gz | awk '{print $1}')
TAP_REPO=https://github.com/<owner>/homebrew-autopilot.git \
  GITHUB_TOKEN=<pat> \
  scripts/update-tap.sh 1.0.0 "$SHA" arm64
```

## Plan schema
`schema/plan.schema.json` (JSON Schema draft-07) describes the plan format.
Point your editor at it for autocomplete + validation, e.g. in VS Code:

```jsonc
// .vscode/settings.json
{ "json.schemas": [
  { "fileMatch": ["**/uitests/**/*.json", "**/testplans/**/*.json"],
    "url": "./schema/plan.schema.json" } ] }
```
