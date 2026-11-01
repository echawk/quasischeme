# Differential tests

`difftest.py` generates random R7RS programs and runs each under several
configurations of `bin/quasischeme`. All of them must print the same
output. With `--guile`, GNU Guile is checked as well, as an oracle.

The programs are typed, so they never signal an error, and they always
terminate. They lean on what has broken before:

- groups of closures that refer to each other, made in loops while the
  collector runs;
- escapes from and re-entries into `call/cc`;
- `set!` of captured variables;
- `letrec` and named `let`;
- vectors, strings, and exact arithmetic past the fixnums.

```sh
make fuzz                                         # 20 programs, the default configurations
python3 tests/fuzz/difftest.py --count 50 --guile # and GNU Guile as an oracle
python3 tests/fuzz/difftest.py --seed 3017 --count 1 --configs default,gc-stress
```

The configurations are listed in `CONFIGS`:

| configuration | what it varies |
|---|---|
| `O0`, `O1` | optimizer levels |
| `escape` | escape-only continuations (re-entry is then left out of the programs) |
| `no-fast` | without the optional code layer |
| `no-flonum-versions`, `no-cpdx`, `no-cpletrec` | without the named optimizer pass |
| `no-stack-sites`, `site-closures`, `parametric` | the continuation machinery's variants |
| `interpret` | SBCL's interpreter |
| `guile-mode` | Guile mode |
| `gc-stress`, `guile-gc-stress` | a collection every 256 KB (`QUASISCHEME_NURSERY`) |

When a program's outputs differ, it is shrunk: top-level forms are
removed while the outputs still differ. The shrunk program is kept in
`tests/fuzz/failures/` (ignored by git), with each configuration's
output.
