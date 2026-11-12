# AGENTS.md — QuasiScheme

Instructions for every coding agent working in this repository (Claude
Code, Codex, or any other). Read this file completely before starting
work.

## 1. What QuasiScheme is

QuasiScheme compiles Scheme to Common Lisp. It grew from Jonathan Rees'
Pseudoscheme. It runs every Revised Report (R1RS to R7RS) and the final
SRFIs, plus three other Schemes' own code:
- Chez Scheme (`--chez`);
- GNU Guile (`--guile`), with a bytecode VM and a C-ABI-compatible
  `libguile`;
- Racket (`--racket`), on Racket's own expander.

Every front end lowers to one core language, essentially R4RS. A shared
back end optimizes it, makes continuations capturable, translates it to
Lisp, and SBCL compiles it. Scheme procedures are Lisp functions, so the
two languages call each other freely.

| Document | Role |
|---|---|
| [`docs/harness/roadmap.md`](docs/harness/roadmap.md) | Plan of record: decisions, current state and baseline, milestones, tickets, risks, north-star goal. |
| [`docs/harness/TICKETS.md`](docs/harness/TICKETS.md) | Live ticket status board. |
| [`docs/harness/agent-protocol.md`](docs/harness/agent-protocol.md) | Ticket lifecycle, reviewer checklist, gates. |
| [`README.md`](README.md) | User-facing overview, layout, systems, test commands. |
| `docs/*.md` (continuations, optimizations, guile, guile-vm, libguile, racket, racket-linklet-compiler, chez, executables, interop, configuration) | Design references for each area. If one conflicts with the roadmap, escalate. |
| [`ROADMAP.md`](ROADMAP.md) | The user's earlier plan. Sections marked "Superseded" are history; sections 1, 2, 4 and 5 remain the user's backlog. |
| `docs/rename-quasischeme.md`, `build/agents/*.txt` | Historical; read for context, do not edit. |
| Untracked root notes: `todo`, `ideas.md`, `future-directions-idea.md`, `next-steps.txt`, `old-revided-reports`, `166-error.out`, `version.sexp`, `paper.pdf`, `rnrs-pdfs/`, `tmp/` | **The user's notes: read-only history.** Never edit, move, stage or commit them. Their open items are tickets (roadmap §3.9). |

## 2. Roles

| Role | Who | Does |
|---|---|---|
| Builder | lower-tier model | Implements exactly **one ticket** at a time, on its own branch. |
| Reviewer | higher-tier model | Reviews each ticket against its acceptance criteria; merges approved tickets into `main`; runs milestone gates; is the only role that edits `docs/harness/roadmap.md` or changes interfaces. |
| Human | Ethan | Pushes `main`, signs off gates, files upstream reports, answers "Open decisions" (roadmap §10). |

If you were not told your role, you are a **builder**.

## 3. Workflow (use the skills)

Each step has a skill in `.claude/skills/`. Agents without skill support
should open the `SKILL.md` file and follow it as written.

1. **Builder: start.** `start-ticket` picks the next eligible ticket and
   creates the branch.
2. **Builder: implement.** Use the domain skills when they apply:
   - `quasischeme-dev`: building, running suites hermetically, hosts
     (SBCL, ECL, CCL), caches, bootstrap regeneration;
   - `pipeline-change`: any change to a front end, the optimizer, the
     continuation transform, the translator or the core language;
   - `measure-perf`: benchmarks, start-up, executable size, instructions
     retired;
   - `correctness`: ratchet counters, difftest, oracles, properties;
   - `run-quasischeme` (existing): driving `bin/quasischeme` in each mode.
3. **Builder: finish.** `finish-ticket` runs the checks, writes the handoff
   note, and marks the ticket ready for review.
4. **Reviewer.** `review-ticket` verifies the work and merges, or requests
   changes.
5. **Reviewer, at the end of a milestone.** `milestone-gate` runs the demo,
   writes the report, and asks the human to sign off.

## 4. Hard rules

1. **One ticket per branch:** `ticket/<ID>-<slug>`. Never commit directly to
   `main`; only a reviewer merges. **Agents never push.**
2. **Stay inside the ticket's scope.** No drive-by refactors.
3. **Every ticket ships with tests** that pass with its test command and
   with `./scripts/check.sh --quick` on SBCL. Shared code (`src/`, outside
   `#+sbcl` blocks) is also checked on ECL before review.
   - Until QSM-0.3 merges, use the runners in §7.
4. **Cap every run.** Use `scripts/cap` (once QSM-0.3 merges) or the
   `run-quasischeme` driver; macOS has no `timeout`. A hang is a finding:
   record it, do not wait it out.
5. **Hermetic runs.** Never write caches or logs outside the repository
   and the session's scratch directory (§7).
6. **Never hand-edit generated files:**
   - `src/*.qso` and `src/spack.lisp`;
   - `vendor/psyntax/psyntax-quasischeme.pp`;
   - README's `<!-- bench … -->` numbers.

   Regenerate them (roadmap §3.5).
7. **Never edit upstream or vendored code:**
   - `vendor/guile-test-suite/`, `vendor/chez-mats/`,
     `vendor/chez-examples/`;
   - `tests/r6rs/`, `tests/chibi/`;
   - `bench/r7rs-benchmarks/` (except where marked `QUASISCHEME:`).

   Patches to `vendor/psyntax/` need a reviewer and a line in its
   `README-quasischeme.md`.
8. **Dependencies:** only those in roadmap §4.1. Anything else needs
   reviewer approval.
9. **Rebuild before running the command:** `bin/quasischeme` is a saved
   image and does not see source edits.
10. **Stop and escalate** (handoff note with status `blocked`) when:
    - an external fact differs from the roadmap;
    - an invariant would have to break;
    - the ticket cannot pass within its scope;
    - a human decision, the container or credentials are needed.

## 5. Design invariants (reviewers reject violations)

- **No CPS of general code.** Scheme procedures stay ordinary Lisp
  functions with ordinary calls and returns, which preserves CL interop.
  Continuations use generalized stack inspection (`docs/continuations.md`).
  (Human decision, 2026-11-12.)
- **SBCL-specific code is guarded** (`#+sbcl`, `#+(and sbcl arm64)`) and
  has a portable fallback that ECL and CCL run. The count of unguarded
  `sb-` references only goes down (QSM-0.7).
- **Every front end produces valid core Scheme** (`docs/core-language.md`
  and its validator, from QSM-0.10).
- **Configurations agree.** Optimizer levels 0, 1 and 2, full and
  escape-only continuations, and `QUASISCHEME_FAST=0` give the same
  observable results (difftest).
- **Caches never change results.** Cold, warm and disabled caches agree,
  and a killed run never leaves a cache that later runs fail on.
- **No absolute developer paths** in tracked files or baked into images'
  behavior.
- **Conformance never drops** below `docs/harness/baseline.md` on any
  host.
- **Size and debug flags are opt-in.** Tree-shaking, stripping and
  compression happen only when explicitly requested.
- **Every new environment variable** is documented in
  `docs/configuration.md`.
- **Correctness rungs** (roadmap §7b):
  - optimizer, continuations and translator: a difftest configuration or
    a property for every new transformation;
  - mode runtimes: suite tallies at or above the baseline;
  - everything else: tests including an error path.

  Ratchet counts (warnings, unguarded `sb-` references) never rise.
  Suppressions need a justification comment and a ticket ID.

## 6. North-star goal (do not build; do not block)

One portable Lisp image runs real programs from all four Scheme
ecosystems unmodified (Racket packages, Guix, Idris 2, LilyPond), diffed
against upstream. It passes the same suites on SBCL, CCL, ECL and Clasp,
and ships executables within 2× of `raco exe` with continuations at
Chez's speed.

Keep these hooks intact:
- guarded SBCL code with fallbacks;
- no CPS;
- modes as separately loadable layers;
- machine-readable tally lines comparable with upstream;
- atomic, path-independent caches;
- instructions-retired benchmarks against the reference Schemes;
- a specified core language.

If a ticket's design would close off a hook, say so in the handoff note.

## 7. Stack and commands

Common Lisp (ASDF, SBCL 2.6.10 for development), with Scheme for the
translator and libraries, C for `src/libguile/`, and Python 3 and sh for
tooling.

**Hermetic environment.** Use this for every command below. `S` is your
scratch directory, or `build/check`.

```sh
export XDG_CACHE_HOME="$S/cache" TMPDIR="$S/tmp" \
       QUASISCHEME_LIBRARY_CACHE_DIRECTORY="$S/cache/qslib" \
       QUASISCHEME_GUILE_CACHE_DIRECTORY="$S/cache/guile" \
       PYTHONDONTWRITEBYTECODE=1
mkdir -p "$S/cache" "$S/tmp"
```

The runners load `~/quicklisp/setup.lisp` (a project requirement).

**Standard suites.** Verified 2026-11-12; counts in roadmap §3.2.

```sh
# a function, not R="sbcl ...": zsh does not word-split $R
qsrun() { QUASISCHEME_LIBRARY_CACHE=0 sbcl --dynamic-space-size 4GB --control-stack-size 500MB --script "$@"; }
qsrun tests/run-syntax-case-tests.lisp   # 17/17
qsrun tests/run-r7rs-tests.lisp          # 978/978
qsrun tests/run-r5rs-tests.lisp          # 189/189
qsrun tests/run-r6rs-tests.lisp          # 8902 passed
qsrun tests/run-continuation-tests.lisp  # 45/45
qsrun tests/run-interop-tests.lisp       # 116/116
# also: library, reports, srfi-system, sbcl and optimizer
# (tests/run-<name>-tests.lisp)
```

**The command and its tests.**

```sh
make -C contrib/cli                          # build bin/quasischeme (~150 s cold)
sh contrib/cli/test.sh "$PWD/bin/quasischeme"   # 51/51
sh tests/run-srfi-tests.sh bin/quasischeme 166 226
python3 -B tests/fuzz/difftest.py --count 8 --seed 42 --keep "$S/fuzz"
```

**Other Schemes' suites.** They write to `OUT`; point it at `$S`.

```sh
OUT="$S/chez" QS="$PWD/bin/quasischeme" sh tests/run-chez-mats.sh hash io
OUT="$S/guile" sh tests/run-guile-tests.sh hash srfi-1
OUT="$S/racket" sh tests/racket/run.sh linklet   # needs: sh utils/racket/setup.sh
```

**Generated files.**

```sh
make bootstrap-check          # needs chez and scheme48 or chibi
```

**Planned.**
- `scripts/cap SECS CMD…` and `scripts/check.sh [--quick|--full] [--lisp sbcl|ecl|ccl]`
  (QSM-0.3).
- ECL and CCL runner commands (QSM-0.7, QSM-0.8).

**Environment notes.**
- macOS has no `timeout`, and SBCL ignores SIGALRM. Use
  `.claude/skills/run-quasischeme/driver.sh` (capped) or `scripts/cap`.
- The Makefile's `test` targets write logs to `/tmp`; prefer the direct
  commands above.
- Racket needs `build/external/racket` (`sh utils/racket/setup.sh`). A cold
  Racket cache takes minutes.
- libguile, LilyPond and Guix tests need podman (`utils/container/`). Skip
  them with a message when it is absent.
- CI is x86-64 Linux, so the arm64 VOP layer is off there.

## 8. Layout

```text
AGENTS.md, CLAUDE.md            agent rules (CLAUDE.md imports this file)
docs/harness/                   roadmap.md, TICKETS.md, agent-protocol.md (plan of record)
docs/                           design references per area; configuration.md lists env vars
notes/                          handoff, review and gate notes; templates/
.claude/skills/                 workflow and domain skills; run-quasischeme/driver.sh
src/                            implementation: *.lisp runtime and passes, *.scm translator (+ .qso)
src/{r6rs,r7rs,srfi,chez,guile,libguile,racket,reports,compat,interop,repl}/  per area
vendor/                         psyntax (patched), guile-test-suite, chez-mats, chez-examples
tests/                          runners (run-*-tests.lisp, *.sh), suites, fuzz/, racket/, libguile/
contrib/cli/                    the quasischeme command; contrib/emacs/
boot/                           bootstrap from other Schemes
utils/                          setup/teardown: racket/, chez/, container/
bench/                          r7rs-benchmarks (vendored), run.sh, results
build/                          ignored: external downloads, caches, check output
```

## 9. Style

- **Lisp:**
  - put SBCL internals under `#+sbcl` with a `#-sbcl` fallback;
  - `;;;;` file headers say what and why;
  - follow the surrounding package and nickname use (`qs`, `qsx`, …).
- **Scheme sources:** follow the file's existing style. The translator's
  `.scm` files need their `.qso` regenerated after a change.
- **Docs:** plain, measured prose with numbers, dates and `file:line`
  citations; update the mode document a change affects.
- **Commits:** the repository's style. A subject `Area: what changed
  (QSM-N.n)` in sentence case, for example
  `Continuations: lazy rebuild over an underflow frame (QSM-2.2)`, then a
  prose body, then `Co-Authored-By: <model> <noreply@anthropic.com>` for
  agent commits.
  - Board-only commits: `Harness: start QSM-N.n`.
  - Merges: `Merge QSM-N.n: <title>`.
- **Comments** explain why. No commented-out code. A TODO must reference
  a ticket ID.
