# Package

version       = "0.0.0"
author        = "Xenoglyphiq contributors"
description   = "Encode and decode Google's Encoded Polyline Algorithm Format"
license       = "MIT OR Apache-2.0"
srcDir        = "src"

# Dependencies

requires "nim >= 2.2.12"

# Tasks

task conformance, "Run every case in .spec/conformance/manifest.json":
  exec "nim c --hints:off -r tests/tconformance.nim"

task examples, "Run the three canonical examples":
  for name in ["encode_route", "decode_route", "precision_6"]:
    exec "nim c --hints:off -r examples/" & name & ".nim"

task fuzz, "Mutation-fuzz the decoder (FUZZ_SECONDS, default 10; FUZZ_SEED)":
  exec "nim c --hints:off -d:release -d:polylineChecked --overflowChecks:on --rangeChecks:on " &
    "--boundChecks:on -r tests/fuzz.nim"

task bench, "Time encode and decode on .spec/bench/route_100k.polyline":
  exec "nim c --hints:off -d:release -r bench/bench.nim"
