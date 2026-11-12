---
name: finish-ticket
description: Builder workflow to hand a QuasiScheme ticket (QSM-N.n) to review. Runs all checks (SBCL, plus ECL for shared code), self-reviews the diff against acceptance criteria and invariants, writes notes/<ID>.md with evidence, sets status to review, and commits. Use when implementation of a ticket is complete or blocked.
---

# finish-ticket

## Steps
1. **Run the checks.** In the hermetic environment (AGENTS.md §7):
   - Rebuild `bin/quasischeme` if `src/` or `contrib/` changed
     (`make -C contrib/cli`).
   - Run the ticket's test command, then `./scripts/check.sh --quick` on
     SBCL. Before QSM-0.3 has merged, run the standard suites in AGENTS.md
     §7.
   - If shared code changed (anything outside `#+sbcl` blocks and
     `src/sbcl-*.lisp`), also run `./scripts/check.sh --quick --lisp ecl`
     once QSM-0.7 has merged.
   - Every run is capped (`scripts/cap` or the `run-quasischeme` driver).
   - A test that needs a missing tool or the container must skip with a
     message.
   - If the checks cannot pass within scope, go to step 7 with status
     `blocked`.
2. **Regenerate generated artifacts** if the ticket could affect them.
   - Translator sources (`src/*.scm`), `builtin.scm`, or the reader and
     writer: regenerate the `.qso` files (README "Bootstrap artifacts").
   - psyntax: `make bootstrap-psyntax`.
   - Then run `make bootstrap-check`. Every change in
     `git diff --stat src/*.qso vendor/psyntax/` must follow from the
     ticket.
   - Regenerate a second time: the output must be identical.
3. **Self-review** `git diff main...HEAD`, checking that:
   - every acceptance criterion has a test or a reproducible command as
     evidence;
   - every changed file is in scope;
   - the AGENTS.md §5 invariants hold, especially:
     - no CPS of general code;
     - SBCL internals only under `#+sbcl`, with a working fallback (the
       unguarded-`sb-` count did not rise);
     - optimizer levels, continuation modes and `QUASISCHEME_FAST=0`
       agree;
     - caches written atomically, with results unchanged by a cold cache;
     - no absolute developer paths;
     - new environment variables documented in `docs/configuration.md`;
     - tree-shaking, stripping and compression stay opt-in;
   - the correctness rung of each touched module is met (roadmap §7b: a
     difftest configuration or property for new transformations; suite
     tallies at least the baseline), with no new suppressions without a
     justification;
   - the north-star hooks (AGENTS.md §6) are preserved;
   - there are no debug prints, commented-out code, or TODOs without a
     ticket ID;
   - no untracked root note is staged (`git status --short` shows them as
     `??` only);
   - the mode document for the area is updated if behavior or numbers
     changed.
4. **Fix** what the self-review finds, then repeat steps 1–3.
5. **Evidence.** Save logs, tally tables and benchmark output to
   `notes/<ID>/`. Performance claims need instructions retired as well as
   time (the `measure-perf` skill).
6. **Write `notes/<ID>.md`** from `notes/templates/handoff.md`. Fill in
   every section, especially the evidence table and the environment notes
   (cache directories, `OUT` directories, hosts used). Paste the decisive
   tally lines; do not just write "tests pass".
7. **Update the board.** In `docs/harness/TICKETS.md`, set the status to
   `review`, or to `blocked` with the exact blocker and what would unblock
   it.
8. **Commit** in the repository's style: `Area: what changed (<ID>)`, a
   prose body, and a `Co-Authored-By:` trailer. Stage paths explicitly;
   never `git add -A`. Do not push. Do not merge.
9. **Report** to the user in 3–5 lines: ticket, status, branch, test
   results, open questions.
