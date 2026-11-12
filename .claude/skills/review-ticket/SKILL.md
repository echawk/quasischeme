---
name: review-ticket
description: Reviewer workflow for a QuasiScheme ticket (QSM-N.n) in `review` status. Independently verifies acceptance criteria on a fresh build, tries adversarial cases (re-entry, cold or killed caches, other modes, other hosts), checks invariants and north-star hooks, writes notes/<ID>.review.md, then merges into main or requests changes. Use when asked to review a ticket or check a builder's work. Intended for higher-tier models.
---

# review-ticket

Argument: a ticket ID. Without one, take the oldest `review` ticket in
`docs/harness/TICKETS.md`.

**Stance:** do not trust the handoff note. Every "yes" must be confirmed
by a check you ran yourself. In practice, the adversarial step below is
where most real bugs are found.

## Steps
1. Read `notes/<ID>.md`, the ticket spec in `docs/harness/roadmap.md` §8,
   the roadmap sections it relies on, and the design-document sections
   for the area.
2. Check out the branch. Run `git diff main...HEAD --stat`, then read the
   full diff, including any regenerated `.qso` files or psyntax image.
3. **Verify independently.**
   - Prefer a fresh clone of the branch in a scratch directory
     (`git clone -b ticket/<ID>-<slug> <repo> <scratch>/rev`).
   - Use the hermetic environment (AGENTS.md §7) and rebuild
     `bin/quasischeme` there.
   - Run the ticket's test and `./scripts/check.sh --quick`. Run
     `--lisp ecl` too when shared code changed.
   - For each acceptance criterion, find and read the test that proves
     it. A test that only checks "no exception" does not count; a
     criterion with no real test is a required change.
   - **Adversarial cases (mandatory).** Run at least 3 inputs the builder
     probably did not test, with a throwaway script. Typical sources:
     - re-entering a continuation through the changed code (generators,
       `amb`, re-entry through `map` or a sort);
     - escape-only mode, `QUASISCHEME_OPTIMIZE=0`, `QUASISCHEME_FAST=0`,
       `QUASISCHEME_STACK_SITES=0`;
     - a cold cache; a cache left by a run killed with `scripts/cap`; a
       moved checkout;
     - the same feature from another mode (`--chez`, `--guile`,
       `--racket`, `--r5rs`);
     - Unicode identifiers and strings, bignums, `+nan.0`, `-0.0`, very
       deep recursion;
     - ECL (and CCL after QSM-3.4) for shared code.
   - **Correctness rung:** confirm the touched modules carry the evidence
     their rung requires (roadmap §7b). If you can, run difftest longer
     than the builder did, for example
     `python3 -B tests/fuzz/difftest.py --count 50 --keep <scratch>/fuzz`.
   - **Performance claims:** re-measure with instructions retired (the
     `measure-perf` skill). Do not accept wall-clock time alone.
4. **Checklist** from `docs/harness/agent-protocol.md`. Pay special
   attention to:
   - CPS creeping in;
   - unguarded SBCL internals;
   - absolute paths;
   - non-atomic cache writes;
   - opt-in flags becoming defaults;
   - hand-edited generated files;
   - scope creep, new unlisted dependencies, and closed-off north-star
     hooks;
   - untracked notes staged by mistake.
5. **Write `notes/<ID>.review.md`** from `notes/templates/review.md`. Give
   each required change as `path:line: problem. fix. why it matters`.
   Answer the builder's questions with decisions.
6. **Approve** (the merge model is roadmap §2, row "Git and merges"):
   `git checkout main && git merge --no-ff ticket/<ID>-<slug> -m "Merge <ID>: <title>"`.
   - Set the ticket to `done`.
   - Commit the review note and the board change as
     `Harness: approve <ID>`, with a `Co-Authored-By:` trailer.
   - Never push.
7. **Request changes:**
   - Commit the review note on the branch as
     `Harness: request changes on <ID>`.
   - Set the ticket to `changes-requested`.
   - On re-review, append `## Round 2` to the same review note.
8. **Roadmap amendments.** If reality differs from the roadmap (a fact, a
   count, a library choice), edit `docs/harness/roadmap.md` and record the
   change under "Roadmap amendments".
9. If this was the last ticket of a milestone, announce that the gate is
   ready (`milestone-gate`).
