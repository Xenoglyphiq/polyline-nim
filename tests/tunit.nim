## Unit tests. The conformance runner (`tests/tconformance.nim`) is the real
## suite; these cover the canonical example, rounding and error details.

import std/[math, unittest]
import polyline

const
  googlePoints = [
    LonLat(lon: -120.2, lat: 38.5),
    LonLat(lon: -120.95, lat: 40.7),
    LonLat(lon: -126.453, lat: 43.252),
  ]
  googleText = "_p~iF~ps|U_ulLnnqC_mqNvxq`@"

proc errorOf(body: proc () {.raises: [PolylineError].}): ref PolylineError =
  try:
    body()
  except PolylineError as e:
    return e
  nil

suite "polyline":
  test "encode Google's example":
    check encode(googlePoints) == googleText

  test "decode Google's example":
    let pts = decode(googleText)
    check pts.len == googlePoints.len
    for i, want in googlePoints:
      check abs(pts[i].lon - want.lon) <= 1e-12
      check abs(pts[i].lat - want.lat) <= 1e-12

  test "math.round is half away from zero, without the +0.5 bug":
    check round(2.5) == 3.0
    check round(-2.5) == -3.0
    check round(0.49999999999999994) == 0.0
    # Through the library at precision 1: 0.25 * 10 = 2.5 -> 3 -> zigzag 6 -> 'E'.
    check encode([LonLat(lon: 0.25, lat: 0.25)], precision = 1) == "EE"
    check encode([LonLat(lon: -0.25, lat: -0.25)], precision = 1) == "DD"

  test "diagnostics carry kind, code and offset":
    let e = errorOf(proc () {.raises: [PolylineError].} =
      discard decode("_p~iF ~ps|U"))
    check e != nil
    check e.kind == ekInvalidInput
    check $e.kind == "invalid_input"
    check e.code == "polyline.invalid_char"
    check e.offset == some(5'u64)

  test "encode errors carry no offset":
    let e = errorOf(proc () {.raises: [PolylineError].} =
      discard encode([LonLat(lon: 0, lat: NaN)]))
    check e != nil
    check e.code == "polyline.non_finite"
    check e.offset.isNone

  test "limits are passed with precision":
    let e = errorOf(proc () {.raises: [PolylineError].} =
      discard decode(googleText, limits = Limits(maxPoints: 2)))
    check e != nil
    check e.kind == ekLimitExceeded
    check e.code == "polyline.too_many_points"
    check Limits().maxPoints == 1_000_000'u64
    check Limits().maxTextLength == 16'u64 * 1024 * 1024
    # Fields left out of a constructor keep their defaults.
    check Limits(maxPoints: 2).maxTextLength == 16'u64 * 1024 * 1024

  test "extreme values raise PolylineError, never a defect":
    let e = errorOf(proc () {.raises: [PolylineError].} =
      discard encode([LonLat(lon: 0, lat: 1e300)]))
    check e != nil
    check e.code == "polyline.overflow"
    let f = errorOf(proc () {.raises: [PolylineError].} =
      discard decode("____________G?____________G?"))
    check f != nil
    check f.code == "polyline.overflow"
    check f.offset == some(14'u64)
