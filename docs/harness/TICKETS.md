# Ticket board

The live status of every ticket. Full specs are in [`roadmap.md`](roadmap.md) §8.

**Status values:** `todo` · `in-progress` · `review` · `changes-requested` · `done` · `blocked`

**Who edits what:**
- Builders change only their own ticket's row: `todo → in-progress → review`, or
  `blocked`.
- Reviewers set `done` or `changes-requested`, and update `GATE-N` rows.
- A ticket is **eligible** when its status is `todo` and every ticket it depends on is
  `done`. Builders take the lowest-numbered eligible ticket unless told otherwise.

**Tracks.** After GATE-0, Track S (Milestone 1), Track C (Milestone 2) and
Track P (Milestone 3) are independent; run one builder per track ("start
track S"). After GATE-1, GATE-2 and GATE-3: Track G (4), Track R (5),
Track N (6) and Track Z (7). Milestone 8 comes last.

**Setup notes.**
- The harness files (AGENTS.md, CLAUDE.md, `docs/harness/`, `notes/`, the
  skills in `.claude/skills/`) already exist. Tickets extend them and never
  recreate them. README.md and `.gitignore` already existed and were appended to.
- Baseline (2026-11-12, SBCL 2.6.10 arm64): every `tests/run-*-tests.lisp`
  runner passes (roadmap §3.2). CI has been red since 2026-10-26 (QSM-0.1).
  The installed `bin/quasischeme` is stale and cannot find `src/srfi/` after
  the repository moved. Rebuild with `make -C contrib/cli` before using it
  (QSM-0.2).
- There are no submodules. The nested clones in `tmp/hawk` and
  `build/external/` are ignored.
- The untracked notes at the repository root are read-only history
  (roadmap §3.9).

## Milestone 0 — Baseline and hygiene

| ID | Title | Depends on | Status | Branch / notes |
|---|---|---|---|---|
| QSM-0.1 | Fix CI: SBCL 2.6.10 | — | todo | Can start at once. CI green is confirmed only after the human pushes |
| QSM-0.2 | Relocatable install and stale-binary check | — | todo | Can start at once. North-star hook: no absolute paths |
| QSM-0.3 | Portable process-group cap and `scripts/check.sh` | — | todo | Can start at once. Most of M0 depends on it |
| QSM-0.4 | Record the baseline | QSM-0.2, QSM-0.3 | todo | Long runs; use `scripts/cap`. Corrects stale doc numbers |
| QSM-0.5 | Crash-safe Racket and library caches | — | todo | Can start at once. Needs `build/external/racket` (`sh utils/racket/setup.sh`) |
| QSM-0.6 | Repository hygiene | QSM-0.3 | todo | |
| QSM-0.7 | ECL loads again, with a guard | QSM-0.3 | todo | North-star hook: guarded SBCL code |
| QSM-0.8 | CI host matrix (smoke) | QSM-0.1, QSM-0.7 | todo | Verify 40ants/setup-lisp or install ECL and CCL directly |
| QSM-0.9 | Pipeline and IR document | — | todo | Can start at once. Reviewer checks every `file:line` |
| QSM-0.10 | Core-language specification and validator | QSM-0.9 | todo | Quotes `ideas.md` |
| QSM-0.11 | Ratchet counters: warnings, lint, coverage | QSM-0.3 | todo | Verify sblint, Mallet, sb-cover |
| QSM-0.12 | Differential and generative testing | QSM-0.3 | todo | Verify check-it; oracles skip when absent |
| QSM-0.13 | SBCL arm64 CLOSURE-INIT: prepare the upstream report | — | todo | Can start at once. Copy, never move, the note in `tmp/`. The human files it |
| GATE-0 | Milestone 0 gate | QSM-0.1–QSM-0.13 | todo | Needs the human's push for CI evidence |

## Milestone 1 — Size and start-up (Track S)

| ID | Title | Depends on | Status | Branch / notes |
|---|---|---|---|---|
| QSM-1.1 | Size and start-up measurement | GATE-0 | todo | |
| QSM-1.2 | Compressed executables (option) | QSM-1.1 | todo | `:sb-core-compression` |
| QSM-1.3 | Spike: image layering | QSM-1.1 | todo | A negative result is acceptable |
| QSM-1.4 | Base core plus mode layers | QSM-1.3 | todo | Only on a "go" from QSM-1.3 |
| QSM-1.5 | Smaller Racket executables | QSM-1.4 | todo | |
| QSM-1.6 | Tree-shaking behind a flag | QSM-1.1 | todo | Off by default; skips when `tree-shaker` is absent (open decision 4) |
| QSM-1.7 | Stripping under a flag | QSM-1.6 | todo | Off by default; Racket needs arities |
| QSM-1.8 | Start-up time | QSM-1.1 | todo | |
| GATE-1 | Milestone 1 gate | QSM-1.1–QSM-1.8 | todo | |

## Milestone 2 — Continuation speed (Track C)

| ID | Title | Depends on | Status | Branch / notes |
|---|---|---|---|---|
| QSM-2.1 | Continuation benchmarks | GATE-0 | todo | |
| QSM-2.2 | Lazy rebuild over an underflow frame | QSM-2.1 | todo | Invariant: no CPS |
| QSM-2.3 | Safety across libraries | QSM-2.1 | todo | |
| QSM-2.4 | Frame-aware primitives | QSM-2.1 | todo | |
| QSM-2.5 | One dynamic environment | QSM-2.2 | todo | May split into 2.5a/2.5b |
| QSM-2.6 | Let-bound locals in machines | QSM-2.1 | todo | Quotes `next-steps.txt` |
| QSM-2.7a | Spike: stack sites on x86-64 | GATE-0 | todo | |
| QSM-2.7b | Stack sites on x86-64 | QSM-2.7a | todo | Only on a "go" from QSM-2.7a |
| QSM-2.8 | Cheaper portable frame pushes | QSM-2.1 | todo | Measure on ECL as well |
| QSM-2.9 | Spike: copying SBCL's control stack | QSM-2.1 | todo | Prototype stays off `main` |
| GATE-2 | Milestone 2 gate | QSM-2.1–QSM-2.9 | todo | |

## Milestone 3 — CL portability (Track P)

| ID | Title | Depends on | Status | Branch / notes |
|---|---|---|---|---|
| QSM-3.1 | Portability inventory | GATE-0 | todo | |
| QSM-3.2 | Tail calls on every host | QSM-3.1 | todo | |
| QSM-3.3 | ECL: the full standard suites | QSM-3.1 | todo | May split by suite |
| QSM-3.4 | CCL: the standard suites | QSM-3.1 | todo | |
| QSM-3.5 | The command on ECL and CCL | QSM-3.3, QSM-3.4 | todo | |
| QSM-3.6 | Spike: Chez, Guile and Racket modes on ECL and CCL | QSM-3.3, QSM-3.4 | todo | |
| QSM-3.7 | CI matrix with full suites | QSM-3.3, QSM-3.4 | todo | |
| QSM-3.8 | Spike: ABCL | QSM-3.1 | todo | |
| QSM-3.9 | Spike: Clasp | QSM-3.1 | todo | Clasp is not installed |
| QSM-3.10 | Remaining host-specific pieces | QSM-3.1 | todo | |
| GATE-3 | Milestone 3 gate | QSM-3.1–QSM-3.10 | todo | From this gate on, full suites on ECL and CCL |

## Milestone 4 — Guile and libguile (Track G)

| ID | Title | Depends on | Status | Branch / notes |
|---|---|---|---|---|
| QSM-4.1 | Guile suite regressions | GATE-1, GATE-2, GATE-3 | todo | Quotes `todo` |
| QSM-4.2 | libguile speed, re-measured | GATE-1, GATE-2, GATE-3 | todo | Needs podman |
| QSM-4.3 | libguile tests without the container | QSM-4.4 | todo | Quotes `todo` |
| QSM-4.4 | Our own `libguile.h` | GATE-1, GATE-2, GATE-3 | todo | Clean-room from the manual; LGPL headers must not be copied |
| QSM-4.5 | Stubs Guix's TLS needs | GATE-1, GATE-2, GATE-3 | todo | Needs podman |
| QSM-4.6 | Spike: Guix stage 3 | GATE-1, GATE-2, GATE-3 | todo | Needs podman |
| QSM-4.7 | Spike: two Guile systems | GATE-1, GATE-2, GATE-3 | todo | Quotes `todo` |
| QSM-4.8 | The Guile suite's tail | QSM-4.1 | todo | |
| QSM-4.9 | Sockets on usocket | GATE-1, GATE-2, GATE-3 | todo | Quotes `todo` |
| GATE-4 | Milestone 4 gate | QSM-4.1–QSM-4.9 | todo | |

## Milestone 5 — Racket ecosystem (Track R)

| ID | Title | Depends on | Status | Branch / notes |
|---|---|---|---|---|
| QSM-5.1 | Racket's suite, re-measured | GATE-1, GATE-2, GATE-3 | todo | |
| QSM-5.2 | Spike: what stops `typed/racket` | GATE-1, GATE-2, GATE-3 | todo | |
| QSM-5.3 | `typed/racket` boots | QSM-5.2 | todo | May split |
| QSM-5.4 | Loading packages | GATE-1, GATE-2, GATE-3 | todo | `utils/racket/packages.sh` |
| QSM-5.5 | brag | QSM-5.4 | todo | |
| QSM-5.6 | scribble | QSM-5.4 | todo | |
| QSM-5.7 | Spike: slideshow | QSM-5.4 | todo | GUI dependencies |
| QSM-5.8 | rhombus | QSM-5.4 | todo | |
| QSM-5.9 | Faster cold start | GATE-1, GATE-2, GATE-3 | todo | |
| GATE-5 | Milestone 5 gate | QSM-5.1–QSM-5.9 | todo | |

## Milestone 6 — RnRS, SRFI and R7RS-Large (Track N)

| ID | Title | Depends on | Status | Branch / notes |
|---|---|---|---|---|
| QSM-6.1 | SRFI 272 | GATE-1, GATE-2, GATE-3 | todo | |
| QSM-6.2 | SRFI status check | GATE-1, GATE-2, GATE-3 | todo | |
| QSM-6.3 | R7RS-Large Red and Tangerine audit | GATE-1, GATE-2, GATE-3 | todo | |
| QSM-6.4 | Real-program corpus | GATE-1, GATE-2, GATE-3 | todo | Needs Akku and snow trees |
| QSM-6.5 | More real programs | GATE-1, GATE-2, GATE-3 | todo | |
| QSM-6.6 | R7RS-Large Foundations tracking | GATE-1, GATE-2, GATE-3 | todo | |
| GATE-6 | Milestone 6 gate | QSM-6.1–QSM-6.6 | todo | |

## Milestone 7 — Chez (Track Z)

| ID | Title | Depends on | Status | Branch / notes |
|---|---|---|---|---|
| QSM-7.1 | The `hash` mats regression | GATE-1, GATE-2, GATE-3 | todo | |
| QSM-7.2 | Spike: Chez internals | GATE-1, GATE-2, GATE-3 | todo | Report only, no code (human decision) |
| QSM-7.3 | The full mats and `5_2` | GATE-1, GATE-2, GATE-3 | todo | |
| GATE-7 | Milestone 7 gate | QSM-7.1–QSM-7.3 | todo | |

## Milestone 8 — Cross-cutting work and spikes

| ID | Title | Depends on | Status | Branch / notes |
|---|---|---|---|---|
| QSM-8.1 | Optimize level 3 | GATE-4, GATE-5, GATE-6, GATE-7 | todo | Touches every mode |
| QSM-8.2 | Move `contrib/racket-linklets` | GATE-4, GATE-5, GATE-6, GATE-7 | todo | |
| QSM-8.3 | Spike: a Scheme-to-C backend | GATE-4, GATE-5, GATE-6, GATE-7 | todo | Not a north star (human decision) |
| QSM-8.4 | Spike: schemify as a differential test | GATE-4, GATE-5, GATE-6, GATE-7 | todo | |
| QSM-8.5 | Spike: a linklet interpreter in Chez Scheme | GATE-4, GATE-5, GATE-6, GATE-7 | todo | |
| QSM-8.6 | `qsc` and `qs` command names | GATE-4, GATE-5, GATE-6, GATE-7 | todo | |
| QSM-8.7 | Named primitives and `defknown` | GATE-4, GATE-5, GATE-6, GATE-7 | todo | |
| QSM-8.8 | Verify: fewer `ps:truep` tests | GATE-4, GATE-5, GATE-6, GATE-7 | todo | |
| GATE-8 | Milestone 8 gate | QSM-8.1–QSM-8.8 | todo | |
