import benchmark_suite_lib

var total = 0
let result = runBenchmark("integer addition", proc() =
  total += 1
, BenchmarkConfig(warmupIterations: 5, iterations: 10, batchSize: 100))

doAssert total == 1500
doAssert result.iterations == 10
doAssert result.batchSize == 100
doAssert result.samplesNs.len == 10
doAssert result.nsPerOperation >= 0.0
