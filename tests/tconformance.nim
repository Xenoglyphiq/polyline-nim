## Conformance runner: loads `.spec/conformance/manifest.json`, runs every case,
## and compares results the way the case says to (`exact` or `float_tol`).
##
## Usage: `nimble conformance` (or `tconformance [manifest.json]`).
## Exit code 0 only if every case passes.

import std/[json, os]
import polyline

type CaseError = object of CatchableError

proc bad(msg: string): ref CaseError = newException(CaseError, msg)

proc toFloat(v: JsonNode): float64 =
  ## Canonical JSON floats: numbers, or "NaN" / "Infinity" / "-Infinity" strings.
  case v.kind
  of JFloat: v.getFloat
  of JInt: float64(v.getBiggestInt)
  of JString:
    case v.getStr
    of "NaN": NaN
    of "Infinity": Inf
    of "-Infinity": NegInf
    else: raise bad("bad float " & $v)
  else: raise bad("bad float " & $v)

proc toPoints(v: JsonNode): seq[LonLat] =
  for item in v.getElems:
    result.add LonLat(lon: toFloat(item["lon"]), lat: toFloat(item["lat"]))

proc fmtPoint(p: LonLat): string = "(" & $p.lon & ", " & $p.lat & ")"

proc compareError(e: ref PolylineError, expect: JsonNode, why: var string): bool =
  if not expect.hasKey("error"):
    why = "unexpected error " & e.code & " (" & $e.kind & ")"
    return false
  let want = expect["error"]
  let wantKind = want["kind"].getStr
  let wantCode = want["code"].getStr
  if $e.kind != wantKind or e.code != wantCode:
    why = "expected " & wantKind & "/" & wantCode & ", got " & $e.kind & "/" & e.code
    return false
  if want.hasKey("offset"):
    let wantOffset = uint64(want["offset"].getBiggestInt)
    if e.offset != some(wantOffset):
      why = "expected offset " & $wantOffset & ", got " &
        (if e.offset.isSome: $e.offset.get else: "none")
      return false
  true

proc runCase(c: JsonNode, why: var string): bool =
  let op = c["op"].getStr
  let input = c["input"]["value"]
  let expect = c["expect"]
  var precision = 5
  var limits = Limits()
  if c.hasKey("options"):
    let o = c["options"]
    if o.hasKey("precision"): precision = o["precision"].getInt
    if o.hasKey("max_points"): limits.maxPoints = uint64(o["max_points"].getBiggestInt)
    if o.hasKey("max_text_length"):
      limits.maxTextLength = uint64(o["max_text_length"].getBiggestInt)

  case op
  of "encode":
    let points = toPoints(input)
    var text: string
    try:
      text = encode(points, precision, limits)
    except PolylineError as e:
      return compareError(e, expect, why)
    if not expect.hasKey("value"):
      why = "expected an error, got \"" & text & "\""
      return false
    let want = expect["value"].getStr
    if text != want:
      why = "expected \"" & want & "\", got \"" & text & "\""
      return false
    true
  of "decode":
    var got: seq[LonLat]
    try:
      got = decode(input.getStr, precision, limits)
    except PolylineError as e:
      return compareError(e, expect, why)
    if not expect.hasKey("value"):
      why = "expected an error, got " & $got.len & " points"
      return false
    let want = toPoints(expect["value"])
    let tol =
      case c["compare"].getStr
      of "exact": 0.0
      of "float_tol": toFloat(c["tolerance"])
      else: raise bad("unknown compare mode " & c["compare"].getStr)
    if got.len != want.len:
      why = "expected " & $want.len & " points, got " & $got.len
      return false
    for i in 0 ..< got.len:
      if not (abs(got[i].lon - want[i].lon) <= tol and abs(got[i].lat - want[i].lat) <= tol):
        why = "point " & $i & ": expected " & fmtPoint(want[i]) & ", got " & fmtPoint(got[i])
        return false
    true
  else:
    why = "unknown op " & op
    false

proc main(): int =
  let path =
    if paramCount() >= 1: paramStr(1)
    else: currentSourcePath().parentDir.parentDir / ".spec" / "conformance" / "manifest.json"
  let manifest = parseFile(path)
  let specVersion = manifest["spec_version"].getStr

  var corePassed, coreTotal, fullPassed, fullTotal = 0
  for c in manifest["cases"].getElems:
    let level = c{"level"}.getStr("core")
    var why = ""
    var ok = false
    try:
      ok = runCase(c, why)
    except CatchableError as e:
      why = "runner error: " & e.msg
    if not ok:
      echo "FAIL ", c["id"].getStr, ": ", why
    # Every case counts toward full; only core cases count toward core.
    inc fullTotal
    if ok: inc fullPassed
    if level == "core":
      inc coreTotal
      if ok: inc corePassed
  echo "polyline nim (spec ", specVersion, "): core ", corePassed, "/", coreTotal,
    ", full ", fullPassed, "/", fullTotal
  if fullPassed != fullTotal: 1 else: 0

when isMainModule:
  quit main()
