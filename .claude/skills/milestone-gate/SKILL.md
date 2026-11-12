---
name: milestone-gate
description: Reviewer workflow to close a QuasiScheme milestone (GATE-N). Verifies all tickets done, runs the full checks on a clean clone on SBCL, ECL and CCL, executes the roadmap's gate demo, collects the agreed gate evidence (suite tallies against the baseline, CI on the host matrix, benchmark tables), does a cross-ticket review and the correctness-rung review, writes notes/gate-<N>.md, and requests human sign-off. Use when asked to "run gate N" or close a milestone.
---

# milestone-gate

Argument: the milestone number N (including inserted milestones like
`1.5`).

## Steps
1. In `docs/harness/TICKETS.md`, confirm every `QSM-N.*` ticket is `done`
   and has a review note. If any is not, stop and list them.
2. **Clean-clone check.** In a scratch directory outside the working tree:
   ```sh
   git clone -b main <repo> <scratch>/gate-N && cd <scratch>/gate-N
   # hermetic environment from AGENTS.md §7, caches under <scratch>
   make -C contrib/cli
   ./scripts/check.sh --full
   ./scripts/check.sh --full --lisp ecl
   ./scripts/check.sh --full --lisp ccl
   ```
   Record exit codes and the tally lines.
   - Before GATE-3, ECL and CCL must not regress from their recorded
     baseline.
   - From GATE-3 on, the full standard suites must pass on them (roadmap
     §2, row "Common Lisp hosts").
3. **Gate evidence** (roadmap §2, row "Gate evidence"). Save to
   `notes/gate-N/`:
   - per-mode suite tallies against `docs/harness/baseline.md`, per host;
   - benchmark tables (the `measure-perf` skill):
     - r7rs-benchmarks including `ctak` and `fibc`
       (`bench/run.sh`, `python3 bench/summarize.py`);
     - start-up time;
     - executable size per mode (`scripts/measure-exe` once QSM-1.1
       exists);

     each with instructions retired;
   - the CI run of the pushed `main` commit, green on every host job. If
     the human has not pushed yet, write "pending human push" and ask
     them to push and report the run (`gh run list -R echawk/quasischeme`).

   Real-program transcripts and fuzz reports may be attached, but they
   are not gate evidence.
4. **Run the demo.** Execute "Gate N demo" from the roadmap. Record the
   exact commands and observed output. When a step needs podman, the
   network or a human action, prepare everything else and ask the human
   to do only that step.
5. **Cross-ticket review:**
   - duplicated helpers;
   - inconsistent environment variable names, or variables missing from
     `docs/configuration.md`;
   - all modes and hosts still agree (difftest configurations);
   - drift from the roadmap or the design documents;
   - north-star hooks intact;
   - status documents (README "Status", mode documents, `baseline.md`)
     reflect the new numbers.
6. **Correctness rungs (standing prompt).** Consider whether any module
   should move up a rung (roadmap §7b), for example:
   - libguile ABI checks with `abidiff` in the container;
   - property tests for a new optimizer pass;
   - formal methods.

   Record the recommendation and the reason in the gate note.
7. **Write `notes/gate-N.md`** from `notes/templates/gate.md`. Apply any
   roadmap amendments. If the baseline legitimately improved, update
   `docs/harness/baseline.md`. Add follow-up tickets to
   `docs/harness/TICKETS.md` if needed.
8. Set the `GATE-N` row to `review` and ask the human to sign off: tick
   the box in the gate note and commit `Harness: sign off GATE-N`. Then
   set the row to `done (signed off <initials> <date>)`.
