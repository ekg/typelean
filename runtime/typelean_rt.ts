// typelean runtime — Lean 4 value model in TypeScript (DESIGN §5, §11).
//
// This is the canonical runtime. `Typelean/Emit.lean` inlines an identical copy
// (`runtimeSource`) into every emitted module so the output is self-contained
// and runnable from any cwd (the fidelity harness writes emitted `.mts` to a
// temp dir and runs `node file.mts`, so a relative `import` would not resolve).
// Keep these two copies in lock-step: any change here MUST be mirrored in
// `Typelean/Emit.lean`'s `runtimeSource`.
//
// Value model:
//   * Constructors      → { _tag: number, _fields: any[] }   (`_rt.ctor`)
//   * Nat / Int         → BigInt                              (Nat is unary in Lean
//                                                          but BigInt here; DESIGN §11)
//   * String / Char     → JS string / number (codepoint)
//   * Bool              → JS boolean
//   * IO α              → a thunk () => α; the driver runs `main` (`_rt.run`)
//   * Closures          → JS arrow functions (curried)
//
// All multi-argument primitives are **curried** (one binder per arrow) because
// typelean emits each IR `app` as a single-argument call — Lean is curried, so
// the runtime must be too.
const _rt = {
  // Saturated constructor application: a tagged object with its field array.
  ctor: (tag, fields) => ({ _tag: tag, _fields: fields }),

  // Nat.repr / Int.repr (BigInt → decimal string).
  natRepr: (n) => n.toString(),
  intRepr: (n) => (n < 0n ? "-" + (-n).toString() : n.toString()),

  // String.append (Lean `String ++`).
  strLength: (s) => [...s].length,
  strAppend: (a) => (b) => a + b,

  // Nat arithmetic (BigInt). Lean `Nat.sub` is truncating (0 below zero).
  natAdd: (a) => (b) => a + b,
  natMul: (a) => (b) => a * b,
  natSub: (a) => (b) => (a > b ? a - b : 0n),
  natDiv: (a) => (b) => (b === 0n ? 0n : a / b),
  natMod: (a) => (b) => (b === 0n ? 0n : a % b),
  natBeq: (a) => (b) => a === b,

  // IO.println : {α} → [ToString α] → α → IO Unit.
  // Lower passes the (computationally-irrelevant) type argument `α` first; it
  // is ignored here. The `ToString` instance is a constructor whose first
  // field is the `toString` method. Returns an IO thunk.
  println: (typeArg) => (inst) => (value) => () => {
    process.stdout.write(inst._fields[0](value) + "\n");
  },
  // IO.print (no trailing newline).
  print: (typeArg) => (inst) => (value) => () => {
    process.stdout.write(inst._fields[0](value));
  },

  // Run an IO action (thunk) — the driver entry point for `main`.
  run: (io) => io(),
};
