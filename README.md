# Polyline for Nim

Encode and decode lists of coordinates as compact ASCII strings. Implements Google's Encoded Polyline Algorithm Format · Spec v0.1.1 · Conformance: **core ✓ full ✓** (44/44)

> **Coordinate order:** `LonLat` is `(lon, lat)`; the encoded string stores latitude first. The library converts at the boundary.

Requires Nim **2.2.12** on the C backend (the JS backend is untested). Standard library only.

## Install

```
nimble install polyline
```

Or in your `.nimble` file:

```nim
requires "polyline >= 0.1.0"
```

To pin the exact release by URL instead: `nimble install https://github.com/Xenoglyphiq/polyline-nim@#v0.1.0`.

## Quick start

```nim
import polyline

let text = encode([
  LonLat(lon: -120.2, lat: 38.5),
  LonLat(lon: -120.95, lat: 40.7),
])
let points = decode(text)
```

## Examples

Run all three with `nimble examples`.

### 1. Encode a three-point route (`examples/encode_route.nim`)
```nim
let route = [
  LonLat(lon: -120.2, lat: 38.5),
  LonLat(lon: -120.95, lat: 40.7),
  LonLat(lon: -126.453, lat: 43.252),
]
echo encode(route)
# _p~iF~ps|U_ulLnnqC_mqNvxq`@
```

### 2. Decode Google's example (`examples/decode_route.nim`)
```nim
try:
  for p in decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@"):
    echo "lon ", p.lon, ", lat ", p.lat
except PolylineError as e:
  stderr.writeLine e.kind, ": ", e.code, " at byte ",
    (if e.offset.isSome: $e.offset.get else: "?")
  quit 1
```

### 3. Round-trip at precision 6 (`examples/precision_6.nim`)
```nim
let text = encode(route, precision = 6) # OSRM, Valhalla
let back = decode(text, precision = 6)
```

## Limits and errors

| Limit | Default | Option name |
|---|---|---|
| Points accepted or produced | 1,000,000 | `Limits.maxPoints` |
| Input length for `decode` | 16 MiB | `Limits.maxTextLength` |

Pass limits as `limits = Limits(maxPoints: 1000)`. Precision (1–10, default 5) is the `precision` argument.

Errors are `PolylineError` (a `CatchableError`) with a `kind` (`ekInvalidInput` or `ekLimitExceeded`; `$kind` gives the spec names `invalid_input` and `limit_exceeded`), a stable `code` such as `polyline.invalid_char`, and the byte `offset: Option[uint64]` where the spec defines one. Full list: spec §3.

`encode` and `decode` are annotated `{.raises: [PolylineError].}`. Overflow is checked before any arithmetic and reported as `polyline.overflow`; no `OverflowDefect` or `RangeDefect` escapes.

`\` is a valid polyline character. Strings copied from JavaScript source often contain `\\` escapes and decode to different points without any error.

## Modules

| Module | Layer | Needs |
|---|---|---|
| `polyline` | core | nothing beyond the standard library |

There is no io layer: everything works on in-memory strings and arrays.

## Development

| Command | What |
|---|---|
| `nimble test` | Unit tests and the conformance runner |
| `nimble conformance` | Every case in `.spec/conformance/manifest.json` |
| `nimble examples` | The three canonical examples |
| `FUZZ_SECONDS=600 nimble fuzz` | Mutation-fuzz the decoder (`FUZZ_SEED` replays a run) |
| `nimble bench` | Timings on `.spec/bench/route_100k.polyline` (`-d:release`; method in `.spec/bench/README.md`) |

## Performance

| Benchmark | Reference | This port | Ratio |
|---|---|---|---|
| Encode 100k points | Rust `polyline` 0.11.0: 0.892 ms | 1.645 ms | 1.84× |
| Decode 100k points | Rust `polyline` 0.11.0: 0.643 ms | 0.802 ms | 1.25× |

Medians on `.spec/bench/route_100k.polyline` (100,000 points), measured 2026-10-05 on an Apple M5 Pro with `nimble bench` (`-d:release`), Nim 2.2.12. Three rounds interleaved with the reference, following `.spec/bench/README.md`. Ratio = this port ÷ reference; the spec's target is within 2×.

## License

MIT OR Apache-2.0
