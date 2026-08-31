# Branch integration and Xcode updates

## Why switching to main failed

On August 30, 2026, the two development lines had diverged after `83c4d6c`:

- `main` at `4824786` contained the design specification, PT protocol capture/review,
  recurrence, and daily docket (redesign phases 1–2).
- `codex/milestone-6-experiments` at `01b70dd` contained the Personal Experiment Lab,
  production WHOOP endpoint, bounded/serialized HealthKit import, source controls,
  sleep/readiness corrections, and the tested workout parser/editor improvements.

Main compiled for an unsigned iPhone destination, but a normally signed build failed because
its app target had no development team. Switching branches also removed the newer app/data
behavior; cleaning build caches alone could not combine the two histories.

## Integration boundaries

The integration retains both histories and both feature sets. Xcode project object IDs that
collided between branches are made distinct, and source/test target membership is checked
against the union of both parents. The app uses the existing development team, bundle ID,
production backend default, and one container containing all 19 SwiftData record types.

No app deletion, store reset, HealthKit anchor reset, credential change, or backend redeploy
is part of this integration. Experimental Apple workout parsing stays unavailable in normal
phone runs. The four-tab navigation remains; later redesign phases are not included.

The protocol-to-workout restriction bridge converts protocol whole-second durations into the
workout model's precise duration type. Opening protocol capture clears the underlying workout
keyboard focus. The docket has its own accessibility container so its identifier does not
overwrite identifiers on individual completion and undo controls.

## Verification

`TASKS.md` records the final simulator unit/UI results and signed-build checkpoint.

To reproduce the synthetic store upgrade checks on an Apple Silicon Mac with Xcode and Node:

```sh
node scripts/verify-store-upgrades.mjs
```

The script derives model/property declarations from `4824786`, `01b70dd`, and the working tree.
For each parent it writes two synthetic records per entity (populated and nil optional fields),
then opens that store with the combined schema in a separate process. It checks retained values,
nil initialization of new optional columns, and insertion into newly added entities. Generated
sources, executables, and SQLite stores remain in the printed temporary directory, never in
the repository or phone data container. Unsupported schema declarations fail explicitly.

This is a macOS SwiftData storage-compatibility check, not a copy of real health history or proof
of every iOS migration scenario. Parser/repository tests cover application-level decoding and
edits, while UI tests cover interaction. Physical-device acceptance remains separate.

## Update the existing phone app

1. Use the integrated `main` checkout and open `ios/WhoopsApp/WhoopsApp.xcodeproj`.
2. Select the **WhoopsApp** scheme and the connected iPhone as the run destination.
3. In the app target's **Signing & Capabilities**, keep automatic signing and the existing
   development team. Do not change the bundle identifier.
4. Build/run with **Command-R**. Update the installed app; do not delete it first.
5. Confirm existing workouts, experiment days, WHOOP connection, and Apple Health source
   selections remain. Open Today and Train, try protocol paste/review, and verify docket
   completion/undo. Then synchronize Apple Health once and confirm the app stays responsive.

If Xcode still fails, provide the first red error in the Issue navigator. A build-folder clean
may help a stale build graph, but do not clear app data or disconnect services as a workaround.
Background HealthKit observer acceptance still requires a real new sample on the phone.
