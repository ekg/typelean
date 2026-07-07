import Typelean

/-! typelean CLI entry point.

    Usage:
    * `typelean`                 — print version/usage banner.
    * `typelean <input.lean>`    — compile a Lean source file and print the
      emitted TypeScript to stdout (non-zero exit on error).

    Any failure — a missing/unreadable input file (reported as a stage-tagged
    `io` error) or a stage-tagged `CompileError` from `Typelean.Pipeline.compile`
    (`frontend` / `lower` / `emit`) — prints a single `typelean: <stage>: <msg>`
    line to stderr and exits non-zero (DESIGN §1.4: no silent drops). -/

/-- Read `path`, returning `.ok source` or `.error "<clean io message>"`
    (a missing/unreadable file is a clean `io`-stage error rather than an
    unhandled IO exception). -/
def readInput (path : String) : IO (Except String String) := do
  try
    return .ok (← IO.FS.readFile path)
  catch e =>
    return .error s!"io: cannot read '{path}': {e}"

def main (args : List String) : IO UInt32 := do
  match args with
  | [] =>
    IO.println s!"typelean {Typelean.version} — Lean 4 → TypeScript compiler"
    IO.println "usage: typelean <input.lean>"
    return 0
  | path :: _ =>
    match ← readInput path with
    | .error msg =>
      IO.eprintln s!"typelean: {msg}"
      return 1
    | .ok source =>
      match ← Typelean.Pipeline.compile source path with
      | .ok ts =>
        IO.println ts
        return 0
      | .error e =>
        IO.eprintln s!"typelean: {e.stage}: {e.msg}"
        return 1
