# Parvaz rewrite: notes

`../parvaz.sumspec` is the Parvaz Agro app in the old notation, domain and
UI in one file. It is being rewritten as layered specs:

- `parvaz-core.sumspec`: the domain, a base spec. Done; it checks clean.
- `parvaz-ui.sumspec`: the screens, a layer over the core. Next.

## Old notation to new

| Old | New |
|---|---|
| `__txs { }` | `__events { }` |
| `__state_scopes`, `domain { }`, `ui { }` | two files: the core and the UI layer |
| `Plot.Drawn = Boundary * ...` (variant refinement) | an inline payload: `Drawn (Boundary * Markings * RouteSettings)` |
| `[Point]` in a payload | a list type, `Points = [Point]` |
| `Missions = [Mission]`, `Missions(Mission')` | `Missions = [Mission by At]`, `Missions[at](...)` |
| `Devices = [Device]` | `Devices = [Device by DeviceId]` |
| `MissionRun = Mission * MissionFlight` (a working copy written back) | `MissionRun = At * MissionFlight`; the mission stays in `Missions` |
| a run inside `PMode.MissionRun` | `Run = Idle \| Active (MissionRun)` in the core |
| `Bool` | a sum named for its meaning (`SingleSideSpraying = Off \| On`) |
| atomics without bases | bases: `Int = __int`, `Meters = __float`, `Text = __text`, ... |
| `CourseAngle_` (the form's choice) | `Course = Auto (CourseAngle) \| Manual (CourseAngle)` in RouteSettings |
| `BatteryLowThreshold = Percent @default 15` | a constant, `BatteryLowThreshold = Percent(15)` |
| `Telemetry @from Aircraft = AircraftStatus` | the input is `AircraftStatus` |
| `... <-` (both sides the same) | written out: `Feed.Live -> Feed.Live(LinkQuality') ...` |
| `X => Y => ...` (chained shared paths) | `X / Y => ...` |
| `@unless` on domain transitions | source patterns and guards (a run needs a connected, disarmed aircraft, 3D fix or better, battery Enough, live feed) |
| `flownAwayEvent FlownAway` | two occurrences: `flownAwayDoneEvent At`, `flownAwayToEvent FlownTo(At * Point)` |

## Where each old transition went

Core, as commands the UI will dispatch:

- `savePlot` (Draft) → `core.addMission(at * name * plot)`; (Editing) →
  `core.updatePlot(at * name * plot)`.
- `startMission`, `resumeMission` (landed) → `core.startMission(at)`,
  `core.resumeMission(at)` with the selected mission's At. In flight,
  `resumeMission` from Holding is a core transition of the same event.
- `copyMission`, `deleteMission` → `core.copyMission(...)`,
  `core.deleteMission(at)`.
- `stopMission`, `returnToHome`, `retryArming`, `cancelArming` → the same
  core events.
- `saveDevice`, `removeDevice`, `selectDevice`, `closeLink` → the same core
  events. `reconnect` → `core.selectDevice(id)` with LastDevice's id.

Core occurrences (the UI reacts to the ones that change its view):

- `armedEvent`: outside a run the core changes nothing; the UI opens
  ManualAircraft from JustMap (old `armedEvent :: PMode.JustMap -> PMode.ManualAircraft`).
- `cancelArming`, `landedEvent`, `homeReachedEvent`, `linkLossEvent` (in a
  run): the UI goes back to `ShowMission.Selected`.
- `manualControlTakenEvent` and `gpsLostEvent` ending a run: the UI goes to
  ManualAircraft.
- `linkLossEvent` in ManualAircraft: the UI goes back to JustMap.
- Stays as it was: `armingFailedEvent`, `routeReachedEvent`,
  `groundMeasuredEvent`, `missionCompletedEvent`, `autoRestoredEvent`,
  `batteryLowEvent`, `aircraftConnectedEvent`, `linkFailedEvent`,
  `homeSetEvent`, `telemetry*Event`.

UI only (the next step): navigation (`goTo*`, `*BackToHome`, `showAbout`,
`closeAbout`), `exportLogs`, the map (`retryMap`, `map*Event`, `locateMe`,
`location*Event`), plot drawing (`newPlot`, `point*`, `shape*`,
`setPointType`, `setPlotController`, `startCorner*`, `edgeMargin*`,
`edgeSelect`, `cancelPlot`), the mission list (`showMission`,
`selectMission`, `backToList`, `closeMissionList`, `editSelectedMission`),
devices (`addDevice`, `editDevice`, `cancelDevice`), the camera and map
follow (`maximizeCamera`, ..., `panMap`, `recenterMap`), ManualAircraft
(`watchAircraft`, `leaveManualAircraft`).

`@announce` (an occurrence the UI must state) goes on the UI's reactions;
`@stream` stays on the core's two streaming occurrences.

## For the UI step

The UI writes its long, repeated paths as `__pattern`s (see "Named
patterns" in `spec/spec-v1.md`). The core already uses three:
`ReadyToFly` (connected, Disarmed, a fix of 3D or better, BatteryReserve
Enough, a live feed: `startMission`, `resumeMission` and `retryArming`,
which now needs a live feed too), `InFlight(phase)` and
`SprayingRun(at)`. A base's patterns aren't visible to a layer, so the UI
writes its own. The paths below are sketches; the UI's layout decides
them.

- The connected aircraft, for the old `@unless
  App(AircraftLink.Connected(Aircraft(...)))` conditions (armed, fix,
  battery, stale feed):
  `__pattern Connected(x) = App(core.Core(core.AircraftLink.Connected(x)))`,
  used in guards: `// not Connected(core.AircraftStatus(core.ArmState.Armed))`.
- The active run:
  `__pattern Running(x) = App(core.Core(core.Run.Active(x)))`.
- The selected mission, with `at` from the UI's selection:
  `__pattern Selected(at, x) = App(core.Core(core.Missions[at](x)))`.
- The Route form. Its setters replace the old `@edits RouteSettings`:
  one event per field, each with its own `@control`:

  ```
  __pattern RouteForm  = App(Plan(PlotEditor(PlotController.Route * core.Plot.Drawn)))
  __pattern Setting(v) = App(Plan(PlotEditor(core.Plot.Drawn(core.RouteSettings(v)))))

  setRouteSpacing core.RouteSpacing#v :: RouteForm -> Setting(v)  @control stepper  @step 0.5
  setSprayHeight  core.SprayHeight#v  :: RouteForm -> Setting(v)  @control stepper  @step 0.5
  ...
  ```

  The plot sits beside the origin (`PlotEditor(PlotOrigin * core.Plot *
  PlotController)`), as the old `PMode.Plot(PlotOrigin.Draft * Plot.Empty)`
  had it, not inside `Draft`/`Editing`: one `Setting` then covers both
  origins, since a target can't use alternatives. The form's own
  presentation, `@view form` and `@overflow scroll`, goes on the UI's
  `PlotController`'s `Route` variant, with its `@size`.

## Open points

- **Presentation on core types.** `@status`, `@view tiles` and `@region`
  sit on core types (StopReason, Feed, MissionFlight, GroundMeasurements,
  Plot's Drawn, BreakPoint), because a layer can't annotate a base's types
  yet. They belong in the UI.
- **Values the core can't name.** Stopping marks a BreakPoint at the
  aircraft's position, but no event brings the position, so the
  BreakPoint is any value (as in the old spec). The same for the figures
  `groundMeasuredEvent` computes.
- **Coarse writes.** `addMission`, `copyMission`, `removeDevice`, the new
  device of `saveDevice` and `logged` write the whole list (`Missions'`),
  as the old spec did: a target can't add or remove one element yet.
- **Checker.** The overlap check doesn't read `f == V` / `f != V` on a sum
  with payloads, which is why `flownAwayEvent` became two events. Worth
  extending.
