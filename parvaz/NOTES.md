# Parvaz rewrite: notes

`../parvaz.sumspec` is the Parvaz Agro app in the old notation, domain and
UI in one file. It is being rewritten as layered specs:

- `parvaz-core.sumspec`: the domain, a base spec. Done; it checks clean.
- `parvaz-ui.sumspec`: the screens, a layer over the core. Done; it
  checks clean.

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

## The UI layer

`parvaz-ui.sumspec` holds only what the screens add: the page, the map
(at `App` level, so it opens where it was left), the plot being drawn,
the forms, the selections and how things are shown. It reads the core
through `core.Core` in sources and guards, changes it only with `>>`, and
follows its occurrences with reactions.

| Old | New |
|---|---|
| `ui { App = Page * AircraftLink * Devices * ... }` | `App = Page * Map * core.Core`; the domain parts are the core's |
| `@from` views (HomeAircraft, LinkStatus, DeviceRow, MissionSummary, MissionRun_, Aircraft_, AircraftPose, HomeMarker, ...) | projections, `__from`: LinkStatus, HomeAircraft, DeviceRows, MissionRows, LogList, RunPanel, AircraftPanel and the ones nested in them |
| `@when` on a view of a sum (HomeAircraft while connected) | a sum projection: its `Disconnected` variant draws nothing |
| `@edits RouteSettings` on `PlotController.Route` | one setter per field (`setRouteSpacing`, ..., `setCourse`), `RouteForm -> Setting(v)`; `@view form`, `@overflow scroll` on `Route` |
| `@control` on a type (`Zoom`, `LogLevelFilter`, `LinkKind`, `Battery_`, the form fields) | a transition carrying the control (`zoomMap`, `setLogLevel`, `setLinkKind`, `switchBatteryFigure`, `setDeviceName`, ...) |
| `@unless` | guards, mostly through the patterns `Armed`, `Connected(x)` and the core's `core.ReadyToFly` |
| `PMode.Plot = PlotOrigin * Plot * ...` | `PlotEditor = PlotOrigin * core.Plot * ...`, the draft beside its origin; `Editing` holds the mission's `At` |
| `PMode.ShowMission.Selected = MissionName * ... * RouteSummary` | `MissionPanel.Selected(core.At)`: the selection only; what it shows is that mission's row |
| `PMode.MissionRun = MissionRun * MissionRun_ * ...` | `RunView = RunPanel * AircraftPanel * AircraftCanvas * BatteryFigure`; the run is the core's |
| a UI transition writing domain state (`savePlot`, `startMission`, `saveDevice`, ...) | the UI event, same name, firing the core's (`>> core.addMission(...)`); a new mission's or device's key is the time now, the event's input |
| an occurrence changing the view (`landedEvent`, `gpsLostEvent`, ...) | a reaction, `core.landedEvent :: Running(core.At#at) -> Selected(at)` |
| `@announce` on an occurrence | on the UI's reaction to it (`core.routeReachedEvent :: App -> App @announce`) |
| `pointDelete` ×3 | one transition writing `core.Plot'` and `ShapeSelection'`; the three outcomes in its comment, since the spec can't tell a shape's last point |
| `(1/4)*screen` in `@size` | `(1/4*screen)`: an annotation's arguments end at a `*` outside brackets |

Patterns (`__pattern`) in the UI: `InPlan(m)`, `RouteForm`, `Setting(v)`,
`Connected(x)`, `Armed` (from the core's `core.Armed`), `Running(x)`,
`Selected(at)`, `Form(x)`, `DeviceList`; it uses the core's
`core.ReadyToFly` as it is. Shared paths (`__path`): `Editor` (the plot
transitions'), `DeviceEditor`, `AcCan`.

## Open points

- **What a projection can't show yet.** A projection's path has no key,
  so the mission the UI selected, or the one the run flies, is described
  as "that mission's row of MissionRows", in comments. Values the old
  spec computed (RouteSummary's RouteLength, SprayLength, EstimatedTime,
  Passes) and the log through its filters aren't projections either.
- **Presentation on core types.** `@status`, `@view tiles` and `@region`
  sit on core types (StopReason, Feed, MissionFlight, GroundMeasurements,
  Plot's Drawn, BreakPoint). They belong in the UI: with `__from`, the UI
  declares projections of those parts and annotates them, and the core
  can drop them.
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
