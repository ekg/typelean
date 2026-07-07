/-! # typelean example: hello

A minimal end-to-end Lean program. `lean --run examples/hello.lean` prints
`hello from typelean`; the emitted TypeScript (once the Lower/Emit stages land)
prints the same under `node`:

    typelean examples/hello.lean > hello.mts && node hello.mts

This is the M1 canary referenced by `ROADMAP.md` M1 and `DESIGN.md` §12. -/
def main : IO Unit := IO.println "hello from typelean"
