# Project knowledge — whoopsididitagain

A cumulative log of hard-won knowledge for this repo. Append to it when a task fails and is then
fixed, phrased so a future session does not repeat the mistake. This is not static config.

`backend/CLAUDE.md` covers the Next.js service. This file covers the repo as a whole and the
iOS app, which previously had nowhere to record lessons.

## Layout

- `ios/WhoopsApp` — SwiftUI app, SwiftData persistence, Keychain session store, unit + UI tests
- `backend` — Next.js App Router OAuth/sync service, PostgreSQL adapter, Vitest tests
- `docs` — `DESIGN.md` (redesign spec), `ARCHITECTURE.md`, `DECISIONS.md` (ADRs), `TASKS.md`
  (execution log), `PROJECT_PLAN.md` (milestone scope)
- `docs/design/mockups` — one self-contained HTML file per screen. Where prose and mockup
  disagree, the mockup wins for visual values and `DESIGN.md` wins for behavior.

## Running the iOS tests — read this before running anything

**CI's simulator destination does not resolve on Robert's Mac.** `.github/workflows/ci.yml` uses
`-destination 'platform=iOS Simulator,name=iPhone 16'`, which is correct for the `macos-15`
runner. Locally it fails with:

```
xcodebuild: error: Unable to find a device matching the provided destination specifier
```

even though `xcrun simctl list devices available` lists an iPhone 16 at OS 18.3.1. Only the
iOS 26.5 runtime devices actually resolve for the `WhoopsApp` scheme.

Locally, use the iPhone 17 Pro by id:

```
xcodebuild -project ios/WhoopsApp/WhoopsApp.xcodeproj -scheme WhoopsApp \
  -destination 'id=E0AE64A0-8A10-4A40-856F-4507B97EB547' \
  -derivedDataPath /tmp/whoops-derived-data CODE_SIGNING_ALLOWED=NO \
  build-for-testing | test-without-building -only-testing:WhoopsAppTests
```

Why this matters: a verifier that copies the CI command verbatim gets a destination error
*before any test executes*. That is easy to misread as a code failure, and easier still to wave
through as if it were a pass. For builds only, `generic/platform=iOS Simulator` also works — that
is what `scripts/check.sh` already uses, so `check.sh` builds fine; if it ever runs tests, its
destination needs substituting too. **If you substitute a command, say so explicitly in your
report.** A silent substitution is indistinguishable from not having run the check.

Lint: `xcrun swift-format lint --recursive ios/WhoopsApp` (config `.swift-format`, 100 cols).

## One simulator, one XCUITest runner — never two at once

Two `xcodebuild ... test-without-building -only-testing:WhoopsAppUITests` runs against the **same
booted simulator** reliably kill each other, with symptoms that look like flaky product code:

```
Restarting after unexpected exit, crash, or test timeout
Test crashed with signal kill
```

This bites when parallel agents or terminals each verify their own UI tests. The crash is
contention, not a regression — retrying on the same device just crashes again.

Fix: give each concurrent runner its own booted device, all on the same runtime, e.g.
`E0AE64A0-8A10-4A40-856F-4507B97EB547` (iPhone 17 Pro), `841F86AE-00B6-41AC-B46B-D92B69C0421E`
(iPhone 17 Pro Max), `75C3D04F-395D-4236-B776-2A4FECEA4AF9` (iPhone 17e). Sharing one
`-derivedDataPath` across those runs is safe for `test-without-building`, which only installs and
runs an already-built bundle — but **never run `build-for-testing` into one derivedDataPath from
two processes at once**; that races on build products.

Consequence to remember: each simulator has its **own SwiftData store**, and that store is
**never reset between runs**. UI tests here drive real parses and saves, so state accumulates all
day. This cuts both ways:

- A test that passes only because an earlier test on *that* device left state behind is a
  **false pass**.
- Accumulated state also causes genuine **false failures**. In one afternoon of parallel work the
  shared device reached 46 workout plans and 10 therapy protocols, at which point even
  unmodified, previously-green tests (`testDocketShowsWindDownAndCompletesWithUndo`,
  `testProtocolPastePathReachesTapChipReview`) failed reproducibly.

So before blaming your diff for a UI-test failure, **check whether an untouched pre-existing test
fails the same way on that device**. If it does, the environment is at fault, not the change.
A fresh ephemeral simulator (`xcrun simctl create`, deleted after use) is the clean way to get a
trustworthy result without disrupting anyone else's in-flight runs.

Write UI tests to tolerate both an empty and an already-populated store.

To force a genuinely empty store for one run:

```
xcrun simctl uninstall <device-id> com.robertcdawson.whoops
```

`app.terminate()` + `app.launch()` does NOT do this — the on-disk SwiftData store survives a
relaunch. This matters most for tests that find their subject with a prefix query plus
`.firstMatch` (e.g. `identifier BEGINSWITH "record-actual-workout-"`): a crashed earlier run can
leave an orphaned row that `.firstMatch` selects instead of the one the test just created, and the
test passes for the wrong reason.

Also: after tapping `protocol-review-save`, `ProtocolCaptureView` does `await onSaved()` then
`dismiss()`, so the tab bar is not immediately interactable. Synchronize on the dismissal
(`app.navigationBars["Train"].waitForExistence(timeout: 5)`) before switching tabs, rather than
tapping into a view that is still going away.

## Adding a Swift file requires manual Xcode project edits

This project has **no file-system-synchronized groups** (`grep -c PBXFileSystemSynchronizedRootGroup
ios/WhoopsApp/WhoopsApp.xcodeproj/project.pbxproj` returns 0). Every new source file needs three
`project.pbxproj` entries:

1. a `PBXFileReference`
2. a group child entry
3. a `PBXBuildFile` in the **correct target's** Sources phase — app files in `WhoopsApp`, test
   files in `WhoopsAppTests` / `WhoopsAppUITests`

Copy the pattern at `project.pbxproj` lines 82-83 and 188-189 (sequential `B1…`/`F1…` ids).
A missing build-file entry surfaces as a misleading **"cannot find X in scope"** compile error —
if you see that for a file you just created, check the pbxproj before debugging the code.

Corollary for tests: if a new test file's target membership is missing, its tests silently do not
run. Always assert the expected test *count*, not just "0 failures".

## The SwiftData migration gate has a blind spot

`node scripts/verify-store-upgrades.mjs [refs...]` performs synthetic disk-backed upgrade checks.
The app's container combines **19 record types** merged from two branch parents
(see `docs/BRANCH_INTEGRATION.md`), so a migration that resets user data is unacceptable — this is
a personal health log with real recorded history.

Two traps:

- **It reads tracked files only** (`git ls-tree HEAD` plus `git ls-files`, lines 31-35). A new
  **untracked** `.swift` file declaring an `@Model` is invisible to it: the gate passes green while
  ignoring the very record type you added. **`git add` new model files before running it.**
- **Its `@Model` parser is strict** (lines 44-48). It only accepts property lines of the exact
  form `var name: String|Int|Double|Bool|Date|Data`, optional `?`, at most `@Attribute(.unique)`,
  declared above `init(`. No default values, no other attributes. A declaration it cannot parse is
  a declaration it cannot check.

Pass the current HEAD as a ref to prove an existing store *upgrades* rather than resets, e.g.
`node scripts/verify-store-upgrades.mjs d39a519 4824786 01b70dd`. If this gate fails, stop and
report — never "fix" it by simplifying the schema until it passes.

## Never fabricate health values

This is the app's core honesty property, and it is load-bearing rather than stylistic. The
readiness engine, the parser, and the docket are all deterministic and versioned; none require an
LLM. Specific rules that have already been enforced in review:

- The protocol parser surfaces ambiguous movements as tap-to-choose candidates and **never guesses**.
- Phase 2 refused to complete workouts from the docket because that would have meant inventing
  session RPE and pain values. Phase 3 resolves this by *launching* the record-actual sheet, not by
  inventing values.
- Pain is absent until the user taps a chip, and absent is stored as `nil`, never `0`.
- One tap on "as prescribed" is a **user assertion** that the prescription was met, which is why
  copying the prescribed numbers into actuals is honest. Prescribed quantities are **snapshotted at
  completion time** so that editing a protocol later cannot rewrite what was already logged.
- Legacy completions that predate a schema addition keep their original meaning and are
  **never backfilled**.

When adding a field that could be inferred, prefer optional-and-absent over a plausible default.

## Verification standards

- Report the *quoted* output of commands you ran. A claim of success without command output is
  treated as a failure.
- Assert test counts against a known baseline. As of phase 2 HEAD (`d39a519`): **147 unit tests,
  0 failures**, and 22 UI tests.
- When a change deliberately breaks existing tests, rewrite them — do not delete them — and name
  every removed test with a reason. Run the *whole* bundle, not just the new test, so repairs are
  proven rather than assumed.
- UI tests drive real parses and saves against the simulator's SwiftData store. They must tolerate
  pre-existing rows rather than assuming a clean store.
