import Typelean.IR

/-! # Typelean.IR.Test — compile-time tests for the typelean IR

This module exercises every constructor of `Typelean.IR.Expr` and `Lit`, every
field of `Decl`/`Module`, and asserts pretty-print output plus structural
invariants. Every assertion is a build-failing check: a `#guard` (which
evaluates a `Bool` and errors if it is `false`) or a `native_decide` proof. If
the IR or its pretty-printer drifts, this file stops compiling, failing the
build.

Run directly (the integrator later wires it into `lake test`; see
`PROTOCOL.md` / `ROADMAP.md` M1):

    lake env lean Typelean/IR/Test.lean
-/

open Typelean.IR

/-! ## Literals — every `Lit` constructor -/

#guard (Lit.toString (.natLit 0)    == "nat_lit 0")
#guard (Lit.toString (.natLit 42)   == "nat_lit 42")
#guard (Lit.toString (.intLit 0)    == "int_lit 0")
#guard (Lit.toString (.intLit (-7)) == "int_lit -7")
#guard (Lit.toString (.strLit "")    == "str_lit " ++ "\"" ++ "\"")
#guard (Lit.toString (.strLit "hi") == "str_lit " ++ "\"" ++ "hi" ++ "\"")
-- a newline in the payload is escaped to backslash-n
#guard (Lit.toString (.strLit "\n")   == "str_lit " ++ "\"" ++ "\\" ++ "n" ++ "\"")
#guard (Lit.toString (.strLit "a\nb") == "str_lit " ++ "\"" ++ "a" ++ "\\" ++ "n" ++ "b" ++ "\"")
-- a quote and a backslash in the payload are escaped
#guard (Lit.toString (.strLit "a\"b") == "str_lit " ++ "\"" ++ "a" ++ "\\" ++ "\"" ++ "b" ++ "\"")
#guard (Lit.toString (.strLit "x\\y") == "str_lit " ++ "\"" ++ "x" ++ "\\" ++ "\\" ++ "y" ++ "\"")
#guard (Lit.toString (.charLit 'a')  == "char_lit " ++ "'" ++ "a" ++ "'")
#guard (Lit.toString (.charLit '\n') == "char_lit " ++ "'" ++ "\\" ++ "n" ++ "'")
#guard (Lit.toString (.charLit '\\') == "char_lit " ++ "'" ++ "\\" ++ "\\" ++ "'")
#guard (Lit.toString (.charLit '\'') == "char_lit " ++ "'" ++ "\\" ++ "'" ++ "'")
#guard (Lit.toString (.boolLit true)  == "bool_lit true")
#guard (Lit.toString (.boolLit false) == "bool_lit false")

-- structural equality on `Lit` (BEq / DecidableEq derived on the non-recursive type)
#guard ((.natLit 1 : Lit) == .natLit 1)
#guard ((.boolLit true : Lit) == .boolLit true)
#guard ((.strLit "x" : Lit) == .strLit "x")
#guard ((.intLit (-7) : Lit) == .intLit (-7))
#guard ((.charLit 'a' : Lit) == .charLit 'a')
#guard (decide (¬ ((.natLit 1 : Lit) = .natLit 2)))
#guard (decide (¬ ((.boolLit true : Lit) = .boolLit false)))
#guard (decide (¬ ((.strLit "x" : Lit) = .strLit "y")))

/-! ## `Expr` — every constructor (incl. the typed `lit` and the new `proj`) -/

#guard (Expr.toString (.var "x")              == "(var x)")
#guard (Expr.toString (.const "Nat.add")      == "(const Nat.add)")
#guard (Expr.toString (.lit (.natLit 7))      == "(lit nat_lit 7)")
#guard (Expr.toString (.lit (.intLit (-3)))   == "(lit int_lit -3)")
#guard (Expr.toString (.lit (.boolLit true))  == "(lit bool_lit true)")
#guard (Expr.toString (.lit (.strLit "ok"))   == "(lit str_lit \"ok\")")
#guard (Expr.toString (.lit (.charLit 'z'))   == "(lit char_lit 'z')")
#guard (Expr.toString (.lam "x" (.var "x"))   == "(lam x (var x))")
#guard (Expr.toString (.app (.var "f") (.var "a")) == "(app (var f) (var a))")
#guard (Expr.toString (.letE "x" (.lit (.natLit 1)) (.var "x"))
        == "(let x := (lit nat_lit 1); (var x))")
#guard (Expr.toString (.ctor "Nat.zero" 0 []) == "(ctor Nat.zero 0 [])")
#guard (Expr.toString (.ctor "Prod.mk" 0 [.lit (.natLit 1), .lit (.natLit 2)])
        == "(ctor Prod.mk 0 [(lit nat_lit 1), (lit nat_lit 2)])")
#guard (Expr.toString (.proj (.var "s") 0)    == "(proj (var s) 0)")
#guard (Expr.toString (.proj (.const "p") 2)  == "(proj (const p) 2)")

-- a nested term: a self-application applied to the identity
#guard (Expr.toString
          (.app (.lam "x" (.app (.var "x") (.var "x")))
                (.lam "y" (.var "y")))
        == "(app (lam x (app (var x) (var x))) (lam y (var y)))")

/-! ## Structural invariants

Inductive constructors have no auto-generated field projections, so we read
fields via `match` and assert the recorded value directly (complementary to the
`toString` golden checks above, which embed the same fields textually). -/

-- Scrutinees use qualified constructors so the expected type is unambiguous;
-- `Expr` has no `BEq`/`DecidableEq` (it is a nested inductive), so field values
-- are compared as primitives (`Nat`/`String` have `BEq`) or via `toString`.
#guard (match Expr.proj (Expr.var "s") 5  with | .proj _ i   => i == 5 | _ => false)
#guard (match Expr.ctor "C" 3 []          with | .ctor _ t _ => t == 3 | _ => false)
#guard (match Expr.lam "x" (Expr.var "x") with | .lam p _    => p == "x" | _ => false)
#guard (match Expr.var "v"               with | .var n      => n == "v" | _ => false)
#guard (match Expr.const "Nat.succ"      with | .const n    => n == "Nat.succ" | _ => false)
#guard (match Expr.lit (.natLit 9)        with | .lit (.natLit n) => n == 9 | _ => false)
#guard (match Expr.app (Expr.var "f") (Expr.var "a")
                 with | .app g b => g.toString == "(var f)" && b.toString == "(var a)" | _ => false)

/-! ## `Decl` — params, body, and the `isRec` recursion flag -/

#guard (Decl.toString { name := "id", params := ["x"], body := .var "x" }
        == "(decl id (x) (var x))")
#guard (Decl.toString { name := "zero", body := .lit (.natLit 0) }
        == "(decl zero () (lit nat_lit 0))")
-- `isRec` defaults to `false` and can be set to `true`
#guard (({ name := "id", params := ["x"], body := .var "x" } : Decl).isRec == false)
#guard (({ name := "f", params := ["n"],
           body := .app (.const "f") (.var "n"), isRec := true } : Decl).isRec == true)

/-! ## `isRec` semantics (decided: a single `Bool`, see `typelean-m1-decide`)

The flag is the *authoritative* Lower-set signal that a decl is recursive —
direct self-reference **or** mutual-SCC member — independent of whether a naive
body self-scan would find the decl's own name. These assertions lock that
contract: a decl may read `isRec == true` even when its body names a *different*
constant (the mutual case Emit cannot derive locally), and `false` even when it
references another (non-recursive) constant. The field value is whatever Lower
set; Emit must trust the field, not re-derive recursion from the body. -/

-- Mutual recursion (model): `g`'s body calls `f`, not itself, yet Lower marks
-- the whole SCC recursive — the bit Emit cannot recover from `g`'s body alone.
#guard (({ name := "g", params := ["n"],
           body := .app (.const "f") (.var "n"), isRec := true } : Decl).isRec == true)
-- A non-recursive decl referencing a *different* constant keeps the default
-- `isRec == false`: referencing another decl alone does not set the flag
-- (Lower only marks self-/mutual-recursion).
#guard (({ name := "id_of_f", params := ["x"],
           body := .const "f" } : Decl).isRec == false)
-- The field is the source of truth, not a body derivation: a decl whose body
-- names itself reads exactly the value Lower recorded (here the default
-- `false`), so Emit must read the field rather than scan the body.
#guard (({ name := "h", params := ["n"],
           body := .app (.const "h") (.var "n") } : Decl).isRec == false)

/-! ## `Module` — empty, single-decl, multi-decl -/

#guard (Module.toString ({} : Module) == "(module)")
#guard (Module.toString
          ({ decls := [ { name := "id", params := ["x"], body := .var "x" } ] } : Module)
        == "(module\n  (decl id (x) (var x)))")
#guard (Module.toString
          ({ decls := [ { name := "id", params := ["x"], body := .var "x" },
                        { name := "zero", body := .lit (.natLit 0) } ] } : Module)
        == "(module\n  (decl id (x) (var x))\n  (decl zero () (lit nat_lit 0)))")

/-! ## A few `native_decide` proofs (compiled evaluation) for the
   `example`/`theorem` flavor requested by the task. -/

example : Expr.toString (.var "x") = "(var x)" := by native_decide
example : Expr.toString (.proj (.var "s") 2) = "(proj (var s) 2)" := by native_decide
example : Expr.toString (.ctor "C" 0 [.var "a", .var "b"])
          = "(ctor C 0 [(var a), (var b)])" := by native_decide
example : Lit.toString (.boolLit true) = "bool_lit true" := by native_decide
example : Decl.toString { name := "id", params := ["x"], body := .var "x" }
          = "(decl id (x) (var x))" := by native_decide
example : Module.toString ({} : Module) = "(module)" := by native_decide
example : (.natLit 1 : Lit) = .natLit 1 := by native_decide
example : (2 + 2 : Nat) = 4 := by native_decide   -- sanity: native_decide is wired
