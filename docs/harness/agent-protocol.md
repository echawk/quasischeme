# Agent protocol

How builders (lower-tier models), reviewers (higher-tier models) and the
human work together on QuasiScheme. [`AGENTS.md`](../../AGENTS.md) has the
short version, and the skills in `.claude/skills/` automate each step.

## Ticket format

Each ticket in [`roadmap.md`](roadmap.md) §8 is a contract with these
fields. When the roadmap table leaves a field out, these defaults apply:

    ID:           QSM-<milestone>.<n>   (inserted: N.5 milestones; splits: a/b suffixes)
    Title:        one line
    Depends on:   see docs/harness/TICKETS.md
    Files:        the layout directories implied by the title; anything
                  outside them must be justified in the handoff note
    Deliverable:  roadmap acceptance column
    Acceptance:   roadmap acceptance column, plus the AGENTS.md §5 invariants
    Test:         roadmap Test column, plus ./scripts/check.sh --quick
                  (until QSM-0.3 merges: the runners in AGENTS.md §7)
    Out of scope: everything belonging to other tickets

A **spike** delivers a report (`docs/harness/<topic>-spike.md`) with a
clear go or no-go. A negative result is acceptable. Prototype code is
merged only on a "go".

## Lifecycle

    todo ──start-ticket──▶ in-progress ──finish-ticket──▶ review ──review-ticket──▶ done
                                │                            │
                                ▼                            ▼
                             blocked ◀───────────── changes-requested ──▶ in-progress

- The builder works on branch `ticket/<ID>-<slug>`, created from an
  up-to-date `main`.
- The builder ends with `notes/<ID>.md` (from `notes/templates/handoff.md`).
  Evidence artifacts (logs, tables, benchmark output) go in `notes/<ID>/`.
- The reviewer writes `notes/<ID>.review.md`. When the verdict is approve,
  the reviewer merges into `main` with `--no-ff` and sets the ticket to
  `done`.
- After `changes-requested`, the builder fixes every item on the same
  branch and appends "Round 2" to the handoff note. The reviewer appends
  "Round 2" to the review note.

## Reviewer checklist (per ticket)

- [ ] Every acceptance statement is met. Run the tests yourself on SBCL,
      after rebuilding `bin/quasischeme` if the ticket touches `src/` or
      `contrib/`. Do not trust the handoff note.
- [ ] No changes outside scope without a stated reason.
- [ ] Tests exercise behavior, including at least one error path.
- [ ] An **adversarial case** was tried by the reviewer. Examples:
  - re-entering a continuation through the changed code;
  - a cold cache, and a cache left by a killed run;
  - escape-only mode, `QUASISCHEME_OPTIMIZE=0`, `QUASISCHEME_FAST=0`;
  - another mode (`--guile`, `--racket`, `--chez`) using the same code;
  - Unicode, bignums, flonum edge cases;
  - a moved checkout;
  - ECL when the ticket touches shared code.
- [ ] No dead code, and no TODOs without a ticket ID.
- [ ] Public names and environment variables match the roadmap, and new
      variables are in `docs/configuration.md`.
- [ ] AGENTS.md §5 invariants hold. In particular:
  - no CPS of general code;
  - SBCL-specific code is guarded and has a fallback;
  - the ratchet counts did not rise.
- [ ] Correctness rung (roadmap §7b) met for the touched modules. No new
      suppressions or lowered thresholds without a justification and a
      ticket ID.
- [ ] North-star design hooks are not closed off.
- [ ] Generated files were regenerated, not edited (`make bootstrap-check`
      when the translator or psyntax changed). Docs are updated if
      affected.
- [ ] No untracked note at the repository root was edited, moved or staged.

## Roadmap changes

- Only reviewers or the human edit `docs/harness/roadmap.md` and the mode
  design documents' plans.
- Small factual amendments are made in a review and recorded under
  "Roadmap amendments" in the review note.
- Scope changes go on a branch `roadmap/<slug>`, committed as
  `Harness: <what changed>` and merged as
  `Merge roadmap/<slug>: <summary>`.
- Inserted milestones use `N.5` numbering and a `GATE-N.5` row, and the
  **Execution order** line is updated.
- Human decisions are recorded in roadmap §2 with
  "(Human decision, YYYY-MM-DD)".

## Merge and push model

As decided in [roadmap §2, row "Git and merges"](roadmap.md#2-decisions-already-made).
That row is the single place for this policy; do not restate it
elsewhere.

## Milestone gate

1. Every ticket in the milestone is `done`, and `./scripts/check.sh --full`
   passes on a **clean clone** of `main` in a scratch directory, after
   building `bin/quasischeme` there.
2. The milestone's **demo** runs end to end. Gate evidence (roadmap §2,
   row "Gate evidence"):
   - per-mode suite tallies against `docs/harness/baseline.md`, on SBCL,
     ECL and CCL;
   - the CI run of the pushed `main` commit, green on the host matrix (or
     "pending human push");
   - benchmark tables: r7rs-benchmarks including `ctak` and `fibc`,
     start-up time, and executable size per mode.

   Record the commands, the observed output and the tables in
   `notes/gate-N/`.
3. The reviewer writes `notes/gate-N.md` (from `notes/templates/gate.md`),
   including:
   - a cross-ticket review;
   - residual risks;
   - roadmap amendments;
   - **the standing correctness prompt:** should any module move up a
     rung (roadmap §7b)?
4. The human signs off by ticking the box in the gate note and committing
   (`Harness: sign off GATE-N`). The `GATE-N` row becomes
   `done (signed off <initials> <date>)`.

## Escalation (builder stops and marks the ticket `blocked`)

- An external fact differs from the roadmap.
- An invariant or a design document would have to change.
- The tests cannot pass within the ticket's scope.
- A new dependency, credentials, the container, or a human decision is
  needed.
- The baseline (`scripts/check.sh`) fails before the ticket changed
  anything.
