---
name: pipeline-change
description: How to change QuasiScheme's compilation pipeline safely. Covers front ends (psyntax, Guile Tree-IL, Racket linklets), the core language, the optimizer passes (cp0, cptypes, cpletrec, cpdx, cpcommonize), the continuation transform, the Pseudoscheme translator, and the CL post-passes; which IR to change for what; invariants (no CPS, valid core forms, all configurations agree); and tools to inspect each stage. Use whenever editing src/psyntax.lisp, src/cp*.lisp, src/continuations.lisp, src/*.scm (translator), src/guile/compile.lisp, src/racket/linklet/compiler.lisp, or src/sbcl-vops.lisp.
---

# pipeline-change

## Principles (non-negotiable)
1. **No CPS of general code.** Scheme procedures stay ordinary Lisp
   functions with ordinary calls and returns, so Lisp code can call them.
   Continuations come from generalized stack inspection: machines, sites
   and frames (`docs/continuations.md`). (Human decision, 2026-11-12.)
2. **One core language.**
   - Every front end hands `qsx:host-eval` (`src/psyntax.lisp:875`) core
     Scheme: `quote`, `if`, `begin`, `set!`, `define`, `lambda`,
     `case-lambda`, `letrec`, `letrec*`, `(primitive x)` and calls.
   - The specification is `docs/core-language.md` (QSM-0.10). Run the
     validator with `QUASISCHEME_CHECK_CORE=1` once it exists.
   - A new core form needs the specification, the validator, cp0, cptypes,
     the continuation transform and the translator updated together, or
     it must not be added.
3. **Configurations agree.** Results must be the same at
   `QUASISCHEME_OPTIMIZE=0`, `1` and `2`, with full and escape-only
   continuations, and with `QUASISCHEME_FAST=0` and
   `QUASISCHEME_STACK_SITES=0`. Each new transformation needs a difftest
   configuration or a property showing this (`correctness` skill).
4. **SBCL-specific speedups** (`src/sbcl-vops.lisp`,
   `src/sbcl-compiler.lisp`, stack sites) are optional layers. The
   portable path must keep working and be tested with the layer off.
5. **Every mode uses the shared back end.** A change to it is tested in
   R7RS, R6RS, Chez, Guile and Racket modes.

## Where things live (until QSM-0.9's docs/pipeline.md)
| Stage | Code | Representation |
|---|---|---|
| R1RS–R7RS and Chez front end | `vendor/psyntax/psyntax-quasischeme.pp` (generated), hooks in `src/psyntax.lisp` (`eval-core` :135) | core s-expressions with `G$n` gensyms |
| Guile front end | Guile's psyntax, then Tree-IL, then `compile-tree-il` (`src/guile/compile.lisp:427`); pre-expander :1564 | Tree-IL structs, then core |
| Guile VM path (separate) | `src/guile/vm.lisp`, `vm-jit.lisp`, `vm-vops.lisp`, `vm-elf.lisp` | bytecode; never reaches the back end |
| Racket front end | expander linklet, then `compile-linklet-form` (`src/racket/linklet/compiler.lisp:1206`) | linklet s-expressions, then a core lambda |
| Opening | `open-top-level` (`src/psyntax.lisp:759`): `open-primitives`, `definitions-as-letrec` | core |
| Optimizer | `optimize-core` (`src/cp0.lisp:782`): cpletrec, cp0, dead bindings, cptypes, cpcommonize, cpdx | core plus `%cp-*` marks and side tables |
| Continuations | `cc-transform` (`src/continuations.lisp:3008`) | core plus `%machine`, `%site`, `%return` |
| Translator | `alpha.scm`, `node.scm`, `generate.scm`, `emit.scm` (loaded from `.qso`) | node tree, then CL |
| Post-passes | `src/psyntax.lisp:1080-1086` | CL |
| Host compile | `compile` / `compile-file`; `src/sbcl-compiler.lisp` patches SBCL; `src/sbcl-vops.lisp` adds VOPs (arm64) | machine code |

## Inspecting each stage
- `QUASISCHEME_OPTIMIZE_TRACE=1` prints each core form before and after
  the optimizer.
- `QUASISCHEME_OPTIMIZE_STATS=1` prints the passes' statistics.
- `bin/quasischeme --emit-lisp prog.scm` writes the Lisp a program
  compiles to (`docs/executables.md`). At the REPL, `,lisp EXPR` and
  `,asm EXPR` do the same for one expression.
- From Lisp: `r7rs:expand`, `r7rs:translate`.
- `QUASISCHEME_RACKET_STATS=1` prints linklet lowering and compile times.

## Testing (required)
- The area's suites:
  - optimizer: `tests/run-optimizer-tests.lisp`;
  - continuations: `tests/run-continuation-tests.lisp`;
  - the standards: r5rs, r6rs, r7rs, with full and escape-only
    continuations.
- At least one mode-crossing check: a Guile or Racket program that
  exercises the changed path (`tests/racket/run.sh linklet`,
  `tests/run-guile-tests.sh <file>`).
- difftest:
  `python3 -B tests/fuzz/difftest.py --count 20 --configs default,O0,escape,no-fast,interpret,guile-mode,gc-stress --keep <scratch>`.
  Add a configuration for any new switch.
- If the translator changed: regenerate the `.qso` files and run
  `make bootstrap-check`.

## Pitfalls
- **SBCL's compile time is superlinear** in closures over shared
  variables and in big components. Stay within `*chunk-sites*`,
  `*letrec-definitions-limit*` and `*cc-transform-limit*`
  (`docs/continuations.md`, "What makes it fast").
- **Re-entry through Lisp code** (a sort's comparison, the bridge) hits a
  barrier and is an error by design. Frame-aware primitives are the fix
  (QSM-2.4), not CPS.
- **`(debug 0)` breaks Racket procedure arities.** Racket linklets keep
  `compute-debug-fun 0` (`docs/racket.md`).
- **Booting** (psyntax's image and the standard libraries) runs
  escape-only. Code compiled without the transform is not recorded in
  captured continuations.
