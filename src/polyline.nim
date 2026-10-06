## Google's Encoded Polyline Algorithm Format: encode and decode lists of
## coordinates as compact ASCII strings.
##
## Implements the polyline spec (see `.spec/spec/SPEC.md`). Points are
## `(lon, lat)`; the encoded string stores latitude first.
##
## Every public proc raises only `PolylineError`. Overflow is detected before
## any `int64` arithmetic, so no `OverflowDefect` or `RangeDefect` can escape.

import std/[math, options]

export options

type
  LonLat* = object
    ## A WGS84 coordinate in degrees, as used by the spec operations `encode`
    ## and `decode`. Field order matches the API, not the string.
    lon*, lat*: float64

  ErrorKind* = enum
    ## Spec error kinds used by `encode` and `decode`. `$kind` is the spec's
    ## canonical name.
    ekInvalidInput = "invalid_input"
    ekLimitExceeded = "limit_exceeded"

  PolylineError* = object of CatchableError
    ## The only error raised by the spec operations `encode` and `decode`.
    kind*: ErrorKind           ## Spec error kind.
    code*: string              ## Stable spec error code, e.g. `"polyline.invalid_char"`.
    offset*: Option[uint64]    ## Byte offset into the input, when the spec defines one.

  Limits* = object
    ## Limits for the spec operations `encode` and `decode`. Defaults match the spec.
    maxPoints*: uint64 = 1_000_000          ## Points accepted or produced.
    maxTextLength*: uint64 = 16 * 1024 * 1024 ## Input length for `decode`, in bytes.

const
  pow10 = [1.0, 1e1, 1e2, 1e3, 1e4, 1e5, 1e6, 1e7, 1e8, 1e9, 1e10]
  two63 = 9223372036854775808.0 ## 2^63; scaled values must lie in [-2^63, 2^63).

proc fail(code: string, kind = ekInvalidInput, offset = none(uint64),
          msg = ""): ref PolylineError =
  var m = code
  if msg.len > 0: m.add ": " & msg
  if offset.isSome: m.add " at byte " & $offset.get
  (ref PolylineError)(kind: kind, code: code, offset: offset, msg: m)

proc checkPrecision(precision: int): float64 {.raises: [PolylineError].} =
  if precision < 1 or precision > 10:
    raise fail("polyline.precision_out_of_range",
               msg = "precision " & $precision & " is outside 1-10")
  pow10[precision]

# Hot loops. Every overflow they could hit is guarded by hand, so the compiler's
# own overflow checks are redundant there and cost ~40% of the run time. They
# stay on in test and fuzz builds (`-d:polylineChecked`), so the fuzzer still
# catches a missing manual guard. The loops never raise: on failure they record
# a `Failure` and return, and the public procs raise once.
when defined(polylineChecked):
  {.push overflowChecks: on.}
else:
  {.push overflowChecks: off.}

type Failure = object
  ## Built from literals only: formatting strings inside the hot loops adds
  ## cleanup code that slows them down even on the success path.
  code: string
  kind: ErrorKind
  offset: int        # -1 when the spec defines none
  msg: string
  byte: uint8        # the offending byte, for invalid_char

func zigzag(d: int64): uint64 {.inline.} =
  (cast[uint64](d) shl 1) xor cast[uint64](ashr(d, 63))

func encodedLen(d: int64): int {.inline.} =
  var u = zigzag(d)
  result = 1
  while u >= 0x20'u64:
    u = u shr 5
    inc result

proc writeValue(s: var string, i: var int, d: int64) {.inline.} =
  var u = zigzag(d)
  while u >= 0x20'u64:
    s[i] = char((0x20'u64 or (u and 0x1F'u64)) + 63)
    inc i
    u = u shr 5
  s[i] = char(u + 63)
  inc i

proc scaleAll(points: openArray[LonLat], scale: float64, scaled: var seq[int64],
              err: var Failure): bool {.raises: [].} =
  ## Spec §3 `encode` step 3 for every coordinate, lat then lon, in order.
  scaled.setLen(2 * points.len)
  var k = 0
  for p in points:
    for x in [p.lat, p.lon]:
      if x.classify in {fcNan, fcInf, fcNegInf}:
        err = Failure(code: "polyline.non_finite", offset: -1, msg: "coordinate is NaN or infinite")
        return false
      # math.round rounds half away from zero on the C backend, the family-wide rule.
      let n = round(x * scale)
      # Guard the float -> int64 conversion (Nim never checks it); NaN fails too.
      if not (n >= -two63 and n < two63):
        err = Failure(code: "polyline.overflow", offset: -1, msg: "scaled coordinate does not fit in int64")
        return false
      scaled[k] = int64(n)
      inc k
  true

proc encodeScaled(scaled: openArray[int64], output: var string,
                  err: var Failure): bool {.raises: [].} =
  ## Spec §3 `encode` steps 4–5: deltas (checked), exact length, then write.
  var total = 0
  var prev = [0'i64, 0'i64]
  for k, v in scaled:
    let p = prev[k and 1]
    if (p < 0 and v > high(int64) + p) or (p > 0 and v < low(int64) + p):
      err = Failure(code: "polyline.overflow", offset: -1, msg: "delta does not fit in int64")
      return false
    total += encodedLen(v - p)
    prev[k and 1] = v
  output = newString(total)
  var i = 0
  prev = [0'i64, 0'i64]
  for k, v in scaled:
    output.writeValue(i, v - prev[k and 1])
    prev[k and 1] = v
  assert i == total
  true

proc decodeInto(text: string, scale: float64, maxPoints: uint64,
                points: var seq[LonLat], err: var Failure): bool {.raises: [].} =
  ## Spec §3 `decode` step 3 onwards.
  var sumLat, sumLon: int64
  var isLon = false
  var latStart = 0
  var i = 0
  let n = text.len
  while i < n:
    let start = i
    var u = 0'u64
    var shift = 0
    while true:
      if i >= n:
        err = Failure(code: "polyline.truncated", offset: start, msg: "input ends mid-value")
        return false
      let c = uint8(text[i])
      if c < 63 or c > 126:
        err = Failure(code: "polyline.invalid_char", offset: i,
                      msg: "byte outside 63-126", byte: c)
        return false
      let b = uint64(c) - 63
      # At most 13 chunks; at shift 60 only 4 bits fit in a uint64.
      if shift > 60 or (shift == 60 and (b and 0x1F) > 0xF):
        err = Failure(code: "polyline.overflow", offset: start, msg: "value does not fit in 64 bits")
        return false
      u = u or ((b and 0x1F) shl shift)
      inc i
      if b < 0x20: break
      shift += 5
    let half = cast[int64](u shr 1)
    let d = if (u and 1) == 1: not half else: half
    if not isLon:
      if (d > 0 and sumLat > high(int64) - d) or (d < 0 and sumLat < low(int64) - d):
        err = Failure(code: "polyline.overflow", offset: start, msg: "running sum does not fit in int64")
        return false
      sumLat += d
      latStart = start
      isLon = true
    else:
      if (d > 0 and sumLon > high(int64) - d) or (d < 0 and sumLon < low(int64) - d):
        err = Failure(code: "polyline.overflow", offset: start, msg: "running sum does not fit in int64")
        return false
      sumLon += d
      if uint64(points.len) >= maxPoints:
        err = Failure(code: "polyline.too_many_points", kind: ekLimitExceeded, offset: -1,
                      msg: "more points than max_points")
        return false
      # Divide; multiplying by 10^-p differs in the last bit.
      points.add LonLat(lon: float64(sumLon) / scale, lat: float64(sumLat) / scale)
      isLon = false
  if isLon:
    err = Failure(code: "polyline.truncated", offset: latStart, msg: "latitude with no longitude")
    return false
  true

{.pop.}

proc raiseFailure(err: Failure) {.noreturn, raises: [PolylineError].} =
  let msg = if err.code == "polyline.invalid_char": "byte " & $err.byte & " is outside 63-126"
            else: err.msg
  raise fail(err.code, err.kind,
             if err.offset < 0: none(uint64) else: some(uint64(err.offset)), msg)

proc encode*(points: openArray[LonLat], precision = 5,
             limits = Limits()): string {.raises: [PolylineError].} =
  ## Spec operation `encode`. Encodes `points` as a polyline string at
  ## `precision` decimal places (1-10; 5 is Google's, 6 is OSRM's and Valhalla's).
  let scale = checkPrecision(precision)
  if uint64(points.len) > limits.maxPoints:
    raise fail("polyline.too_many_points", ekLimitExceeded,
               msg = $points.len & " points, limit " & $limits.maxPoints)
  var err: Failure
  var scaled: seq[int64]
  # Scale every coordinate once, before any delta (spec error order).
  if not scaleAll(points, scale, scaled, err): raiseFailure(err)
  if not encodeScaled(scaled, result, err): raiseFailure(err)

proc decode*(text: string, precision = 5,
             limits = Limits()): seq[LonLat] {.raises: [PolylineError].} =
  ## Spec operation `decode`. Decodes a polyline string into `(lon, lat)` points.
  ## `precision` must match the one used to encode.
  ##
  ## `\` (92) is a valid character: strings copied from JavaScript source often
  ## contain `\\` escapes, which decode to different points without any error.
  let scale = checkPrecision(precision)
  if uint64(text.len) > limits.maxTextLength:
    raise fail("polyline.text_too_long", ekLimitExceeded,
               msg = $text.len & " bytes, limit " & $limits.maxTextLength)
  var err: Failure
  if not decodeInto(text, scale, limits.maxPoints, result, err): raiseFailure(err)
