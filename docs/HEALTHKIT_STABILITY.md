# HealthKit startup stability

## Evidence and limits

An August 30, 2026 iOS 26.5 simulator launch ended with `EXC_BAD_ACCESS` while HealthKit formatted
an anchored query's date predicate. The crash report contains many simultaneous
`HKAnchoredObjectQuery.activation` stacks entered through `HealthKitClient.anchoredChanges`.
The workout editor had not opened. Ten baseline launch repeats passed, so the framework crash
itself was not reliably reproducible.

Synthetic tests did reliably reproduce three application defects before the fix:

| Boundary | Before fix | Required behavior |
| --- | --- | --- |
| Eight concurrent refreshes | Eight active reads; all reused the first metric's nil anchor | One active query; each import reads the preceding committed anchor |
| Two observer starts while registration is suspended | 28 queries registered for 14 types | One set of 14 observers |
| Metric-inclusion notification | Delivered on a background thread | UI notifications delivered on the main actor |

These are confirmed application races. Fixing them removes the parallel-query activation pattern
seen in the crash; it does not establish a root cause inside Apple's formatter or prove that an
OS/framework crash can never recur. No health payloads or raw crash reports are committed here.

## Implementation

- `LiveHealthKitRepository` uses a cancellation-aware FIFO import permit. The permit covers reading
  the anchor, every query page, applying the page, and committing the next anchor. Manual refreshes
  and observer callbacks use this same path. Only one anchored query is active per repository.
- The permit suspends tasks instead of blocking a thread. History reads and source controls do not
  acquire it, so waiting for HealthKit does not lock the UI or cached history out of the repository.
- A queued cancellation removes that waiter promptly. An active query is allowed to settle before
  the permit is released; a cancelled caller does not commit the returned batch or continue to
  another metric. Failure and cancellation both release the permit. Partial non-cancellation
  failures still allow other available metrics to import.
- `HealthKitClient` claims observer registration under its lock before the first suspension point.
  Each callback invokes its HealthKit completion handler when its queued synchronization returns.
- Metric-inclusion changes invalidate history on the repository actor, then publish their
  notification on `MainActor` for SwiftUI subscribers.

An actor alone does not preserve invariants across an `await`; see
[Apple's actor reentrancy guidance](https://developer.apple.com/videos/play/wwdc2021/10133/).
HealthKit invokes query handlers asynchronously on background queues; see
[HKHealthStore.execute](https://developer.apple.com/documentation/healthkit/hkhealthstore/execute(_:)).

## Data safety

Read authorization, source selections, the 180-day window, 500-sample pages, and source precedence
are unchanged. No store reset, anchor reset, permission change, HealthKit write, or destructive
migration is needed. Persisted anchors still advance only after their corresponding data saves.

## Verification and phone acceptance

Regression coverage includes parallel refreshes, observer/manual overlap, observer-start
idempotence, failure recovery, queued and active cancellation, anchor progression, main-thread
notification delivery, and history responsiveness while a query is suspended. The final verification
passed 125 unit tests, all 20 UI tests, and 20 repeated simulator launches. `TASKS.md` records the
result bundles and supporting parser, backend, build, and formatting checks. Passing launches do
not replace physical-device acceptance or prove the intermittent framework fault cannot recur.

After updating from Xcode, keep the existing app and Health connection. Close and relaunch the app
a few times, open Today and Train, then use Settings to synchronize Apple Health once. Confirm it
stays responsive and existing history/source selections remain intact. If a crash recurs, capture
its time and Xcode crash report; do not delete the app or its data to work around it.
