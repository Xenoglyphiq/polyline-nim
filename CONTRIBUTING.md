# Contributing to Polyline for Nim

Thanks for helping. This package is one of several language ports of the same spec, and all of them must behave identically.

## How this repo works

- The package itself lives at the repo root, laid out the way Nim expects: `polyline.nimble` and `src/polyline.nim`. The conformance runner is `tests/tconformance.nim`, and the fuzzer is `tests/fuzz.nim`.
- **`.spec/`** is a copy of the spec and its conformance cases from **`Xenoglyphiq/polyline-spec`**, at the version in `.spec/SPEC_VERSION`. Don't edit it here; it's replaced when the port moves to a newer spec.
- **`.kit/`** holds shared conventions, schemas and the validator. Don't edit it here either.

Read `.kit/CONVENTIONS.md` and `.spec/spec/SPEC.md` before changing behavior.

## Where to send a change

| You want to… | Where |
|---|---|
| Fix a bug in this port | Here. Add a test or point to the conformance case it fixes |
| Change how the library behaves | The spec repo `Xenoglyphiq/polyline-spec`. Open an issue there first |
| Report that this port behaves differently from another | The spec repo, with the input; it becomes a conformance case |
| Improve docs or examples for this port | Here |

## Checks every PR must pass

1. `python .kit/validate.py .spec` (needs `pip install pyyaml jsonschema`)
2. Build and unit tests: `nimble test`, plus `nim check src/polyline.nim` with no warnings
3. Conformance runner: `nimble conformance`; every claimed level must pass
4. The three canonical examples: `nimble examples`

## Style

- Follow Nim's own conventions for names, errors and packaging.
- Errors keep the kinds and codes from the spec; tests assert kind and code, never message text.
- Every public item has a doc comment naming the spec operation it implements.
- Public procs stay `{.raises: [PolylineError].}`. Check for overflow before `int64` arithmetic and guard every float-to-int conversion; never let a defect escape.

## License

By contributing you agree your contribution is licensed under MIT OR Apache-2.0, the same as this project.
