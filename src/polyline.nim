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

proc scaleValue(x, scale: float64): int64 {.raises: [PolylineError].} =
  ## Scale one coordinate to its integer form (spec §3 `encode`, step 3).
  if x.classify in {fcNan, fcInf, fcNegInf}:
    raise fail("polyline.non_finite", msg = "coordinate is NaN or infinite")
  # math.round rounds half away from zero on the C backend, the family-wide rule.
  let n = round(x * scale)
  # Guard the float -> int64 conversion; a failed comparison (NaN) also lands here.
  if not (n >= -two63 and n < two63):
    raise fail("polyline.overflow", msg = "scaled coordinate does not fit in int64")
  int64(n)

proc delta(curr, prev: int64): int64 {.raises: [PolylineError].} =
  ## `curr - prev`, checked before subtracting.
  if (prev < 0 and curr > high(int64) + prev) or
     (prev > 0 and curr < low(int64) + prev):
    raise fail("polyline.overflow", msg = "delta does not fit in int64")
  curr - prev

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

proc encode*(points: openArray[LonLat], precision = 5,
             limits = Limits()): string {.raises: [PolylineError].} =
  ## Spec operation `encode`. Encodes `points` as a polyline string at
  ## `precision` decimal places (1-10; 5 is Google's, 6 is OSRM's and Valhalla's).
  let scale = checkPrecision(precision)
  if uint64(points.len) > limits.maxPoints:
    raise fail("polyline.too_many_points", ekLimitExceeded,
               msg = $points.len & " points, limit " & $limits.maxPoints)

  # Pass 1: validate and scale every coordinate before any delta (spec error order).
  for p in points:
    discard scaleValue(p.lat, scale)
    discard scaleValue(p.lon, scale)

  # Pass 2: deltas, overflow checks and the exact output length.
  var total = 0
  var prevLat, prevLon: int64
  for p in points:
    let lat = scaleValue(p.lat, scale)
    let lon = scaleValue(p.lon, scale)
    total += encodedLen(delta(lat, prevLat))
    total += encodedLen(delta(lon, prevLon))
    prevLat = lat
    prevLon = lon

  # Pass 3: write. Every check has passed, so the subtractions cannot overflow.
  result = newString(total)
  var i = 0
  prevLat = 0
  prevLon = 0
  for p in points:
    let lat = scaleValue(p.lat, scale)
    let lon = scaleValue(p.lon, scale)
    result.writeValue(i, lat - prevLat)
    result.writeValue(i, lon - prevLon)
    prevLat = lat
    prevLon = lon
  assert i == total

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

  var sumLat, sumLon: int64
  var isLon = false
  var latStart = 0
  var i = 0
  while i < text.len:
    let start = i
    var u = 0'u64
    var chunks = 0
    while true:
      if i >= text.len:
        raise fail("polyline.truncated", offset = some(uint64(start)),
                   msg = "input ends mid-value")
      let c = uint8(text[i])
      if c < 63 or c > 126:
        raise fail("polyline.invalid_char", offset = some(uint64(i)),
                   msg = "byte " & $c & " is outside 63-126")
      let b = uint64(c - 63)
      inc chunks
      if chunks > 13:
        raise fail("polyline.overflow", offset = some(uint64(start)),
                   msg = "value has more than 13 chunks")
      let shift = 5 * (chunks - 1)
      # At shift 60 only 4 bits fit in a uint64.
      if shift == 60 and (b and 0x1F) > 0xF:
        raise fail("polyline.overflow", offset = some(uint64(start)),
                   msg = "value does not fit in 64 bits")
      u = u or ((b and 0x1F) shl shift)
      inc i
      if b < 0x20: break

    let half = cast[int64](u shr 1)
    let d = if (u and 1) == 1: not half else: half
    template addChecked(sum: untyped) =
      if (d > 0 and sum > high(int64) - d) or (d < 0 and sum < low(int64) - d):
        raise fail("polyline.overflow", offset = some(uint64(start)),
                   msg = "running sum does not fit in int64")
      sum += d
    if not isLon:
      addChecked(sumLat)
      latStart = start
      isLon = true
    else:
      addChecked(sumLon)
      if uint64(result.len) >= limits.maxPoints:
        raise fail("polyline.too_many_points", ekLimitExceeded,
                   msg = "more than " & $limits.maxPoints & " points")
      # Divide; multiplying by 10^-p differs in the last bit.
      result.add LonLat(lon: float64(sumLon) / scale, lat: float64(sumLat) / scale)
      isLon = false

  if isLon:
    raise fail("polyline.truncated", offset = some(uint64(latStart)),
               msg = "latitude with no longitude")
