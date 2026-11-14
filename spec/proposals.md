# Proposals

Ideas that are in no language version yet. Each one says its version
impact (see `VERSIONING.md`):

- **additive**: it can go into the next minor language version
- **breaking**: it waits for the next major language version

Until the first release, any proposal can go straight into 1.0 (see
"Before the first release" in `VERSIONING.md`).

## Two events with the same transition (Postponed)

Version impact: additive.

    g, h :: Y -> Z  -- two events "g" and "h" with the same transition

## `<-` is a shorthand, `a' <-` means `a -> a'`

Version impact: additive.

It builds on shared paths, which are in v1 (see "Shared path" in `spec-v1.md`):

    X / Y => A' * B' <-

Means:

    X(Y(A' * B')) <-

## Annotation argument kinds

Version impact: additive.

Builds on annotations (see "Annotations (@name)" in `spec-v1.md`), whose
arguments are opaque text today. A declaration may state its argument
kind, so the checker validates it:

    __annotations {
      @unless <pattern>   -- unavailable while this state holds
      @when   <pattern>
      @control <name>
    }

For a `<pattern>` argument the checker can resolve every name against the
types, and warn when the pattern can never hold, always holds, or
contradicts the transition's source (`@unless Page.Home` on a transition
from `Page.Home`).

An atomic takes no annotations: a type that needs `@default` or `@range`
is a newtype of it.

## Layered specs, more

Version impact: additive. Builds on layered specs (see "Layered specs
(__imports)" in `spec-v1.md`), which allow what a layer over one core needs
and nothing more. Each item below lifts one restriction, so a spec valid
today keeps its meaning.

- **Occurrences.** A way for a base to mark its occurrences (from the
  system or the world) apart from its commands (from a user), so the
  checker can warn about a command that no layer dispatches.
- **Several dispatches.** One transition firing several base events
  (`>> core.a >> core.b`), and in which order they apply.
- **Modules.** Generalizing layers to a module system:
  - A file reached through two imports (a diamond): one shared base
    state, held once in the importer's root.
  - Dispatching an event of any accessible spec, not only a direct
    import, and naming its types (`core.lib.T`).
  - Renaming on import (`as`), and import paths beyond relative files.
- **Annotations.** `@announce` and `@stream` as annotations on
  reactions, and `@control` on dispatching and view-only transitions.
- **Drone.** Splitting `example/drone.sumspec` into a core and a UI: view
  state (`Page`, `PMode`) out of the domain, and `@from`/`@edits` replaced
  by reading the base and by forms that hold a draft and dispatch a base
  event with it.

## Checking `@default` and `@range`

Version impact: additive.

Builds on the primitive types and the comparisons of v1 (see "Primitive
types" and "Comparing values" in `spec-v1.md`), and on annotations
(see "Annotations (@name)" in `spec-v1.md`). A newtype over an atomic
carries the annotations, since an atomic takes none:

    __atomics { Port = __int  Meters = __float }

    PortSetting = Port    @default 14550 @range 1..65535
    SprayHeight = Meters  @default 3 @range 1..10

The checker can then verify that a `@default` is a literal of the type,
that `@range low..high` has `low <= high`, and that the default lies
inside the range. Today these are opaque tokens. `Percent` (`0..100`) and
`Degrees` (`0..360`) would be `__float` newtypes with a `@range` instead
of atomics with a comment.

## Literal patterns

Version impact: additive.

A literal pattern says "the value is this literal": `Type(literal)`. It
is a pattern, so it goes where a pattern goes. The decisions behind it
are in `literal-patterns.md`.

    Count(0)    Meters(1.5)    Name("main")

Syntax:

- Only the form `Type(literal)`. A bare `0` is not a pattern.
- A literal is an integer (`15`, `-1`), a decimal (`1.5`) or a string
  (`"abc"`), as in "Comparing values" in `spec-v1.md`.
- A payload pattern starts with an uppercase type name, and a literal
  with a digit, `-` or `"`, so the first token after `(` tells them apart.
  `A(1)` already parses (a value in a target, see "Computed values" in
  `spec-v1.md`), and the checker rejects it in a source today, so no
  spec changes meaning.
- A literal is not the payload of a variant directly: write
  `NewTodo.Typing(Text("hi"))`, not `NewTodo.Typing("hi")`. (Open: a
  value in a target already takes the second form, since a variant
  carrying one type is a head that holds one value; see "Computed
  values" in `spec-v1.md`.)
- No alternation (`Count(0 | 1)`), no range (`Count(0..9)`), and no
  binding (`Count(0)#c`): the value is known. Use two transitions or a
  guard, or write the literal where the value is needed.

Types: the head type resolves through newtypes to a base, and the
literal must fit that base (the table in "Comparing values"):

| The head type resolves to | Literal that fits |
|---|---|
| `__int` | integer |
| `__float` | integer, decimal |
| `__text` | string |
| a sum without payloads | none (use the variant) |
| an atomic with no base | none |
| a product, a list, a sum with payloads | none |

Two types with the same base stay different: `Meters(3)` is not
`Seconds(3)`. Equality is by value, so `Meters(3)` and `Meters(3.0)` are
the same.

Where it may appear:

- a source and a pattern in a guard (`Count(0)`);
- an input head: `setSpeed Speed(0) :: Moving -> Stopped` applies only
  for that input;
- an element key: `Slots[Slot(0)]` is the element with that key (only a
  key type with a base takes a literal);
- a target and an `__init`, as a value: in v1 (see "Computed values" in
  `spec-v1.md`).

The checker orders patterns as it does variants. A literal behaves like
a variant of an unbounded sum of its type:

- equal literals are the same pattern; different literals of one type
  are disjoint, so two transitions of one event that differ only in a
  literal source or a literal input do not overlap;
- a literal is inside its bare type, so `Count(0)` against `Count`
  overlaps, as a variant against its sum does;
- literals of different types never relate.

A literal pattern and a guard `c == 0` say the same; both stay, with no
lint. Reachability treats a literal as its bare type. Tracking values
(per type, a finite set of literals or "any"; a warning only when a
source literal is never given to the type) is a later step that needs
the literals and arithmetic in targets (both in v1).

The printer keeps the literal's spelling. A code generator tests exact
equality for every type: integers, strings character by character with
no normalization, and floats with the target's own float equality.

A named constant (see "Named constants" in `spec-v1.md`) defined as
`Zero = Count(0)` is a pattern equal to `Count(0)`, and one defined as
`GPSFix.Fix3D` is a pattern equal to that variant. As a pattern head it
takes no arguments, and it may appear where the literal pattern may. Today
the checker rejects a constant in a pattern. This comes after literal
patterns exist.

## Arithmetic, more

Version impact: additive.

Arithmetic in targets is in v1 (see "Computed values" in `spec-v1.md`).
What is left:

- Division, and `min`/`max`, if a spec needs them (zero, integer or
  float division?).
- Arithmetic in guards, with the same expressions: a side of a
  comparison may be one (`c + 1 <= max`). See "Guard on data".

## Prelude

Version impact: additive.

An optional `.sumspec` file, embedded in the checker and loaded before the
user's spec. It holds the definitions most specs repeat:

    __atomics { Int = __int  Float = __float  Text = __text }

    Bool = True | False

Later it could hold `Ordering` or `Maybe`.

Nothing is reserved. A declaration or definition of the same name in the user's spec
replaces the prelude's, so a spec that needs its own `Text` just defines
it. `Bool` is an ordinary sum, so patterns work on it
(`SingleSideSpraying.True`) and `@control toggle` is a hint over a
two-variant sum. The variants are capitalized, so `@default false` becomes
`@default False`.

## Dependent type

Version impact: additive.

    BoundedList = { xs : [Int] // 2 <= xs.len /\ xs.len <= 10 }

## Guard on data

Version impact: additive.

Guards on patterns and comparisons of values are in v1 (see "Guards" and
"Comparing values" in `spec-v1.md`). What is left:

- **Membership**, `x in ys`: done, see "Membership" in `spec-v1.md`. A form
  for "some element satisfies a comparison" is still open, and so is testing a
  key of a list given as an input (an element path reads the list in the state).
- **Named constants**, such as `BatteryLowThreshold`: done, see "Named
  constants" in `spec-v1.md`.
- **Arithmetic and calls**, such as `a + 1` (see "Computed values" in
  `spec-v1.md`, which defines the expressions, and "Arithmetic, more")
  or `further(p, b)`, and
  whether guards share the predicate language of the dependent type
  above.
- Whether a failed guard also shows the control disabled. `@unless` stays
  for the UI ("disabled, with a reason"); a guard is part of the
  transition's meaning.

What it would replace in a real spec (`temp.sumspec`, Parvaz Agro), where
conditions are still encoded as enum states or `@after`:

    -- a derived enum becomes a threshold; the sticky latch stays a state
    batteryLowEvent ... Feed.Live * BatteryCharge#c
      // c <= BatteryLowThreshold
      -> ...

    -- `@after TelemetryAge 60` becomes part of the transition
    linkLossEvent ... Feed.Stale(TelemetryAge#a)
      // a >= 60
      -> AircraftLink.Disconnected

Gains: fewer copies of a transition (`linkLossEvent` has five), fewer
derived-state enums, and rules that were comments become checkable.

### From `@unless`

`@unless P` means "available only while the state does not match `P`",
which is the guard `not P`, with `P` written from the root type. Three
cases:

- A single path on a sum is the complementary variants, as a plain
  positive pattern on the source. No guard is needed, and this is the
  best form because the checker already understands it:

      @unless ...AircraftLink.Disconnected   =>  AircraftLink.Connected
      @unless ...ArmState.Armed              =>  ArmState.Disarmed
      @unless ...BatteryReserve.Low          =>  BatteryReserve.Enough
      @unless ...GPSFix.{NoFix | Fix2D}      =>  GPSFix.{Fix3D | DGPS | RTKFix}

  So a guard is not needed where a variant pattern says it:

      goToAircraft
        :: App
        => Page.Home * AircraftLink.Connected
        -> Page.Plan(PMode.ManualAircraft)

- Several `@unless` lines are an AND: each forbids one thing, so the
  transition needs all of them false (`not a and not b`), or all the
  positive patterns at once. The six lines of `startMission` collapse
  into its source.
- A compound `@unless (X * Y)` is `not (X and Y)`, which is
  `not X or not Y`. A source pattern cannot say "or" across two parts of
  the state, so it needs a guard, or two transitions:

      pagePlanBackToHome :: App => Page.Plan
        // not ( Page.Plan(PMode.ManualAircraft)
               and AircraftLink.Connected(Aircraft(AircraftStatus(ArmState.Armed))) )
        -> Page.Home

The "reason" text is lost in the conversion: a guard only blocks. So
`@unless` stays where the UI must say why a control is disabled; the
target can derive the reason from the unmet pattern or guard. A checker
lint could flag an `@unless` that a source pattern expresses.

## Generic type

Version impact: additive.

    List a = [a]

## Variant refinement

Version impact: additive.

    PMode.ShowMission = List | Selected Mission

A variant declared without a payload gets its payload from a separate
definition, addressed by its path. Today the payload is written inline:

    PMode
      = ...
      | ShowMission (List (...) | Selected Mission)

## Naming an element

Version impact: additive.

    rename TodoId#id :: Todos[id]#t -> ...

`L[x]#t` names the element, with the element type (`Todo`), not the
list type. Not allowed yet.

## Branches on a guard

Version impact: additive.

Builds on branches (see "Branches" under "Shared path" in `spec-v1.md`).
Several conditions on one source, with the source written once and one
`//` per branch:

    f :: T(Int#i)
      // i <  10 -> ...
      // i >= 10 -> ...

Means:

    f :: T(Int#i) // i <  10 -> ...
      :: T(Int#i) // i >= 10 -> ...

It's for a long source that only a condition splits. A split on variants
is a branch on a shared path, which can also bind values:

    toggleTodo TodoId#id
      :: Todos[id]
      => Completion.Active -> Completion.Completed
      => Completion.Completed -> Completion.Active

Rules:

- Each branch is a transition with the shared source and its own guard.
  The checker works on the expanded transitions, so overlap needs nothing
  new: `i < 10` and `i < 20` warn.
- A branch binds nothing, as every guard: `// Mode.Editing(#t) -> ...`
  stays an error. Bind on the source, or use branches on a shared path.
- Branches have no order: it reads like a `case`, but the first branch
  that holds doesn't win, and overlapping branches warn.
- Nothing checks that the branches cover every case. When none holds,
  the event doesn't apply, as with any guard.
- No `otherwise` branch: it would depend on the other branches, so a
  branch would no longer be one transition.

Open:

- How it combines with branches on a shared path
  (`:: App => Src // g -> T // h -> U => ...`), and its canonical layout.
- A factor shared by branches, such as
  `AircraftLink.Connected(Aircraft(Feed.Stale))` in every source of
  `linkLossEvent`: `/` can't hold it, since it sits beside `Page`, not
  around it.
