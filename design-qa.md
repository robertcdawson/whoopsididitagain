# Native journal design QA

## September 4 experience improvements — 0.11.0

The approved experience plan includes all nine review areas and phase 6 Bring to PT. Implementation
is complete; all 197 unit tests and 43 UI cases passed. The signed 0.11.0 build is installed on the
paired iPhone. Physical acceptance remains pending.

- First focused run: 194 unit tests and three UI flows passed (draft restoration after relaunch,
  PT preview/PDF preparation, and the short workout path with explicit scores and duration).
- Additional checks cover reopening modified protocol completions, composite draft-source deletion,
  missing versus explicit-zero movement pain, confirmed draft discard, correction after Undo expiry,
  and bottom Save/microphone position in both handedness modes with accessibility text and keyboard.
- The 19-to-20-model synthetic disk-backed upgrade from `11c8d78` preserved every existing field,
  including nils. Output: `/tmp/whoops-experience-upgrade.log`.
- Backend lint, typecheck, 10 tests, and production build passed using arm64 Node 24.19.0. The
  initial shell selected an x64 Node for the test subprocess; correcting PATH resolved the missing
  optional Rollup binary without changing dependencies or lockfiles.
- Native-resolution focused screenshots show readable PT sections and a bottom Share PDF button;
  the workout editor keeps duration, RPE, pain, and Save visible while details remain expandable.
- The largest-text keyboard captures show an enabled Save above the keyboard in both handedness
  modes. Coordinate taps save successfully; microphone hit areas remain at least 44 points.
- Draft recovery uses a dedicated sheet with an explicit discard-confirmation alert. This avoids
  competing modal transitions and passed keep, resume, discard, and reopen checks.
- PDF pagination retains selectable text through a long note. No historical adherence percentage,
  causal claim, healing date, or clinical clearance is inferred from current prescriptions.

Focused evidence: `/tmp/whoops-experience-build/Logs/Test/Test-WhoopsApp-2026.09.04_16-44-04--0700.xcresult`.
Final-source unit evidence: `/tmp/whoops-experience-third/Logs/Test/Test-WhoopsApp-2026.09.04_17-00-55--0700.xcresult`
(197 unit tests passed; the accompanying draft UI test was subsequently corrected and rerun).
Both-handedness keyboard evidence: `/tmp/whoops-experience-unit-final/Logs/Test/Test-WhoopsApp-2026.09.04_17-03-02--0700.xcresult`;
native captures are in `/tmp/whoops-experience-final-reach-captures`.
The signed 0.11.0 device build passes; app and widget both retain
`group.com.robertcdawson.whoops`. On September 4 at 17:22 Pacific, `devicectl` installed
`com.robertcdawson.whoops` over the existing app without uninstalling or resetting its store
(database sequence 3620; `/tmp/whoops-experience-install.log`).

The full UI suite ran in three independent simulator batches. All 43 declared cases have passing
final results. One older parser test initially attempted to use the composer behind the newly
required recovery sheet; it now explicitly resumes and verifies the saved input before parsing.
Its focused rerun passed without further product changes.

- 13/13: `/tmp/whoops-experience-third/Logs/Test/Test-WhoopsApp-2026.09.04_17-05-47--0700.xcresult`.
- 14/15 initially: `/tmp/whoops-experience-unit-final/Logs/Test/Test-WhoopsApp-2026.09.04_17-06-02--0700.xcresult`;
  the remaining parser case passed in `/tmp/whoops-experience-third/Logs/Test/Test-WhoopsApp-2026.09.04_17-15-52--0700.xcresult`.
- 15/15: `/tmp/whoops-experience-build/Logs/Test/Test-WhoopsApp-2026.09.04_17-07-45--0700.xcresult`.

Final native screenshot exports are in `/tmp/whoops-experience-final-ui-captures` and
`/tmp/whoops-experience-final-pt-captures`. Swift formatting, plist/project/asset validation, and
`git diff --check` passed.

Phone acceptance must cover left-thumb completion and correction of check-in, protocol, pain, and
workout entries; first-use speech/microphone permissions and interruption/backgrounding; resumed
and discarded drafts; larger text and VoiceOver; PT date changes, PDF preview/share; and the pending
phase-5 cold/warm quick-action and map long-press checks. No physical acceptance is inferred from
simulator or signed-build results.

## Phase 5 ad-hoc pain addendum (September 3)

**Current result: automated verification passed; physical-phone acceptance pending.**

- The implementation follows the `PainLog` mockup's one-handed order: area chip, 0–10 chip,
  optional dictated note, then a thumb-zone save action. Native large-sheet scrolling and Dynamic
  Type take precedence over the fixed HTML frame.
- Home Screen **Log Pain**, `whoops://pain`, Body's visible action, and a Body-map long press all
  converge on the same editor. Ordinary map taps retain affected-area editing; VoiceOver has a
  named Log pain action.
- Standalone events use stable body-area IDs and remain separate from morning check-ins, readiness,
  experiments, workout pain, restriction logic, and current trend calculations.
- Body history supports correction and confirmed deletion. The regression creates an entry, edits
  the same ID, relaunches to prove persistence, verifies the corrected value, and confirms that a
  swipe alone cannot permanently delete it.
- Final-source verification passed: **186 unit tests and 37 UI tests**, with zero failures. The
  repository-wide check also passed backend lint, typecheck, 10 tests, production build, Swift
  formatting, and the iOS build-for-testing. The additive 19-to-20-model synthetic store upgrade
  preserved every seeded field, including nils. The pain editor was visually checked in the
  simulator at native resolution.
- The signed 0.10.0 app was installed over the existing phone app without uninstalling or resetting
  its store. The app and widget signatures carry the same `group.com.robertcdawson.whoops` App
  Group entitlement.
- Pending physical acceptance: confirm cold/warm quick-action routing, map long press and ordinary
  tap, dictation permission/on-device fallback, correction/confirmed deletion, Dynamic Type, and
  VoiceOver on Robert's iPhone.

Automated result bundles:

- Unit: `/tmp/whoops-phase5-full/Logs/Test/Test-WhoopsApp-2026.09.03_15-55-42--0700.xcresult`
- UI: `/tmp/whoops-phase5-full/Logs/Test/Test-WhoopsApp-2026.09.03_15-56-28--0700.xcresult`

## Reopened after physical-phone feedback (August 31)

The previous simulator acceptance below did not cover bottom-action reachability or every
secondary screen. Robert's annotated `IMG_5416.jpg`–`IMG_5420.jpg` identify missing link/input
affordances, old workout-detail surfaces, duplicate Body copy, and obscured bottom actions.
The new coordinate-tap regression reproduces the old layout failure: the library link ended
at y=824 while it needed to be at or above y=772. This pass is not accepted until those issues
are corrected and recaptured; the earlier pass is retained as historical evidence only.

**Current final result: accepted** — final-source regression, phone-target compile, visual
comparison, and Robert's September 1 physical-phone approval are complete. Remaining feature work
may continue in the documented order.

## Structured body-map addendum (August 31)

- **Source visual truth:**
  `/Users/robertdawson/.codex/generated_images/01a045b1-b161-7552-a3a7-7a83c02dd1b4/exec-e2e0c789-c190-4ef9-9dcb-31902c3cbed0.png`
- **Implementation screenshot:** `/tmp/whoops-body-map-picker-implementation-final.png`
- **Combined comparison:** `/tmp/whoops-body-map-picker-comparison.png`
- **Viewport and density:** native iPhone 17 Pro simulator, 402 × 874 points, 1206 × 2622
  pixels at 3×. The 853 × 1844 source and native screenshot were each normalized to 1844
  pixels high and placed side by side in a 1702 × 1844 comparison. This is a native app, so
  browser CSS size and deviceScaleFactor do not apply.
- **State:** light journal, normal text, focused right arm, Back view, “Posterior upper arm
  (triceps area)” selected, persistent confirmation visible. The implementation contains
  synthetic restriction data only.

### Findings and comparison history

1. **[P2, fixed] Opaque illustration background.** The first native capture
   (`/tmp/whoops-body-map-picker-implementation.png`) showed a beige rectangular image boundary
   over the journal dots. The four anatomy assets were regenerated from their exact edit targets
   with genuine alpha and verified as transparent PNGs. The second capture removes the boundary.
2. **[P2, fixed] Focus highlight was broader than the illustrated upper arm.** The first capture
   used a wide rounded rectangle without a figure-level selection cue. Hit frames now align to
   the rendered arm, use a capsule-like radius, retain at least 44 points, and show an SF Symbol
   checkmark. The final capture and the selected text row identify the same posterior upper-arm
   area without labeling the elbow as triceps.
3. **[P3, accepted native adaptation] Labeled rows replace leader lines.** The source keeps all
   labels beside one large anatomical drawing. The implementation uses a 320-point focus image
   followed by full-width 44-point rows, a List fallback, and a pinned confirmation action. This
   requires scrolling for lower rows but keeps each target readable, tappable, VoiceOver-addressable,
   and practical one-handed. It preserves the source hierarchy and selection semantics.

The source and final implementation were opened together in the same combined comparison after
both P2 fixes. The full view is sufficient for focused comparison as well: at normalized height,
the header, anatomy art, selected figure marker, selected row, and persistent CTA are all readable.
The original native screenshot remains available for pixel-level inspection.

### Required fidelity surfaces

- **Fonts and typography — pass:** journal Literata hierarchy is consistent with the production
  shell; labels wrap as whole phrases and the selected anatomy term remains explicit.
- **Spacing and layout — pass:** native status/safe areas, scrolling, 44-point targets, and the
  pinned CTA take precedence over the static concept's taller single canvas. No action is covered.
- **Colors and tokens — pass:** paper, blue ink, amber selection, red margin, and gray rule reuse
  shared journal tokens with a non-color checkmark and selected state.
- **Image quality — pass:** all four project anatomy assets are full-resolution transparent PNGs
  with real generated line art; no opaque rectangle, placeholder, emoji, or code-drawn anatomy
  substitutes the visual asset.
- **Copy and content — pass:** entire-arm, shoulder, posterior upper arm, elbow, forearm, and
  wrist/hand remain separate; “triceps area” qualifies only posterior upper arm. No diagnostic or
  healing claim is added.
- **Interaction and accessibility — pass:** coarse navigation does not select, detailed areas
  multi-select, entire-region and detailed choices are mutually exclusive, List/Clear/Remove/Add
  another paths work, Reduce Motion crossfades, and the saved selection reopens.

No actionable P0/P1/P2 body-map difference remains in the tested state. Robert approved the
corrected physical-phone flow on September 1, 2026.

final result: passed

## Phone-feedback pass: implementation and current evidence

- Target: disposable **WHOOPs Dependability QA**, iPhone 17 Pro / iOS 26.5, 402 × 874 points
  (1206 × 2622 native pixels), matching the supplied phone screenshots' aspect and density.
- Annotated sources `IMG_5416.jpg`–`IMG_5420.jpg` and native captures are normalized to 402 × 874
  under `/tmp/whoops-dependability-qa/{reference,normalized}`. These private diagnostic artifacts
  are not committed or uploaded. Synthetic data differs from the source; source health values
  are never copied into app fixtures.
- The old-layout reproduction failed with `824.0` greater than `772.0`. Reserving a separate
  measured navigation row fixes it; the same coordinate-tap test passes at normal and
  Accessibility XXXL sizes and actually opens Your Movements.
- Today/Work/Body and completed-workout/reference pairs were opened together. The corrections
  are separate readiness rows, underlined actions, one Body selector, the exact-default note
  cleanup, a full wrapped workout title, and paper instead of white/gray secondary cards.
- Editor comparison exposed nested borders; removing redundant form modifiers and resetting
  the inner text-field style to plain leaves one border. Focused duration entry shows a stronger
  border, the native keyboard, and Done. Small status text uses darker green/amber inks with
  paper contrast ratios 4.90:1 and 4.73:1 (red 4.82:1), plus non-color status cues. Unfocused
  input borders have 3.21:1 contrast against paper.
- The wrapping title field initially inserted a newline on software-keyboard Done. Its
  single-line binding now ends focus while permitting visual wrapping. True multiline notes
  keep Return/newlines. The existing submit/cancel/save/tab keyboard test passes this correction.
- Follow-up editing checks found the native floating Done toolbar overlapping Actual load's
  focused value. Done now occupies a measured bottom safe-area inset. Secondary-page tests also
  exposed list buttons whose accessibility rows were wider than their hit areas; journal list
  actions now fill the row before applying their rectangular hit shape. Both fixes pass
  targeted coordinate-tap, save/reopen, and cancellation checks. iOS 26's reset confirmation
  is an anchored native popover without a Cancel row; the test dismisses outside its bounds.
- Before the final color correction, the full unit run reported `Executed 166 tests, with 0
  failures`. Final-source acceptance now passes **167 unit tests and 33 UI tests**, with zero
  failures, and the unsigned physical-iPhone target build passes.
- Synthetic disk-backed storage compatibility passes from HEAD (`0f65324`) to the working tree:
  `Verified 19 model types` and `PASS: all persisted fields from HEAD, including nils, survived
  the upgrade`. This macOS check complements the iOS rationale-cleanup tests; it does not read
  the phone's store or substitute for phone acceptance.
- The first full UI run exposed an invalid numeric-edit update loop in duration estimates.
  A stack sample showed repeated SwiftUI text updates and a 1.7 GB simulator-app footprint.
  Numeric editors now validate model updates in their Binding setters. `WorkoutFieldInput`
  separates pending text from accepted text and reconciles the display without re-publishing
  the model. A rejecting setter alone left invalid digits visible; the shared state resolves
  that as well. The estimate test checks third-decimal rejection and save/reopen; it now passes
  with all **166 unit tests** in `whoops-dependability-reconciliation.xcresult`; the subsequent
  final full suite also passes. Only the hung disposable app
  was terminated after diagnostics, allowing the first suite to continue.
- The large-text failure recording exposed narrow two-column completed-workout rows: long
  titles broke inside words and made populated history excessively tall. These rows now stack
  title/session information above the date at accessibility sizes. The bottom-action test
  retains its frame-clearance and coordinate-tap assertions and checks available title width.
  Its page drag starts in the paper margin to avoid nested text-editor gesture capture.
- The final-source populated-history proof passes both completed-workout editing and bottom
  navigation tests (`whoops-dependability-history-proof.xcresult`, 2 UI tests, zero failures).
  Its normal/Accessibility XXXL captures show the library link fully above navigation. The
  detail/editor captures were opened beside the matching annotated sources: paper rows,
  wrapped titles, and single bordered inputs resolve the identified differences.
- The clean-state full run passes **166 unit tests** and **32 of 33 UI tests**. Its one failure
  is a test-driver tap into an obscured Parse button. The failure recording and hierarchy show
  Parse at y=421.7–481.7, behind Done starting at y=423, with the keyboard key frame at y=583.
  The test's guessed 100-point keyboard clearance missed the actual footer; no parse began.
  The helper now measures Done, scrolls to clear bounds when needed, and coordinate-taps the
  visible action. Both focused parser checks pass (`whoops-dependability-parser-tap.xcresult`).
  App source is unchanged by this test-only correction.
- Secondary-screen comparison then exposed bright legacy status colors on paper. Warnings,
  errors, connection status, and explicit secondary status text now use the journal's darker
  text inks. The new token-contrast test and secondary-route UI test pass in
  `whoops-dependability-colors.xcresult`. The old/new Restrictions captures were opened together
  and confirm readable amber/red and secondary ink. The partial `whoops-dependability-ready`
  run was deliberately interrupted before this correction; it is not acceptance evidence.
  The final full run is `whoops-dependability-verified.xcresult`.

### Final acceptance evidence (August 31, 14:07)

The final source was frozen throughout the full run. Exact command output:

```text
Executed 167 tests, with 0 failures (0 unexpected) in 2.178 (2.241) seconds
Executed 33 tests, with 0 failures (0 unexpected) in 1124.461 (1124.491) seconds
** TEST SUCCEEDED **
** BUILD SUCCEEDED **
Verified 19 model types
PASS: all persisted fields from HEAD, including nils, survived the upgrade
```

The unit count is the initial migration's 161 plus four readiness/rationale cases, one numeric
input-state case, and one contrast case. The UI count is the initial 31 plus two new bottom-action
and secondary-route cases; existing editing, parsing, persistence, and keyboard tests were
retained and strengthened. Swift-format lint, both property-list checks, and `git diff --check`
pass. No backend code or authoritative health calculations changed in this follow-up.

All 33 named final-run captures were exported to `/tmp/whoops-dependability-qa/verified`, then
normalized into `normalized`. Each of the five annotated references was opened together with
its final native counterpart at 402 × 874. Synthetic records and text-size settings differ from
the private phone state; no screenshot health values were copied into fixtures.

| Phone feedback | Final comparison and behavior evidence |
| --- | --- |
| Today metric rows and check-in affordance | Separate labeled rows, status icons/inks, underlined check-in; unavailable values remain honest. |
| Work links and unreachable bottom action | PT action underlined; Your Movements fully above navigation at normal and Accessibility XXXL; coordinate tap opens the library. |
| Workout detail and editor mismatch | Paper surfaces replace white grouped cards; full title wraps, inputs have one visible border, native date controls remain editable. |
| Keyboard and numeric editing | Focused value and Done visible; third decimal rejected, valid decimal saved/reopened, submit/save/cancel/scroll/tab dismissal passes. |
| Body duplication and default rationale | One selector prompt, underlined actions, only the exact shipped note cleaned; custom notes and record dates covered by unit tests. |
| Secondary screen readability | Final Restrictions capture uses dark journal status inks; earlier secondary-route comparisons cover settings, sleep, protocol, experiment, and actual-work screens. |

Native navigation bars, date pickers, keyboard, placeholders, and confirmation popovers are
intentional platform controls. This is targeted visual/contrast acceptance, not a claim that
every possible accessibility configuration or real-device state has been exhaustively audited.
No app was installed on the phone, and no commit or push was performed.

### Current verification commands and artifacts

```sh
xcodebuild -project ios/WhoopsApp/WhoopsApp.xcodeproj -scheme WhoopsApp \
  -destination 'platform=iOS Simulator,id=DAAED7E5-3314-4C71-88F0-9988B41F7592' \
  -derivedDataPath /tmp/whoops-dependability-build -parallel-testing-enabled NO \
  -collect-test-diagnostics never -resultBundlePath /tmp/whoops-dependability-verified.xcresult \
  CODE_SIGNING_ALLOWED=NO test

xcodebuild -project ios/WhoopsApp/WhoopsApp.xcodeproj -scheme WhoopsApp \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/whoops-journal-device-verified \
  CODE_SIGNING_ALLOWED=NO build

node scripts/verify-store-upgrades.mjs HEAD
xcrun swift-format lint --recursive ios/WhoopsApp
plutil -lint ios/WhoopsApp/WhoopsApp/Resources/Info.plist \
  ios/WhoopsApp/WhoopsApp.xcodeproj/project.pbxproj
git diff --check
```

Logs: `/tmp/whoops-dependability-verified.log`,
`/tmp/whoops-dependability-device-verified.log`, and
`/tmp/whoops-dependability-store-upgrade.log`. The simulator is disposable and contains only
synthetic records. After proving populated-history behavior, its test app was uninstalled
successfully before the final full suite, covering a clean launch through populated history.
No usual simulator or phone store was reset. Recreate an isolated simulator and substitute
its ID to repeat after cleanup.

After exporting final evidence, the named disposable simulator was shut down and deleted.
Only this run's `/private/tmp/whoops-dependability-build` and
`/private/tmp/whoops-journal-device-verified` derived-data caches were removed. These contain
rebuildable output and synthetic QA state, not user records. Logs, result bundles, and exported
screenshots remain available; no regular simulator, phone data, or source file was deleted.

### Phone acceptance checklist (after final automated verification)

1. Build this checkout onto the existing app with Xcode ⌘R; do not uninstall or reset data.
2. On Today, confirm the three readiness rows and their honest values/statuses. Tap the
   underlined check-in link; save, reopen, and cancel an edit.
3. Scroll each main page to its bottom. Open Your Movements from Work and all trends/export
   from Body; no action should sit behind the navigation. Repeat with larger text if used.
4. Open a completed workout: paper detail, full title. Use a test workout or a genuine correction
   to check title, date/time, duration, RPE, pain, and actual load/reps; save and reopen. Cancel
   a subsequent edit and verify no change. Do not add invented measurements to real history.
5. Try Done, Save, Cancel, a scroll, and a zone change after typing. The keyboard must not linger.
6. Check Settings/restrictions/sleep schedule and protocol paste/review. Confirm the same paper
   controls, one Body selection prompt, and preservation of custom notes and existing records.

Stop for Robert's approval here. Remaining widgets/notifications and ad-hoc pain logging follow
only after approval; there is no new analytics work in this pass.

## Historical scope and evidence (initial migration; superseded)

- Source visual truth: `docs/design/mockups/{TodayZone,WorkZone,BodyZone,CheckIn,Capture,ParseReview,RecordActual}.html`.
- Behavior source: `docs/DESIGN.md`. This is a production SwiftUI migration, not a web prototype.
- Source captures: `/tmp/whoops-journal-qa/*-reference.png`, rendered in Chrome at 390 × 844 CSS pixels, density 1.
- Final native target: isolated **WHOOPs Journal Visual Final**, iPhone 17e / iOS 26.5, 390 × 844 points, 1170 × 2532 pixels, density 3.
- Implementation captures and test results are local diagnostic artifacts under `/tmp/whoops-journal-qa/` and `/tmp/whoops-journal-*.xcresult`; they are not shipped or uploaded.
- State: light journal, normal text and Accessibility XXXL, right/left-handed layout, empty and populated local synthetic history. No real health records or mockup recovery scores are injected.
- Native status bar, home indicator, keyboard, navigation bars, and scrolling are intentional differences from the chrome-free, fixed-height HTML. Different source/fixture content is not treated as a pixel-layout defect.

## Findings and comparison history

1. **[P1, fixed] Paper decoration covered page content.** The first simulator comparison showed the docket and lower Work content hidden. A fixed-height background stack imposed its size on the bottom navigation. The margin and notebook holes now draw in a proposal-sized Canvas. The second comparison (`visual2`) shows the full page and correctly bounded navigation.
2. **[P2, fixed] Taped-card text had a shadow.** The shadow modifier affected foreground text as well as the paper. It now belongs only to the card background.
3. **[P2, fixed] Largest-text navigation broke words into letters.** Persistent zone labels now scale within a bounded navigation range and remain on one line; page content retains unrestricted Dynamic Type. The page date stacks below its title at accessibility sizes.
4. **[P2, fixed] Check-in save required scrolling.** The primary action now sits in the bottom safe area, uses a shorter accessible-size label, and remains above the keyboard. Symptom pills wrap by measured width rather than stretching across a grid.
5. **[P1, fixed] Workout intake accessibility identity.** A container-level disclosure identifier masked the nested editor's identity. The expansion action is now a separate native Button, keeping nested editor and parsing controls independently addressable. Final-source parsing, plan editing, completion editing, reported-total correction, and intake tests pass.
6. **[P2, fixed] Cadence chips split words at normal size.** The larger bundled font exposed a fixed horizontal-row constraint. Cadence and weekday controls now wrap by measured width, preserving whole labels and touch targets. Protocol review also mirrors its content insets with the notebook margin.
7. **[P2, fixed] Capture status-bar contrast.** A globally light journal left dark system text against the capture mockup's dark background. Capture now explicitly uses dark system chrome, returning to light chrome for paper review and entry sheets. Capture can scroll at accessibility sizes.
8. **[P2, fixed] Navigation exposed duplicate system tabs and undersized accessibility bounds.** The system tab bar was visually covered but remained in the accessibility tree. Each tab now explicitly hides it; journal labels have rectangular hit regions. Focused normal/large-text checks pass, including absent system tabs and at least 44-point button dimensions.
9. **[P2, fixed] Populated protocol heading broke a word at Accessibility XXXL.** The action menu took width from the heading. At accessibility sizes the title and menu now stack, and the title uses a dynamically scaled headline style. The check-in action shortens to “Save,” with the full “Save check-in” accessibility label.
10. **[P2, fixed] Record-actual repeated prescribed quantities.** The docket already supplies a quantity-bearing title; appending a second summary produced “ring row 3×10 3×10.” The sheet now renders that title once, with a UI regression assertion. Protocol review also uses the shared journal button/paper footer instead of an unrelated platform pill/material.

The source and implementation were opened together in the same comparison inputs for Today,
Work, Body, Check-in, Capture, Parse Review, and Record Actual. The first final-source comparison
uses `/tmp/whoops-journal-qa/normalized-final/Journal-*.png` (native density 3 downsampled to
390 × 844, source density 1). It confirms findings 1–7 and reveals findings 8–10 above.
The final post-fix comparison uses `/tmp/whoops-journal-qa/normalized-acceptance/Journal-*.png`,
exported from `whoops-journal-acceptance.xcresult`. All seven source/native pairs were opened
together again at the same normalized dimensions. All ten findings above are resolved; no
remaining P0–P2 visual defect was observed in the tested states.

| Final capture | State and acceptance evidence |
| --- | --- |
| Today, Work, Body | Normal text; real synthetic docket/protocol/restriction data; clear typography and bounded navigation |
| CheckIn, Capture, ParseReview, RecordActual | Native entry flows; readable chips, contrasting capture chrome, paper save footer, single quantity-bearing title |
| Today-LargeText, Work-LargeText, Body-LargeText, CheckIn-LargeText | Accessibility XXXL; stacked headers, whole protocol words, visible Save action, one-line zone navigation |
| LeftHanded, ParseReview-LeftHanded, Settings | Mirrored margin/gear and review insets; Settings remains reachable |
| ReadinessDetails, CheckIn-Notes | Preserved detailed evidence and multiline notes/keyboard interaction |

The normalized captures expose the full typography, card edges, chips, and navigation clearly;
separate focused crops were unnecessary. Original 3× captures and their export manifest remain
under `/tmp/whoops-journal-qa/acceptance/` for closer inspection. Small native sheet safe-area
and scroll-chrome differences are accepted platform adaptations, not redesigned content.

## Required fidelity surfaces

- **Typography — pass:** Literata regular/italic and Caveat are bundled, with SIL Open Font Licenses. Caveat is restricted to the main verdict. Native control labels retain platform behavior. Registration is covered by a passing unit test. Normal and large-text captures have readable, unbroken labels.
- **Spacing/layout:** notebook margin, dot pitch, binding holes, drawn rules, selected-zone outline, and taped cards use shared components. Native safe areas and 44-point touch targets supersede fixed mockup dimensions; long content scrolls.
- **Scale affordance:** longer numerical scales show their full range and a swipe hint because eleven independent 44-point targets cannot fit across a 390-point phone.
- **Colors/tokens:** the mockups' warm paper, blue ink, red pen, amber, and tape colors use the shared journal palette. Light-only mode is deliberate and documented pending separate dark artwork.
- **Assets:** the Body figure reuses the source vector paths; no rasterized screenshot is used as UI. Fonts are local assets, and platform controls use SF Symbols. Paper and pen components remain vector drawing primitives as specified by the repository.
- **Copy/content:** headings, zone labels, notebook tone, and main actions follow the mockups. Clinical countdowns, surgery dates, healing claims, and adherence percentages are not fabricated. Body shows record dates and recorded restrictions; Work shows actual item-completion counts.

## Intentional scope boundaries

- Existing edit/save/cancel/delete, workout results, source settings, experiment logging, weekly review, and exports remain reachable.
- Phase 3 stays complete. This visual migration does not implement phases 4–6 (widgets/notifications, standalone pain logging, PT summaries).
- Body selection uses named accessible controls beside the figure; the decorative figure does not invent injury coordinates.
- Typing remains available for check-in notes; dictation/capture retains the existing protocol workflow.
- Settings and detailed editors use native forms on journal paper, not fixed-height HTML replicas.
- A physical-phone acceptance pass remains necessary for camera, real health permissions, and final user approval.

## Verification checklist

- [x] Full unit suite: 161 passing after the shared visual changes.
- [x] Final physical iPhone target compile without signing or installation: `** BUILD SUCCEEDED **`.
- [x] Focused navigation, handedness, docket/undo, and check-in checks.
- [x] Intake regression and revised accessibility capture.
- [x] Complete unit + UI regression run on the final source: 161 unit and 31 UI tests, zero failures.
- [x] Final density-normalized source/native comparison, including capture/review/actual sheets.
- [x] Final formatting and diff checks.
- [ ] Phone acceptance (user).

**Earlier result (superseded): passed** — native visual implementation, source comparison, and automated
regression are complete. Physical-phone acceptance is the user handoff, not a claimed test result.

## Verification environment note

An initial full regression attempt was interrupted when the Mac's disk filled. A simulator
launch failed with SQLite error 13 (`database or disk is full`), and a physical-target compile
reported `No space left on device`. This was not a migration failure or a memory-pressure kill.
Only this run's disposable QA simulator and temporary build directories were removed; source,
phone data, and pre-existing simulators were untouched. Verification restarted serially with
`-collect-test-diagnostics never` to avoid large failure sysdiagnoses. The simulator destination
was substituted for the CI destination as documented in `CLAUDE.md`.

After final acceptance and screenshot export, the disposable **WHOOPs Journal Visual Final**
simulator was also removed. Its synthetic state is reproducible from the UI tests; exported
screenshots, final result bundles, and build logs were retained. Recreate an isolated simulator
and substitute its destination ID to repeat the command below.

The native verification commands use this isolated simulator rather than modifying the user's
usual simulator or phone. Signing, bundle identity, and the 19-model store are unchanged:

```sh
xcodebuild -project ios/WhoopsApp/WhoopsApp.xcodeproj -scheme WhoopsApp \
  -destination 'platform=iOS Simulator,id=D046FAF0-F6E9-421A-ABD6-DBB5924F2CF3' \
  -derivedDataPath /tmp/whoops-journal-polish -parallel-testing-enabled NO \
  -collect-test-diagnostics never -resultBundlePath /tmp/whoops-journal-acceptance.xcresult \
  CODE_SIGNING_ALLOWED=NO test

xcodebuild -project ios/WhoopsApp/WhoopsApp.xcodeproj -scheme WhoopsApp \
  -destination 'generic/platform=iOS' -derivedDataPath /tmp/whoops-journal-device-verified \
  CODE_SIGNING_ALLOWED=NO build

xcrun swift-format lint --recursive ios/WhoopsApp
plutil -lint ios/WhoopsApp/WhoopsApp/Resources/Info.plist \
  ios/WhoopsApp/WhoopsApp.xcodeproj/project.pbxproj
git diff --check
```

The first device compile ended with `** BUILD SUCCEEDED **`. Swift formatting and diff checks
emitted no errors; both property-list checks reported `OK`.

The complete first regression run reported `Executed 161 tests, with 0 failures` and
`Executed 31 tests, with 2 failures`. Both failures were test targeting issues: `LabeledContent`
exposes “Confidence, Low” as a combined label; the notes test tapped the pinned save area because
an obscured field was reported hittable. Matching the combined label and scrolling notes fully
above the save action fixed both. The focused rerun (`whoops-journal-controls.xcresult`) reported
`Executed 2 tests, with 0 failures`. The keyboard assertion still covers multiline entry, Done,
scroll dismissal, background/foreground, and Cancel; no assertion was removed.

After the navigation correction, `whoops-journal-navigation.xcresult` reported
`Executed 161 tests, with 0 failures` and `Executed 2 tests, with 0 failures`. The subsequent
whole-suite run on the final polish, `whoops-journal-acceptance.xcresult`, reported
`Executed 161 tests, with 0 failures`, `Executed 31 tests, with 0 failures`, and
`** TEST SUCCEEDED **` on August 31. The final phone compile log,
`/tmp/whoops-journal-device-acceptance.log`, ends with `** BUILD SUCCEEDED **`.

Coverage grew from 160 to 161 unit tests and from 27 to 31 UI tests. No test was deleted.
`testFourTabShellIsVisible` was renamed to `testThreeJournalZonesAndSettingsGearAreVisible`
because the specified navigation is now three zones plus a gear. Existing workout, parsing,
keyboard, experiment, and weekly-review tests were updated to navigate through the new shell.

## September 1 restriction discoverability and selection-state regression

### Visual truth and comparison

- **Source visual truth:** the approved focused body-area concept at
  `/Users/robertdawson/.codex/generated_images/01a045b1-b161-7552-a3a7-7a83c02dd1b4/exec-e2e0c789-c190-4ef9-9dcb-31902c3cbed0.png`.
- **Reported regression:** the September 1 phone screenshots showed a selected right posterior
  upper-arm area while Torso was visually painted as selected, its rows remained unchecked, and
  the confirmation button correctly reported one selected area.
- **Final implementation evidence:**
  `/tmp/whoops-body-final-attachments.PvXlfc/3442E731-C41A-4A73-BEBF-F507BDFC69F7.png`.
- **Same-image comparison:** `/tmp/whoops-body-selection-sep1-comparison.png` places the approved
  source and final native implementation side by side. The source is arm-focused while the native
  regression capture is deliberately Torso-focused; this difference proves focus navigation no
  longer mutates or paints selection state.
- **Viewport and density:** iPhone 17 Pro simulator, portrait. The full figure, focus title,
  detailed rows, selected-area chip, and confirmation button are legible in the full comparison,
  so a separate crop is unnecessary.

### Resolved findings

- **P1 — resolved:** transient focus was rendered with selection styling. Every figure highlight,
  row checkmark, chip, count, and confirmation label now derives from the same selected-ID set.
- **P1 — resolved:** Restrictions had no first-class Settings entry. Settings now begins with a
  labeled Body & restrictions section and a Restrictions route.
- **P2 — resolved:** the five-record selector looked like an incomplete anatomy menu. It is now
  labeled Choose restriction; the full anatomy catalog remains in Edit affected areas and List.
- **P2 — resolved:** restriction-to-injury matching used editable names. The Body story now follows
  the stable `injury:<restriction-id>` relationship.
- **P2 — resolved:** overlapping torso/leg hip, groin, and glute IDs could duplicate semantic
  selections. Those areas now have one canonical torso/pelvis identity.
- **P3 — accepted scope:** the 126-choice catalog is a practical external musculoskeletal
  localization system, not an exhaustive clinical ontology of organs, muscles, or bones.

### Required fidelity surfaces

- **Typography — pass:** journal type, hierarchy, and link treatment match the approved native
  visual system.
- **Spacing/layout — pass:** full-body and focused screens scroll, retain one-handed large targets,
  and keep the fixed confirmation action reachable.
- **Colors/tokens — pass:** only actual selected areas receive the amber selection treatment.
- **Image quality — pass:** the existing source anatomy artwork is reused and zoomed rather than
  replaced with a placeholder or approximate drawing.
- **Copy/content — pass:** Choose restriction describes saved records; Edit affected areas and List
  describe anatomical choices; the confirmation count is grammatically and numerically correct.
- **Interaction/accessibility — pass:** broad figure targets do not overlap, figure and row controls
  expose Selected or Not selected values, full-region and detailed selections are exclusive, and
  selected areas persist after save and reopen.

### Verification

- [x] Focused unit coverage for catalog breadth, stable IDs, persistence, and invalid payloads.
- [x] Focused UI coverage for Settings discoverability and the one-arm/Torso regression.
- [x] Full unit suite: 171 tests, zero failures.
- [x] Full UI suite: 35 tests, zero failures.
- [x] Unsigned physical-iPhone target: `** BUILD SUCCEEDED **`.
- [x] Store-upgrade verification from `0f65324`, `d39a519`, and `4824786`: all persisted fields,
  including nils, survived.
- [x] Swift formatting, property-list validation, test build, and repository diff checks.
- [x] Physical-phone acceptance (Robert, September 1, 2026).

final result: passed
