import std/[strutils, unittest]
import benchmark_suite_lib

suite "Benchmark Suite":
  test "normalizes invalid config values":
    var counter = 0
    let body: BenchmarkBody = proc() =
      inc counter
    let result = runBenchmark("counter", body,
      BenchmarkConfig(warmupIterations: -10, iterations: 0, batchSize: 0))

    check result.name == "counter"
    check result.iterations == 1
    check result.batchSize == 1
    check counter == 1
    check result.samplesNs.len == 1

  test "runs warmups and batched iterations":
    var counter = 0
    let body: BenchmarkBody = proc() =
      inc counter
    let result = runBenchmark("batched", body,
      BenchmarkConfig(warmupIterations: 2, iterations: 3, batchSize: 4))

    check counter == 20
    check result.iterations == 3
    check result.batchSize == 4
    check result.samplesNs.len == 3
    check result.totalNs >= 0
    check result.maxNs >= result.minNs
    check result.meanNs >= 0.0
    check result.medianNs >= 0.0

  test "runs a suite in declaration order":
    var a = 0
    var b = 0
    let bodyA: BenchmarkBody = proc() =
      inc a
    let bodyB: BenchmarkBody = proc() =
      inc b
    let suiteResult = runSuite([
      ("a", bodyA),
      ("b", bodyB)
    ], BenchmarkConfig(warmupIterations: 1, iterations: 2, batchSize: 1))

    check suiteResult.results.len == 2
    check suiteResult.results[0].name == "a"
    check suiteResult.results[1].name == "b"
    check a == 3
    check b == 3

  test "formats summary and csv output":
    let body: BenchmarkBody = proc() =
      discard
    let suiteResult = runSuite([
      ("item", body)
    ], BenchmarkConfig(warmupIterations: 0, iterations: 2, batchSize: 2))

    let line = summaryLine(suiteResult.results[0])
    let csv = toCsv(suiteResult)

    check line.contains("item")
    check line.contains("ns/op=")
    check csv.startsWith("name,iterations,batch_size")
    check csv.contains("item,2,2")
