switch("path", "$projectDir/../src")

# Keep the compiler overflow checks on inside the hot loops for tests and fuzzing,
# so a missing manual guard becomes a crash the tests and fuzzer catch.
switch("define", "polylineChecked")
