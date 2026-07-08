import Typelean.IR
import Typelean.Basic

/-! # Typelean.Emit

Pipeline **stage 3**: render typelean `IR` as a self-contained TypeScript
module (ESM `.mts`, runnable by Node type-stripping — DESIGN §1.3, §5). The
output is a single file: a `const _rt = { … }` runtime preamble (an identical
copy of `runtime/typelean_rt.ts`, inlined so the emitted file is runnable from
any working directory) followed by the compiled declarations and a driver call
to `main`.

Value model (mirrors `runtime/typelean_rt.ts`, DESIGN §5/§11):
* `ctor`  → `_rt.ctor(tag, [fields])`          (`{ _tag, _fields }`)
* `lit`   → `BigInt` for `Nat`/`Int`, JS string for `String`, `boolean` for `Bool`
* `const` → a runtime primitive (`_rt.<fn>`) for `@[extern]` stdlib constants,
            the mangled top-level binding for emitted user decls, or `undefined`
            for imported types/opaques that carry no runtime value
* `lam`/`app` → curried arrow functions / calls
* `proj`  → `(...)._fields[idx]`
* `switch` → an IIFE that dispatches on the scrutinee's runtime `_tag` -/

namespace Typelean.Emit
open Typelean.IR

/-! ## Runtime preamble

An identical copy of `runtime/typelean_rt.ts` (keep in lock-step). Inlined into
every emitted module so the output is self-contained. -/

/-- The runtime source, one line per element so `"` and `\` are escaped once at
    the Lean-string level rather than inside a giant raw literal. -/
def runtimeSource : String :=
  String.intercalate "\n"
  [ "const _rt = {"
  , "  ctor: (tag, fields) => ({ _tag: tag, _fields: fields }),"
  , "  natRepr: (n) => n.toString(),"
  , "  intRepr: (n) => (n < 0n ? \"-\" + (-n).toString() : n.toString()),"
  , "  strLength: (s) => [...s].length,"
  , "  strAppend: (a) => (b) => a + b,"
  , "  natAdd: (a) => (b) => a + b,"
  , "  natMul: (a) => (b) => a * b,"
  , "  natSub: (a) => (b) => (a > b ? a - b : 0n),"
  , "  natDiv: (a) => (b) => (b === 0n ? 0n : a / b),"
  , "  natMod: (a) => (b) => (b === 0n ? 0n : a % b),"
  , "  natBeq: (a) => (b) => a === b,"
  , "  println: (typeArg) => (inst) => (value) => () => { process.stdout.write(inst._fields[0](value) + \"\\n\"); },"
  , "  print: (typeArg) => (inst) => (value) => () => { process.stdout.write(inst._fields[0](value)); },"
  , "  run: (io) => io(),"
  , "};"
  ]

/-! ## Name mangling

Lean `Name`s (as `toString`) may contain `.`, numeric components, and macro
scopes. We sanitize to a valid TS identifier and prefix emitted decls/consts
with `typelean_` (injective, avoids collisions with JS keywords/`_rt`). IR
variable names from Lower (`binderBase_depth`, e.g. `n_0`, `__1`) are already
valid and need no prefix. -/

/-- True if `c` is a character legal in a TS identifier (post-first-char set,
    which is a superset of the first-char set for our purposes). -/
def isIdentChar (c : Char) : Bool :=
  c.isAlphanum || c == '_' || c == '$'

/-- Replace every char illegal in a TS identifier with `_`. -/
def sanitizeIdent (s : String) : String :=
  String.ofList (s.toList.map fun c => if isIdentChar c then c else '_')

/-- Mangle a decl/const Lean name (as `toString`) to a TS binding reference:
    `typelean_` ++ sanitized (dots → `_`). -/
def mangleDecl (s : String) : String :=
  "typelean_" ++ sanitizeIdent s

/-! ## Runtime primitive table

A mapping from Lean `@[extern]` stdlib constant names (as `toString`) to their
runtime implementations. Constants not in the table fall back to either an
emitted user-decl binding or `undefined` (an imported type/opaque with no
runtime value). DESIGN §9. -/

/-- Lean constant name (as `toString`) → runtime reference (`_rt.<fn>`). -/
def primTable : List (String × String) :=
  [ ("IO.println", "_rt.println")
  , ("IO.print",   "_rt.print")
  , ("Nat.repr",   "_rt.natRepr")
  , ("Int.repr",   "_rt.intRepr")
  , ("String.length", "_rt.strLength")
  , ("String.append", "_rt.strAppend")
  , ("Nat.add",    "_rt.natAdd")
  , ("Nat.mul",    "_rt.natMul")
  , ("Nat.sub",    "_rt.natSub")
  , ("Nat.div",    "_rt.natDiv")
  , ("Nat.mod",    "_rt.natMod")
  , ("Nat.beq",    "_rt.natBeq")
  ]

/-- Look up a constant name in the primitive table. -/
def primOf (n : String) : Option String :=
  primTable.lookup n

/-! ## String literal escaping

Render an IR `String` literal as a double-quoted JS string literal, escaping
the characters that would break the literal or change its meaning. -/

/-- Escape one char for inclusion in a `"…"` JS string. -/
def escapeJsChar (c : Char) : String :=
  match c with
  | '"'  => "\\\""
  | '\\' => "\\\\"
  | '\n' => "\\n"
  | '\r' => "\\r"
  | '\t' => "\\t"
  | c =>
    if c.toNat < 32 then "\\u{" ++ toString c.toNat ++ "}"  -- control chars
    else toString c

/-- Render a TS string literal for `s`: `"…escaped…"`. -/
def jsStringLit (s : String) : String :=
  "\"" ++ String.ofList (s.toList.flatMap (fun c => (escapeJsChar c).toList)) ++ "\""

/-! ## Expression emission -/

/-- Emit a TS expression for an IR expression. `declNames` is the set of
    emitted user-declaration names (as `toString`), used to resolve `const`
    references to emitted bindings vs runtime primitives vs `undefined`. -/
partial def emitExpr (declNames : List String) : Expr → String
  | .var n        => sanitizeIdent n
  | .lam p b     => "((" ++ sanitizeIdent p ++ ") => " ++ emitExpr declNames b ++ ")"
  | .app f a     => "(" ++ emitExpr declNames f ++ ")(" ++ emitExpr declNames a ++ ")"
  | .letE n v b  =>
    "(() => { const " ++ sanitizeIdent n ++ " = " ++ emitExpr declNames v
      ++ "; return " ++ emitExpr declNames b ++ " })()"
  | .ctor _ tag args =>
    "_rt.ctor(" ++ toString tag ++ ", ["
      ++ String.intercalate ", " (args.map (emitExpr declNames)) ++ "])"
  | .lit l => match l with
    | .natLit n  => toString n ++ "n"
    | .intLit i  => toString i ++ "n"
    | .strLit s  => jsStringLit s
    | .charLit c => toString c.toNat ++ "n"
    | .boolLit b => toString b
  | .const n =>
    match primOf n with
    | some rt => rt
    | none =>
      if declNames.contains n then mangleDecl n
      else "undefined"
  | .proj st idx => "(" ++ emitExpr declNames st ++ ")._fields[" ++ toString idx ++ "]"
  | .switch scrut self cases default =>
    let scrutE := emitExpr declNames scrut
    let caseStrs := cases.map fun c =>
      let fields := String.intercalate ", " (c.params.map sanitizeIdent)
      "    case " ++ toString c.tag ++ ": {"
        ++ (if c.params.isEmpty then "" else " const [" ++ fields ++ "] = __v._fields;")
        ++ " return " ++ emitExpr declNames c.body ++ "; }"
    let defaultStr := match default with
      | some d => "    default: { return " ++ emitExpr declNames d ++ "; }"
      | none   => "    default: { throw new Error(\"typelean: non-exhaustive switch\"); }"
    "(() => { const __v = " ++ scrutE ++ "; switch (__v._tag) {\n"
      ++ String.intercalate "\n" caseStrs ++ "\n" ++ defaultStr
      ++ "\n  } })()"

/-! ## Declaration emission -/

/-- Emit one top-level declaration. Recursive decls (`isRec`) use a hoisted
    `function` so they can self-reference (DESIGN §5/§11); others use `const`.
    Curried params are rendered as a single arrow `((p1) => (p2) => body)`. -/
def emitDecl (declNames : List String) (d : Decl) : String :=
  let name := mangleDecl d.name
  let body := emitExpr declNames d.body
  match d.params, d.isRec with
  | [], false =>
    "const " ++ name ++ " = " ++ body ++ ";"
  | [], true =>
    "function " ++ name ++ "() { return " ++ body ++ "; }"
  | ps, true =>
    "function " ++ name ++ "(" ++ String.intercalate ", " (ps.map sanitizeIdent) ++ ") { return " ++ body ++ "; }"
  | ps, false =>
    -- curried arrow: (p1) => (p2) => body
    let lam := ps.foldr (fun p acc => "(" ++ sanitizeIdent p ++ ") => " ++ acc) body
    "const " ++ name ++ " = " ++ lam ++ ";"

/-! ## Module emission -/

/-- Emit a complete self-contained TypeScript module: runtime preamble, the
    topologically-ordered declarations, and a driver call to `main` (an IO
    thunk) if present. -/
def emitModule (m : Module) : String :=
  let declNames := m.decls.map (·.name)
  let header := "// typelean-emitted (M1) — self-contained ES module.\n" ++ runtimeSource
  let decls := m.decls.map (emitDecl declNames)
  let driver :=
    if declNames.contains "main" then "\n\n" ++ mangleDecl "main" ++ "();" else ""
  header ++ "\n\n" ++ String.intercalate "\n\n" decls ++ driver ++ "\n"

end Typelean.Emit
