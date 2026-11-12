# Review: <ID> — <title>

- **Verdict:** approve | changes-requested
- **Reviewer:** <model name>
- **Date:** YYYY-MM-DD
- **Commit reviewed:** <sha>

## Verification
```sh
<commands the reviewer ran (fresh clone of the branch in a scratch dir when practical)>
```
<results, including the adversarial inputs tried and what each produced>

## Checklist
- [ ] Acceptance criteria met (each verified independently)
- [ ] Scope respected
- [ ] Tests meaningful, including an error path; no real external calls
- [ ] Adversarial cases tried
- [ ] No dead code / untracked TODOs
- [ ] Interfaces match the roadmap
- [ ] AGENTS.md §5 invariants hold
- [ ] North-star hooks preserved
- [ ] Generated files regenerated (not hand-edited); docs updated

## Required changes
1. `<path:line>`: <problem>. <fix>. <why it matters, e.g. which later ticket depends on it>

## Non-blocking suggestions
- <suggestion>

## Answers to builder questions
- <question>: <answer / decision>

## Roadmap amendments
<none | exact change made to docs/harness/roadmap.md>

<!-- On re-review append:
## Round 2
- **Verdict:** ...
- **Commit reviewed:** ...
### Verification
...
-->
