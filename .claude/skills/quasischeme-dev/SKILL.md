---
name: quasischeme-dev
description: Day-to-day development know-how for QuasiScheme across Common Lisp hosts. Covers hermetic suite runs, capping runs, rebuilding bin/quasischeme, caches, running on ECL and CCL, guarding SBCL internals, setup downloads (Racket source, container), and regenerating .qso files and the psyntax image. Use whenever building, running tests, touching quasischeme.asd, src/*.lisp outside a single mode, contrib/cli, boot/, or anything that must work on ECL or CCL.
---

# quasischeme-dev

## Principles (non-negotiable)
1. **Hermetic and capped.**
   - Every run redirects caches to a scratch or `build/` directory
     (AGENTS.md §7).
   - Every run is killed after a limit. macOS has no `timeout` and SBCL
     ignores SIGALRM, so use a process-group kill: `scripts/cap` once
     QSM-0.3 merges, or `.claude/skills/run-quasischeme/driver.sh`.
   - A hang is a finding to record, not to wait out.
2. **Rebuild before you trust the command.** `bin/quasischeme` is a saved
   SBCL image. It does not see source edits, and before QSM-0.2 it bakes
   in its install directory. After `src/` changes, or after moving the
   checkout, run `make -C contrib/cli`.
3. **SBCL internals only under `#+sbcl`.**
   - Put SBCL internals under `#+sbcl` (or `#+(and sbcl arm64)`), with a
     `#-sbcl` portable version. Prefer the portability libraries already
     used: float-features, trivial-garbage, bordeaux-threads, CFFI, babel,
     UIOP, trivial-gray-streams.
   - An unguarded `sb-ext:` broke ECL once (`src/numbers.lisp:290`,
     2026-11-01).
4. **Never hand-edit generated files.** Regenerate them, twice, and
   compare.
5. **Never touch the untracked notes** at the repository root.

## Running suites
- Standard suites: `sbcl --dynamic-space-size 4GB --control-stack-size 500MB --script tests/run-<name>-tests.lisp`.
  - `<name>` is one of: syntax-case, r7rs, r5rs, r6rs, continuation,
    interop, library, reports, srfi-system, sbcl, optimizer.
  - Set `QUASISCHEME_LIBRARY_CACHE=0` so a stale cache cannot hide
    anything.
  - The first run compiles everything through ASDF (about 12 s cold).
- Each runner prints one tally line, such as
  `R7RS: 978 of 978 tests passed`. Compare it with
  `docs/harness/baseline.md` (QSM-0.4), or with roadmap §3.2 until then.
- Escape-only continuations: add `--continuations=escape` to the r5rs,
  r6rs and r7rs runners.
- Command-line tests: `sh contrib/cli/test.sh "$PWD/bin/quasischeme"`.
  They need an absolute path and take about 5 minutes.
- SRFI programs: `sh tests/run-srfi-tests.sh bin/quasischeme N …`. Only
  130 SRFIs have test programs (`ls src/srfi/tests`).
- Chez mats, Guile suite, Racket: see AGENTS.md §7. Always set `OUT` to a
  scratch directory.
  - Chez and Racket use `bin/quasischeme` (`QS=`/`PS=`).
  - Guile loads the system from source.
- The Makefile's `test` targets write to `/tmp/quasischeme-test-*.log`.
  Call the runners directly instead.

## Hosts
- **SBCL 2.6.10:** the development host. CI pins a version in
  `.github/actions/setup-lisp/action.yml`. Keep it equal to what the code
  needs (QSM-0.1).
- **ECL 26.5.5:**
  - On 2026-11-12, `ecl --norc --shell tests/run-r7rs-tests.lisp` exited
    silently. Loading through
    `ecl --norc --eval '(require :asdf)' --eval '(load …quicklisp/setup.lisp)' --eval '(push (truename "./") asdf:*central-registry*)' --eval '(asdf:load-system :quasischeme/r7rs)'`
    shows the errors.
  - QSM-0.7 documents the supported command.
  - ECL compiles through C, so it is slow. Cap generously.
- **CCL 1.14** (`ccl`, darwinarm64 locally): status unknown until QSM-0.8.
- **ABCL and Clasp:** spikes only (QSM-3.8, QSM-3.9).
- `make -C contrib/cli LISP=ccl|ecl|clisp` exists. Whether it works on
  each host is QSM-3.5.
- **Tail calls** are not guaranteed outside SBCL and CCL (QSM-3.2). Do
  not add code that relies on Lisp-level tail calls without checking.

## Caches and downloads
- **Caches:**
  - ASDF fasls go to `$XDG_CACHE_HOME/common-lisp/`;
  - the library cache goes to `QUASISCHEME_LIBRARY_CACHE_DIRECTORY`, with
    Racket's module cache and saved cores beside it in `../racket/`;
  - the Guile module cache goes to `QUASISCHEME_GUILE_CACHE_DIRECTORY`.
- **A run killed while filling the Racket cache corrupts it** until
  QSM-0.5. Use a fresh cache directory after any killed Racket run.
- **Racket source:**
  - `sh utils/racket/setup.sh` fills `build/external/racket` (tag v9.3)
    and rktio;
  - `utils/racket/packages.sh` fills `build/external/racket-pkgs`;
  - `QUASISCHEME_RACKET_SOURCE` and `QUASISCHEME_RKTIO_DIRECTORY` point
    elsewhere.
- **The container:** `utils/container/` (podman) provides Guile's
  headers, real Guile, Guix and LilyPond. Tests that need it skip with a
  message when podman is unavailable.
- **Quicklisp:** `~/quicklisp/setup.lisp` is loaded by every runner, and
  missing dependencies download on first use.

## Generated files
- After changing a translator source (`src/*.scm`), `builtin.scm`, or
  `read.scm`/`write.scm`, use `quasischeme/bootstrap`:
  `(quasischeme-bootstrap:regenerate-pso-files)` and the others listed in
  README "Bootstrap artifacts". Then clear the fasl cache (its timestamps
  have 1-second resolution) and reload in a fresh image.
- psyntax image: `make bootstrap-psyntax`.
- Check: `make bootstrap-check`. It needs `chez`, and `scheme48` or
  `chibi-scheme` (all installed). CI checks the same fixpoint.

## Testing (what a ticket must add)
- A test in the runner of the area changed: a new form in the suite file
  or a new `tests/run-*` case, with an error path.
- For command-line behavior: a case in `contrib/cli/test.sh`.
- For host portability: the same test passes on ECL. From QSM-3.4 on, it
  also passes on CCL.

## Pitfalls
- **R7RS program files** need `(import (scheme base) (scheme write))`. `-p`
  and the REPL import for you.
- **The installed binary** printed
  `cannot find library (SCHEME::SRFI SCHEME::|:1|)` after the checkout
  moved: it was stale (`-V` shows `install-dir`).
- **Guile's REPL** needs `,q` twice at an error level.
- **zsh does not word-split** `$var`. Use arrays or write commands out in
  examples.
- **Wall-clock times vary by about 30%** on the development machine. Use
  instructions retired for comparisons (`measure-perf`).
