## Small deterministic benchmark runner.
##
## The widget provides a dependency-free harness for microbenchmarks:
## warm up, run a fixed number of iterations, collect nanosecond timings,
## and return summary statistics that callers can render or persist.

import std/[algorithm, strutils, times]

type
  BenchmarkBody* = proc() {.closure.}

  BenchmarkConfig* = object
    warmupIterations*: int
    iterations*: int
    batchSize*: int

  BenchmarkResult* = object
    name*: string
    iterations*: int
    batchSize*: int
    totalNs*: int64
    minNs*: int64
    maxNs*: int64
    meanNs*: float
    medianNs*: float
    samplesNs*: seq[int64]

  BenchmarkSuiteResult* = object
    results*: seq[BenchmarkResult]

func defaultBenchmarkConfig*(): BenchmarkConfig =
  BenchmarkConfig(warmupIterations: 10, iterations: 100, batchSize: 1)

func validateConfig(config: BenchmarkConfig): BenchmarkConfig =
  result = config
  if result.warmupIterations < 0:
    result.warmupIterations = 0
  if result.iterations < 1:
    result.iterations = 1
  if result.batchSize < 1:
    result.batchSize = 1

proc elapsedNs(startedAt: Time): int64 =
  (getTime() - startedAt).inNanoseconds

proc runBatch(body: BenchmarkBody, batchSize: int) =
  for _ in 0 ..< batchSize:
    body()

func median(sortedSamples: openArray[int64]): float =
  if sortedSamples.len == 0:
    return 0.0
  let mid = sortedSamples.len div 2
  if (sortedSamples.len mod 2) == 1:
    float(sortedSamples[mid])
  else:
    (float(sortedSamples[mid - 1]) + float(sortedSamples[mid])) / 2.0

proc summarize(name: string, samples: seq[int64], batchSize: int): BenchmarkResult =
  var sorted = samples
  sorted.sort()

  var total: int64 = 0
  for sample in samples:
    total += sample

  BenchmarkResult(
    name: name,
    iterations: samples.len,
    batchSize: batchSize,
    totalNs: total,
    minNs: sorted[0],
    maxNs: sorted[^1],
    meanNs: float(total) / float(samples.len),
    medianNs: median(sorted),
    samplesNs: samples
  )

proc runBenchmark*(name: string, body: BenchmarkBody,
                   config: BenchmarkConfig = defaultBenchmarkConfig()): BenchmarkResult =
  ## Run one benchmark and return per-batch timing statistics in nanoseconds.
  let cfg = validateConfig(config)

  for _ in 0 ..< cfg.warmupIterations:
    runBatch(body, cfg.batchSize)

  var samples = newSeqOfCap[int64](cfg.iterations)
  for _ in 0 ..< cfg.iterations:
    let startedAt = getTime()
    runBatch(body, cfg.batchSize)
    samples.add elapsedNs(startedAt)

  summarize(name, samples, cfg.batchSize)

proc runSuite*(benchmarks: openArray[(string, BenchmarkBody)],
               config: BenchmarkConfig = defaultBenchmarkConfig()): BenchmarkSuiteResult =
  ## Run benchmarks in declaration order with one shared config.
  for benchmark in benchmarks:
    result.results.add runBenchmark(benchmark[0], benchmark[1], config)

func nsPerOperation*(item: BenchmarkResult): float =
  ## Mean nanoseconds for one body call, accounting for batch size.
  item.meanNs / float(item.batchSize)

func formatNanoseconds*(ns: float): string =
  ## Format a nanosecond duration using a compact human-readable unit.
  if ns < 1_000.0:
    $ns.formatFloat(ffDecimal, 2) & " ns"
  elif ns < 1_000_000.0:
    $(ns / 1_000.0).formatFloat(ffDecimal, 2) & " us"
  elif ns < 1_000_000_000.0:
    $(ns / 1_000_000.0).formatFloat(ffDecimal, 2) & " ms"
  else:
    $(ns / 1_000_000_000.0).formatFloat(ffDecimal, 2) & " s"

func summaryLine*(item: BenchmarkResult): string =
  ## Render one compact line suitable for logs or snapshot files.
  item.name & ": mean=" & formatNanoseconds(item.meanNs) &
    " median=" & formatNanoseconds(item.medianNs) &
    " min=" & formatNanoseconds(float(item.minNs)) &
    " max=" & formatNanoseconds(float(item.maxNs)) &
    " ns/op=" & formatNanoseconds(item.nsPerOperation)

func toCsv*(suite: BenchmarkSuiteResult): string =
  ## Render suite results as CSV for simple machine parsing.
  result = "name,iterations,batch_size,total_ns,min_ns,max_ns,mean_ns,median_ns,ns_per_op\n"
  for item in suite.results:
    result.add item.name
    result.add ","
    result.add $item.iterations
    result.add ","
    result.add $item.batchSize
    result.add ","
    result.add $item.totalNs
    result.add ","
    result.add $item.minNs
    result.add ","
    result.add $item.maxNs
    result.add ","
    result.add $item.meanNs
    result.add ","
    result.add $item.medianNs
    result.add ","
    result.add $item.nsPerOperation
    result.add "\n"
