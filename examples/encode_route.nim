## Canonical example `encode_route`: encode a three-point route and print the string.
import polyline

let route = [
  LonLat(lon: -120.2, lat: 38.5),
  LonLat(lon: -120.95, lat: 40.7),
  LonLat(lon: -126.453, lat: 43.252),
]
echo encode(route)
