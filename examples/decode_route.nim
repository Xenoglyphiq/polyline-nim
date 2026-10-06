## Canonical example `decode_route`: decode Google's example and print each point.
import polyline

try:
  for p in decode("_p~iF~ps|U_ulLnnqC_mqNvxq`@"):
    echo "lon ", p.lon, ", lat ", p.lat
except PolylineError as e:
  stderr.writeLine e.kind, ": ", e.code, " at byte ",
    (if e.offset.isSome: $e.offset.get else: "?")
  quit 1
