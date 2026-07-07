import Lean
import Typelean.Basic

/-! # Typelean.Frontend

Pipeline **stage 1**: load Lean 4 source text and run it through Lean's own
frontend (parser + elaborator) to obtain a fully type-checked
`Lean.Environment`. Reusing `Lean.Elab` is the core of typelean's compatibility
strategy — we never re-implement elaboration, so typelean inherits Lean's
parsing, macro expansion, type-class resolution, coercion insertion, universe
inference, `do`-notation desugaring, pattern-match compilation, and termination
checking *verbatim*.

Implementation route (the `lean --run` machinery, decomposed so we keep the
`MessageLog` and can return a positioned first error):

1. `Lean.enableInitializersExecution` — required before
   `importModules (loadExts := true)` so imported environment extensions
   initialize. Idempotent; `lean --run` does the same at startup.
2. `Lean.initSearchPath (← Lean.findSysroot)` — make `import` headers
   (e.g. `import Init`) resolve against the Lean sysroot (`<sysroot>/lib/lean`)
   plus any `LEAN_PATH` entries (Lake sets these).
3. `Lean.Parser.parseHeader` — parse the `module`/`prelude`/`import …` header;
   yields the header syntax, the post-header parser position, and a `MessageLog`.
4. `Lean.Elab.processHeader` — resolve the header's imports into an
   `Environment` via `Lean.importModules (loadExts := true)`. Missing-module
   errors are caught here and folded into the returned message log.
5. `Lean.Elab.Command.mkState` + `Lean.Elab.IO.processCommands` — elaborate the
   command body (everything after the header) command-by-command, starting from
   the post-header parser position so imports are not re-parsed.
6. Drain the full message log — `importMsgs ++ commandState.messages` (see the
   code: `Lean.Elab.IO.processCommands` rebuilds `commandState.messages` from
   per-command snapshots only and *drops* the seed `importMsgs`, so we re-merge
   them) — on `hasErrors`, take the first error (with file/position via
   `Message.toString`) and return `.error (.at "frontend" <msg>)`; otherwise
   return `.ok env`.

> The `typelean-frontend` subtask owns this file. Keep the public signature of
> `elaborateSource` stable; the integrator depends on it.
>
> **Consumer requirement.** `elaborateSource` calls
> `Lean.importModules (loadExts := true)`, which runs imported modules'
> `initialize` blocks via Lean's IR interpreter. That needs the stdlib's native
> externs (e.g. `IO.getRandomBytes`) linked into the running executable, so any
> `lean_exe` that runs `elaborateSource` — the `typelean` CLI and any test
> driver — **must** declare `supportInterpreter := true` in `lakefile.lean`.
> Without it, import resolution fails with “Could not find native
> implementation of external declaration …”. (This is a property of the
> *consuming* executable, not of this module.)
-/

namespace Typelean.Frontend
open Lean Elab

/-- One-shot guard so we only initialize the search path once per process. -/
builtin_initialize searchPathInitialized : IO.Ref Bool ← IO.mkRef false

/-- Initialize Lean's import search path so `import` headers resolve.

    Adds the Lean sysroot library directory (`<sysroot>/lib/lean`, where
    `Init.olean` lives) and any `LEAN_PATH` entries to Lean's search path.
    Idempotent: a one-shot guard makes repeated calls a no-op. -/
def ensureSearchPath : IO Unit := do
  if (← searchPathInitialized.get) then return
  -- `findSysroot` honors `LEAN_SYSROOT`, else runs `lean --print-prefix`.
  let root ← Lean.findSysroot
  Lean.initSearchPath root
  searchPathInitialized.set true

/-- Extract the first error message from a `MessageLog` as a positioned,
    human-readable string (e.g. `"<input>:1:10: error: …"`).

    Iterates `reportedPlusUnreported` (reported then unreported, in insertion
    order) so we surface the chronologically earliest error regardless of
    snapshot reporting state. Returns a fallback if (unexpectedly) the log has
    no error despite `hasErrors`. -/
def firstErrorMessage (log : MessageLog) (fileName : String) : IO String := do
  for msg in log.reportedPlusUnreported do
    if msg.severity == .error then
      -- `Message.toString` always ends in a newline; trim it for a clean
      -- `CompileError.msg` (`String.trimAscii` returns a `Slice`, so `.toString`).
      return (← msg.toString).trimAscii.toString
  return s!"{fileName}: elaboration reported an error with no diagnostic message"

/-- Elaborate Lean 4 source text into a fully type-checked `Lean.Environment`
    by driving Lean's own frontend (`Lean.Elab`), so typelean inherits Lean's
    parsing/elaboration semantics verbatim.

    `fileName` is used for diagnostics. Returns the elaborated environment, or
    a stage-tagged `CompileError` carrying the first elaboration failure (with
    position). -/
def elaborateSource (source : String) (fileName : String := "<input>") :
    IO (Except Typelean.CompileError Environment) := do
  -- 1. Allow environment extensions to be loaded from imported `.olean` files.
  --    Idempotent; required by `importModules (loadExts := true)`.
  unsafe Lean.enableInitializersExecution
  -- 2. Resolve `import …` headers against the Lean sysroot (+ `LEAN_PATH`).
  ensureSearchPath
  let inputCtx := Parser.mkInputContext source fileName
  -- 3. Parse the module header (`module`/`prelude`/`import …`).
  let (header, parserState, headerMsgs) ← Parser.parseHeader inputCtx
  -- 4. Resolve the imports into an environment. `processHeader` catches
  --    missing-module errors and folds them into the returned message log.
  let (env, importMsgs) ← Elab.processHeader header {} headerMsgs inputCtx
  -- 5. Elaborate the command body (everything after the header), starting from
  --    the post-header parser position so imports are not re-parsed.
  let commandState := Command.mkState env importMsgs
  let s ← Elab.IO.processCommands inputCtx parserState commandState
  -- 6. Drain the message log: return the first error, or the environment.
  --    `Lean.Elab.IO.processCommands` rebuilds `commandState.messages` from
  --    per-command snapshot diagnostics only — `Lean.Language.Lean.processCommands`
  --    seeds the command parser with `.empty`, not the incoming
  --    `commandState.messages`, so the header/import messages carried in
  --    `importMsgs` are *dropped* from `s.commandState.messages`. Re-merge them
  --    so an import/header failure (e.g. a missing module, or a missing native
  --    implementation when the consuming exe lacks `supportInterpreter := true`)
  --    is surfaced as the first error rather than a misleading downstream
  --    "unknown constant" elaboration error. The two logs are disjoint (the seed
  --    is dropped, never duplicated), so the append is lossless and order-preserving
  --    (header → import → command errors).
  let finalEnv := s.commandState.env
  let msgs := importMsgs ++ s.commandState.messages
  if msgs.hasErrors then
    let first ← firstErrorMessage msgs fileName
    return .error (Typelean.CompileError.at "frontend" first)
  else
    return .ok finalEnv

end Typelean.Frontend
