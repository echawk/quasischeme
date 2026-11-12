---
name: correctness
description: QuasiScheme's correctness rungs and how to meet them. Covers the ratchet counters (compiler warnings, unguarded SBCL references, lint counts), differential and generative testing (tests/fuzz/difftest.py, oracles Chez, Guile, Racket, Chibi), properties for optimizer passes, the core-language validator, and when a suppression is allowed. Use when adding a transformation, an optimizer pass, a new configuration switch, a runtime primitive, or when a ratchet count changes.
---

# correctness

The strategy and each module's rung are in roadmap §7b. This skill is the
how-to.

## Principles (non-negotiable)
1. **Ratchets only tighten.** The counts recorded in
   `docs/harness/baseline.md` may only go down:
   - compiler warnings and style-warnings in a full load (QSM-0.11);
   - unguarded `sb-` references (QSM-0.7);
   - lint findings, if a linter is adopted.

   A rise fails `scripts/check.sh`.
2. **New transformations prove agreement.** Any new optimizer rewrite,
   continuation-transform change or translator change needs a difftest
   configuration or a property showing the observable result does not
   change.
3. **Oracles decide disputes.** When QuasiScheme and an oracle disagree on
   a standard-conforming program, the oracle is presumed right until the
   report says otherwise. Record the analysis.
4. **Suppressions need a reason.** Muffling a warning, adding a skip,
   raising a limit, or excluding a test needs:
   - a comment with the reason and a ticket ID;
   - reviewer approval recorded in the review note.

## Differential testing
- `tests/fuzz/difftest.py` generates typed, terminating R7RS programs and
  runs them under configurations (`CONFIGS`): `O0`, `O1`, `escape`,
  `no-fast`, `no-flonum-versions`, `no-cpdx`, `no-cpletrec`,
  `no-stack-sites`, `site-closures`, `parametric`, `interpret`,
  `guile-mode`, `gc-stress`, `guile-gc-stress`. `--guile` adds GNU Guile
  as an oracle.
- **Always** run it with `python3 -B` and `--keep <scratch>`, so nothing
  is written into the tree (it keeps shrunk failures).
- **Reproduce a failure:**
  `python3 -B tests/fuzz/difftest.py --seed N --count 1 --configs default,<cfg> --keep <scratch>`.
- **Planned (QSM-0.12):** Chez, Racket and Chibi oracles, each skipped
  with a message when absent; a fixed seed range in
  `scripts/check.sh --full`.
- **A new switch** (environment variable or flag) that changes code
  generation gets a `CONFIGS` entry in the same ticket.

## Properties
- **Verify in QSM-0.12:** check-it (https://github.com/yurrriq/check-it)
  for Lisp-side properties.
- **The basic property for an optimizer pass:** for random core forms
  with integer and list operations, the evaluated results at
  `QUASISCHEME_OPTIMIZE=0` and `2` are equal.
- Keep generators small and terminating. Shrink failures before
  recording them.

## Core-language validator
- Once QSM-0.10 lands, `QUASISCHEME_CHECK_CORE=1` checks every form
  entering `host-eval`.
- Run the standard suites with it when you change a front end or a pass
  that produces core forms.

## Future rungs (not required yet; reviewers consider them at each gate)
- libguile ABI: `abidiff` (libabigail) against real libguile, inside the
  Linux container (ELF only); ASan/UBSan on the C tests.
- Formal methods: the PLT Redex R6RS model as an oracle for core forms;
  Coalton for new pure passes.

## Testing (what each kind of ticket adds)
- **An optimizer or transform change:** a regression test in
  `tests/run-optimizer-tests.lisp` or `tests/run-continuation-tests.lisp`,
  plus difftest at `--count 20` or more with the affected configurations.
- **A runtime primitive:** suite cases, including an error path and an
  oracle comparison where an oracle has the primitive.
- **A counter change:** the new count in `docs/harness/baseline.md`, with
  the reason in the handoff note.

## Pitfalls
- **difftest's default `--keep`** is `tests/fuzz/failures/` (ignored), and
  plain `python3` writes `__pycache__` into the tree. Use `-B`.
- **Oracles differ legitimately** on unspecified behavior: evaluation
  order, the printing of floats, `eq?` on numbers. The generator avoids
  these, so keep new generator features inside specified behavior.
