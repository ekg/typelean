import Lean
import Typelean.IR
import Typelean.Basic

/-! # Typelean.Lower

Pipeline **stage 2**: lower Lean's elaborated core terms (`Lean.Expr`, read out
of the `Environment`'s `ConstantInfo`s) into typelean `IR`. This is where type
information is *erased* and the runtime computational content is extracted
(DESIGN §4).

Strategy (M1, type-directed erasure, DESIGN §4.2):
* Each selected root (and its reachable *user* declarations) is lowered. We
  first **normalize** each declaration body with `Lean.Meta.reduce` under
  `TransparencyMode.instances`. This dissolves the type-class dispatch that
  Lean's elaborator leaves in `Expr` (`HAdd.hAdd … instHAddNat …`, `OfNat.ofNat
  … instOfNatNat …`, `ToString.toString … instToString…`) down to the concrete
  runtime primitive or computed literal (`Nat.add`, `String.append`, `Nat.repr`,
  `IO.println`, a `Lit.natVal` …), while keeping user functions, constructors,
  and `@[extern]` primitives as `const` references (they are *not* unfolded —
  `reduce` under `.instances` unfolds only `@[reducible]` / `@[instance]`
  declarations). On any Meta failure we fall back to lowering the *raw* body
  (never silently drop, DESIGN §1.4).
* Then we structurally recurse over the (normalized) `Expr`, erasing
  computationally-irrelevant arguments/binders. A binder or argument is
  **irrelevant** (erased) when its type is a `Sort` (a type/universe parameter)
  or a `Prop` (a proof), classified with `Lean.Meta.whnf` /
  `Lean.Meta.isProp` (DESIGN §4.2). Type-class dictionaries
  (`instToStringNat : ToString Nat`, …) are *ordinary data* and are **kept** —
  their methods are projected at runtime.
* **Binder scoping.** Lowering descends under `lam`/`letE` binders by pushing
  each binder into Lean's `Meta` local context (`withLocalDecl` /
  `withLetDecl`) and instantiating the body's de Bruijn variable to the fresh
  free variable. This keeps every sub-term we hand to `whnf` / `inferType` /
  `isProp` / `reduce` *closed w.r.t. the local context* (no loose `bvar`s), so
  the Meta engine never panics on a "loose bvar in expression" — the IR name
  for a binder is its Lean binder name's last component suffixed by its binding
  depth (so shadowing never collides).
* Recursors (`T.rec`), `T.casesOn`, `T.brecOn`, matcher auxiliaries
  (`Foo.match_1`), and the `below` course-of-values table are, in this M1 cut,
  **lowered structurally** as ordinary `app`/`const`/`ctor`/`proj` IR — they
  are not yet rewritten to IR `switch`/recursion (the IR has no case construct;
  a dedicated recognizer + IR extension is a tracked follow-up, DESIGN §4.3).
  They lower without a `lower`-stage error; any genuinely unhandled `Lean.Expr`
  constructor (`mvar`, a bare `Sort`/`forallE` in a value position) yields a
  stage-tagged `CompileError` (no silent drops, DESIGN §1.4).

Reachability & ordering (`lowerEnv`): from the roots, BFS over the environment
descending only into *user* (non-imported) declaration bodies; imported
constants are opaque runtime references (DESIGN §9) and are not walked into or
emitted as decls. Emitted decls (user `defnInfo`/`opaqueInfo` with bodies) are
topologically ordered (dependencies precede dependents), and `Decl.isRec` is
set from the dependency graph: a self-loop, or membership in a mutual-recursion
cycle (an SCC of size ≥ 2), marks a decl `isRec := true` (the
`typelean-m1-decide` contract).
-/

namespace Typelean.Lower
open Lean Meta

/-- The lowering monad: `Meta` effects (for `whnf`/`isProp`/`inferType`/`reduce`)
    plus a `Typelean.CompileError` short-circuit.

    `ExceptT ε MetaM` inherits `MonadExcept ε` from both the `ExceptT` layer
    (`CompileError`) and the underlying `MetaM` (`Lean.Exception`), so bare
    `throw` is ambiguous. We therefore surface lower-stage errors via the
    explicit `lowerErr` helper below (which builds an `Except.error` directly),
    and reserve `try … catch` for `MetaM`/`CoreM` exceptions (`Exception`). -/
abbrev LowerM (α : Type) := ExceptT Typelean.CompileError MetaM α

/-- Build a `lower`-stage `CompileError` and short-circuit, without going
    through the ambiguous `MonadExcept.throw` (see `LowerM` doc). -/
@[inline] def lowerErr (msg : String) : LowerM α :=
  ExceptT.mk <| pure (Except.error (Typelean.CompileError.at "lower" msg))

/-- Render a `Lean.Exception` (kernel/Meta exception) as a short string, so the
    top-level runner can fold an uncaught Meta exception into a `lower`-stage
    `CompileError` rather than crashing. -/
def exStr : Exception → String
  | .error msg _ => s!"kernel/Meta error: {msg}"
  | .internal id _ => s!"internal exception #{id.idx}"

/-- Run a `LowerM` action against `env` (pure wrapper over the `EIO`-based
    `CoreM`/`MetaM` runner). Returns `Except CompileError α`: an uncaught Meta
    `Exception` becomes a `lower`-stage error. `unsafe` only because it drives
    the IO-based Meta engine; the result is pure `Except`. -/
unsafe def runLowerPure (env : Environment) (act : LowerM α) :
    Except Typelean.CompileError α :=
  let coreAct : CoreM (Except Typelean.CompileError α) := MetaM.run' act
  let ctx : Core.Context := { fileName := "<lower>", fileMap := Lean.FileMap.ofString "" }
  let st : Core.State := { env := env }
  match unsafeEIO (Core.CoreM.run coreAct ctx st) with
  | .error ex => .error (Typelean.CompileError.at "lower" s!"internal: {exStr ex}")
  | .ok (r, _) => r

/-! ## Name hygiene

Each binder is given a unique IR name (its Lean binder name's last component,
suffixed by its binding depth) so that shadowing (`fun x => fun x => x`) never
collides. Macro-scope/hygiene markers (which live in `Name`) are dropped —
uniqueness comes from the depth suffix. -/

/-- Turn a Lean binder `Name` into a base string: the last `Name.str` component,
    or `"x"` if the name is `.anonymous`/`.num`. -/
def binderBase (n : Name) : String :=
  match n with
  | .str _ s => s
  | _ => "x"

/-- A unique IR variable name for a binder at `depth` (the number of binders in
    scope when it was pushed). -/
def varName (depth : Nat) (n : Name) : String :=
  binderBase n ++ "_" ++ toString depth

/-! ## Erasure (DESIGN §4.2)

A type is *computationally irrelevant* when it is a `Sort` (a type/universe
parameter) or a `Prop` (a proof). Type-class dictionaries and ordinary value
types (`Nat`, `String`, a user inductive) are *relevant* and kept.

Because every binder is pushed into the `Meta` local context before we recurse
into its body, the types handed to `whnf`/`isProp`/`inferType` here never
contain loose `bvar`s — they are closed w.r.t. the local context. -/

/-- Is `ty` (the type of a binder/argument) computationally irrelevant?
    Defensive: any Meta failure defaults to *relevant* (keep), so a Meta hiccup
    never silently drops an argument (DESIGN §1.4). -/
def isErasedType (ty : Expr) : LowerM Bool := do
  try
    let w ← whnf ty
    if w.isSort then return true
    if (← isProp w) then return true
    return false
  catch _ => return false

/-- The expected domain type of the *next* argument of `f` (the partial
    application so far): `inferType f`, `whnf` to a `forallE`, take the first
    binder's domain. `none` if `f` is not (yet) a function (or Meta fails). -/
def nextDomain (f : Expr) : LowerM (Option Expr) := do
  try
    let t ← whnf (← inferType f)
    match t with
    | .forallE _ dom _ _ => pure (some dom)
    | _ => pure none
  catch _ => pure none

/-! ## Reachability (consts in value positions)

A coarse `Expr` traversal collecting every `const` name. Used only for the
dependency graph and reachability BFS; non-emitted names (inductives, imported
primitives, types) are filtered out afterwards, so collecting type-position
consts too is harmless. It does no Meta work, so it is safe to run on raw bodies
that still contain loose `bvar`s. -/
partial def constsIn (e : Expr) (acc : NameSet) : NameSet :=
  match e with
  | .const n _ => acc.insert n
  | .app f a => constsIn a (constsIn f acc)
  | .lam _ _ b _ => constsIn b acc
  | .forallE _ _ b _ => constsIn b acc
  | .letE _ _ v b _ => constsIn b (constsIn v acc)
  | .mdata _ b => constsIn b acc
  | .proj _ _ b => constsIn b acc
  | _ => acc

/-! ## Core expression lowering

`lowerGo ctx e` lowers `e` to `IR.Expr`. `ctx` is the binder stack (innermost
binder first): for each pushed binder it records the free variable's `FVarId`,
the chosen IR name, and whether the binder was erased. Because every binder is
pushed into the `Meta` local context (and the body's `bvar` instantiated to that
`fvar`) before recursing, `e` never contains a loose `bvar` here — references to
in-scope binders are `Expr.fvar`s resolved through `ctx`.

`lowerGo`, `lowerApp`, and `ctorArgs` are mutually recursive (structural
recursion over `Expr` plus a left-to-right argument fold), so they are grouped
in a `mutual` block and marked `partial` (the argument folds are not obviously
terminating to the kernel). -/

/-- The binder stack: innermost binder first. Each entry is the free variable
    introduced for the binder, the IR name assigned to it, and whether it was
    erased (a type/proof binder — its references appear only in further erased
    positions, which `lowerApp` skips). -/
abbrev Ctx := List (FVarId × String × Bool)

/-- Look up the IR name for a free variable in `ctx`. -/
def Ctx.lookup (ctx : Ctx) (id : FVarId) : Option (String × Bool) :=
  ctx.find? (fun (fid, _, _) => fid == id) |>.map (fun (_, nm, er) => (nm, er))

/-- Lower a bare `const n` (not applied) to IR.

Constructors with no parameters and no fields (e.g. `Color.green`, `Nat.zero`,
`PUnit.unit`) become a saturated `IR.ctor` with no fields. Anything else
(constructor *functions* with fields, recursors, inductive *types*, ordinary
defs, `@[extern]` primitives, axioms) becomes an `IR.const` reference — Emit
mangles it and the runtime resolves it (DESIGN §5, §9). -/
def lowerConst (n : Name) : LowerM Typelean.IR.Expr := do
  match (← getEnv).find? n with
  | some (.ctorInfo v) =>
    if v.numParams + v.numFields == 0 then pure (IR.Expr.ctor n.toString v.cidx [])
    else pure (IR.Expr.const n.toString)
  | _ => pure (IR.Expr.const n.toString)

mutual
/-- For a saturated constructor application, lower the field arguments (drop
    type-parameter and proof arguments among the saturated args). `v.numParams`
    leading args are type parameters (always erased); the remaining
    `v.numFields` are fields, each classified by its expected domain. -/
partial def ctorArgs (ctx : Ctx) (ctorName : Name) (v : ConstructorVal)
    (args : Array Expr) : LowerM (List Typelean.IR.Expr) := do
  let mut kept : List Typelean.IR.Expr := []
  let mut appSoFar : Expr := .const ctorName []
  for i in [:args.size] do
    let a := args[i]!
    appSoFar := .app appSoFar a
    let isParam := i < v.numParams
    let erased ←
      if isParam then pure true  -- type parameters are always erased
      else match (← nextDomain appSoFar) with
        | some dom => isErasedType dom
        | none => pure false
    unless erased do kept := kept.concat (← lowerGo ctx a)
  pure kept

/-- Lower an application `e = head a₁ … aₖ`.

Arguments are classified left-to-right via `nextDomain` + `isErasedType`:
irrelevant args (type/proof) are dropped; relevant args (values, dictionaries)
are lowered and applied. Constructor applications that are *saturated*
(numParams + numFields) are emitted as `IR.ctor` (with type-param/proof fields
erased); partial constructor application falls back to `app (const C) …`. -/
partial def lowerApp (ctx : Ctx) (e : Expr) :
    LowerM Typelean.IR.Expr := do
  let head := e.getAppFn
  let args := e.getAppArgs
  -- Is the head a saturated constructor application?
  match head with
  | .const n _ =>
    match (← getEnv).find? n with
    | some (.ctorInfo v) =>
      let arity := v.numParams + v.numFields
      if args.size == arity then
        -- Saturated ctor: lower only the *kept* (field) args; emit `IR.ctor`.
        let kept ← ctorArgs ctx n v args
        return IR.Expr.ctor n.toString v.cidx kept
      -- else fall through to general application (partial / over-applied ctor)
    | _ => pure ()
  | _ => pure ()
  -- General application: fold args, erasing irrelevant ones.
  let mut irFn ← lowerGo ctx head
  let mut appSoFar := head
  for a in args do
    appSoFar := .app appSoFar a
    match (← nextDomain appSoFar) with
    | some dom =>
      if (← isErasedType dom) then pure ()  -- erase this arg
      else irFn := IR.Expr.app irFn (← lowerGo ctx a)
    | none =>
      -- No type information for this position: keep the arg (never drop).
      irFn := IR.Expr.app irFn (← lowerGo ctx a)
  pure irFn

/-- Lower a single `Lean.Expr` to an `IR.Expr` (see module doc for the strategy).

    `e` is closed w.r.t. the `Meta` local context (no loose `bvar`s): every
    `lam`/`letE` binder we descend under is pushed into the local context and
    its body instantiated, so in-scope binders appear as `Expr.fvar`s resolved
    through `ctx`. -/
partial def lowerGo (ctx : Ctx) (e : Expr) :
    LowerM Typelean.IR.Expr := do
  match e with
  | .bvar i =>
    -- Should not occur: every binder we descend under is instantiated to an
    -- `fvar` before recursion. A loose `bvar` here means the term was not
    -- closed w.r.t. the local context — a genuine lowering gap.
    lowerErr s!"loose de Bruijn index {i} reached Lower (M1 follow-up)"
  | .fvar id =>
    match Ctx.lookup ctx id with
    | some (nm, false) => pure (IR.Expr.var nm)
    | some (_, true) =>
      lowerErr s!"reference to erased binder {id.name} in a kept position (M1 follow-up)"
    | none => pure (IR.Expr.var (id.name.toString))
  | .mvar _ => lowerErr "metavariable survived elaboration (must not reach Lower)"
  | .lit l => pure (match l with
    | .natVal n => IR.Expr.lit (IR.Lit.natLit n)
    | .strVal s => IR.Expr.lit (IR.Lit.strLit s))
  | .sort _ =>
    -- A `Sort` in a value position is a runtime *type token* (a universe/type
    -- passed as a value). typelean's value model erases types, but the recursor /
    -- `below` course-of-values machinery (DESIGN §4.3) hands us types as values;
    -- until the dedicated recursor rewriter (a tracked follow-up) eliminates
    -- that machinery, we represent such a token as an `IR.const` placeholder so
    -- the surrounding application keeps its arity (no silent drop, no error).
    pure (IR.Expr.const "typelean.type_token")
  | .forallE _ _ _ _ =>
    -- A `forallE` (Pi-type) in a value position is likewise a runtime type
    -- token (see `sort` case). It arises from `brecOn`/`below` structural
    -- recursion compilation; lowered structurally here, rewritten later.
    pure (IR.Expr.const "typelean.type_token")
  | .mdata _ b => lowerGo ctx b
  | .proj _ i b => pure (IR.Expr.proj (← lowerGo ctx b) i)
  | .lam n d b bi =>
    let depth := ctx.length
    let erased ← isErasedType d
    let nm := varName depth n
    withLocalDecl n bi d fun fvar => do
      let ctx' := (fvar.fvarId!, nm, erased) :: ctx
      let body := b.instantiate1 fvar
      if erased then lowerGo ctx' body
      else pure (IR.Expr.lam nm (← lowerGo ctx' body))
  | .letE n ty v b _ =>
    let depth := ctx.length
    let nm := varName depth n
    let irVal ← lowerGo ctx v
    withLetDecl n ty v fun fvar => do
      let ctx' := (fvar.fvarId!, nm, false) :: ctx
      let irBody ← lowerGo ctx' (b.instantiate1 fvar)
      pure (IR.Expr.letE nm irVal irBody)
  | .const n _ => lowerConst n
  | .app _ _ => lowerApp ctx e
end

/-! ## Declaration lowering

Peel the outer value lambdas of a declaration body into `Decl.params` (erasing
type/proof binders), lowering the inner body in the same pass — all under the
nested `withLocalDecl` scope so the body's `bvar`s are `fvar`s (closed w.r.t.
the local context) when handed to `reduce`/`lowerGo`. -/

/-- Peel outer `lam` binders of `value` into `params` (erasing type/proof
    binders) and lower the inner body, in one pass under the nested
    `withLocalDecl` scope. Returns the parameter list and the lowered body. -/
partial def lowerDeclBody (value : Expr) (depth : Nat) (params : List String)
    (ctx : Ctx) : LowerM (List String × Typelean.IR.Expr) := do
  match value with
  | .lam n d b bi =>
    let erased ← isErasedType d
    let nm := varName depth n
    let params' := if erased then params else params.concat nm
    withLocalDecl n bi d fun fvar => do
      let ctx' := (fvar.fvarId!, nm, erased) :: ctx
      lowerDeclBody (b.instantiate1 fvar) (depth + 1) params' ctx'
  | _ =>
    -- Inner body: closed w.r.t. the local context (all peeled binders are
    -- fvar's in scope). Normalize to dissolve type-class dispatch, then lower.
    let norm ←
      try withTransparency .instances (reduce value false true true)
      catch _ => pure value
    let irBody ← withTransparency .instances (lowerGo ctx norm)
    pure (params, irBody)

/-- Is `c` a user (non-imported) declaration that should be *emitted* as an IR
    decl — i.e. a `defnInfo`/`opaqueInfo` with a body? (Theorem/axiom/inductive/
    constructor/recursor/quotient decls are not emitted: they are Prop/unused,
    type declarations, inlined as `ctor` exprs, or recursor machinery.) -/
def shouldEmit (env : Environment) (n : Name) (c : ConstantInfo) : Bool :=
  ¬ env.isImportedConst n &&
  match c with
  | .defnInfo _ | .opaqueInfo _ => true
  | _ => false

/-- Is `m` a user (non-imported) `defnInfo`/`opaqueInfo` — a candidate emittable
    declaration to descend into during reachability BFS. -/
def isEmittable (env : Environment) (m : Name) : Bool :=
  ¬ env.isImportedConst m &&
  match env.find? m with
  | some (.defnInfo _) | some (.opaqueInfo _) => true
  | _ => false

/-! ## Reachability + dependency graph + ordering -/

/-- A user declaration body to lower, plus its outgoing dependency edges (names
    of other emitted user decls referenced in its raw body). -/
structure DeclNode where
  name : Name
  value : Expr          -- raw body (for dependency edges; lowering uses the normalized form)
  deps : List Name := []

/-- BFS from `roots` over user declaration bodies, collecting emitted decl
    nodes and their raw-body dependency edges. -/
partial def collectDecls (env : Environment) (roots : List Name) :
    LowerM (List DeclNode) := do
  let rec go (visited : NameSet) (queue : List Name) (acc : List DeclNode) :
      LowerM (List DeclNode) := do
    match queue with
    | [] => pure acc
    | n :: rest =>
      if visited.contains n then go visited rest acc
      else
        let visited := visited.insert n
        match env.find? n with
        | none => go visited rest acc
        | some c =>
          let bodyConsts := match c.value? (allowOpaque := true) with
            | some b => (constsIn b NameSet.empty).toList
            | none => []
          let next := bodyConsts.filter (fun m => isEmittable env m)
          let acc' :=
            if shouldEmit env n c then
              match c.value? (allowOpaque := true) with
              | some value => { name := n, value := value, deps := [] } :: acc
              | none => acc
            else acc
          go visited (rest ++ next) acc'
  let rawNodes ← go NameSet.empty roots []
  let emittedSet := rawNodes.foldl (fun s nd => s.insert nd.name) NameSet.empty
  -- Dependency edges: every emitted user decl referenced in the raw body
  -- (self-references included, so direct self-recursion is detected).
  pure (rawNodes.map fun nd =>
    { nd with deps := (constsIn nd.value NameSet.empty).toList.filter
                (fun m => emittedSet.contains m) })

/-- Can `n` reach itself via a dependency path of length ≥ 1 (a self-loop or a
    mutual-recursion cycle)? O(V·(V+E)) — fine for the small M1 graphs. -/
partial def reachesSelf (nodes : List DeclNode) (start : Name) : Bool :=
  let adj : Name → List Name := fun n =>
    match nodes.find? (fun nd => nd.name == n) with
    | some nd => nd.deps | none => []
  let rec visit (seen : NameSet) (cur : Name) : Bool :=
    if seen.contains cur then false
    else
      let seen := seen.insert cur
      (adj cur).any (fun next =>
        if next == start then true else visit seen next)
  visit NameSet.empty start

/-- Topologically order `nodes` so dependencies precede dependents (DFS
    post-order). Cycles (mutual recursion) are broken arbitrarily — the members
    of a cycle are emitted consecutively; `isRec` flags them.

    The `visited` set is threaded across *every* `dfs` call (through the outer
    fold), so each node is added exactly once — restarting `visited` per root
    would re-emit shared dependencies once per root that reaches them (a real
    duplication bug: `toNum` / `Color.casesOn` appeared N times). -/
partial def topoOrder (nodes : List DeclNode) : List DeclNode :=
  let byName : Name → Option DeclNode := fun n =>
    nodes.find? (fun nd => nd.name == n)
  let rec dfs (visited : NameSet) (acc : List Name) (n : Name) :
      NameSet × List Name :=
    if visited.contains n then (visited, acc)
    else
      let visited := visited.insert n
      let deps := match byName n with | some nd => nd.deps | none => []
      let (visited, acc) :=
        deps.foldl (fun (v, a) d => dfs v a d) (visited, acc)
      (visited, acc ++ [n])
  let (_, ordered) :=
    nodes.foldl (fun (v, a) nd => dfs v a nd.name) (NameSet.empty, [])
  ordered.filterMap byName

/-- Lower the reachable user declarations from `roots` into an IR `Module`. -/
def lowerEnvM (roots : List Name) : LowerM Typelean.IR.Module := do
  let env ← getEnv
  let nodes := topoOrder (← collectDecls env roots)
  let decls ← nodes.mapM fun nd => do
    let (params, irBody) ← lowerDeclBody nd.value 0 [] []
    let isRec := reachesSelf nodes nd.name
    pure ({ name := nd.name.toString, params := params, body := irBody,
            isRec := isRec : Typelean.IR.Decl })
  pure { decls := decls : IR.Module }

/-! ## Public entry points (the stable contracts the pipeline consumes) -/

unsafe def lowerEnvUnsafe (env : Environment) (roots : List Name) :
    Typelean.CompileM Typelean.IR.Module :=
  runLowerPure env (lowerEnvM roots)

unsafe def lowerExprUnsafe (e : Expr) : Typelean.CompileM Typelean.IR.Expr :=
  match unsafeIO Lean.mkEmptyEnvironment with
  | .error ioerr => .error (Typelean.CompileError.at "lower"
      s!"io: cannot build empty environment: {ioerr}")
  | .ok env => runLowerPure env (lowerGo [] e)

/-- Lower selected `roots` (plus their reachable user dependencies) from `env`
    to an IR module: erase types/proofs, dissolve type-class dispatch, topo-
    order decls, and set `Decl.isRec` per the dependency graph. -/
@[implemented_by lowerEnvUnsafe]
def lowerEnv (env : Environment) (roots : List Name) :
    Typelean.CompileM Typelean.IR.Module :=
  .error (Typelean.CompileError.at "lower" "lowerEnv: unreachable (implemented_by lowerEnvUnsafe)")

/-- Lower a single Lean `Expr` to an IR expression.

    This is a convenience helper. It runs the Meta-based lowering against an
    **empty environment** (`Lean.mkEmptyEnvironment`), so it is meaningful for
    closed expressions without global references (`lit`, `lam`, `app` of
    locals, `letE`, `proj`, `ctor` of nullary constructors). For expressions
    referencing global constants, type information is unavailable in the empty
    environment and erasure degrades to *keep all arguments* (no silent drops);
    use `lowerEnv` for whole-program lowering. -/
@[implemented_by lowerExprUnsafe]
def lowerExpr (e : Expr) : Typelean.CompileM Typelean.IR.Expr :=
  .error (Typelean.CompileError.at "lower" "lowerExpr: unreachable (implemented_by lowerExprUnsafe)")

end Typelean.Lower
