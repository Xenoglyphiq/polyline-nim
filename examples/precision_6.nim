## Canonical example `precision_6`: round-trip a route at precision 6 (OSRM, Valhalla).
import polyline

let route = [
  LonLat(lon: -73.985713, lat: 40.748441),
  LonLat(lon: -73.978569, lat: 40.751657),
  LonLat(lon: -73.968285, lat: 40.785091),
]
let text = encode(route, precision = 6)
let back = decode(text, precision = 6)

echo text
for i, a in route:
  let b = back[i]
  echo "(", a.lon, ", ", a.lat, ") -> (", b.lon, ", ", b.lat, ")"
  if abs(a.lon - b.lon) > 1e-6 or abs(a.lat - b.lat) > 1e-6:
    quit "round trip mismatch", 1
echo "round trip matches"
