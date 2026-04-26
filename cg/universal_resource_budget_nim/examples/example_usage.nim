## Example usage of Resource Budget.

import resource_budget_lib

let limits = [
  resourceLimit("items", softLimit = 80, hardLimit = 100),
  resourceLimit("cache", softLimit = 400, hardLimit = 512),
]
let usages = [
  resourceUsage("items", current = 70, requested = 5),
  resourceUsage("cache", current = 500, requested = 20),
]
let summary = decide(limits, usages)

doAssert not summary.allowed
doAssert summary.decisionFor("items").severity == bsOk
doAssert summary.decisionFor("cache").severity == bsOverLimit
