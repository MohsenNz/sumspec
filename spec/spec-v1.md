# SumSpec

This document defines SumSpec **1.0**.

## Comments

A comment starts with `--` and runs to the end of the line. It can go anywhere whitespace can, on its own line or after code:

```
-- Where the user is in the app
Page
  = Home
  | Plan    (PMode * Missions)  -- planning a mission
  | Devices
```

## Types

In SumSpec we express state with type, so a type here is equivalent to a state in state-machine.

### Product Type

```
T = A * B
```

This is a type named T that is a product of A and B.

### Sum Type

```
Y = V1 | V2
```

The type Y has two variants V1 and V2. Each variant can carry one optional Type too.

```
Y = V1
  | V2
  | V3 A
```

Now Y is a sum of V1, V2 and `V3 A`.

## State Transitions

```
t :: A -> B
```

This is a transition of the event `t`: when `t` happens, the app moves from state A (Type A) to state B (Type B).

We show a state (in a transition) like this:

```
trans1 :: Y.V1 -> Y.V3(A)

Z = Y * C

trans2 :: Z(Y.V1 * C) -> Z(Y.V2 * C)
```

The transition of trans1 changes state Y.V1 to Y.V3(A). We show the state of product types with parenthesis: `Z(...)`, and refer to sum types with dot `Y.V1`. The State of a variant with a value is shown like a product type, `Y.V3(A)`.

**More Examples:**

```
T2 = A
   | B (X * Y * Z)
   | C

trans3 :: T2.A -> T2.B(X * Y * Z)
```

**Note**: types are uppercase and events are lowercase

### Transition parts:

In transition `trans3 :: T2.A -> T2.B(X * Y * Z)` we call each part like this:

```haskell
trans3
-- ↑ event name
  :: T2.A
  -- ↑ source; state pattern
  -> T2.B(X * Y * Z)
  -- ↑ target     ↑ argument
```

**Event:** the name before `::`, something that happens to the app: a user's action or an occurrence in the outside world. An event may have several transitions; see "Several transitions for one event".

**Source:** the left side of ->, the state the app must be in for the transition to apply (a precondition).

**Target:** the right side of ->, the state the app is in after the transition.

**State pattern:** a description of a set of states, such as Page.Plan(PMode.JustMap), written on either side of a transition (and in its input).

**Argument:** a pattern inside the parentheses after a type or variant, saying which inner state must be there.

## Quick Start Example

```
__atomics {
  A
  B
  C
}

__events {
  trans1
  trans2
}

-- The app starts with Y at V1; C may have any value.
__init :: Z(Y.V1)

Z = Y * C

Y = V1
  | V2
  | V3 A

trans1 :: Y.V1 -> Y.V3(A)

trans2 :: Z(Y.V1 * C) -> Z(Y.V2 * C)
```

The root is `Z`. In `example/drone.sumspec`, the app starts on the home page:

```
__init :: App(Page.Home)
```


## Types, more

### Products are keyed by type

A product's components are identified by their type names, so a type appears at most once in a product (that's why `T = A * A` is invalid).

The order of components doesn't matter, so these are the same state:

```
Z(Y.V1 * C)
Z(C * Y.V1)
```

### NewType

`T = A` defines a newtype: `T` has the same structure as `A` but is a different type, never equal to `A`. So the following is valid:

```
At = Timestamp
T  = At * Timestamp
```

Loop is not allowed (`A = B`, `B = A` is invalid).

### Primitive types

`__int`, `__float` and `__text` are the built-in base types: a whole number, a number that may have a fractional part, and a piece of text. A type gets one as its base in `__atomics`:

```
__atomics {
  Timestamp         -- opaque: each target supplies it
  Port  = __int
  Ratio = __float
  Name  = __text
}
```

- Each atomic is its own type: `Port = __int` and `Count = __int` are different types.
- A primitive says what kind of value a type holds.
- A bare atomic (`Timestamp`) has no base: the notation does not decompose it, and each target supplies it.

### Inline payloads and paths

A variant's payload may be an inline product or an inline sum, nested to any depth:

```
PMode
  = JustMap
  | Plot        (PlotOrigin * Plot)
  | ShowMission
      ( List
          ( Empty
          | NonEmpty MissionSummaries
          )
      | Selected Mission
      )
```

A path selects nested variants with dots: `PMode.ShowMission.List.Empty`.

A list isn't inline: it has a type name (`MissionSummaries = [MissionSummary]`); see "List".

## Naming

Types and variants are uppercase; events are lowercase.

Name an event for what happens:

- A command, something the user or another system asks for, is an imperative verb: `toggleTodo`, `startTyping`, `commit`.
- An occurrence, something that happened to the app, is in the past tense: `linkLost`, `uploadFinished`.

`Event` suffix is optional for occurrences, it's up to you to use it: `linkLossEvent`

This is a convention; the type checker doesn't check it.

Each sum has its own variant namespace. `Ring.Partial` and `Path.Partial` are different variants, and a variant may share a type's name (`PMode.Plot` is a variant, `Plot` is a type). Variant names are unique within one sum. Names inside a payload always refer to types:
in `| Plot (PlotOrigin * Plot)`, the second `Plot` is the type `Plot`.

## Transitions, more

### Sum without a variant

In a state pattern, a sum written without choosing a variant stands for any of its variants:

```haskell
showMission :: Page.Plan(PMode.JustMap * Missions)
            -> Page.Plan(PMode.ShowMission.List * Missions)
```

Here the target is `List.Empty` or `List.NonEmpty(...)`: `List` is a new state (see "Source and target"), so either variant is possible.

### Alternatives

A source that applies to some variants of a sum, but not all, names them between `.{` and `}`, separated by `|`:

```haskell
-- The same as two transitions, from Flight.Arming and from Flight.Flying.
flightFailed FailureReason#r :: Flight.{Arming | Flying} -> Flight.Failed(r)
```

`S.{A | B}` means `S.A` or `S.B`, as `S.A` picks one variant. Each alternative is written from `S`, may take arguments, and may hold more alternatives, for a named payload or an inline one:

```haskell
MissionFlight.{Arming | Failed
  | Flying(FPhase.{Approaching | Holding | Returning | PilotControl})}

Flight.Landed.{Spot | Field}
```

- There are at least two alternatives, each written once: `Page.{Home}` is an error; write `Page.Home`. Only alternatives go between `.{` and `}`: a factor beside them goes outside (`Page.{Home | Logs} * Link.On`).
- Alternatives go only in a source and in a pattern in a guard. A target sets one state, and an input and `__init` are one value, so they have none.
- A source with alternatives is one transition per alternative, with the same target; with alternatives in two parts, one per combination. Each is checked on its own: the target must fit every alternative, and a part keeps its value only where every alternative fixes its path. Alternatives of one group pick different variants, so they don't overlap each other.
- In a guard, `S.{A | B}` means `S.A or S.B`.
- An alternative binds no value: the other alternatives don't have it. `Mode.{Edit(#t) | View}` is an error; write a transition for each.
- Alternatives pick variants only; a literal such as `Count(0)` has none.

### Arguments in state patterns

In a state pattern, the arguments are what goes inside the parentheses after a type or variant.
They narrow down what the inner parts of the state must be.

Arguments may be left out: a bare type (`Missions`), a bare sum (`PMode.ShowMission.List`) and a variant with a payload (`Page.Plan`) can each be written without them. What a left-out part means depends on the side of the transition; see "Source and target".

When arguments are written, they must fit what they follow:

- A product, or a variant carrying a product, takes some or all of its factors, in any order, each at most once: `Z(C * Y.V1)`, `Z(C)`.
- A variant carrying one type takes one argument headed by that type: `Y.V3(A)`, `Plot.Drawn(Boundary)`.
- A newtype takes one argument headed by its base type. With `Boundary = Ring`, write `Boundary(Ring.Enclosed)`, not `Boundary.Enclosed`.
- When the one type a variant carries, or a newtype's base, is a named product, its factors may be written directly, one level deep. With `Plot = Empty | Drawn PlotDrawn` and `PlotDrawn = Boundary * Markings`, `Plot.Drawn(Boundary)` means `Plot.Drawn(PlotDrawn(Boundary))`; with `B = D` and `D = G * H`, `B(G * H)` means `B(D(G * H))`. The long form is valid too. A lone name or constant stands for the whole value or for a factor, by its type. Only one level is skipped: with `B = C` and `C = D`, write `B(C(G * H))`.
- A sum takes no arguments; pick a variant with `.` instead, or several with `.{` (see "Alternatives").
- An atomic type, and a variant without a payload, take no arguments.
- A list type takes no arguments; pick an element with an element path instead (`Todos[id](...)`).

An argument may also be a named value (`t`), which fits where its type is expected; see "Named values". An element path (`Todos[id]`) fits where its list type is expected; see "Element paths".

A path continues with `.` only into a sum: a named sum or an inline sum payload. To pick a variant of a payload that is a named type, use an argument: `Page.Plan(PMode.JustMap * Missions)`.

The two sides of a transition are states of the same type: they're headed by the same type name. `Page.Home -> Page.Plan` is valid, `Page.Home -> Missions` isn't. An element path is headed by its list type, so `Todos[id](...)` is a state of `Todos`.

### Source and target

The two sides of a transition are read differently:

- The **source** side is a precondition. A part that is left out may have any value.
- The **target** side is the effect. A part that is left out, or written without a prime, keeps its value. A primed part, `A'`, gets a new value, set by the transition; a prime goes only on a part that keeps its place, not inside a new state. A name or a computed value (`Attempts(n + 1)`, `Attempts(0)`) sets the part to that value. A part whose variant differs from the source's is a **new state**.

A new state didn't exist before the transition, so nothing in it can keep its value: inside a new state, a part that is left out, or written without a prime, may have any value, and nothing takes a prime.

A part keeps its value only where the source fixes the same variants along its path. In `Page -> Page.Plan(PMode.JustMap)`, the source may have been `Page.Home`, so `Plan` is a new state.

Examples, with the types of `example/drone.sumspec`:

```haskell
-- Only the mode changes; Missions keeps its value.
changeMode :: Page.Plan(PMode * Missions) -> Page.Plan(PMode' * Missions)

-- The same, with the unchanged part left out.
changeMode :: Page.Plan -> Page.Plan(PMode')

-- The mode and the missions both change.
changeAll :: Page.Plan -> Page.Plan(PMode' * Missions')

-- The source leaves out Markings, so any markings match. The target
-- enters a new state, ShowMission.Selected, whose Mission may have any
-- value; Missions gets a new value.
savePlot :: Page.Plan(PMode.Plot(PlotOrigin.Draft * Plot.Drawn(Boundary(Ring.Enclosed))))
         -> Page.Plan(PMode.ShowMission.Selected * Missions')

-- Plan is a new state: PMode is set, and Missions may have any value.
goToPlan :: Page.Home -> Page.Plan(PMode.JustMap)
```

Where a prime may go:

- Only on a bare type name (`A'`, `Missions'`), and only on the target side.
- Not twice (`A''`), while no `A'` on the source.
- Not inside a new state: `Page -> Page.Plan(PMode')` is an error.
- Right after its name: `A '` is read as `A'`, but the type checker warns about the space.

`Missions'` says that a list changed, not how (added, removed, edited).

### Guards

A guard is a condition on the current state, written after the source. The transition applies only while the guard holds:

```
goToAircraft :: App
             => Page.Home // not AircraftLink.Disconnected
             -> Page.Plan(PMode.ManualAircraft)
```

- A guard starts with `//` and is built from patterns with `not`, `and`, `or` and parentheses. `not` binds tighter than `and`, and `and` tighter than `or`. These are words only here; elsewhere they are ordinary lowercase names.
- A guard is read where the source is. After a shared path (`App =>`), a pattern in the guard is an argument of the innermost shared path, written like the source's arguments: `not AircraftLink.Disconnected` above is `not App(AircraftLink.Disconnected)`. Without a shared path, a pattern in the guard describes the same type as the source (`Page.Home // not Page.Plan`).
- So a local transition sees only its own part of the state. To look at a wider part, start the transition with a shared path that holds both: `App => ...`. To look at the other parts of one list element, start it with the element path: `Files[p] => Kind.Text // Flag.On -> Kind.Binary`.
- A guard is a condition on the source. A pattern in it may use a name the transition binds in its input or source, as an element path does: `drop Id#p :: App => Page.Home // Files[p](Kind.Text) -> Page.Plan`. It names no value: `#x` in a guard is an error, so name the value in the input or on the source side. It sets no value either, so a prime in a guard is an error too.
- An element path in a guard tests a key: `// Todos[k]` holds when an element has the key `k`, and `// not Todos[k]` when none has. It reads the list in the state, so it can't test a list given as an input. The overlap warning takes `Todos[k]` and `not Todos[k]`, with the same name `k`, to exclude each other. Two element paths are the same element only when their keys have the same name, so `Todos[k](Mode.On)` and `Todos[j](Mode.Off)` can both hold, in a source or in a guard.
- A condition that is one variant of a sum is often better written in the source as a positive pattern. `not AircraftLink.Disconnected` is the same as `AircraftLink.Connected` there. Use a guard for what a source cannot say: a negation across several parts (`not (A and B)`), or an `or` across them.

```
-- The second source says the same as the guard in the first.
a :: App => Page.Home // not Link.Off -> Page.Plan
b :: App => Page.Home * Link.On -> Page.Plan
```

#### Comparing values

A guard may compare values. A comparison is `left op right`, with `==`, `!=`, `<`, `<=`, `>` or `>=`. It is a condition like a pattern, and `not`, `and`, `or` combine it with them:

```
-- Start only with enough charge and at least a 3D fix.
startMission :: App
             => Battery(BatteryCharge#c) * GPSFix#g
             // c > 15 and g >= GPSFix.Fix3D
             -> ...
```

- A side is a **name** (`c`: a value bound with `#c` in the input or source), a **literal**, a **variant** without a payload (`GPSFix.Fix3D`), or a **constant** (`BatteryLowThreshold`, see "Named constants").
- A literal is an integer (`15`, `-1`), a decimal (`1.5`) or a string (`"abc"`, no escapes, no quote or line break inside). A `-` touches its digits.
- The type of a name resolves through newtypes: to an atomic with a base (`__int`, `__float`, `__text`), to a sum without payloads (an enumeration), to an atomic with no base, or to anything else (a product, a list, a sum with payloads).
- Two values compare only if they have the same type: `Meters` and `Seconds` do not, though both are `__float`. A name compares with a literal or a variant that fits it:

  | The value is | A literal that fits | Operators |
  |---|---|---|
  | `__int` | integer | all |
  | `__float` | integer, decimal | all |
  | `__text` | string | `==` `!=` |
  | a sum without payloads | a variant of that sum | all |
  | an atomic with no base | none (name against name only) | `==` `!=` |
  | a sum with payloads | a variant of that sum without a payload | `==` `!=` |
  | a product or a list | none (name against name only) | `==` `!=` |

- `==` and `!=` compare every type, by structure. Two values of a product are equal when every factor is equal, and two of a sum when they are the same variant with equal payloads. Two values of a list `[T]` are equal when they have the same items in the same order, and two of a keyed list `[T by K]` when they have the same keys with equal elements, in any order. A number inside a value compares as it does alone.
- A variant with a payload can't be written as a value (`Shape.Circle` is an error here): test it with a pattern.
- A comparison says less than a pattern about what matters. When one part decides, compare that part (`Id#a ... a == b`) rather than the whole value.
- A sum without payloads is **ordered by the order of its variants, the first being the smallest**: with `GPSFix = NoFix | Fix2D | Fix3D | DGPS | RTKFix`, `g >= GPSFix.Fix3D` holds for `Fix3D`, `DGPS` and `RTKFix`. Reordering its variants changes what a guard means, so keep the order meaningful once a guard compares it.
- A variant has the type of its sum, so a newtype of that sum doesn't compare with it directly. Name the base value inside the newtype instead: with `Primary = GPSFix`, write `Primary(GPSFix#g) // g >= GPSFix.Fix3D`, or `Primary(#g)` for short (see "Bare binding").
- `not`, `and`, `or` and `in` can't be value names in a condition.
- A comparison reads the values the transition binds; it binds none. A guard still only restricts.

#### Named constants

A named constant is a fixed value with a name, defined once and used in a guard in place of a literal. Its definition starts with `__const` and gives the value, with the type it has: a literal of a type, or a variant of a sum:

```
__const BatteryLowThreshold = BatteryCharge(15)
__const MinimumFix          = GPSFix.Fix3D

batteryLow :: App => Battery(BatteryCharge#c) // c <= BatteryLowThreshold -> ...
start      :: App => GPSFix#g                 // g >= MinimumFix         -> ...
```

- A constant is a value, not a type. It is a side of a comparison, either side, or a value in a target or `__init` (see "Computed values"), and nothing else: not a type of a factor or a payload, an input, a list element, or a pattern on the source side. Write a test that needs the value as a guard (`// c == BatteryLowThreshold`).
- The name is uppercase, like a type's, and shares the types' name space: no type, atomic or other constant has it.
- A constant of a constant is not allowed. `__const Low = BatteryLowThreshold` doesn't parse, since the value is a literal or a variant; `Low = BatteryLowThreshold` is a newtype of a constant, and a constant is not a type.

The overlap warning reads a constant as the literal or variant it stands for: `c < Low` and `c >= 15` exclude each other when `Low` is `Percent(15)`.

#### Membership

`x in ys` holds when the value `x` is in the list value `ys`. It is a condition like a comparison, and `not`, `and` and `or` combine it with the others. `in` is a word only in a guard:

```
Ids = [Id]

select   Id#i :: App => Ids#ids // not (i in ids) -> Ids'
unselect Id#i :: App => Ids#ids // i in ids       -> Ids'
```

- The right side is a name whose type resolves through newtypes to a list type (keyed or not).
- The left side is any side of a comparison: a name, a literal, a variant or a constant. It has the same type rules as `==`.
- The left side has the element type. Items compare as `==` does.
- `in` always tests an item, also in a keyed list, where it ignores the keys: two elements with different keys can be equal items. To test a key, use an element path (see "Guards"): `Todos[k]`, or `not Todos[k]`.


### Several transitions for one event

An event may apply from more than one state, reaching a different
target or having a different effect from each. Write the name (and the
input) once, then one transition per state, each starting with `::`:

```
f :: A -> B
  :: C -> D
```

An event is defined once, with all its transitions together. A transition
starts with `::`, so layout doesn't matter, and comments may go between
transitions; the canonical form puts each `::` under the first.

### Event inputs

An event may take an input, a value it brings with it. The input's type
goes after the event's name:

```
startTyping Text :: NewTodo.Blank -> NewTodo.Typing(Text)
```

The input is one type: an atomic or a defined type, such as a list type
(`Ids = [Id]`).
An event that brings several values takes a product defined for them:

```
Ref = Id * Name

select Ref :: State.Off -> State.On
```

The input is a pattern headed by its type, read like a source pattern.
It can name the input or its parts (see "Named values"):

```
startTyping Text#t :: NewTodo.Blank -> NewTodo.Typing(t)
select Ref(Id#i * Name#n) :: Item(i * State.Off) -> Item(State.On)
```

A variant or argument written in the input is a precondition on it, as
on the source side.

### Shared path (=>)

The two sides of a transition often start with the same path. `=>` writes it once, before both sides:

```
-- The same as: Files[p](FileState.Staged) -> Files[p](FileState.Modified)
unstage Path#p :: Files[p] => FileState.Staged -> FileState.Modified
```

`S => A -> B` means `S(A) -> S(B)`: each side is what would go inside the parentheses after `S`:

```
-- The same as: Page.Plan(PMode.JustMap * Missions)
--           -> Page.Plan(PMode.ShowMission.List * Missions)
showMission :: Page.Plan 
            => PMode.JustMap * Missions
            -> PMode.ShowMission.List * Missions
```

Shared paths chain with `/`, outermost first: `X / Y => a -> b` means `X(Y(a)) -> X(Y(b))`. Spaces around `/` are optional; the canonical form has them.

A shared path takes no arguments, prime or naming.

#### Branches

Several transitions of an event often share the same paths. Write the paths once after `::`, then one branch per transition, each starting with `=>`:

```
-- The same as:
--   :: Files[p] => FileState.Untracked -> FileState.Staged
--   :: Files[p] => FileState.Modified -> FileState.Staged
add Path#p
  :: Files[p]
  => FileState.Untracked -> FileState.Staged
  => FileState.Modified -> FileState.Staged
```

- Each branch is a transition of its own, `:: <shared paths> => <branch>`, and follows every rule of a transition. A branch may have a guard.
- The shared paths are common to all the branches. A branch can't add paths of its own: write them out in its source and target, or start a new `::`.
- The event's input is visible in every branch. A name a branch binds (`#t`) belongs to that branch only, so two branches may use the same name.
- Branches have no order: they're the event's transitions, so two branches whose sources can apply to the same state get the overlap warning (see "Several transitions for one event").
- `::` still starts a new transition, with its own shared paths, so an event may mix branches and other transitions.
- A transition without a shared path has no branches: `:: A.B -> A.C => ...` is an error.

The canonical form puts one branch on the line of its shared paths, and several one per line, each `=>` under the `::`.

#### Named paths (__path)

A shared path written again and again gets a name with `__path`. Its body is written as it is used, segments joined by `/`:

```
__path Editor = App / Page.Plan / PlanPage.Plot

-- The same as: :: App / Page.Plan / PlanPage.Plot => PlotController.Field * ... -> ...
pointSelect core.Point#pt
  :: Editor
  => PlotController.Field * ShapeSelection.Selected
  -> ShapeSelection.Selected(PointSelection.Selected(pt))
```

A path's name stands, among a transition's shared paths, for its segments, in place: `Editor => ...`, `X / Editor => ...`, `Editor / PlotController.Route => ...`. It is expanded before checking, as shared paths and named patterns are.

- The name is uppercase and new to the spec: no type, atomic, constant, pattern or other path has it.
- Each segment is a path (`Page.Plan` may continue into variants); a segment may be another named path, but not in a cycle.
- A segment has no element key: in `Files[p] =>` the key names a value of the transition, which a path doesn't define.
- A path goes only among shared paths, before `=>`, and nowhere a pattern goes.
- A path is local to its spec, as a named pattern is.

An error found in a path's segments is reported at the use, with the place in the path: `Elsewhere is not a variant of Page (in path Bad, at 17:25)`.


### Named patterns (__pattern)

A spec often writes the same long path again and again. `__pattern` gives a state pattern a name, with parameters for the parts that change:

```
__pattern Setting(v)      = App(Plan(PlotEditor(core.Plot.Drawn(core.RouteSettings(v)))))
__pattern RouteForm       = App(Plan(PlotEditor(PlotController.Route * core.Plot.Drawn)))
__pattern Selected(at, x) = core.Core(core.Missions[at](x))

setRouteSpacing core.RouteSpacing#v :: RouteForm -> Setting(v)  @control stepper
setSprayHeight  core.SprayHeight#v  :: RouteForm -> Setting(v)  @control stepper
```

A use is written like any head, with its arguments in parentheses, one per parameter, separated by commas: `Selected(at, MissionState.Stopped)`. Each argument is what may go in a head's parentheses, so it may be several factors joined by `*`: `InEditor(Doc(Title#t) * Mode.Editing)`. A pattern without parameters is used by its name alone: `RouteForm`.

A use stands for the body, each parameter replaced by its argument. The type checker expands every use before it checks the spec, as it does shared paths, so a pattern adds no meaning of its own: `setRouteSpacing` above is checked as

```
setRouteSpacing core.RouteSpacing#v
  :: App(Plan(PlotEditor(PlotController.Route * core.Plot.Drawn)))
  -> App(Plan(PlotEditor(core.Plot.Drawn(core.RouteSettings(v)))))
```

A pattern can be used wherever a pattern goes: in a source, a target, a guard, an input, a dispatch's arguments and `__init`. What it may hold there is what its expansion may hold: alternatives in its body are fine in a source or a guard, not in a target.

A pattern goes where a pattern goes, never among a transition's shared paths before `=>`: a shared path with a name is a `__path` (see "Named paths").

Rules:

- The name is uppercase. It is new to the spec: no type, atomic, constant or other pattern has it.
- The parameters are lowercase and distinct, and the body uses each one.
- The body is a type pattern. It names nothing (no `#x`, `Head(#x)` or `[each #x]`): a value is named at the use, in an argument (`Setting(core.RouteSpacing#v)`). Every lowercase name in it is a parameter, standing for a whole argument (spliced into the arguments where it is), or for the key of an element path (`Missions[at]`), whose argument is then one name. A parameter is never a path segment, a primed or named pattern, or a value inside a computed one.
- A use gives exactly one argument per parameter. A comma goes only between a pattern's arguments; a type's arguments are joined by `*`. Nothing follows a pattern after a dot (`P.X`), and it takes no element key (`P[x]`).
- A pattern may use another, but not in a cycle.
- A pattern is local to its spec: a layer doesn't see a base's patterns. The base's events are read with them expanded.

An error found in an expansion is reported at the use, with the place in the body it comes from: `Of is not a variant of Link (in pattern Bad, at 20:26)`. A pattern that is never used is checked only against the rules above. The canonical form keeps patterns and their uses as written.

## Named values (#name)

A pattern followed by `#x` names the value it matches; a lowercase name
alone in a pattern stands for that value:

```
startTyping Text#t :: NewTodo.Blank -> NewTodo.Typing(t)
```

- `P#x` matches `P` and names its value `x`. `P` is any pattern headed by
  a type: `Text#t`, `Completion.Active#c`, `Ids#ids`. `#x` is one
  token: no space between `#` and the name. The canonical form writes no
  space before `#` either, and the type checker warns about one
  (`Text #t`).
- A name is given once per transition, in the input or on the source
  side. A name given in the input is visible in every transition of the
  event; one given on a source belongs to that transition. Its type is like: `Completion` for `Completion.Active#c`, `Ids` for `Ids#ids`.
- **On the source side**, a name that is used is a guard: the value there
  must equal the named one. `unlock` applies only when the entered code
  `c` equals the lock's secret:

  ```
  Lock   = Secret * State
  Secret = Code
  State  = Locked | Unlocked

  unlock Code#c :: Lock(Secret(c) * State.Locked) -> Lock(State.Unlocked)
  ```

- **On the target side**, a name sets the part to the named value:
  `Title(e)` is the title, set to the text `e`:

  ```
  startTyping Text#t :: NewTodo.Blank -> NewTodo.Typing(t)
  ```

- **On the target side**, a value may also be computed from names,
  literals and constants: `Attempts(n + 1)`. See "Computed values".
- Names belong to one transition. Two transitions of an event may name
  their input differently.

A name says which value; a prime says only that the value is new.
`Title'` is some new title, and `Title(e)` is the title `e`.

### Bare binding

`Head(#n)` names the one value inside `Head` without writing its type. It means `Head(T#n)`, where `T` is the type `Head` holds, and every rule for names applies to it:

```
Attempts = Int
NewTodo  = Blank | Typing Text

bump   :: App => Attempts(#n) // n < 3 -> Attempts'
submit :: NewTodo.Typing(#t) -> NewTodo.Blank
```

- `Head` holds one value when it is a newtype (`Attempts(#n)` is `Attempts(Int#n)`), a variant carrying one type (`NewTodo.Typing(#t)` is `NewTodo.Typing(Text#t)`), or an element that isn't a product (`Tags[id](#t)` with `Tags = [Tag by TagId]`).
- It is an error on a head with several parts or no single value: a product, a variant carrying a product, a sum, a list type, an atomic or a variant without a payload.
- A newtype of a newtype binds the next value, not the innermost: with `A = B` and `B = Int`, `A(#n)` gives `n` the type `B`. To reach the `Int`, write `A(B(#n))`.
- `#n` is the whole argument: `Head(#n * C)` is a syntax error. Write `Head(T#n * C)`.

### Computed values

A target may set a value computed from the values the transition names, with `+`, `-` and `*`. A counter and its reset read in two lines:

```
__atomics { Int = __int }

Attempts = Int

retry   :: App => Link.Failed * Attempts(#n)
                -> Link.Connecting * Attempts(n + 1)

connect :: App => Link.Connecting
                -> Link.Up * Attempts(0)
```

A computed value is built from:

- names the transition gives (`#n` in the input or the source);
- literals (`0`, `-1`, `1.5`, `"main"`, as in "Comparing values") and named constants (`Count(c + Step)`);
- `+`, `-` and `*`, and parentheses. `*` binds tighter than `+` and `-`, and all three group from the left: `Attempts(n * 2 + 1)` is `(n * 2) + 1`.

No division, no function calls and no operations on text. Overflow and rounding are the target's own; the spec promises nothing.

**Where it goes.** A computed value is always the whole argument of the type it sets, so the reader sees which part changes. That type is a head that holds one value, the same heads as in "Bare binding":

```
Link  = Off | Connecting | Up | Failed Attempts
Tries = Off | Counting Int
Scores = [Int by Id]

fail  :: App => Link.Connecting * Attempts(#a)
             -> Link.Failed(Attempts(a + 1)) * Attempts(a - 1)  -- a newtype
count :: App => Tries.Counting(#n) -> Tries.Counting(n + 1)     -- a variant carrying one type
score Id#id :: Scores[id](#s) -> Scores[id](s * 2)              -- an element
```

- It is never a factor or a whole side by itself: `Link.Up * (a - 1)` and `-> (a + 1)` are errors. Write the type around it: `Attempts(a - 1)`.
- It goes only on the target side and in `__init`, where a value is set. A source, an input or a guard tests a value instead: name it and compare it in a guard (`Attempts(#n) // n < 3`).
- A plain literal or constant is a value too, in the same place: `Attempts(0)`, `Count(Start)`. A lone constant may also stand as a factor, as a name of its type does: `Link.Off * MaxTries` with `__const MaxTries = Attempts(5)`.

**Why `*` is not ambiguous.** In the arguments of a pattern, `*` separates factors (`Item(i * State.Off)`). A head that holds one value takes no factors, so under such a head, values joined by `*` are a multiplication: `Attempts(n * 2)`. Under a product, they are factors, and a value in them (`Item(a * 2)`) is the error above. With `+` or `-`, the arguments are one computed value, whatever the head: `Attempts(n + 1 * 2)` is `n + (1 * 2)`.

## List

We show a list of T like: `[T]`

A list only define as a newtype and is written by a type name everywhere else:

```
Points = [Point]

Ring = Partial Points | Enclosed Points

pick Points#ps :: Ring.Partial -> Ring.Enclosed(ps)
```

- A list of lists names the inner list: `Row = [Cell]`, `Grid = [Row]`.
- A list can't be a product's factor (`[A] * B`), a variant's payload
  (`V [A]`) or a pattern (`[A]`, in an input or on a side): write its
  type name.

### Keyed lists

A keyed list, `[T by K]`, is a list whose elements are identified by a
key of type `K`:

```
Todos    = [Todo by TodoId]
Files    = [FileState by Path]
Branches = [Tip by BranchName]
```

- No two of its elements have the same key.
- `K` is an atomic or a defined type.
- `[T by K]` and `[T]` are different types, and so are two keyed lists
  with different keys.
- `by` is a word only inside the brackets; it can still be a name
  elsewhere.

An element of a keyed list is picked with an element path,
`Todos[id]`; see "Element paths".

### Element paths

`L[x]` is the element of the keyed list type `L` whose key equals the named value `x`:

```
Todos = [Todo by TodoId]
Todo  = Title * Completion * RowMode

toggleTodo TodoId#id :: Todos[id](Completion.Active) -> Todos[id](Completion.Completed)
```

`Todo[id]` will be resolved to a `Todo` and then `(Completion.Active)` will apply
to that `Todo`: `Todo(Completion.Active)`.

- `L` is a type defined as a keyed list (`Todos = [Todo by TodoId]`).
  The path starts at the list type, so from a variant that carries the
  list: `Ring.Points(Points[i](...))`.
- On the source side, `L[x]` is a precondition: the element exists and
  matches its arguments. Without arguments, it only has to exist.
- On the target side, `L[x](...)` is that element's new state.
  Without arguments, the element keeps its value.
- An element takes no prime (`Todos[id]'`): prime its parts instead,
  `Todos[id](Title')`. It can't be named (`Todos[id]#t`) either, and it
  doesn't go in the input.

**More Examples:**

```
deleteTodo TodoId#id :: Screen.WithTodos(Todos[id]) -> Screen.NoTodos
```

A path is written from where the list is, so the parts around it can be
written too.

```
Projects = [Project by ProjectId]
Project  = Name * Todos
Ref      = ProjectId * TodoId

toggleTodo Ref(ProjectId#p * TodoId#t)
  :: Projects[p](Todos[t](Completion.Active))
  -> Projects[p](Todos[t](Completion.Completed))
```

A path picks an element of each list it goes through, so nested lists work.
`Projects[p]` is the project, and `Todos[t]` the todo inside it.

#### Several elements: `L[each #x in xs]`

`L[each #x in xs]` is every element of `L` whose key is in the list `xs`.
It stands for `L[x]`, once for each `x` in `xs`:

```
Files = [FileState by Path]
Paths = [Path]

mergeConflicted Paths#ps
  :: Files[each in ps] => FileState.Unmodified -> FileState.Conflicted
```

The word `each` says that the path picks several elements; `L[x]`
picks one. In the brackets, `each` is always the word, never a value
named `each`.

- `xs` is a name of the transition (from the input or the source side)
  whose type is a list, keyed or not, or a newtype of one. It holds keys
  of `L`: its element type is `L`'s key type.
- `#x`, optional, names the key of each listed element, a value of
  `L`'s key type, as `#x` names a value anywhere. The transition can use
  `x` anywhere, as one element's key
  (`Branches[each #b in bs] -> Branches[b](Tip')`) or as a value. It is
  a new name: nothing else in the transition is named `x`. Without it,
  `L[each in xs]`, the key is unnamed.
- On the source side, it's a precondition, as for one element: every
  listed element exists and matches the arguments, or the transition
  doesn't happen. An empty list matches.
- On the target side, each listed element gets the new state. Without
  arguments, each keeps its value.
- It's written on the source side, or in a shared path
  (`Files[each in ps] =>`), which puts it on both sides. On the target,
  each element is written `L[x]`, using the name; so without `#x` the
  target can't write those elements, and the path goes in a shared
  path, or on a source side whose target leaves the list alone.
- A transition picks several elements once: it has at most one
  `L[each ...]`.

#### Every element that matches: `L[each #x]`

`L[each #x]` is every element of `L` that matches, with `#x` naming the
key of each; `L[each]` leaves it unnamed:

```
commit :: Files[each] => FileState.Staged -> FileState.Unmodified
clear  :: Files[each #p] -> Files[p](FileState.Unmodified)
```

- On the source side, it's a filter, not a precondition: the elements
  that match the arguments take part, and the others keep their values.
  The transition happens even when none match. Without arguments, it's
  every element.
- On the target side, each element the source picked gets the new
  state, written `L[x](...)`.
- `x` is a name of the transition, of `L`'s key type, new to it. A name
  given inside the arguments is one element's (`Sizes[each #p](#n) ->
  Sizes[p](n + 1)` adds one to each).
- It is placed like `L[each #x in xs]`: on the source side or in a
  shared path, never on the target or in a guard, and a transition has
  at most one `L[each ...]`.

`L[each #x in xs]` and `L[each #x]` differ on the source side: every
listed element must match the first, while the second takes the
elements that match.

## Language version

A spec may declare the language version it's written for, as the first
line (a comment may come before it):

```
__version 1.0
```

The version is `major.minor`, written as one token (`1.0`, not `1. 0`).
A spec without the header is version 1.0. See `VERSIONING.md` for 
how versions are numbered.

## Initial state (__init)

`__init :: P` gives the state the app starts in. `P` is a state pattern, like a target. Every spec has exactly one `__init`, written among the definitions (after `__atomics` and `__events`).

`P` is a whole new state: nothing has a value before it, and no event brings an input. So:

- A part that is left out may have any value.
- Nothing in it takes a prime (`__init :: App(Mode')` is an error).
- Nothing in it is named or uses a name (`Text#t`, `x`), and it has no element path (`Todos[id]`). It may give a value with literals and constants: `Attempts(0)`, `Count(Start + 1)` (see "Computed values").
- `__init` isn't listed in `__events`, and no `->` follows the `::`.

`__atomics` and `__events` are written before any type, transition or `__init`.

## Annotations (@name)

An annotation is metadata: something the application needs that the
types can't say, such as how a value is drawn, its default, or a side
effect of a transition. SumSpec gives it no meaning; the target (the code
generator) does.

The annotations a spec uses are listed once in an `__annotations` block,
next to `__atomics` and `__events` (the header blocks come in any order).
A comment next to each name documents it:

```
__annotations {
  @control  -- the widget that edits a value or triggers a transition
  @default  -- the value a part starts with
  @status   -- how a variant is shown: loading, error or empty
  @effect   -- a side effect of the transition
}
```

An annotation is `@name` (no space after the `@`) followed by its
arguments. Several may follow one another. Where it's written says what
it belongs to:

| Written                                  | Belongs to              |
|------------------------------------------|-------------------------|
| `Plot @default Empty = Empty \| Drawn`   | the type `Plot`         |
| `PortSetting = Port @default 14550`      | the type `PortSetting`  |
| `\| Failed FailureReason @status error`  | the variant `Failed`    |
| `Mission = Name * Plot @control map`     | the member `Plot`       |
| `go :: A -> B @control button`           | the transition          |

After the body of a newtype or a list, an annotation belongs to the type,
as it does after the name. In a sum or a product it belongs to the
variant or member it follows. After the target of a transition it
belongs to that transition; with branches (`=>`), to the branch it
follows. A sum or product as a whole takes its annotations after its
name. Atomics, constants and `__init` take none.

SumSpec doesn't decompose the arguments: they're text for the target.
They run to the end of the line, to a comment, or to one of `@ = | * ::`,
so another annotation, variant or member may follow on the same line:

```
PortSetting = Port  @default 14550 @range 1..65535

Screen @default Home
  = Home                @control tab
  | Failed Reason       @status error

landed :: Page.Plan => PMode.Flying -> PMode.JustMap
       @effect notify "Mission saved"
```

Inside brackets, `( [ {`, the arguments go on, across lines too, and
may hold any of those characters; a string is one unit. A comment inside
brackets is dropped, and each run of spaces and line breaks counts as
one space:

```
       @unless ( Page.Plan(PMode.ManualAircraft)
               * AircraftLink.Connected )
```

This is the only place in SumSpec where a line break matters.

The checker reports an annotation that isn't listed in `__annotations`
(a spec without the block uses none), and a name listed twice. It
doesn't check the arguments.

## Layered specs (__imports)

An application often has a core, its data and the events that change it,
and something over it: a UI, a command line, an API. Each can be a spec
of its own. A **layer** imports a **base spec**: it holds the base's state
as a part of its own, reads it, and changes it only by firing the base's
events. The base is complete on its own and knows nothing of its layers,
so several layers (a UI and a CLI) can share one base.

```
-- todo-core.sumspec: the base
__atomics { Text = __text  TodoId }
__events  { toggleTodo  clearCompleted }

__init :: Core(ItemsLeft(0))

Core       = Todos * ItemsLeft
Todos      = [Todo by TodoId]
Todo       = Title * Completion
...

-- todo-ui.sumspec: a layer over it
__imports {
  core "todo-core.sumspec"
}

__atomics { }
__events  { toggleClicked  clearClicked }

__init :: App(Filter.All)

App    = Filter * core.Core
Filter = All | Active | Completed

toggleClicked core.TodoId#id :: App -> App  >> core.toggleTodo(id)
```

### Import

A spec lists the base specs it imports in an `__imports` block, a header
block written at most once, with `__atomics` and `__events`. Each entry
is `name "file"`, and a comment next to it documents it:

```
__imports {
  core "todo-core.sumspec"   -- the todos and what can be done to them
  log  "log.sumspec"
}
```

The file is a spec, found relative to the importing file. `name` is the
qualifier: the layer writes
everything the base declares with it, `core.Todos`, `core.toggleTodo`, as
one token, with no space around the `.`. Only the first name of a path is
qualified: `core.Completion.Active`. The variants of a base type are
reached through it; a bare `Active` is never a base variant.

The base is checked on its own first. The layer reports one error on its
entry in `__imports` when the file is missing, doesn't parse, or has errors. An
import cycle is an error, and so is reaching one file through two imports
(`a` and `b` both importing `c`). A layer sees only the specs it imports,
not their imports.

### The base's state

The layer's root, the head of its `__init`, is a product with the base's
root as a factor: `App = Filter * core.Core`. Products are keyed by type,
so `core.Core` is an ordinary factor. The base's root appears there once
and nowhere else.

The base's part of the state is the base's own: only base events change
it. So no target of a layer transition, and not the layer's `__init`,
writes inside the base's root: `core.Core(...)` and `core.Core'` go only
on the source side and in guards. The base's part starts at the base's
`__init`; the layer's `__init` leaves it out.

A source or a guard reads the base's state through its root, so the
layer reads base data instead of copying it:

```
startEditing core.TodoId#id
  :: App => View.List * core.Core(core.Todos[id](core.Title#t))
         -> View.Editing(EditText(t) * id)
```

A base type may also be the layer's own data, outside the base's root:
a draft (`Draft = core.Title`) is the layer's to write.

### Dispatch (>>)

A layer transition may fire one base event, after its target. Both
happen as one step: the layer's transition, and the base event's
transition from the current state:

```
clearClicked :: App => Filter -> Filter.All  >> core.clearCompleted
```

When the base event takes an input, the dispatch gives it, in
parentheses: one name or value of the input's type, or the arguments of
the input's type as after its name in a target. With
`rename Rename(TodoId#id * Title#t)` in the base, `>> core.rename(id * e)`
gives the input `core.Rename(id * e)`. The names are the transition's,
as on its target side. An event without an input takes no argument.

The dispatched event happens in every state the transition applies to:
its source and guard imply a source of the event. With
`stop :: Link.Up -> Link.Down` in the base:

```
-- Error: Link is left open, and stop needs Link.Up.
stopClicked :: App(Mode.On) -> App(Mode.Off)  >> core.stop

-- Either of these says it:
stopClicked :: App => Mode.On * core.Core(core.Link.Up) -> Mode.Off  >> core.stop
stopClicked :: App(Mode.On) // App(core.Core(core.Link.Up)) -> App(Mode.Off)  >> core.stop
```

- Only variants are read, as in the overlap check (see "Warnings"): the
  variants the source and the guard require include those of one of the
  event's sources. A guard that forbids the other variants counts too
  (`// not App(core.Core(core.Link.Down))`), and each clause of an `or`
  must imply a source on its own.
- A sum left open is enough when the event has a source for each of its
  variants: with `flip :: Link.Up -> Link.Down` and
  `:: Link.Down -> Link.Up`, a dispatch of `core.flip` needs no `Link`.
- A pattern on a base's type says the same wherever it is written: the
  event's `Core => Link.Up` is implied by `core.Link.Up` anywhere in the
  layer's source. A projection's variants are those of the base part it
  reads, so `Status.Up` implies `core.Link.Up` with
  `Status __from core.Core / core.Link`.
- The event's guards and input are taken to hold: a value can't be
  read from the variants. A guard on a value in the layer (`// n > 3`)
  implies no variant.

### Reactions

A layer may add its own changes to a base event by giving transitions
for its name, qualified. They happen whenever the base event does,
whether a layer dispatches it or not, in the same step:

```
core.clearCompleted :: App => View.Editing -> View.List
```

A reaction isn't listed in `__events`; the event is the base's. If it
writes the input, it has the base event's input type. A reaction follows
every rule of a layer transition, writes nothing inside the base's root,
and dispatches nothing.

A dispatching transition counts as a transition of the event it fires,
so a reaction whose source can apply to the same state gets the overlap
warning (see "Warnings").

### Projections (__from)

A layer often shows the base's data: a screen draws the connected aircraft's battery, or a row per saved device. The data is the base's, so the layer doesn't copy it; a copy would need a reaction to every base event to stay up to date. A **projection** is a type of the layer that reads a part of the base's state. `__from`, right after its name, gives the path to that part:

```
HomeView = About * LinkStatus * HomeAircraft

LinkStatus          __from core.Core
                    @view status
  = core.LinkSession
  * core.AircraftLink

HomeAircraft        __from core.Core / core.AircraftLink
                    @view tiles
  = Disconnected
  | Connected (core.BatteryReserve * Battery * HomeIndicators)

Battery             __from core.AircraftStatus / core.Battery
  = core.BatteryCharge

HomeIndicators      __from core.AircraftStatus
  = core.GPSFix * core.Satellites * core.ArmState
```

A projection is part of the layer's state like any other type, and it carries its own annotations, so presentation lives in the layer, not on the base's types. Its value is always the base part's, seen through its structure: no transition writes it.

**The path** is a chain of the base's types, joined by `/`, each holding the next: `core.Core / core.AircraftLink`. It has no variant or element key. Where it starts:

- A projection outside any other reads from the base's root: its path starts with it (`core.Core`).
- A projection inside another reads from where its parent reads. Its path starts with the type of the parent's source part there, or with one of that type's factors. Inside `HomeAircraft.Connected`, the source is the connected `core.Aircraft`, so `HomeIndicators` reads `core.AircraftStatus`, one of its factors. For a list's element, the path starts with the element's type: `DeviceRow __from core.Device` inside `DeviceRows __from core.Core / core.Devices = [DeviceRow by core.DeviceId]`.
- Each type after the first is a factor of the type before it. The type at the end is the projection's **source**.

**The body fits the source**, through newtypes:

- A product, or a single type when the source is a product, shows some of the source's factors, each the same type, or a projection read inside the source.
- A sum has every variant of the source sum, by name. A variant without a payload shows nothing of the source's payload, so `HomeAircraft.Disconnected` draws nothing; this is how a part is drawn only in some states. A payload is projected against the source variant's payload.
- A keyed list `[E by K]` has a keyed list source with the same key, and `E` is the source's element type or a projection of it.
- A single type with any other source is the source's type.

**Reading and writing.** Sources and guards match a projection like any state: `App(Page.Home(HomeView(HomeAircraft.Connected)))`. No target and no `__init` names a projection or anything inside it: it is read, not set. A new state that holds one leaves it out. For reachability, a projection's variants count as reached from the start, as the base decides them.

A projection selects parts of the base's state; it doesn't compute. A value worked out from the base's data, such as a count or a route's length, isn't a projection.

The checker reports:

- a path that names a type that isn't a base's;
- a path that starts elsewhere than it should, or a step that isn't a factor of the type before it;
- a factor, a variant, a key or an element that doesn't fit the source, or a missing variant;
- a target or an `__init` that names a projection;
- `__from` in a spec without `__imports`, or written after the annotations (where it would read as their arguments).

## Summary:

```
=  used for type definition
|  sum type
*  product type; or multiplication inside a head that holds one value
+  addition in a computed value; - subtraction
.  selects a variant of a sum type
:: starts a transition
-> state transition
=> a path both sides of a transition share
/  joins shared paths, the segments of a __path, and the types of a __from path
,  separates the arguments of a named pattern (__pattern)
@  an annotation: metadata for the target
>> fires an event of a base spec (see "Layered specs")
```

## Warnings

Transitions of one event on different types describe its effect on different parts, and all of them happen. Two transitions on the same type should have sources that exclude each other: somewhere, they pick different variants. Otherwise one state can match both, and the spec doesn't say which happens; the type checker warns:

```
-- Warned: Level is left out of the second source, so it may be Low.
press :: App(Mode.Off * Level.Low) -> App(Mode.On)
      :: App(Mode.Off) -> App(Level.High)
```

The check reads only variants: two sources that differ only in a named value (`Todos[a]`, `Todos[b]`) are taken to overlap.

A guard can separate two transitions whose sources overlap. They do not overlap when their guards can never hold in the same state: one requires a variant and the other forbids it (`// Link.On` and `// not Link.On`), or they require different variants of one part. The check does not notice that several forbidden patterns together can cover every variant of a part, so it may warn about guards that really do exclude each other; write one of them as a positive pattern then.

Comparisons of a name with a literal or a variant count too: `c < 15` and `c >= 15`, or `p == 1` and `p == 2`, exclude each other, and so do `n > 4` and `n < 5` on integers. Comparisons of two names are not read. Two transitions of one event that use the same name with the same type are taken to mean the same value.

From `__init`, the type checker finds the variants the app can reach: a transition can happen once every variant its source writes has been reached, and its target then reaches the variants it writes. A part that may have any value (left out of `__init` or of a new state, or primed) reaches every variant inside it. The checker warns about a variant of a type inside the app's state that is never reached, and reports only the outermost one (not `Bolt` inside an unreached `Locked (Bolt | Chain)`). Parts of a source are tested one at a time and names are ignored, so a variant may be counted as reached when the app can't really get there, but never the other way around.

A transition whose source writes a variant that is never reached, or whose type no state holds (a type outside the app's state), can never happen, and the type checker warns about it, naming the outermost variant its source needs. Such a transition also adds nothing, so what only it would reach is reported as never reached as well.

### Membership Warnings

The overlap warning takes the same membership, true in one guard and false in the other, to exclude each other: `i in ids` and `not (i in ids)`. Two left sides are the same when they are the same name of one type, or the same value (a constant is read as its value). Any other membership may hold, and a comparison says nothing about one.
