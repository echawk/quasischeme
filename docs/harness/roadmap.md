# QuasiScheme: every Scheme, compiled to Common Lisp

Ticket prefix `QSM`. Repository: this one
(pushes go to `git@github.com:echawk/quasischeme.git`, remote `echawk`).

This file is the plan of record for agent work. Status lives in
[`TICKETS.md`](TICKETS.md); the ticket lifecycle is in
[`agent-protocol.md`](agent-protocol.md); the rules are in
[`../../AGENTS.md`](../../AGENTS.md). Design detail lives in the mode
documents under `docs/`, which this roadmap links to rather than restates.

## 1. One-paragraph summary

QuasiScheme grew from Jonathan Rees' Pseudoscheme (1991–1994) into a
system that runs every Revised Report from R1RS to R7RS, all final SRFIs
through 279 except 272, and three other Schemes' own code: Chez Scheme
(`--chez`), GNU Guile with its own boot-9, a bytecode VM and a
C-ABI-compatible `libguile` (`--guile`), and Racket through Racket's own
expander (`--racket`). Every front end lowers its source to one small
core language, essentially R4RS plus a few additions, and a shared back
end optimizes it, makes continuations capturable, translates it to Common
Lisp and lets the host Lisp (SBCL today) compile it. Scheme procedures
are Lisp functions, so Scheme and Lisp call each other freely. The work
ahead is portability to other Common Lisps, faster continuations,
smaller and faster-starting executables, and closing the remaining gaps
in each of the four subprojects. **The governing design principle:
Scheme code compiles to ordinary direct-style Lisp. Nothing is CPS
converted, because that would break calling between Scheme and Lisp.**

## 2. Decisions already made

| Topic | Decision |
|---|---|
| Duration | Open-ended. Milestones are ordered by the tracks below, not by dates. |
| Language / stack | Common Lisp (ASDF) for the runtime, the optimizer and the mode layers; Scheme for the self-hosted translator (`src/*.scm`, pre-translated to `.qso`) and the libraries; C for `src/libguile/`. Python 3 and POSIX sh for tooling. |
| Development host | SBCL 2.6.10 on arm64 macOS. CI runs on x86-64 Ubuntu 24.04. |
| North stars | All three: (1) all four ecosystems run real programs unmodified, diffed against upstream; (2) portable QuasiScheme (the same suites on SBCL, CCL, ECL and Clasp); (3) small, fast deliverables (executables within 2× of `raco exe`, continuations at Chez speed). The Scheme-to-C backend is not a north star; it is a spike in Milestone 8. (Human decision, 2026-11-12.) |
| First wave after Milestone 0 | Three parallel tracks, one builder each: size and start-up (Milestone 1), continuation speed (Milestone 2), CL portability (Milestone 3). (Human decision, 2026-11-12.) |
| Later tracks | Guile and libguile (Milestone 4), the Racket ecosystem (Milestone 5), RnRS/SRFI/R7RS-Large (Milestone 6), Chez (Milestone 7), cross-cutting work and spikes (Milestone 8). (Human decision, 2026-11-12.) |
| Chez | A spike report only (go/no-go on representing Chez's internals; no code), plus ordinary bug fixes such as the possible `hash` mats regression. (Human decision, 2026-11-12.) |
| Common Lisp hosts | SBCL on every ticket. SBCL, ECL and CCL at every gate, locally and in a CI matrix. ABCL and Clasp get spikes only. (Human decision, 2026-11-12.) Until GATE-3, "ECL and CCL at a gate" means: their per-host baseline in `docs/harness/baseline.md` does not regress. From GATE-3 on, the full standard suites must pass on them. (Agent interpretation, 2026-11-12; confirm in §10, item 5.) |
| Continuations | Keep the current design: generalized stack inspection (portable frames on `*fstack*`) plus SBCL-internal stack work where it exists (the arm64 stack sites in `src/sbcl-vops.lisp`). Work through `docs/continuations.md` "Further work" and spike deeper SBCL stack work. **No CPS of general code; it preserves CL interop.** Every SBCL-internal mechanism needs a portable fallback for the other hosts. (Human decision, 2026-11-12: "we do no CPS to any code presently, since it would greatly inhibit normal interop with common lisp.") |
| Executable size | zstd core compression as an option; a base core plus per-mode layers loaded on demand; tree-shaking and dropping debug information only when explicitly requested, under a flag, using the user's `tree-shaker` library. (Human decision, 2026-11-12.) |
| Gate evidence | Per-mode suite tallies against the recorded baseline, plus green CI on the host matrix; benchmark tables (r7rs-benchmarks including `ctak` and `fibc`, start-up time, executable size per mode). Real-program transcripts and fuzz reports are ticket evidence, not gate evidence. (Human decision, 2026-11-12.) |
| Correctness level | Two tiers now: cheap ratchets (compiler-warning counts, SBCL-specific-code counts, lint counts, coverage reports) and differential and generative testing (oracles, optimizer-level agreement, random programs). libguile ABI checks and formal methods are future rungs. Each gate considers whether a module should move up a rung. (Human decision, 2026-11-12.) |
| Docs location | `docs/harness/` (`roadmap.md`, `TICKETS.md`, `agent-protocol.md`) is the plan of record. Superseded `ROADMAP.md` sections get dated markers with their text kept. The mode documents stay as linked design references. (Human decision, 2026-11-12.) |
| Untracked notes | Left untracked and in place, read-only history. Every open item became a ticket that cites the note's path and quotes the item (§3.9). (Human decision, 2026-11-12.) |
| Git and merges | The setup was committed on `harness/setup` from `main`; the human merges it. Afterwards the reviewer merges approved tickets into `main` locally and automatically, with `--no-ff`. Agents never push. The human pushes `main`, and its CI result is gate evidence. (Human decision, 2026-11-12.) |
| Commit style | The repository's own: `Area: what changed`, sentence case, with the ticket ID in parentheses at the end of the subject, a prose body, and a `Co-Authored-By:` trailer for agent commits. Not Conventional Commits. |
| Agent workflow | Ticketed milestones with reviewer gates (see `agent-protocol.md` and `AGENTS.md`). |

**Execution order:** 0 → {1, 2, 3 in parallel} → {4, 5, 6, 7 in parallel}
→ 8. The first tickets of Milestones 4–7 depend on GATE-1, GATE-2 and
GATE-3; Milestone 8 depends on GATE-4 to GATE-7. To start a later track
early, the human records a decision in §2 and a reviewer changes those
dependencies on the board.

## North-star goal (not in current scope)

**Dream: one portable Common Lisp image that runs real programs from all
four Scheme ecosystems unmodified, ships them as small, fast-starting
executables, and checks itself against each ecosystem's own
implementation.**

1. **Real programs, diffed against upstream.** A Racket package
   (brag, scribble, slideshow, rhombus), a Guix build of `hello`, Idris 2,
   and LilyPond all run unmodified, and their output matches the upstream
   implementation's.
2. **Portable.** The same suites pass on SBCL, CCL, ECL and Clasp.
3. **Small and fast.** Executables are within 2× of `raco exe`'s size,
   and continuations run at Chez's speed.

No ticket implements this. **Do not build it now.** Do make the design
choices below so it stays feasible. Reviewers reject changes that close
these doors.

| Design hook | Applies to | Why it matters for the dream |
|---|---|---|
| Every SBCL-only mechanism sits behind `#+sbcl` (or a host feature) with a working portable fallback, and the count of unguarded `sb-` references only goes down | every ticket; enforced from QSM-0.7 | Portability to CCL, ECL and Clasp |
| No CPS of general code; Scheme procedures stay ordinary Lisp functions with ordinary returns | Milestone 2, Milestone 8 | Interop with Lisp, and the C backend spike's C API |
| A mode's runtime is a separately loadable layer; nothing in the base core refers to a mode's internals by name | QSM-1.3, QSM-1.4, Milestones 4–5 | Small executables per mode |
| Every runner prints a machine-readable tally line, and every result can be compared with an upstream implementation's | QSM-0.3, QSM-0.4, QSM-0.12, QSM-6.4 | "Diffed against upstream" for real programs |
| Caches (library, Guile module, Racket module, saved Racket core) are written atomically and keyed by content, never by absolute install path | QSM-0.2, QSM-0.5 | Relocatable, shippable executables |
| Benchmarks are measured by instructions retired as well as time, against Chez, Guile and Racket on the same machine | QSM-1.1, QSM-2.1 | "Chez speed" and "2× of `raco exe`" are checkable claims |
| The core language has a written specification and a validator | QSM-0.10 | A second back end (C) and other hosts can target the same core |

## 3. Current state: facts the agents must know

### 3.1 Pipeline and entry points

The full pipeline is in QSM-0.9's document once it exists
(`docs/pipeline.md`). Until then:

- **Shared back end.**
  1. Core Scheme (s-expressions) enters `qsx:host-eval` (`src/psyntax.lisp:875`).
  2. `open-top-level` runs `open-primitives` and `definitions-as-letrec`.
  3. `optimize-core` (`src/cp0.lisp:782`) runs cpletrec, cp0, dead-binding removal, cptypes, cpcommonize and cpdx.
  4. `cc-transform` (`src/continuations.lisp:3008`) runs when continuations are full, the default. It is a source-to-source pass that adds the `%machine` and `%site` macros.
  5. The Pseudoscheme translator runs `alpha-top`, producing a node tree (`src/node.scm`), then `generate-top`, producing CL.
  6. CL post-passes (`src/psyntax.lisp:1080-1086`).
  7. SBCL `compile` or `compile-file`.
- **Front ends.**
  - R1RS–R7RS and Chez: psyntax (`vendor/psyntax/psyntax-quasischeme.pp`) produces core Scheme.
  - Guile: Guile's psyntax produces Tree-IL; `src/guile/compile.lisp:427` turns it into core Scheme. A separate VM path (`src/guile/vm*.lisp`) runs `.go` bytecode and never reaches the back end.
  - Racket: Racket's extracted expander produces linklets; `src/racket/linklet/compiler.lisp:1206` turns them into a core lambda.
- **Entry points.**
  - `bin/quasischeme`, built by `make -C contrib/cli` from `contrib/cli/`.
  - The Lisp packages `R5RS`, `R6RS` and `R7RS` (`src/api.lisp`).
  - The test runners `tests/run-*-tests.lisp`.

### 3.2 Baseline verified on 2026-11-12

SBCL 2.6.10 on arm64 macOS (Darwin 27), on a `git archive HEAD` snapshot
of `159409b` with caches redirected to a scratch directory. Wall times
are from 6 to 10 jobs running at once on 10 cores.

| Runner | Result | Wall |
|---|---|---|
| `tests/run-syntax-case-tests.lisp` (includes the cold ASDF compile) | 17 of 17 | 11.9 s |
| `tests/run-r7rs-tests.lisp` | 978 of 978 | 10.6 s |
| `tests/run-r5rs-tests.lisp` | 189 of 189 | 13.7 s |
| `tests/run-r6rs-tests.lisp` | 8902 passed, 0 failed | 30.5 s |
| `tests/run-reports-tests.lisp` | 993 of 993 | 13.4 s |
| `tests/run-continuation-tests.lisp` | 45 of 45 | 10.9 s |
| `tests/run-interop-tests.lisp` | 116 of 116 | 18.0 s |
| `tests/run-library-tests.lisp` | 73 of 73 | 21.9 s |
| `tests/run-srfi-system-tests.lisp` | 62 of 62 | 20.0 s |
| `tests/run-sbcl-tests.lisp` | 2 of 2 | 17.2 s |
| `tests/run-optimizer-tests.lisp` | 11 of 11 | 9.4 s |
| `make -C contrib/cli` (build) | 160,063,264-byte binary | 151 s |
| `contrib/cli/test.sh` | 51 of 51 | 285 s |
| `tests/run-srfi-tests.sh BIN 166 226` | both pass (SRFI 166: 352 passed, 0 failed) | — |
| `tests/fuzz/difftest.py --count 8 --seed 42` | 0 of 8 programs differ (6 configurations) | 115 s |
| `tests/run-chez-mats.sh 5_1 5_3 hash fx record io` | 4003 pass, 389 fail, 164 error, 1 crash | 128 s |
| `tests/run-guile-tests.sh hash alist strings srfi-1 numbers syntax` | 31,386 pass, 0 fail | 313 s |
| `tests/run-guile-tests.sh hooks coverage sandbox ecmascript` (LIMIT=300, cold module cache) | hooks: 14 pass, 1 fail; coverage, sandbox, ecmascript: killed at the limit | — |
| `tests/racket/run.sh linklet` | 7 of 7 linklets; the expander step and 44 programs were blocked by a corrupt cache (§3.3) | — |
| `#lang racket/base` hello, fresh cache | cold 428 s; warm 0.18 s | — |

Not run in the baseline:
- the full Chez mats, the full Guile suite and the full SRFI run (QSM-0.4 records them);
- `make test-escape`, `run-library-corpus.lisp`, `make test-programs`, `bench/`, `make bootstrap-check`;
- libguile, LilyPond and Guix, which need the podman container;
- Racket's own suite.

**Executables, measured 2026-11-12.** A whole image is dumped with
`uiop:dump-image`, with no compression; every mode's runtime is in one
image.

| Program | Size | zstd -9 | Start-up |
|---|---|---|---|
| R7RS hello (`--compile`) | 159,866,624 B | 32,197,180 B | 1.34 s |
| Chez hello | 160,063,264 B | — | 1.31 s |
| Guile hello | 159,932,168 B | — | 1.77 s |
| `#lang racket/base` hello | 476,650,440 B | 77,471,091 B | 2.21 s |
| The same Racket program via Racket 9.3 `raco exe` | 56,304,949 B | — | 0.43 s |

The SBCL here has `:sb-core-compression`.

### 3.3 Known defects found by the baseline (all are Milestone 0 tickets)

1. **CI has been red since 2026-10-26.** The last green run was
   2026-10-26T04:42Z. Every run since fails in `.github/actions/setup-lisp`
   with `Symbol "FDEFN-MAKUNBOUND" not found in the SB-KERNEL package` at
   `src/core.lisp:553`. CI pins SBCL 2.6.9; the code now needs 2.6.10
   (commit d8607ec). Ticket QSM-0.1.
2. **`bin/quasischeme` bakes in its install directory.** `-V` printed
   `install-dir "<home>/schemes/pseudoscheme/"` (the old checkout) after the repository
   moved. Every `(import (srfi N))` then failed with
   `cannot find library (SCHEME::SRFI SCHEME::|:1|)`, and `--racket -e`
   hung. The SRFI path comes from `asdf:system-relative-pathname` at image
   save time (`src/psyntax.lisp:1631`). Ticket QSM-0.2.
3. **A killed Racket run corrupts the module cache.** Later runs fail with
   `open-input-file: cannot open module file … base_rkt.zo` until the
   cache directory is changed. Ticket QSM-0.5.
4. **ECL no longer loads.** `src/numbers.lisp:290` (commit a9a9e09,
   2026-11-01) uses `sb-ext:` without `#+sbcl`, so the load fails with
   `There is no package with the name SB-EXT`. Commit 91aa594 had made
   R5RS, R6RS and R7RS pass on ECL. How to run the runners on ECL is
   undocumented. Ticket QSM-0.7.
5. **A tracked junk file:** `tests/fuzz/__pycache__/difftest.cpython-315.pyc`
   embeds an absolute home-directory path. Ticket QSM-0.6.
6. **Stale numbers in the docs.** QSM-0.4 corrects them.
   - README says "about 17,500" Chez mat clauses pass; `build/mats-latest.txt` (2026-10-25) says 20,528.
   - ROADMAP says the Guile suite has 43,190 passes; `docs/guile.md` says 43,278.
   - The docs say 44 CLI tests; there are 51.
   - `docs/executables.md` says a `racket/base` executable is 200 MB; it is 477 MB.
7. **A possible Chez regression.** `hash` mats went from 982 pass / 77 fail
   (2026-10-25) to 940 pass / 135 fail, on both the stale and a fresh
   binary. Ticket QSM-7.1.

### 3.4 Conventions

- **Lisp style.** Packages and nicknames `qs`, `qsx`, `qsr`, `qsg`, `qsl`,
  `qs-r7rs`. SBCL-specific code goes under `#+sbcl`, with a portable
  version after `#-sbcl`. File headers are `;;;;` prose that states what
  and why.
- **Scheme symbols** are CL symbols in the `SCHEME` package, named by
  inverted case (README "Symbols and case").
- **Prose docs** are plain and measured, with numbers and dates, citing
  `docs/…` paths and `file:line`.
- **ID schemes already in use; do not collide with them:**
  - "idea N" (`docs/optimizations.md`);
  - "Stage N" (`docs/guile.md`);
  - "milestone N" and "strategy A/B/C" (`docs/racket.md`);
  - `ROADMAP.md` sections 1–7;
  - SRFI numbers;
  - the string `M4` already appears.

  Harness IDs are `QSM-N.n`, milestones are written "Milestone N", and gates are `GATE-N`.
- **Environment variables** are documented in `docs/configuration.md`.
  Every new one must be added there.

### 3.5 Generated artifacts (never hand-edit)

- `src/*.qso` and `src/spack.lisp`: regenerated by `make bootstrap-pso`, or
  `(quasischeme-bootstrap:regenerate-pso-files)` (README "Bootstrap
  artifacts").
- `vendor/psyntax/psyntax-quasischeme.pp`: regenerated by
  `make bootstrap-psyntax` (`(qsx:rebuild)`).
- `make bootstrap-check` rebuilds both from two unrelated seeds and
  compares them with what is checked in. CI does the same.
- README's benchmark numbers between `<!-- bench … -->` markers:
  `python3 bench/summarize.py --update bench/RESULTS.md README.md`.

### 3.6 Upstream or vendored code (do not edit)

- `vendor/guile-test-suite/` (LGPL, unmodified)
- `vendor/chez-mats/`
- `vendor/chez-examples/`
- `tests/r6rs/` (Racket's R6RS suite)
- `tests/chibi/`
- `bench/r7rs-benchmarks/` (local changes only where marked `QUASISCHEME:`)

`vendor/psyntax/` is patched upstream code: patches are recorded in
`vendor/psyntax/README-quasischeme.md`, and a change there needs a
reviewer.

### 3.7 Tools

- **On PATH:**
  - Lisps: sbcl 2.6.10 (`:sb-core-compression`), ecl 26.5.5, abcl 1.9.2, ccl 1.14 darwinarm64;
  - qlot;
  - Schemes: chez and petite 10.4.1, racket/raco 9.3 CS, guile 3.0.11, chibi-scheme, gosh, csi, scheme48, idris2, snow-chibi;
  - podman, gh, python3 3.15, expect, clang, zstd.
- **Missing:**
  - `timeout`/`gtimeout`: use the driver's or `scripts/cap`'s process-group kill;
  - clasp, LispWorks, Allegro, clisp, roswell, akku, gsi, lilypond and guix: lilypond and guix run inside the container;
  - valgrind, hyperfine, abidiff.
- Tests that need a missing tool must skip with a message.

### 3.8 Git

- `main` tracks `echawk/main`. The second remote, `origin`, is upstream
  Pseudoscheme. There is no `.gitmodules`.
- **Nested repositories:**
  - `tmp/hawk/` is a reference clone of github.com/djwatson/hawk (now ignored);
  - `build/external/*` holds setup-script downloads (ignored). They are not submodules.
- **Left to the human (§10):** a stash (`stash@{0}`), two prunable
  worktrees, and the branches `worktree-agent-aa6a4caca0a6696f1` and
  `2.13-asdf`.
- **Ignored:** `bin/`, `/build/`, `boot/build/`, `*.fasl`, the session-ID
  files, `166-error.out`, `tmp/`, `.claude/settings.local.json`.
- **Caches outside the repository:**
  - ASDF fasls in `~/.cache/common-lisp/`;
  - the library cache in `~/.cache/quasischeme/`, with the Racket cache beside it;
  - the Makefile's logs in `/tmp/quasischeme-test-*.log`.

  Hermetic runs redirect them (AGENTS.md §7).

### 3.9 Untracked notes: inventory and owning tickets

The untracked files at the repository root are the user's notes. They
are read-only history and stay untracked and in place. Each open item
has a ticket that quotes it.

| Note | Open item (quoted or summarized) | Ticket |
|---|---|---|
| `todo` | "fix boostrap & test CI" | QSM-0.1 |
| `todo` | "should see if there are easy ways to make the scheme impl portable across all modern common lisp implementations. - abcl, ecl, clasp, dotcl, claminga, LCL, evergreen, ..." | Milestone 3 (QSM-3.1–3.10); other implementations: §10 item 7 |
| `todo` | "Bring in usocket for networking support across schemes which expect it" (done for SRFI 106 only) | QSM-4.9 |
| `todo` | "for guile, we should offer two systems perhpas? - :guile which binds directly to the C API/interface from common lisp - :pseudoscheme/guile which is our implementation" | QSM-4.7 |
| `todo` | "maybe `qsc` is the compiler (to common lisp) with qs as the repl/interactive?" | QSM-8.6 |
| `todo` | "also change version to 1.0 when the change occurs. - likely once guile and chez are complete & all srfi's are implemented." | §10 item 1 |
| `todo` | "there should be an interpreter for linklets in the source tree written in chez-scheme" | QSM-8.5 |
| `todo` | "additionally we should test and see how if the emitted code from schemify will run here" | QSM-8.4 |
| `todo` | "Guile test suite regressions (2026-10-24 …): ecmascript.test crashes … sandbox.test crashes … hooks.test: 'run-hook: destructive procs' fails … coverage.test: 1 fail, 1 error" | QSM-4.1 |
| `todo` | "libguile tests that run on any machine (no podman, no LilyPond, no real Guile)" | QSM-4.3 |
| `ideas.md` | "Allow for compiling scheme into C (using current frontend; ie will be a new emit for our core scheme)" | QSM-8.3 (spike) |
| `ideas.md` | "we should add a document which actually describes its behavior ; ie IIRC it is *essentially* r4rs" | QSM-0.10 |
| `future-directions-idea.md` | "We have to write our own `libguile.h` regardless. It must be written clean-room from the manual" | QSM-4.4 |
| `future-directions-idea.md` | "Real builds through `guix-daemon`." (Guix stage 3) | QSM-4.6 |
| `future-directions-idea.md` | "Keep schemify for cross-checking. Running both backends and comparing results is a cheap differential test." | QSM-8.4 |
| `future-directions-idea.md` | "the existing `contrib/racket-linklets` work would move to something like `src/racket/` with tests under `tests/`" | QSM-8.2 |
| `future-directions-idea.md` | "Chez's optimize level 3 would map to a `(safety 0)` mode." | QSM-8.1 |
| `future-directions-idea.md` | "Fewer boolean tests. Recognise procedures that return booleans and use CL tests directly, avoiding the `ps:truep` wrapper." | QSM-8.8 (verify) |
| `future-directions-idea.md` | "The Racket shim and the nanopass test both need converting." (no nanopass test is in the tree) | QSM-8.2 checks it |
| `next-steps.txt` | "Next is let-bound locals instead of pre-binding them to `'qs:false` and assigning them with `SETQ`." | QSM-2.6 |
| `next-steps.txt` | "After that comes the optimization-level switch, then the named-primitive, `defknown` and arm64 VOP layers" | QSM-8.1, QSM-8.7 |
| `next-steps.txt` | Items 1–7 (lazy resume) | none: tried and not kept (`docs/optimizations.md:677`, commit 2232bd6) |
| `tmp/sbcl-arm64-closure-init-bug.txt` (and the repro `.lisp`) | the upstream report for arm64 `CLOSURE-INIT` without a card mark | QSM-0.13 |
| `166-error.out` | SRFI 166: 7 failures, 1 error | none: fixed (352 passed, 0 failed on 2026-11-12) |
| `version.sexp` | contains `"3.0"`; nothing reads it | §10 item 1 |
| `tmp/hawk/` | a clone of a C tracing JIT | §10 item 2 |
| `old-revided-reports`, `paper.pdf`, `rnrs-pdfs/` | reference material | none |
| `claude-current`, `claude-session` | Claude session resume IDs | none (ignored) |

### 3.10 Existing plans and how they relate

- **`ROADMAP.md`** (2026-10-23). These sections are marked "Superseded by
  docs/harness/roadmap.md" with their text kept:
  - "Where things stand";
  - "3. Continuations";
  - "6. The other Schemes' modes";
  - the Portability bullet of "7. Directions queued".

  Sections 1 (Speed), 2 (The library cache), 4 (The Lisp bridge) and 5
  (Real-world libraries) remain the user's backlog and are not yet
  ticketed (§10 item 6).
- **Mode design documents:** `docs/continuations.md`,
  `docs/optimizations.md`, `docs/guile.md`, `docs/guile-vm.md`,
  `docs/libguile.md`, `docs/racket.md`, `docs/racket-linklet-compiler.md`,
  `docs/chez.md` and `docs/executables.md`. These are design references;
  if one conflicts with this roadmap, escalate.
- **Historical, read-only:**
  - `docs/rename-quasischeme.md` (done 2026-10-18);
  - the untracked notes (§3.9);
  - `build/agents/*.txt` (ignored notes from earlier agent sessions).

## 4. Architecture

```text
 R1RS..R7RS, Chez        Guile source              Racket source (.rkt)
       |                      |                           |
   psyntax (vendor/)    Guile's psyntax           Racket's expander (extracted linklet)
       |                      |                           |
       |                   Tree-IL ------.             linklets
       |                      |          |                |
       |              compile-tree-il   Guile compiler   compile-linklet-form
       |                      |          -> CPS -> bytecode -> VM / JIT (src/guile/vm*.lisp)
       v                      v                           v
                     core Scheme (s-expressions; spec: QSM-0.10)
                                   |
        open-top-level: open-primitives, definitions-as-letrec   (src/psyntax.lisp)
                                   |
        optimize-core: cpletrec, cp0, cptypes, cpcommonize, cpdx (src/cp*.lisp)
                                   |
        cc-transform (full continuations; src/continuations.lisp)  -- no CPS
                                   |
        Pseudoscheme translator: alpha -> node tree -> generate (src/*.scm, .qso)
                                   |
        Common Lisp + post-passes -> SBCL compile / compile-file (+ src/sbcl-vops.lisp)
                                   |
   runtimes: src/r6rs, src/r7rs, src/numbers.lisp, src/chez, src/guile,
             src/racket/native, src/libguile (C), src/interop.lisp
                                   |
   bin/quasischeme = one saved SBCL image with every mode   (contrib/cli)
```

### 4.1 Recommended libraries and tools

| Concern | Choice | Why |
|---|---|---|
| Portability shims | float-features, trivial-garbage, bordeaux-threads (v2 API), trivial-gray-streams, trivial-cltl2, CFFI, babel, cl-unicode, UIOP (already used; ROADMAP §7) | Already the project's choice; keeps SBCL internals behind `#+sbcl` |
| Sockets | usocket (already used for SRFI 106) | Portable across Lisps |
| Image compression | SBCL `:compression` with zstd (`:sb-core-compression`, SBCL ≥ 2.2.6; https://bugs.launchpad.net/bugs/1881089) | 160 MB to 32 MB measured; costs start-up time |
| Tree-shaking | The user's `tree-shaker` (ASDF system `tree-shaker` 0.1.0, unpublished, commit `ce22e9d`, found through Quicklisp's local projects; SBCL only, tested on 2.6.9 arm64), behind a flag | 8–14% off a small program per its README; must keep the runtime's packages |
| Lint (ratchet only) | sblint (https://github.com/fukamachi/sblint) and/or Mallet (https://github.com/fukamachi/mallet): **verify in QSM-0.11** | Counts as a ratchet, not a gate on today's backlog |
| Coverage | `sb-cover` (an SBCL contrib): **verify in QSM-0.11** | Reports only |
| Property tests | check-it (https://github.com/yurrriq/check-it): **verify in QSM-0.12** | For optimizer passes |
| Differential testing | `tests/fuzz/difftest.py` (exists), with oracles Guile (exists), Chez, Racket and Chibi (all installed) | Checks against independent implementations |
| CI with several Lisps | 40ants/setup-lisp (https://github.com/40ants/ci): **verify in QSM-0.8**; one report says only SBCL and ECL work | The matrix for ECL and CCL |

### 4.2 Repository layout (harness files marked "new")

```text
AGENTS.md                      new: rules for every agent
CLAUDE.md                      new: @AGENTS.md
docs/harness/roadmap.md        new: this plan
docs/harness/TICKETS.md        new: status board
docs/harness/agent-protocol.md new: lifecycle, reviewer checklist, gates
docs/                          existing mode design documents (references)
notes/                         new: handoff, review and gate notes; templates/
.claude/skills/                start-ticket, finish-ticket, review-ticket, milestone-gate (new);
                               quasischeme-dev, pipeline-change, measure-perf, correctness (new);
                               run-quasischeme (existing)
scripts/                       planned in QSM-0.3: cap, check.sh
src/  vendor/  tests/  boot/  contrib/  utils/  bench/  examples/   as in README "Repository layout"
```

## 5. Domain model / core data structures

The hub is the **core Scheme form**: the s-expression language every front
end produces and the back end consumes (specified by QSM-0.10). The
others:
- **psyntax core output:** `(primitive x)` and `G$n` gensyms.
- **Tree-IL:** 18 struct types.
- **Linklet:** an s-expression with correlated objects.
- **Optimizer side tables:** `*vi*`, plus marks `%cp-the-T`,
  `%cp-assume-T` and `%cp-dx`.
- **Continuation frames:** `#(machine promoted site n live …)` on
  `*fstack*`, or SBCL arm64 stack-site marks.
- **The Pseudoscheme node tree:** tagged vectors.
- **Library cache entries:** fasls keyed by a build signature.

**Invariants**
- **No CPS of general code.** Scheme procedures are ordinary Lisp
  functions with ordinary calls and returns, so Lisp code (`sort`,
  `mapcar`, CLOS) calls them directly. (Human decision, 2026-11-12.)
- **SBCL-specific code is guarded.** It sits under `#+sbcl` (or
  `#+(and sbcl arm64)`), with a portable fallback that the other hosts
  run, and the fallback is tested (QSM-0.7 counts unguarded uses).
- **Every front end's output is valid core Scheme,** accepted by the
  QSM-0.10 validator.
- **Optimizer levels agree.** `QUASISCHEME_OPTIMIZE=0`, `1` and `2`, full
  and escape-only continuations, and `QUASISCHEME_FAST=0` all produce the
  same observable behavior (difftest's configurations).
- **Generated files come from their generator.** The bootstrap fixpoint
  holds (`make bootstrap-check`).
- **Caches never change behavior.** A cold cache, a warm cache and
  `QUASISCHEME_LIBRARY_CACHE=0` give the same results, and a killed run
  never leaves a cache that later runs fail on.
- **No absolute developer paths** in tracked files or in saved images'
  behavior.
- **Conformance never regresses** below the recorded baseline
  (`docs/harness/baseline.md`, from QSM-0.4) on any host.
- **Size and debugging flags are opt-in.** Tree-shaking and stripping
  debug information happen only when explicitly requested.

## 6. External integrations: facts and pain points

### 6.1 Host Common Lisps
- **SBCL** 2.6.10 was released 2026-10-29 (https://sbcl.org/news.html).
  - The CI pin is 2.6.9 (QSM-0.1).
  - `src/sbcl-vops.lisp` and `src/sbcl-compiler.lisp` patch SBCL internals, written against `sbcl-2.6.9`; they switch on when the internals they use exist.
- **ECL.** 26.5.5 is installed locally. 26.3.27 was released 2026-03-27
  (https://ecl.common-lisp.dev/posts/ECL-26327-release.html).
  - It compiles through C, so it is slow to compile.
  - Its compiled code eliminates only self tail calls (verify in QSM-3.2).
- **CCL.** 1.14 darwinarm64 is installed and runs. The 1.13 release notes
  excluded arm64, and the Homebrew formula is deprecated
  (https://lists.clozure.com/pipermail/openmcl-devel/2024-August/012910.html,
  https://formulae.brew.sh/formula/clozure-cl). Verify the arm64 build's
  status in QSM-3.4.
- **ABCL** 1.9.2 (2023). It cannot save images (unverified; QSM-3.8) and
  has no TCO.
- **Clasp** 2.7.0 (2025-01, https://clasp-developers.github.io/news.html).
  Not installed (QSM-3.9).
- **Tail calls.** The CL standard does not require tail-call elimination;
  SBCL and CCL do it, the others only partly (https://quickdocs.org/ptc).
  A host without it needs a trampoline strategy (QSM-3.2).
- **SBCL arm64 bug.** `CLOSURE-INIT` stores without a GC card mark. A local
  fix is in `src/sbcl-compiler.lisp:259`. No upstream fix was found by
  2026-11-07 (https://planet.sbcl.org/); verify in QSM-0.13.

### 6.2 Reference implementations
- **Racket** 9.3 (2026-08-13, https://blog.racket-lang.org/2026/08/racket-v9-3.html).
  - The source is fetched by `utils/racket/setup.sh` into `build/external/racket` (tag v9.3).
  - Packages are fetched by `utils/racket/packages.sh` into `build/external/racket-pkgs`.
  - Racket disclosed a compromised macOS snapshot build host: snapshots built on or before 2026-08-10 are suspect. Use release tags only.
- **Guile** 3.0.11 (2025-12-01). Guile mode loads the installed Guile's
  Scheme sources.
- **Chez** 10.4.1: `chez`/`petite` on PATH; source in
  `build/external/chezscheme`.
- **Racket CS sizes.** The floor is the Chez boot files; `raco exe` keeps
  only reachable modules; boot files can be LZ4-compressed, at about a 25%
  start-up cost
  (https://racket.discourse.group/t/how-to-make-small-executables/2244,
  https://racket.discourse.group/t/code-compression-options/908).
  Measured locally: 56.3 MB for a `racket/base` hello, starting in 0.43 s.

### 6.3 Container (podman)
`utils/container/` builds a Linux container with Guile, Guix and
LilyPond. libguile, LilyPond and Guix tests run only there.
**Pain point:** podman needs `podman machine` running on macOS. Tests
that need it skip with a message when it is absent.

### 6.4 Quicklisp
The runners load `~/quicklisp/setup.lisp` when it exists and fetch any
missing dependencies on first use.
**Pain point:** the first run needs network access. CI caches
`~/quicklisp`.

### 6.5 GitHub Actions
- `.github/workflows/ci.yml` has a `test` job and a `bootstrap` job;
  `bench.yml` runs by hand.
- The runners are x86-64, so the arm64-only VOP layer is off there and CI
  exercises the portable continuation frames. Good for portability; bad
  for catching arm64-only bugs. Local gate runs cover arm64.

### 6.6 SRFIs and R7RS-Large
- **SRFIs** (https://srfi.schemers.org/, fetched 2026-11-12):
  - the newest final SRFI is 279;
  - SRFI 272 (Pretty Printing, final 2026-11-01) is not in `-V`'s `scheme.srfi` list (QSM-6.1);
  - drafts to watch: 266, 268, 276 and 280–288.
- **R7RS-Large.** Only the Red edition (data structures) and the Tangerine
  edition (numerics, generators, regex, mapping, bitwise, format) were
  finalized (https://small.r7rs.org/wiki/RedEdition,
  https://groups.google.com/g/scheme-reports-wg1/c/Vk8oqyUoLHg).
  - The work has since split into Foundations and Batteries, published as fascicles, with a 2028 target (https://scheme-reports.simplelists.com/scheme-reports/msg/26443044/).
  - The Batteries work is reported as stalled.
  - So the plan is an audit of Red and Tangerine (QSM-6.3) and tracking Foundations (QSM-6.6).

## 7. Core algorithms

### 7.1 The pipeline
See §3.1 and §4. QSM-0.9 writes the complete pipeline document: every
front end, every IR, each with its producer and consumer at
`file:line`, and one program traced through every stage using the real
tools (`QUASISCHEME_OPTIMIZE_TRACE=1`, `--emit-lisp`, `,lisp`).

### 7.2 Continuations (Milestone 2)
The current design is described in `docs/continuations.md`.
- **Capture.** Machines (state-machine procedures) record frames: on
  `*fstack*` (portable), or as code marks read from SBCL's stack (arm64
  stack sites). Capture copies only new frames.
- **Re-entry.** Throw to the base, then rebuild every frame recursively,
  outermost first. This is O(depth) per re-entry.
- **v1 work, ordered for measurable wins:**
  1. benchmarks (QSM-2.1);
  2. lazy rebuild of the innermost K frames over an underflow frame
     (QSM-2.2): O(K) per re-entry, and iterative;
  3. cross-library safety, so fewer sites (QSM-2.3);
  4. frame-aware primitives, so fewer barriers (QSM-2.4);
  5. one dynamic environment, so capturing it is O(1) (QSM-2.5);
  6. let-bound locals (QSM-2.6).
- **Host-specific work, each with a portable fallback:**
  - stack sites on x86-64 (QSM-2.7a/b);
  - a cheaper portable frame stack (QSM-2.8);
  - a spike on copying SBCL's stack directly (QSM-2.9).
- **Properties every change keeps:**
  - the continuation suite passes;
  - the R5RS, R6RS and R7RS suites pass with full continuations;
  - difftest agrees across `default`, `escape`, `no-stack-sites`, `site-closures` and `parametric`;
  - re-entry through a frame-aware primitive gives the same result as escape-only where both are defined.

### 7.3 Executable layering (Milestone 1)
- **v1, exact and simple:**
  - measure each ASDF system's share of the image (QSM-1.3);
  - save a base image (core, R5RS/R6RS/R7RS, Chez, CLI);
  - load the Guile, libguile and Racket layers from fasl bundles on demand when their flag is given (QSM-1.4);
  - build a Racket executable from the base image plus the Racket layer plus only the compiled linklets the program reaches (QSM-1.5).
- **Stretch:**
  - a shared installed runtime plus per-program fasls, Racket's SharedCollects model (§10 item 10);
  - tree-shaking under a flag (QSM-1.6).
- **Pain points:**
  - a saved image's state that lives in specials must be re-established when a layer loads;
  - the Racket saved core preloads `racket/base`, which is why it is large;
  - SBCL's compiler stays reachable, so even a shaken image keeps it (tree-shaker README).

## 7b. Correctness strategy

| Module / area | Rung now | Tools | Evidence required per ticket |
|---|---|---|---|
| Optimizer (`src/cp*.lisp`), continuation transform (`src/continuations.lisp`), translator (`src/*.scm`) | Differential and generative, plus suites | `difftest.py` configurations; check-it properties (verify in QSM-0.12); the QSM-0.10 core validator | New transformation: a difftest configuration or a property showing O0 and O2 (or full and escape) agree, plus a regression test |
| Mode runtimes (`src/r6rs`, `src/r7rs`, `src/chez`, `src/guile`, `src/racket/native`) | Conformance suites plus oracle diffs | Upstream suites (chibi, Racket R6RS, Chez mats, Guile suite, racket-test-core); oracle runs against chez, guile, racket, chibi | Per-mode tally at least the baseline; a failing upstream test fixed gets its runner count updated |
| SBCL-specific code (`src/sbcl-*.lisp`, `#+sbcl` blocks) | Cheap ratchets | Count of unguarded `sb-` references (QSM-0.7), SBCL warning counts (QSM-0.11) | Counts do not rise; the portable fallback is exercised by a test with the SBCL path off (`QUASISCHEME_FAST=0`, `QUASISCHEME_STACK_SITES=0`) |
| libguile C layer (`src/libguile/*.c`) | Example tests (container) | `tests/libguile/run.sh`; **future rungs:** `abidiff` against real libguile on Linux (ELF only, https://man7.org/linux/man-pages/man1/abidiff.1.html), ASan/UBSan | Program tests in the container |
| Generated files | Fixpoint | `make bootstrap-check` | Regenerated, never hand-edited |
| Everything else | Example tests plus ratchets | Runners, `contrib/cli/test.sh`, the QSM-0.11 counts | Tests for the change, including an error path |

- **Commands:** `scripts/check.sh` (planned in QSM-0.3), with the ratchet
  counters from QSM-0.7 and QSM-0.11, and `--full` adds the difftest run
  from QSM-0.12.
- **Ratchet:** strictness only increases. Counts are recorded in
  `docs/harness/baseline.md` and may only go down. A suppression needs a
  justification comment, a ticket ID and reviewer approval recorded in the
  review note.
- **Future rungs** (not adopted yet): libguile ABI checks with `abidiff`
  in the container; formal methods (the PLT Redex R6RS model,
  https://users.cs.northwestern.edu/~robby/an-operational-semantics-for-scheme,
  as an oracle for core forms; Coalton for new pure passes).
- **Standing gate prompt:** at every gate the reviewer considers, and
  records in the gate note, whether any module should move up a rung.

## 8. Milestones and tickets

Tickets are sized for one builder session. Each milestone ends at a
reviewer gate. **Parallel tracks:**
- after GATE-0: Track S (Milestone 1), Track C (Milestone 2) and Track P
  (Milestone 3), one builder each;
- later: Track G (4), Track R (5), Track N (6) and Track Z (7);
- Milestone 8 last.

The default test for every ticket is `scripts/check.sh` (until QSM-0.3
merges: the runners in AGENTS.md §7). "Tally ≥ baseline" means the
counts in `docs/harness/baseline.md`.

### Milestone 0: Baseline and hygiene

| ID | Title | Deliverable / acceptance | Test |
|---|---|---|---|
| QSM-0.1 | Fix CI: SBCL 2.6.10 | (1) `.github/actions/setup-lisp/action.yml` installs SBCL 2.6.10 x86-64 Linux with a verified sha256 (fact checked against sbcl.org: verify); (2) `quasischeme.asd` fails at load with a message naming the minimum SBCL version when an internal it needs is absent, instead of a READ error; (3) `make test` and `boot/bootstrap.sh --all --check` pass locally; (4) the handoff note gives the exact `gh run` command for the human to check after pushing. Quotes `todo`: "fix boostrap & test CI". | `make test`; `SBCL=sbcl boot/bootstrap.sh --no-install --check` |
| QSM-0.2 | Relocatable install and stale-binary check | (1) The image finds `src/srfi/` and other source directories from `QUASISCHEME_HOME`, else from the executable's own location, else from the build root, never only from a path baked in at save time; (2) `-V` prints the build's git commit and the resolved install directory; (3) a CLI test copies the tree to a new directory, runs the binary there, and `(import (srfi 1))` works; (4) `scripts/check.sh` (or the runner) warns when `bin/quasischeme` is older than `HEAD`; (5) `docs/configuration.md` documents `QUASISCHEME_HOME`. | `make -C contrib/cli test` |
| QSM-0.3 | Portable process-group cap and `scripts/check.sh` | (1) `scripts/cap SECS CMD…` runs a command in its own process group, kills the whole group after SECS, and exits 124 with a message; works in sh, bash and zsh on macOS and Linux; (2) `scripts/check.sh [--quick\|--full] [--lisp sbcl\|ecl\|ccl]` runs the suites with every cache redirected under `build/check/`, prints one tally line per suite, compares them with `docs/harness/baseline.md`, and exits non-zero on any regression or cap; (3) `--quick` covers syntax-case, r7rs, r5rs, continuation and interop in under 3 minutes on the reference machine; `--full` covers every `tests/run-*-tests.lisp`, the CLI tests, the SRFI programs and difftest; (4) no output goes outside the repository. | `scripts/check.sh --quick` |
| QSM-0.4 | Record the baseline | (1) `docs/harness/baseline.md` holds every suite's tally per host (SBCL now; ECL and CCL as far as they get), including the full Chez mats, the full Guile suite with cold and warm module caches, all SRFI programs, `make test-escape`, the library corpus, `tests/racket/run.sh linklet`, bench geomeans, and the executable-size table, with versions and the date; (2) a machine-readable section that `check.sh` reads; (3) stale numbers corrected in README.md, `docs/executables.md` and `docs/chez.md` (see roadmap §3.3 item 6), with the old `ROADMAP.md` table left as it is under its superseded marker. | `scripts/check.sh --full` |
| QSM-0.5 | Crash-safe Racket and library caches | (1) Every cache file (`.zo`, `.fasl`, `.meta`, saved cores) is written to a temporary name and renamed into place; (2) an entry that fails to load is discarded and rebuilt rather than signaling; (3) a test kills a cold `#lang racket/base` run partway (`scripts/cap`) and a rerun then succeeds; (4) the same for the library cache. | the new kill-and-rerun test |
| QSM-0.6 | Repository hygiene | (1) `tests/fuzz/__pycache__/` is removed from the index (`git rm --cached`) and `__pycache__/` is ignored; (2) `check.sh` fails when a tracked text file contains an absolute home-directory path (`/Users/<name>/`, `/home/<name>/`); (3) `difftest.py` writes nothing in the tree when `--keep` names another directory. | `scripts/check.sh --quick` |
| QSM-0.7 | ECL loads again, with a guard | (1) `src/numbers.lisp:290` and any other unguarded SBCL reference is fixed so `quasischeme/r7rs` loads on ECL 26.5.5; (2) R5RS 189/189 and R7RS 978/978 on ECL; (3) a lint (`scripts/sbcl-refs` or in `check.sh`) counts `sb-` package references outside `#+sbcl` and the allowed files, records the count in the baseline, and fails when it rises; (4) the command for running a runner on ECL is documented in AGENTS.md §7. | `scripts/check.sh --quick --lisp ecl` |
| QSM-0.8 | CI host matrix (smoke) | (1) CI gains ECL and CCL jobs that load the system and run the runners that pass today on that host; (2) CCL's state is established (does `quasischeme/r7rs` load on CCL 1.14?) and recorded in the baseline; failures become follow-up rows in Milestone 3; (3) the per-host baselines are what the jobs compare against. | the workflow, run locally with `scripts/check.sh --lisp ccl` |
| QSM-0.9 | Pipeline and IR document | `docs/pipeline.md`: (1) every front end (R1RS–R7RS, Chez, Guile native, the Guile VM path, Racket) to CL; (2) a table of each IR with its representation, producer and consumer (`file:line`); (3) one small program traced through every stage with real output from `QUASISCHEME_OPTIMIZE_TRACE=1`, `--emit-lisp` and `,lisp`; (4) linked from README.md and AGENTS.md. The reviewer checks every `file:line`. | reviewer spot-check |
| QSM-0.10 | Core-language specification and validator | (1) `docs/core-language.md`: every core form, its semantics, and how it differs from R4RS and R5RS (`values`, `letrec*`, `case-lambda`, `(primitive x)`, letrec checks, continuation marks as calls), quoting `ideas.md`: "it is *essentially* r4rs - should note this somewhere explicitly"; (2) a validator (`QUASISCHEME_CHECK_CORE=1`) that checks each form entering `host-eval`; (3) it accepts everything the R5RS, R6RS and R7RS suites and the Guile and Racket smoke tests produce, and rejects at least 10 malformed forms in a test. | `QUASISCHEME_CHECK_CORE=1 scripts/check.sh --quick` |
| QSM-0.11 | Ratchet counters: warnings, lint, coverage | (1) `check.sh` records the number of compiler warnings and style-warnings in a full load and fails when it rises; (2) sblint and/or Mallet are tried, and their counts recorded or the tool rejected with reasons (verify); (3) a documented `sb-cover` command produces a coverage report for one runner (report only, not gated). | `scripts/check.sh --quick` |
| QSM-0.12 | Differential and generative testing | (1) `difftest.py` gains oracles Chez (via `chez-akku`'s R7RS libraries or a prelude), Racket (`#lang r7rs` or a prelude: verify) and Chibi, each skipped with a message when absent; (2) a fixed seed range runs in `check.sh --full`; (3) at least one check-it property (or a generator in Python if check-it is rejected) asserts that `QUASISCHEME_OPTIMIZE=0` and `2` agree on random core forms; (4) the counts are recorded. | `scripts/check.sh --full` |
| QSM-0.13 | SBCL arm64 CLOSURE-INIT: prepare the upstream report | (1) The repro from `tmp/sbcl-arm64-closure-init-repro.lisp` is copied (not moved) into `tests/sbcl/closure-init-repro.lisp`; (2) it is run on stock SBCL 2.6.10 arm64 and on SBCL master (fetched into `build/external/`), with results recorded; (3) `docs/harness/sbcl-closure-init-report.md` is ready for the human to file at bugs.launchpad.net/sbcl; (4) the local fix in `src/sbcl-compiler.lisp` is switched off automatically once upstream has the barrier. Agents do not file it; filing is the human's. | `sbcl --non-interactive --no-userinit --load tests/sbcl/closure-init-repro.lisp` |

**Gate 0 demo:** a clean clone of `main` with `scripts/check.sh --full`
passes on SBCL, matching `baseline.md`. `scripts/check.sh --quick --lisp
ecl` passes. The CCL result matches its recorded baseline. After the
human pushes, the GitHub Actions run of that commit is green on the SBCL,
ECL and CCL jobs. A copied tree runs `(import (srfi 1))`. The executable
size table and the benchmark geomeans are recorded.

**Pain point:** CI runs x86-64 and develops on arm64. The VOP layer is
arm64-only, so CI tests the portable continuation frames; local runs test
the stack sites.

### Milestone 1: Size and start-up (Track S)

| ID | Title | Deliverable / acceptance | Test |
|---|---|---|---|
| QSM-1.1 | Size and start-up measurement | `scripts/measure-exe` builds hello in every mode (r7rs, r6rs, r5rs, chez, guile, `racket/base`, `#lang racket`) and the `raco exe` equivalent, and records size, zstd size, and start-up (median of 5 runs, wall time and instructions retired) in `bench/SIZES.md`. | `scripts/measure-exe` |
| QSM-1.2 | Compressed executables (option) | `--compile … --compress[=LEVEL]` and `make -C contrib/cli COMPRESS=1` save with zstd compression when `:sb-core-compression` is present, else stop with a clear message; on other hosts the flag says it is unsupported; size and start-up measured; documented in `docs/executables.md` and `docs/configuration.md`. | `make -C contrib/cli test` with a compressed-build test |
| QSM-1.3 | Spike: image layering | `docs/harness/image-layers-spike.md`: each system's share of the image (`room`, heap walk), which state each mode keeps in the image, the Racket saved core's contents, how a layer loads on demand, and a go/no-go with size targets for QSM-1.4 and QSM-1.5. A negative result is acceptable. | report |
| QSM-1.4 | Base core plus mode layers | (Only on a "go" from QSM-1.3.) The base image leaves out the Guile, libguile and Racket systems; `--guile` and `--racket` load their layer from a fasl bundle; an R7RS hello executable contains no mode layer; every suite matches the baseline; sizes and start-up meet QSM-1.3's targets. | `scripts/check.sh --full`; `scripts/measure-exe` |
| QSM-1.5 | Smaller Racket executables | A `--compile` Racket executable holds the base, the Racket layer and only the compiled linklets the program reaches, not the 477 MB preloaded core; size and start-up meet QSM-1.3's targets; tests/racket programs still pass. | `sh tests/racket/run.sh linklet`; `scripts/measure-exe` |
| QSM-1.6 | Tree-shaking behind a flag | `--compile … --tree-shake` (and `QUASISCHEME_TREE_SHAKE=1`) uses the `tree-shaker` system when it can be loaded (Quicklisp local projects), with `:keep-packages` covering every package the runtime resolves by name (`SCHEME`, `QS`, `QSX`, the mode packages); unavailable means a clear message and an unshaken build; off by default; a CLI test per mode compares shaken and unshaken output; sizes measured. | `make -C contrib/cli test` (skips when tree-shaker is absent) |
| QSM-1.7 | Stripping under a flag | `--strip=docstrings,source-forms` (tree-shaker options) and a per-mode safe set; a test shows backtraces and procedure arities still behave as documented (Racket needs arities; `docs/racket.md`); off by default. | CLI tests |
| QSM-1.8 | Start-up time | A start-up profile of the R7RS hello executable (1.34 s on 2026-11-12) in the handoff note; the largest init-time cost is removed or deferred; median start-up improves by at least 30% over QSM-1.1's measurement. | `scripts/measure-exe` |

**Gate 1 demo:** the `bench/SIZES.md` table before and after, for every
mode, with compression and layering; r7rs-benchmarks geomeans
(including `ctak` and `fibc`) within noise of the baseline; suites at the
baseline on SBCL, ECL and CCL; CI green.

### Milestone 2: Continuation speed (Track C)

| ID | Title | Deliverable / acceptance | Test |
|---|---|---|---|
| QSM-2.1 | Continuation benchmarks | `bench/cont/` adds re-entry microbenchmarks (a generator's yield; re-entry at depths 10, 100, 1,000, 10,000; `amb`) alongside `ctak` and `fibc`; a runner records instructions retired for QuasiScheme (full, escape-only, `QUASISCHEME_STACK_SITES=0`) and for Chez, Guile and Racket; the table goes in `docs/continuations.md`. | the runner |
| QSM-2.2 | Lazy rebuild over an underflow frame | Re-entry rebuilds only the innermost K frames on top of an underflow frame that rebuilds more when returned to (`docs/continuations.md` "Lazy rebuilding"); re-entry at depth 100,000 does not overflow the stack; QSM-2.1's deep re-entry gets faster; the continuation, R5RS, R6RS and R7RS suites pass; difftest agrees. | `scripts/check.sh --full` |
| QSM-2.3 | Safety across libraries | Each exported procedure's safety is recorded in the library cache and trusted for unassignable imports (`docs/continuations.md` "Safety across libraries"); `lattice`, `matrix`, `conform` and `quicksort` retire fewer instructions; suites pass. | bench subset and `scripts/check.sh --full` |
| QSM-2.4 | Frame-aware primitives | R6RS `fold-left`, `fold-right`, `find`, `filter`, `partition`, `exists`, `for-all`, `remp`, `memp` and `assp`, the sorts, `force` and `call-with-port` become frame-aware, so re-entry through them works; one test per primitive re-enters through it. | `run-continuation-tests.lisp` |
| QSM-2.5 | One dynamic environment | Winders, handlers, parameterization and marks are one captured value (O(1) to capture); suites and difftest pass; QSM-2.1 numbers recorded. May split into 2.5a/2.5b. | `scripts/check.sh --full` |
| QSM-2.6 | Let-bound locals in machines | Only variables live across a label are hoisted; others stay let-bound (quoting `next-steps.txt`: "let-bound locals instead of pre-binding them to `'qs:false` and assigning them with `SETQ`"); benchmark table shows the change; suites pass. | bench subset and `scripts/check.sh --full` |
| QSM-2.7a | Spike: stack sites on x86-64 | Report on porting the arm64 site marks (`src/sbcl-vops.lisp`, `docs/continuations.md` "Stack sites") to SBCL x86-64, the CI architecture: go/no-go with an estimate. | report |
| QSM-2.7b | Stack sites on x86-64 | (Only on a "go".) x86-64 sites with the same marks and `QUASISCHEME_STACK_SITES=0` fallback; suites pass on x86-64 in CI. | CI, `scripts/check.sh --full` |
| QSM-2.8 | Cheaper portable frame pushes | A per-thread frame stack (vector plus fill pointer) replaces the special binding per site on the portable path (`docs/continuations.md` "Cheaper portable frame pushes"); faster on ECL and CCL and with `QUASISCHEME_STACK_SITES=0` on SBCL; suites pass on all three hosts. | `scripts/check.sh --full --lisp ecl` |
| QSM-2.9 | Spike: copying SBCL's control stack | Report on capturing and reinstating SBCL control-stack segments directly (arm64), within the no-CPS invariant and with the portable fallback intact; go/no-go with measurements from a prototype kept out of `main`. | report |

**Gate 2 demo:** the continuation benchmark table (QSM-2.1) before and
after, against Chez, Guile and Racket, with `ctak` and `fibc` from
r7rs-benchmarks; suites at the baseline on SBCL, ECL and CCL; CI green.

### Milestone 3: CL portability (Track P)

| ID | Title | Deliverable / acceptance | Test |
|---|---|---|---|
| QSM-3.1 | Portability inventory | `docs/portability.md`: every SBCL-specific use (1,711 `sb-` references counted on 2026-11-12) classified by subsystem and by its portable replacement, with the ratchet count from QSM-0.7. | report plus the counter |
| QSM-3.2 | Tail calls on every host | Tests of deep mutual tail recursion (10⁷ calls) in each host's compiled and interpreted code; a strategy for hosts without full TCO (a trampoline for non-self tail calls under a host feature); ECL passes. | the new tests on SBCL, ECL, CCL |
| QSM-3.3 | ECL: the full standard suites | R6RS (8902; only 1,614 were reached on 2026-10-27), reports, continuations and interop pass on ECL. May split by suite. | `scripts/check.sh --full --lisp ecl` |
| QSM-3.4 | CCL: the standard suites | R5RS, R7RS, R6RS, reports and continuations pass on CCL 1.14 (arm64 macOS) and on CCL x86-64 Linux in CI. | `scripts/check.sh --full --lisp ccl` |
| QSM-3.5 | The command on ECL and CCL | `make -C contrib/cli LISP=ecl` and `LISP=ccl` build a working `bin/quasischeme`; `contrib/cli/test.sh` passes, with mode tests that need SBCL skipped with a message. | `make -C contrib/cli test LISP=ecl` |
| QSM-3.6 | Spike: Chez, Guile and Racket modes on ECL and CCL | Report: what blocks each mode (VOPs, `sb-alien`, FFI through CFFI, threads), with go/no-go per mode and host. | report |
| QSM-3.7 | CI matrix with full suites | The ECL and CCL CI jobs run the full standard suites (after QSM-3.3 and QSM-3.4). | CI |
| QSM-3.8 | Spike: ABCL | Report: does it load, what of the image model fails (no saved images: verify), TCO. | report |
| QSM-3.9 | Spike: Clasp | Install Clasp 2.7 (or later) in the container or locally (verify how), try loading, and report. | report |
| QSM-3.10 | Remaining host-specific pieces | `disable-float-traps`, listing the environment, the standard binary ports, and the CLI's interrupts work on ECL and CCL (ROADMAP §7 "Portability"). | tests per piece |

**Gate 3 demo:** R5RS, R6RS, R7RS, reports and continuation suites pass
on SBCL, ECL and CCL locally and in the CI matrix; the portability
inventory's counter is below its Gate 0 value.

### Milestone 4: Guile and libguile (Track G)

| ID | Title | Deliverable / acceptance | Test |
|---|---|---|---|
| QSM-4.1 | Guile suite regressions | Quoting `todo`: "ecmascript.test crashes … sandbox.test crashes … hooks.test: 'run-hook: destructive procs' fails … coverage.test: 1 fail, 1 error". Each is fixed or explained, with cold and warm module caches (sandbox hung at `call-with-allocation-limit 0` per ROADMAP). | `OUT=… sh tests/run-guile-tests.sh hooks coverage sandbox ecmascript` |
| QSM-4.2 | libguile speed, re-measured | A benchmark of C programs calling `scm_*` functions and of LilyPond's small score, on our libguile and on real Guile in the container, with a table in `docs/libguile.md`. | container |
| QSM-4.3 | libguile tests without the container | Quoting `todo`: "libguile tests that run on any machine (no podman, no LilyPond, no real Guile)". `tests/libguile/run.sh` runs on macOS with our own headers (after QSM-4.4), and compares with recorded expected output. | `sh tests/libguile/run.sh` |
| QSM-4.4 | Our own `libguile.h` | A clean-room header written from the Guile manual (Guile's headers are LGPL; quoting `future-directions-idea.md`: "It must be written clean-room from the manual"); the existing extension tests compile against it. | container |
| QSM-4.5 | Stubs Guix's TLS needs | `scm_c_hook_add`, array handles, weak vectors (`docs/libguile.md` "What's next" item 1); guile-gnutls loads in the container. | container |
| QSM-4.6 | Spike: Guix stage 3 | Report on building `hello` through `guix-daemon` with our Guile as the client (quoting `future-directions-idea.md`: "Real builds through `guix-daemon`"). | report |
| QSM-4.7 | Spike: two Guile systems | Quoting `todo`: "`:guile` which binds directly to the C API/interface from common lisp; `:pseudoscheme/guile` which is our implementation". A report with a go/no-go. | report |
| QSM-4.8 | The Guile suite's tail | The full suite's remaining failures (exact error keys, sockets, source properties) fixed or explained per file; tally recorded. | `make test-guile` |
| QSM-4.9 | Sockets on usocket | Quoting `todo`: "Bring in usocket for networking support across schemes which expect it". Guile's socket procedures (and Chez's where they exist) on usocket; tests. | the mode's tests |

**Gate 4 demo:** the full Guile suite tally against the baseline, with no
crashes on a cold module cache; the libguile speed table; CI green on the
host matrix.

### Milestone 5: Racket ecosystem (Track R)

| ID | Title | Deliverable / acceptance | Test |
|---|---|---|---|
| QSM-5.1 | Racket's suite, re-measured | `tests/racket/run-suite.sh` run in full, with a per-file table in `docs/racket.md` against real Racket's counts. | `sh tests/racket/run-suite.sh` |
| QSM-5.2 | Spike: what stops `typed/racket` | Report on `quasischeme --racket -I typed/racket`: the first blockers, time and memory, a plan. | report |
| QSM-5.3 | `typed/racket` boots | A typed `#lang typed/racket` program runs and prints what Racket prints; cold and warm times recorded. May split. | a new program in `tests/racket/programs/` |
| QSM-5.4 | Loading packages | Packages fetched by `utils/racket/packages.sh` load through collection links; a package's module is required from a program. | a new program |
| QSM-5.5 | brag | A sample brag grammar parses its input, with output equal to Racket's. | a new program |
| QSM-5.6 | scribble | A small Scribble document renders to text, with output equal to Racket's. | a new program |
| QSM-5.7 | Spike: slideshow | Report on slideshow's dependencies (`racket/gui`, `racket/draw`): go/no-go. | report |
| QSM-5.8 | rhombus | A Rhombus hello world runs, with output equal to Racket's. | a new program |
| QSM-5.9 | Faster cold start | The cold `#lang racket/base` time (428 s with parallel load on 2026-11-12; "a minute" in `docs/racket.md`) measured alone, profiled, and reduced. | measurement |

**Gate 5 demo:** `tests/racket/run.sh linklet` and the suite table
against the baseline; typed/racket, brag and scribble programs in the
program tests; CI green on the host matrix.

### Milestone 6: RnRS, SRFI and R7RS-Large (Track N)

| ID | Title | Deliverable / acceptance | Test |
|---|---|---|---|
| QSM-6.1 | SRFI 272 | SRFI 272 (Pretty Printing, final 2026-11-01) in `src/srfi/`, with its test program, listed in `-V` and `src/srfi/README.md`. | `sh tests/run-srfi-tests.sh bin/quasischeme 272` |
| QSM-6.2 | SRFI status check | A script compares `-V`'s `scheme.srfi` list with a dated snapshot of srfi.schemers.org's final list and reports what is missing. | the script |
| QSM-6.3 | R7RS-Large Red and Tangerine audit | Every library name of both editions resolves and has a smoke test; a table in `docs/libraries.md` maps each to its SRFI. | the smoke tests |
| QSM-6.4 | Real-program corpus | Akku (228/387) and snow-fort (91/130) re-run; the three biggest causes of failure fixed; numbers recorded. | `tests/run-library-corpus.lisp` |
| QSM-6.5 | More real programs | At least 10 real R7RS or R6RS programs added to `tests/programs/` with expected output taken from Chibi or Chez. | `make test-programs` |
| QSM-6.6 | R7RS-Large Foundations tracking | `docs/r7rs-large.md`: the fascicles published so far, what each requires, and gaps. | report |

**Gate 6 demo:** SRFI 272's test passes, the audit table is complete,
corpus numbers are against the baseline; CI green on the host matrix.

### Milestone 7: Chez (Track Z)

| ID | Title | Deliverable / acceptance | Test |
|---|---|---|---|
| QSM-7.1 | The `hash` mats regression | Bisect `hash` (982 pass on 2026-10-25, 940 on 2026-11-12) and fix it, or show that the counting changed. | `sh tests/run-chez-mats.sh hash` |
| QSM-7.2 | Spike: Chez internals | Report only, no code: what representing `$` primitives, the inspector and `compile-file` object code would need, and a go/no-go. | report |
| QSM-7.3 | The full mats and `5_2` | A full mats run recorded; why `5_2` does not finish. | `make test-chez` |

**Gate 7 demo:** the full mats tally against the baseline; the spike
report; CI green on the host matrix.

### Milestone 8: Cross-cutting work and spikes

| ID | Title | Deliverable / acceptance | Test |
|---|---|---|---|
| QSM-8.1 | Optimize level 3 | `--optimize-level=3` (and the importable declaration) compiles with `(speed 3) (safety 0)` as Chez's level 3 (`docs/optimizations.md` idea 1), quoting `future-directions-idea.md`: "Chez's optimize level 3 would map to a `(safety 0)` mode."; benchmarks recorded; level-3 programs that are correct give the same results. | difftest with a level-3 configuration |
| QSM-8.2 | Move `contrib/racket-linklets` | Quoting `future-directions-idea.md`: "the existing `contrib/racket-linklets` work would move to something like `src/racket/` with tests under `tests/`". Also confirms the "nanopass test" mentioned there is gone or converted. | its tests |
| QSM-8.3 | Spike: a Scheme-to-C backend | Quoting `ideas.md`: "Allow for compiling scheme into C (using current frontend; ie will be a new emit for our core scheme)". A report from the QSM-0.10 core language: go/no-go. | report |
| QSM-8.4 | Spike: schemify as a differential test | Quoting `todo`: "test and see how if the emitted code from schemify will run here", and `future-directions-idea.md`: "Keep schemify for cross-checking". A report and, on a go, a difftest configuration. | report |
| QSM-8.5 | Spike: a linklet interpreter in Chez Scheme | Quoting `todo`: "there should be an interpreter for linklets in the source tree written in chez-scheme". A report with a go/no-go. | report |
| QSM-8.6 | `qsc` and `qs` command names | Quoting `todo`: "maybe `qsc` is the compiler (to common lisp) with qs as the repl/interactive?". Links built by `contrib/cli/Makefile`, behavior by name, CLI tests. | `make -C contrib/cli test` |
| QSM-8.7 | Named primitives and `defknown` | Quoting `next-steps.txt`: "the named-primitive, `defknown` and arm64 VOP layers for run-time speed". Benchmark table. | bench subset |
| QSM-8.8 | Verify: fewer `ps:truep` tests | Determine whether boolean-returning procedures still go through `ps:truep` (`future-directions-idea.md` §4 item 5); if so, implement; else record "done". | bench subset |

**Gate 8 demo:** the level-3 benchmark table; the spike reports; suites at
the baseline on SBCL, ECL and CCL; CI green.

## 9. Risk register

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| CI stays red because SBCL internals move between releases | High | High | QSM-0.1 adds a version check with a clear message; the setup action pins version and checksum |
| Gate numbers are noisy (wall times vary 30% on this machine; ROADMAP §1) | High | Medium | Measure instructions retired (`/usr/bin/time -l`) alongside time; record the machine |
| Image layering breaks a mode's saved state | Medium | High | QSM-1.3 spike first, with a go/no-go; every suite on every mode before merge |
| Tree-shaking drops names the runtime finds at run time (the `SCHEME` package, `intern`) | High | Medium | Off by default; keep-packages; a shaken-versus-unshaken test per mode |
| Portability work slows SBCL (portable code paths) | Medium | Medium | Host-specific fast paths stay under features; benchmark tables at each gate |
| ECL's slow compiles make gate runs long | High | Low | `--quick` per ticket on SBCL only; ECL and CCL at gates |
| Continuation changes break re-entry in rare paths | Medium | High | difftest configurations, re-entry tests per primitive, full suites with both continuation modes |
| typed/racket needs far more of Racket than the natives provide | High | Medium | QSM-5.2 spike before work; package tickets ordered by size |
| Cold Racket cache takes minutes, so Racket tickets are slow | High | Medium | Keep a warm cache per worktree; QSM-5.9 |
| The tree-shaker library is unpublished, so CI cannot load it | High | Low | QSM-1.6 skips cleanly; §10 item 4 |
| Container-dependent tests (libguile, LilyPond, Guix) cannot run on CI | Medium | Medium | Skip with message; run at gates locally with podman |

## 10. Open decisions (human)

1. **Version numbers.** What does `version.sexp` (`"3.0"`) mean? Nothing
   reads it, and `src/version.scm` says 1.0. `todo` also says "change version
   to 1.0 when … guile and chez are complete & all srfi's are implemented".
   When does the version change next?
2. **`tmp/hawk/`.** It is a clone of github.com/djwatson/hawk, a C tracing
   JIT. Is it reference material for the C-backend spike (QSM-8.3) or for
   the Guile JIT, or can it go?
3. **Git leftovers.** These are left to you:
   - the stash `stash@{0}` ("WIP on main: abfc764 …");
   - the prunable worktrees under the old `pseudoscheme` path and an old scratchpad (`git worktree prune`);
   - the branches `worktree-agent-aa6a4caca0a6696f1` and `2.13-asdf`.
4. **`tree-shaker`.** Should it be published, or made portable across
   Lisps, or both? Until it is published, QSM-1.6 loads it from Quicklisp's
   local projects and skips when it is absent, so CI does not exercise it.
5. **Gate meaning for ECL and CCL before GATE-3.** Confirm the
   interpretation in §2: before Gate 3, "no regression from each host's
   recorded baseline"; from Gate 3, full suites.
6. **`ROADMAP.md` sections 1, 2, 4 and 5** (speed, library cache, Lisp
   bridge, real-world libraries) are not ticketed. Should a reviewer turn
   them into milestones later?
7. **Other Common Lisps** named in `todo` (dotcl, "claminga", LCL,
   evergreen): in scope for spikes, or out?
8. **Filing upstream.** QSM-0.13 prepares the SBCL bug report; you file it
   (an outward action).
9. **Reference machine** for gate numbers: this Apple M-series Mac, with
   instructions retired as the primary measure. Confirm.
10. **A shared installed runtime** (Racket's SharedCollects model) as a
    later size step after QSM-1.5: yes or no?

## 11. Context for agents

- **Read before coding:** AGENTS.md, this roadmap's §2, §3, §5 and the
  North-star hooks, then the mode document for the area you touch.
- **Rebuild after changes.** `bin/quasischeme` is a saved image; it does
  not see source changes until rebuilt (`make -C contrib/cli`).
- **Hermetic runs.** Redirect `XDG_CACHE_HOME`, `TMPDIR` and the
  QuasiScheme cache variables (AGENTS.md §7). Cap every run.
- **Verify-first.** "Verify" facts in this roadmap are owned by the first
  ticket that touches them. That ticket checks the fact at its source and
  records the result in its handoff note.
- **Generated files** are regenerated with their tools, never edited
  (§3.5).
- **Tests that need a missing tool or the container** skip with a message.
- **Notes are history.** The untracked notes (§3.9) are never edited,
  moved or committed. Cite them by path.
- **Gate evidence** is per-mode suite tallies against the baseline, green
  CI on the host matrix, and benchmark tables. Transcripts and fuzz
  reports belong in ticket notes.
