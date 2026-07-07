import Typelean

/-- typelean CLI entry point.

    Usage:
    * `typelean`                 — print version/usage banner.
    * `typelean <input.lean>`    — compile a Lean source file and print the
      emitted TypeScript to stdout (non-zero exit on error).

    The real pipeline is wired by the `typelean-integrate-m1` subtask; until
    then `compile` returns a "not yet wired" error. -/
def main (args : List String) : IO UInt32 := do
  match args with
  | [] =>
    IO.println s!"typelean {Typelean.version} — Lean 4 → TypeScript compiler"
    IO.println "usage: typelean <input.lean>"
    return 0
  | path :: _ =>
    let source ← IO.FS.readFile path
    match ← Typelean.Pipeline.compile source path with
    | .ok ts => IO.println ts; return 0
    | .error e =>
      IO.eprintln s!"typelean: {e.stage}: {e.msg}"
      return 1
