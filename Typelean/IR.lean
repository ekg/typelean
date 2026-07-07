/-! # Typelean.IR

The typelean **intermediate representation**: an untyped, computational lambda
calculus that sits between Lean's elaborated `Lean.Expr` and the emitted
TypeScript. Types, proofs, and universe levels are erased here; what remains is
the runtime computational content (à la Lean's own `Lean.Compiler.LCNF`).

This is the stable contract between the Lower stage (`Lean.Expr → IR`) and the
Emit stage (`IR → TypeScript`); both are developed in parallel against this
shape (see `DESIGN.md` §2, §4, §5). The public type names `Expr`, `Decl`,
`Module` (plus the helper `Lit`) are the symbols downstream stages import.

Constructors:
* `var`, `lam`, `app`, `letE` — the pure lambda calculus (curried, call-by-value).
* `ctor` — a saturated constructor application (`name`, numeric `tag`, field
  `args`; type/proof args already erased by Lower).
* `lit` — a *typed* literal (see `Lit`): `Nat`/`Int`/`String`/`Char`/`Bool`.
  Emit renders each with the correct runtime constructor.
* `const` — a reference to a top-level declaration (mangled by Emit).
* `proj` — a structure field projection: `struct_` is (at runtime) a constructor
  object and `idx` is the 0-based field index (DESIGN §4.4, §5). -/

namespace Typelean.IR

/-- Typed IR literals.

`Nat`/`Int` carry arbitrary-precision values (Emit renders `Nat` as a runtime
`bigint`); `String`/`Char` carry their value directly (codepoint semantics);
`Bool` is a plain boolean. Replacing the previous stringly-typed
`lit (raw : String)` lets Lower preserve literal information and Emit emit the
correct runtime constructor without re-parsing. -/
inductive Lit where
  /-- A `Nat` literal (e.g. `42`); emitted as a runtime `bigint`. -/
  | natLit (n : Nat)
  /-- An `Int` literal (e.g. `-7`); emitted as a runtime `bigint`. -/
  | intLit (i : Int)
  /-- A `String` literal; emitted as a runtime string (codepoint semantics). -/
  | strLit (s : String)
  /-- A `Char` literal; emitted as a runtime Unicode code point. -/
  | charLit (c : Char)
  /-- A `Bool` literal; emitted as a JS `boolean`. -/
  | boolLit (b : Bool)
  deriving Inhabited, DecidableEq, BEq, Hashable

/-- IR expressions: untyped core terms produced by lowering and consumed by emit. -/
inductive Expr where
  /-- Local variable, referenced by name (lowering chooses a naming scheme). -/
  | var (name : String)
  /-- Lambda abstraction over a single parameter (curried). -/
  | lam (param : String) (body : Expr)
  /-- Application of a function to a single argument (curried). -/
  | app (fn arg : Expr)
  /-- `let name := value; body`. -/
  | letE (name : String) (value body : Expr)
  /-- Saturated constructor application: constructor `name` with numeric `tag`
      and field arguments `args` (type/proof args already erased). -/
  | ctor (name : String) (tag : Nat) (args : List Expr)
  /-- A typed literal value (see `Lit`). -/
  | lit (l : Lit)
  /-- Reference to a top-level declaration (mangled by Emit). -/
  | const (name : String)
  /-- Structure field projection: `struct_.{idx}`. At runtime `struct_` is a
      constructor object and `idx` is the 0-based field index (DESIGN §4.4, §5). -/
  | proj (struct_ : Expr) (idx : Nat)
  deriving Inhabited

/-- A top-level IR declaration: `name params* := body`. -/
structure Decl where
  /-- The (unmangled) declaration name; Emit mangles it into a TS identifier. -/
  name : String
  /-- Value parameters (curried); type/proof binders are erased by Lower. -/
  params : List String := []
  /-- The declaration body. -/
  body : Expr
  /-- Whether this declaration is (self-)recursive. Set by Lower when it detects
      a self-reference; read by Emit to choose a TCO-friendly form (a `function`
      declaration / trampoline) over a `const` arrow (DESIGN §11). Defaults to
      `false` so non-recursive decls are unaffected. The exact contract (a plain
      boolean vs. a richer `RecursionKind`) is tracked by the
      `typelean-ir-recursion-kind` follow-up subtask. -/
  isRec : Bool := false
  deriving Inhabited

/-- A whole IR module: an ordered list of declarations (topologically ordered by
    Lower so that dependencies precede dependents). -/
structure Module where
  decls : List Decl := []
  deriving Inhabited

/-! ## Pretty-printer

A deterministic, S-expression-style pretty-printer for `Lit`, `Expr`, `Decl`,
and `Module`, good enough for golden/snapshot tests and debugging. Every
constructor is fully parenthesized so nesting is unambiguous; string/char
literals are escaped (a minimal subset: `\`, the surrounding quote, and common
control chars).

The same renderer backs `toString` (via `ToString`) and `repr`/`#eval` (via
`Repr`), so debug output and golden output agree. -/

/-- Escape a string for inclusion inside a `"…"` IR literal. -/
private def escapeStr (s : String) : String :=
  String.ofList (s.toList.flatMap fun c =>
    match c with
    | '"'  => ['\\', '"']
    | '\\' => ['\\', '\\']
    | '\n' => ['\\', 'n']
    | '\t' => ['\\', 't']
    | '\r' => ['\\', 'r']
    | _    => [c])

/-- Escape a char for inclusion inside a `'…'` IR literal (quotes included). -/
private def escapeChar (c : Char) : String :=
  "'" ++ (match c with
    | '\'' => "\\'"
    | '\\' => "\\\\"
    | '\n' => "\\n"
    | '\t' => "\\t"
    | '\r' => "\\r"
    | _    => s!"{c}") ++ "'"

/-- Render a literal as `nat_lit 42` / `str_lit "hi"` / `bool_lit true` / … . -/
def Lit.toString : Lit → String
  | .natLit n  => s!"nat_lit {n}"
  | .intLit i  => s!"int_lit {i}"
  | .strLit s  => s!"str_lit \"{escapeStr s}\""
  | .charLit c => s!"char_lit {escapeChar c}"
  | .boolLit b => s!"bool_lit {b}"

/-- Render an expression as a fully-parenthesized S-expression. -/
def Expr.toString : Expr → String
  | .var name       => s!"(var {name})"
  | .lam param body => s!"(lam {param} {body.toString})"
  | .app fn arg     => s!"(app {fn.toString} {arg.toString})"
  | .letE name v b  => s!"(let {name} := {v.toString}; {b.toString})"
  | .ctor name tag args =>
    s!"(ctor {name} {tag} [{String.intercalate ", " (args.map Expr.toString)}])"
  | .lit l          => s!"(lit {l.toString})"
  | .const name     => s!"(const {name})"
  | .proj st idx    => s!"(proj {st.toString} {idx})"

/-- Render a declaration as `(decl name (params…) body)`. -/
def Decl.toString (d : Decl) : String :=
  s!"(decl {d.name} ({String.intercalate " " d.params}) {d.body.toString})"

/-- Render a module as `(module decl₁ decl₂ …)` with one declaration per line
    (or just `(module)` when empty). -/
def Module.toString (m : Module) : String :=
  match m.decls with
  | [] => "(module)"
  | ds => "(module\n" ++ String.intercalate "\n" (ds.map fun d => "  " ++ Decl.toString d) ++ ")"

/-- Pretty-printing goes through `ToString` (for `toString` / `s!"{}"`) and
    `Repr` (for `repr` / `#eval`), both delegating to the `toString` renderer
    above so the two views never disagree. -/
instance : ToString Lit    := ⟨Lit.toString⟩
instance : ToString Expr    := ⟨Expr.toString⟩
instance : ToString Decl    := ⟨Decl.toString⟩
instance : ToString Module  := ⟨Module.toString⟩

instance : Repr Lit    := ⟨fun a _ => Lit.toString a⟩
instance : Repr Expr    := ⟨fun a _ => Expr.toString a⟩
instance : Repr Decl    := ⟨fun a _ => Decl.toString a⟩
instance : Repr Module  := ⟨fun a _ => Module.toString a⟩

end Typelean.IR
