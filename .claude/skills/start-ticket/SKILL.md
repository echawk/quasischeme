---
name: start-ticket
description: Builder workflow to begin a QuasiScheme ticket (QSM-N.n). Picks the next eligible ticket (or the one named, or a track's next), checks dependencies, creates the ticket branch, marks it in-progress, records a baseline, and gathers the spec. Use when asked to "start", "pick up", "work on" a ticket, "the next ticket" or "start track S/C/P/G/R/N/Z".
---

# start-ticket

Arguments:
- an optional ticket ID (`QSM-2.1`), or
- a track name (S = Milestone 1, C = 2, P = 3, G = 4, R = 5, N = 6, Z = 7).

Without either, pick the next eligible ticket.

## Steps
1. **Sync.** Run `git status --short --untracked-files=no`. If a tracked
   file is modified, stop and report it.
   - The untracked notes at the root (`todo`, `ideas.md`, …) are expected.
     Never touch them.
   - Otherwise run `git checkout main`. There is no `git pull`: agents
     never fetch or push unless told.
2. **Choose the ticket.** Open `docs/harness/TICKETS.md`.
   - With an ID: its status must be `todo` or `changes-requested`, and
     every dependency must be `done`. Otherwise stop and list what is
     missing.
   - With a track: the lowest-numbered eligible ticket in that track's
     milestone.
   - Without either: the lowest-numbered eligible `todo` ticket, following
     the roadmap's **Execution order** line. Skip `GATE-*` rows; they
     belong to reviewers.
3. **Read the context** before writing code:
   - the ticket's row in `docs/harness/roadmap.md` §8, plus its milestone's
     gate demo and pain points;
   - roadmap §2 (decisions), §3 (current state), §5 (invariants), and the
     North-star hooks table;
   - the design document for the area: `docs/continuations.md`,
     `docs/optimizations.md`, `docs/guile.md`, `docs/libguile.md`,
     `docs/racket.md`, `docs/chez.md`, `docs/executables.md`, or
     `docs/pipeline.md` once QSM-0.9 has written it;
   - `AGENTS.md` §4–§6;
   - handoff and review notes of the dependency tickets
     (`notes/<dep>.md`, `notes/<dep>.review.md`);
   - if the ticket quotes an untracked note (`todo`, `ideas.md`,
     `future-directions-idea.md`, `next-steps.txt`, `tmp/…`), read that
     note. Read only; never edit it.
4. **Branch.** `git checkout -b ticket/<ID>-<short-slug>`. For
   `changes-requested`, reuse the existing branch.
5. **Mark in progress.** In `docs/harness/TICKETS.md`, set the status to
   `in-progress` and record the branch. Commit only that change, with the
   message `Harness: start <ID>`.
6. **Baseline.** Set up the hermetic environment (AGENTS.md §7). Then run
   `./scripts/check.sh --quick`, or, before QSM-0.3 has merged, the
   standard suites in AGENTS.md §7. Do this before changing anything.
   - Rebuild `bin/quasischeme` first if the ticket uses the command
     (`make -C contrib/cli`).
   - If the baseline fails, stop and report it: the cause is not your
     ticket.
7. **Plan.** Write down for yourself:
   - which files change;
   - which test proves each acceptance criterion;
   - which domain skill applies: `quasischeme-dev`, `pipeline-change`,
     `measure-perf`, `correctness`, or `run-quasischeme`;
   - whether generated artifacts (`.qso`, the psyntax image) will change;
   - whether the change touches shared code that ECL must still load.

   If a criterion is ambiguous, choose the reading most consistent with
   the roadmap and record it under "Deviations" in the handoff note. Do
   not stall.
8. Implement test-first where practical, then run `finish-ticket`.

## Do not
- Start a ticket whose dependencies are not `done`.
- Combine tickets on one branch.
- Edit `docs/harness/roadmap.md`, the mode documents' plans, vendored
  paths, or the untracked notes.
- Introduce CPS of general code, or unguarded SBCL internals.
