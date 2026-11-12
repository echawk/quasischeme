# Gate <N>: <milestone name>

- **Reviewer:** <model name>
- **Date:** YYYY-MM-DD
- **main at:** <sha>

## Tickets
| ID | Review note | Status |
|---|---|---|
| QSM-N.1 | notes/QSM-N.1.review.md | done |

## Clean-clone check
```sh
git clone -b main <repo> <scratch>/gate-N && cd <scratch>/gate-N
make -C contrib/cli && ./scripts/check.sh --full
./scripts/check.sh --full --lisp ecl; ./scripts/check.sh --full --lisp ccl
```
<result: exit code and decisive lines>

## CI
<CI run for the pushed main commit, per host job (SBCL, ECL, CCL): link or id, result; or "pending human push">

## Demo
> <the roadmap "Gate N demo" text, quoted>

```sh
<exact commands>
```
Observed:
```text
<observed output>
```
Evidence: `notes/gate-N/`:
- per-mode suite tallies against `docs/harness/baseline.md`, per host;
- benchmark tables (r7rs-benchmarks including ctak and fibc; start-up time; executable size per mode).

## Correctness rungs
<Standing prompt: should any module move up a rung (roadmap §7b)? Recommendation and reason.>

## Cross-ticket review
- <duplication, inconsistent APIs or error formats, migrations from empty, drift from roadmap or design, north-star hooks>

## Residual risks
- <risk>: <mitigation or follow-up ticket>

## Roadmap amendments
- <change, or none>

## Human sign-off
- [ ] Approved: <initials> <date>
