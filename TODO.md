# TODO

## Remaining

### Open questions

### Closer to an EFSM (`spec/efsm-gaps.md`)
Decide on each gap, one at a time, then move it to `proposals.md`:
- [ ] Where a local transition applies (decided in part; waits for
      derived values in "How updates change values").
- [x] Event inputs.
- [x] Event outputs (decided: none; side effects go in annotations on
      transitions).
- [ ] Guards on data: see "Guards on data, in steps" below.
- [x] How updates change values, Part A: named values.
- [x] How updates change values, Part B: derived values (replaced by
      arithmetic in targets, now in v1: "Computed values" in
      `spec/spec-v1.md`).
- [ ] How updates change values, Part C: list updates (form chosen:
      an action clause, `// __remove ts[id]`).
- [ ] Nondeterminism between transitions: first match, once guards
      exist (see gap 5).
- [ ] Values inside a new state (decided in part: see `spec/efsm-gaps.md`
      gap 7; literals and arithmetic in targets are in v1, the warning
      for a part nothing sets is open).

### Guards on data, in steps
The design is in `spec/proposals.md` ("Guard on data", "Prelude"). Do
the steps in order; each one moves `spec-v1.md`, `grammar.ebnf`, the
examples, the golden tests and `CHANGES.md` together.
- [x] 1. Primitive types: `__int`, `__float`, `__text` as the base of an
      atomic in `__atomics` (`Port = __int`). Types only: the atomic is
      still a leaf. No literals or operations yet.
- [x] 2. Guards with pattern predicates only: a `//` clause before `->`;
      read where the source is (after `P =>`, its patterns are arguments
      of `P`); `not`, `and`, `or`; binds no value; the overlap warning
      reads guards. Needs no primitives.
- [x] 3. Guards with comparisons and literals: `== != < <= > >=` on
      names, integer, decimal and string literals, and variants of sums
      without payloads (ordered by declaration); a newtype inherits its
      base's operations, so `Meters` and `Seconds` still don't compare.
      `in` moved to "Later".
- [x] 3b. Named constants: `BatteryLowThreshold = BatteryCharge(15)` as
      a side of a comparison.
- [ ] 4. {Optional, later} Prelude: an embedded `.sumspec` with
      `Bool = True | False`, `Int = __int`, `Float = __float` and
      `Text = __text`; a definition of the same name in the user's spec
      replaces it.

### Editor support
The plan is in `docs/lsp.md`. In order:
- [x] `sumspec lsp` with diagnostics (the `lsp` package). A range is the
      token at the error's position for now.
- [ ] Ranges on errors (start and end). Names have them in the
      language server (a name's end follows from its text), which
      covers navigation and semantic tokens; errors still use the token
      at their position.
- [x] Parse recovery per definition: every parse error
      (`parseSpecPartial` also gives the partial AST).
- [ ] Check a partial AST in the language server, without spurious
      errors about names whose definitions didn't parse.
- [x] Document symbols, go-to-definition, references.
- [x] Semantic tokens.
- [x] Neovim: the plugin `sumspec.nvim` (a repository of its own), with
      the filetype, the server's configuration and a fallback syntax
      file.
- [ ] VS Code: an extension with a TextMate grammar (also for Shiki,
      Sublime and GitHub) and `vscode-languageclient`.
- [x] A resolved model (`SumSpec.Model`), then hover and completion.
- [ ] Formatting, once the AST keeps comments.
- [ ] {Optional, later} A tree-sitter grammar.

### Versioning
- [ ] Release 0.1.0.0: date it in `CHANGES.md`, then tag `v0.1.0.0`.

### Later (`spec/proposals.md`)
Not part of v1. Each one changes the semantics, so it needs a spec
update before any code:
- [x] `=>` (shared construction path).
- [ ] Naming an element (`Todos[id]#t`).
- [x] Alternatives in a pattern (`Page.{Home | Logs}`).
- [x] Branches on a shared path (`:: App => A -> B => C -> D`), with `/`
      chaining shared paths.
- [ ] Branches on a guard (`f :: T(Int#i) // i < 10 -> ... // i >= 10 -> ...`).
- [x] Annotations (`__annotations`), also on transitions: names
      checked, arguments opaque.
- [ ] Argument kinds for annotations (`@unless <pattern>`), and checking
      `@default` and `@range` (see proposals.md).
- [x] Layered specs (core and UI): `__imports`, qualified names, events
      that dispatch base events (`>>`) or react to them (see "Layered
      specs" in `spec/spec-v1.md`).
- [ ] Layered specs, more: occurrences and the "never dispatched"
      warning, several dispatches, modules (shared bases, transitive
      dispatch, `as`), splitting the drone example (see "Layered specs,
      more" in `spec/proposals.md`).
- [ ] The dispatch warning by coverage: warn when a dispatch's source can
      hold in some state where the event can't happen, not only when it
      excludes every source of the event.
- [x] Parvaz core: `parvaz/parvaz-core.sumspec`, the domain of
      `parvaz.sumspec` as a base spec (see `parvaz/NOTES.md`).
- [ ] Parvaz UI: `parvaz/parvaz-ui.sumspec`, a layer over the core; the
      patterns and reactions it needs are in `parvaz/NOTES.md`.
- [x] `__from`: projections, a layer's types that read a part of a base's
      state and are never written (see "Projections" in
      `spec/spec-v1.md`). Presentation goes on them, in the layer.
- [ ] `__from` takes its own rule, `type_path = type_name , [ "(" ,
      type_path , ")" ]`, instead of a `type_pattern` the checker then
      narrows down. A path with `*`, a variant step, a name, a key, a prime
      or alternatives becomes a syntax error. Steps:
      - `grammar.ebnf`: the rule, used in `type_def`; drop the "chain"
        clause from the checker notes.
      - `Syntax.hs`: `typeDefFrom :: Maybe (NonEmpty Name)`, outermost
        first. `Parser.hs`: `typePath`.
      - `Pretty.hs`: `renderTypePath` (`a(b(c))`), also used by
        `renderModel`. `qualifySpec` qualifies each name.
      - `Check.hs`: drop `chain` and its three messages; the base-type,
        start and factor checks stay.
      - LSP `Index.hs`: each name in the path is a type use.
      - `spec-v1.md`: the path is a chain of types, anything else a syntax
        error; adjust the checker's list.
      - Tests: move the `Chain` and `Variant` cases from
        `test/check/error-projections.sumspec` to
        `test/parse/error-from-chain.sumspec` (`core.Core(core.Todos * core.Link)`)
        and `test/parse/error-from-variant.sumspec` (`core.Core(core.Link.Up)`).
- [ ] Move Parvaz's presentation annotations (`@status`, `@view`,
      `@region`) from the core's types to the UI's projections.
- [ ] Computed projections (`:=`, Part B in `spec/efsm-gaps.md`): a value
      worked out from the base's data, such as a count or a route's length.
- [ ] A target adds or removes one element of a keyed list, instead of
      writing the whole list (`Missions'`).
- [ ] The overlap check reads `x == V` and `x != V` on a sum with payloads,
      as it does on an enumeration.
- [ ] `__const`: a named constant written with a keyword,
      `__const MaxPort = Port(100)`, so it no longer reads like a newtype
      and the parser needs no lookahead to tell it from a type (the
      "Constant or type" note in `grammar.ebnf`). Breaking before the
      first release: the plain `C = T(15)` form goes; migrate the drone
      example and the constants tests. Later, with literal patterns, a
      constant may also stand where a pattern goes (`Settings(DefaultPort)`).
- [x] `__pattern`: a named state pattern with parameters, expanded
      before checking: `__pattern Setting(v) = App(PlotEditor(core.Plot.Drawn(core.RouteSettings(v))))`,
      used as `Setting(v)`, the arguments separated by commas (see "Named
      patterns" in `spec/spec-v1.md`). The Parvaz core uses it.
- [ ] A layer uses a base's patterns (`core.ReadyToFly`), their bodies
      qualified as the base's events are.
- [ ] Warn about a `__pattern` that is never used; its body is checked
      only through its uses.
- [ ] Dependent types and generic types.
- [x] Arguments through a named product: a variant or a newtype that holds
      a named product takes the product's factors directly, one level
      only (see "Arguments in state patterns" in `spec/spec-v1.md`).
      Preferred over variant refinement and a type `__alias`.
- [ ] Variant refinement (`PMode.ShowMission = ...`): on hold, see
      "Arguments in state patterns" in `spec/spec-v1.md`.
- [ ] Several events with one transition (`g, h :: Y -> Z`).
- [ ] `<-` shorthand.
- [x] Named constants (`BatteryLowThreshold = BatteryCharge(15)`): in
      v1 as comparison sides in guards (see "Named constants" in
      `spec/spec-v1.md`).
- [x] Bare binding (`Attempts(#n)`): in v1 (see "Bare binding" in
      `spec/spec-v1.md`).
- [x] Membership in guards (`i in ids`): in v1 (see "Membership" in
      `spec/spec-v1.md`).
- [x] Equality on every type (`==` and `!=` on products, lists and sums
      with payloads): in v1 (see "Comparing values" in `spec/spec-v1.md`).
- [x] Arithmetic in targets (`Attempts(n + 1)`, `Attempts(0)`,
      `Attempts(n * 2)`, inside a head that holds one value): in v1 (see "Computed values" in
      `spec/spec-v1.md`).
- [ ] Arithmetic in guards, with the same expressions (see "Arithmetic,
      more" in `spec/proposals.md`).
- [ ] Literal patterns in sources, guards and inputs (see "Literal
      patterns" in `spec/proposals.md`); decide whether a literal may be
      a variant's payload directly, as a value in a target already is.
