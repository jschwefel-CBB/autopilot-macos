# CI & Distribution

## Continuous integration
`.github/workflows/ci.yml` builds and tests on a `macos-14` runner.

The **unit tests run headless**; the **AX-driven integration tests self-skip**
when `AXIsProcessTrusted()` is false (which it is on a stock GitHub runner), so
the suite stays green without an Accessibility grant. To actually exercise the
integration tests, you need a self-hosted runner with Accessibility granted to
the test process — stock GitHub macOS runners cannot grant TCC permissions
non-interactively.

## Releases
`scripts/release.sh <version>` produces a release build + a tarball under
`dist/`. It deliberately stops short of publishing (tagging / `gh release
create`) so nothing irreversible runs automatically — the printed next steps
show the manual publish commands and how to compute the sha256 for a Homebrew
formula.

## Release workflow (`.github/workflows/release.yml`)

Triggered by pushing a `v*` tag (e.g. `git tag v1.0.0 && git push origin v1.0.0`).

**What it does:**
1. Builds `autopilot` + `AutopilotMCP` on arm64 (`macos-14`) and x86_64 (`macos-13`) in parallel.
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
