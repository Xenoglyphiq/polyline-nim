## Mutation fuzzer for `decode` (standard library only).
##
## Corpus: every decode input in `.spec/conformance/manifest.json`, plus a few
## random strings. Each iteration takes a corpus entry, applies 1-4 random
## mutations and runs `decode`. Invariants:
##   - only `PolylineError` escapes; any other exception or defect is a failure;
##   - a raised error always has a non-empty `code`;
##   - if `decode` succeeds, `encode` of the result succeeds or raises
##     `polyline.overflow` (values near the int64 edge lose precision as f64).
##
## Environment: `FUZZ_SECONDS` (default 10), `FUZZ_SEED` (default: time-based).
## Build with overflow, range and bound checks on (see `nimble fuzz`) so a
## missing guard turns into a defect the harness catches.

import std/[json, monotimes, os, random, strutils, times]
import polyline

proc loadCorpus(r: var Rand): seq[string] =
  let path = currentSourcePath().parentDir.parentDir / ".spec" / "conformance" / "manifest.json"
  for c in parseFile(path)["cases"].getElems:
    if c["op"].getStr == "decode":
      result.add c["input"]["value"].getStr
  for _ in 0 ..< 8:
    var s = newString(r.rand(0 .. 40))
    for ch in s.mitems:
      ch = char(if r.rand(1) == 0: r.rand(63 .. 126) else: r.rand(0 .. 255))
    result.add s

proc randomByte(r: var Rand): char =
  char(if r.rand(1) == 0: r.rand(63 .. 126) else: r.rand(0 .. 255))

proc mutate(r: var Rand, s: var string) =
  case r.rand(5)
  of 0: # flip a byte (XOR with a random non-zero mask)
    if s.len > 0:
      let i = r.rand(s.len - 1)
      s[i] = char(uint8(s[i]) xor uint8(r.rand(1 .. 255)))
  of 1: # insert a random byte
    s.insert($randomByte(r), r.rand(s.len))
  of 2: # delete a byte
    if s.len > 0:
      let i = r.rand(s.len - 1)
      s.delete(i .. i)
  of 3: # duplicate a slice
    if s.len > 0:
      let a = r.rand(s.len - 1)
      let b = r.rand(a .. s.len - 1)
      s.insert(s[a .. b], r.rand(s.len))
  of 4: # truncate
    s.setLen(r.rand(s.len))
  else: # append "~" * k
    s.add repeat('~', r.rand(1 .. 16))

proc failWith(input, why: string) =
  echo "FUZZ FAILURE: ", why
  echo "input: ", escape(input)
  quit 1

proc check(input: string) =
  var points: seq[LonLat]
  try:
    points = decode(input)
  except PolylineError as e:
    if e.code.len == 0: failWith(input, "PolylineError with empty code")
    return
  except Defect as e:
    failWith(input, "decode raised " & $e.name & ": " & e.msg)
  except CatchableError as e:
    failWith(input, "decode raised " & $e.name & ": " & e.msg)
  try:
    discard encode(points)
  except PolylineError as e:
    if e.code != "polyline.overflow":
      failWith(input, "re-encode raised " & e.code)
  except Defect as e:
    failWith(input, "re-encode raised " & $e.name & ": " & e.msg)
  except CatchableError as e:
    failWith(input, "re-encode raised " & $e.name & ": " & e.msg)

proc main() =
  let seconds = parseFloat(getEnv("FUZZ_SECONDS", "10"))
  let seed =
    if existsEnv("FUZZ_SEED"): parseBiggestInt(getEnv("FUZZ_SEED"))
    else:
      let t = getTime()
      t.toUnix * 1_000_000_000 + t.nanosecond
  echo "seed ", seed
  var r = initRand(seed)
  let corpus = loadCorpus(r)

  let start = getMonoTime()
  let budget = initDuration(nanoseconds = int64(seconds * 1e9))
  var iterations = 0
  while true:
    # Check the clock every 1024 inputs; it costs more than a decode.
    if (iterations and 1023) == 0 and getMonoTime() - start >= budget: break
    var s = corpus[r.rand(corpus.len - 1)]
    for _ in 1 .. r.rand(1 .. 4):
      mutate(r, s)
    check(s)
    inc iterations
  let elapsed = (getMonoTime() - start).inNanoseconds.float64 / 1e9
  echo "iterations ", iterations, ", elapsed ", formatFloat(elapsed, ffDecimal, 1), " s, clean"

when isMainModule:
  main()
