# SumSpec: proposed features

Gaps found while auditing the Parvaz specs against `sumspec-spec-v1.md` (2026-11). Each
names the problem it solves, a sketch of the syntax, and what the checker would gain.
Ordered by value to the Parvaz specs.

## 1. Keyed projections

**Problem.** A `__from` path has no element key, so a view of "the selected mission" or
"the run's mission" can't be projected. Today the workaround is to project the whole keyed
list and let a sibling `core.At` pick the element, which the checker can't verify.

**Sketch.** An element step in a `__from` path takes its key from the factor of the key's
type beside the projection. Products are keyed by type, so there is at most one:

```
MissionPanel = List MissionRows | Selected (core.At * SelectedMission)
SelectedMission __from core.Core / core.Missions[core.At]   -- key: the sibling core.At
```

A key read from base state (the run's mission) would need a path into a variant:
`core.Missions[core.Run.Active / core.At]`.

**Checker gains.** It knows which element is shown, checks the shown fields against it, and
can warn when the key's type doesn't match the list's.

## 2. Computed values

**Problem.** Values worked out from state (RouteSummary from a Plot, the log through its
filters, BatteryReserve from BatteryCharge) are neither projections, which don't compute,
nor written state. Today they live in comments or ad-hoc annotations.

**Sketch.**

```
RouteSummary __computed from core.Plot
  = RouteLength * SprayLength * EstimatedTime * Passes
```

**Checker gains.** It treats them like projections: no target writes them, a new state
leaves them out, their variants count as reached. Their value stays opaque.

## 3. A sum narrowed to some variants, as a type

**Problem.** The old spec wrote `StopReason(Commanded | BatteryLow)` as a payload; the
rewrite needed a separate `ReturnReason` sum, a second type for the same values.

**Sketch.** Reuse the alternatives syntax as a type:

```
| Interrupted (StopReason.{Commanded | BatteryLow} * RouteEntry)
```

A value is a `StopReason`: it compares with one and maps to one target type.

**Checker gains.** A target writing another variant there is an error.

## 4. Annotation arguments the checker reads

**Problem.** Annotation arguments are free text, so `@when` paths broke silently (missing
`core.`, unclear where they are read from).

**Sketch.** `__annotations` declares an argument's kind:

```
__annotations {
  @when <pattern>     -- read where the annotation sits
  @step <number>
}
```

**Checker gains.** It resolves `<pattern>` arguments like guards and reports typos and
unknown variants.

## 5. Blocked-with-a-reason guards

**Problem.** The old `@unless` meant "shown, disabled, with a reason"; a guard removes the
transition instead. Kotlin's Offered / Blocked(reason) / Absent split has no source in the
spec.

**Sketch.** A second guard kind: the transition doesn't apply, but its control is drawn
disabled with the named reason:

```
leaveManualAircraft
  :: InPlan(PlanPage.ManualAircraft) //? not Armed : AircraftArmed
  -> InPlan(PlanPage.JustMap)
```

**Checker gains.** Reasons are listed and checked; overlap and dispatch rules read it as a
guard.

## 6. List literals and element insert/delete

**Problem.** There is no empty-list value (the log page can't write `LogTagFilter` empty),
and a target can't add or remove one element, so `addMission`, `copyMission`,
`removeDevice` and `logged` write the whole list (`Missions'`).

**Sketch.**

```
goToLogs :: Page.Home -> Page.Logs(LogLevelFilter.All * LogTagFilter([]))
addMission NewMission(At#at * MissionName#n * Plot#p)
  :: Missions // not Missions[at] -> +Missions[at](n * p)
deleteMission At#at :: Missions[at] -> -Missions[at]
```

**Checker gains.** It knows which element appears or goes; `not Missions[at]` after a
`+Missions[at]` is a provable contradiction.

## 7. Defaults in the language

**Problem.** `@default` is free text, so a part left out of a new state may take any value,
which blinds the reachability check. Writing every part out (as the UI spec now does)
works but is verbose.

**Sketch.** A type may declare a default; a new state that leaves out a part of such a type
fills it from the default. A left-out part whose type has no default is a warning, not
"any value":

```
Undo = Ready | Empty  __default Empty
FPhase = ...          -- no default, on purpose: every transition names the phase
```

**Costs to weigh.** A transition alone no longer shows the resulting state; "left out" in a
target means keep, default or any; entries that must not take the default (a run's camera
carried into ManualAircraft) must be remembered. Patterns like `NewEditor` stay useful where
the starting state should be visible in place.

**Checker gains.** New states are fully determined, so reachability gets more precise, and
forgotten parts are reported.
