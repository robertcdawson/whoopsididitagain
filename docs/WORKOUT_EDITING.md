# Workout editing

## Entry points

In Train, open a planned or completed workout and tap **Edit**. Planned cards also retain their
Edit button. Saving a completion updates the same workout and movement identities; it never
recreates actual values from the plan. Cancel discards the draft. Edits stay local.

## Field audit

| Record | Editable fields and controls |
| --- | --- |
| Planned session | Title, scheduled date/time, format, time cap, primary stimulus, targets/context, estimated minimum/maximum duration |
| Planned score | Add, change, or remove completed rounds and additional reps; independently correct/reset movement totals |
| Planned segments | Type, rounds, work/rest duration, recovery, notes, order; add/remove segments |
| Prescribed movements | Name, movement mapping, original wording, reps, distance, calories, load/unit, percent of 1RM, duration, tempo, notes; add, duplicate, remove, reorder |
| Completed session | Title, start date/time, end date/time, duration, session RPE, post-session pain, session notes |
| Completed score | Add, change, or remove rounds and additional reps without replacing actual movement totals |
| Actual movements | Name, mapping, reps, distance, calories, load/unit, duration, modification, pain during, notes; add, duplicate, remove, reorder |
| System-managed information | Record IDs, links to the original plan/prescription, parser versions/confidence/timestamps/diagnostics, original pasted-source snapshot, and calculated restriction evaluations |

The source snapshot and parser diagnostics retain what was originally submitted and inferred.
Correct the structured workout fields; editing a result does not rewrite source provenance,
the original prescription, WHOOP records, or Apple Health samples. Restriction evaluations are
recomputed from edited prescriptions rather than edited directly. Completion status follows actual
logging/deletion rather than an independent text field.

## Timing and quantities

- Moving the start date/time preserves elapsed duration and moves the end, including across midnight.
- Editing the end updates duration. The end picker cannot select a time before the start.
- Editing duration keeps the start fixed and moves the end. Save requires a positive duration.
- Duration input and display use minutes with up to two decimal places; stored fractional seconds
  are not rounded just by opening a field. Estimated duration ranges also accept decimal minutes
  and remain compatible with older integer-valued JSON.
- Session RPE is 1–10. Session and movement pain are 0–10. Actual quantities allow zero or blank;
  blank remains unknown and is not regenerated from the plan on subsequent edits.
- Load and percentage fields preserve in-progress decimal entry and use the local decimal separator.
- Targets/context retain spaces and line breaks while typing; nonempty lines become separate targets.
- Score changes never silently overwrite independently recorded actual movement totals.
- Removing an actual movement or score requires confirmation and affects only the draft until Save.
- Converting a work segment to rest requires confirmation before clearing incompatible work data.

## Persistence and verification

Completed edits validate before modifying existing rows. Upsert retains the workout ID and existing
movement IDs, preserves order, removes only deleted child rows, and rejects cross-workout ID reuse.
New/duplicated movements get independent IDs. Trend and experiment reads use the corrected records
on their next load. No storage reset or destructive migration is needed.

Regression coverage includes field round-trips, optional clearing, timing/date changes, duplicate
prevention, plan/actual separation, invalid-edit isolation, decimal/legacy estimates, and UI
save/cancel/reopen flows. See `TASKS.md` for the latest validation and physical-device acceptance.
