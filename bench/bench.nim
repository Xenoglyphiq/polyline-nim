## Benchmark per `.spec/bench/README.md`: precision 5; decode once untimed;
## 3 warm-up runs, then 15 timed runs each of encode(points) and decode(text);
## report median and min. Run: `nimble bench` (built with -d:release).

import std/[algorithm, monotimes, os, strformat, strutils, times]
import polyline

const
  warmup = 3
  runs = 15

proc timed(body: proc ()): (float, float) =
  for _ in 1 .. warmup: body()
  var ms: seq[float]
  for _ in 1 .. runs:
    let start = getMonoTime()
    body()
    ms.add (getMonoTime() - start).inNanoseconds.float / 1e6
  ms.sort()
  (ms[runs div 2], ms[0])

proc main() =
  let path = if paramCount() >= 1: paramStr(1) else: ".spec/bench/route_100k.polyline"
  let text = readFile(path).strip(leading = false, chars = {'\n'})
  let points = decode(text)
  doAssert encode(points) == text, "round trip must reproduce the input"

  var sink = 0
  let (encMed, encMin) = timed(proc () = sink += encode(points).len)
  let (decMed, decMin) = timed(proc () = sink += decode(text).len)
  doAssert sink > 0
  echo &"polyline nim {NimVersion} -d:release ({points.len} points): " &
    &"encode median {encMed:.3f} ms (min {encMin:.3f}), " &
    &"decode median {decMed:.3f} ms (min {decMin:.3f})"

main()
