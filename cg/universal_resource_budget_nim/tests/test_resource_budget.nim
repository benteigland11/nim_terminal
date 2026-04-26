import std/unittest
import resource_budget_lib

suite "resource budget":
  test "allows usage below soft limit":
    let decision = decide(resourceLimit("items", 8, 10), resourceUsage("items", 4, 2))
    check decision.allowed
    check decision.severity == bsOk
    check decision.projected == 6
    check decision.remaining == 4

  test "warns at soft limit and blocks beyond hard limit":
    let warning = decide(resourceLimit("items", 8, 10), resourceUsage("items", 7, 1))
    check warning.allowed
    check warning.severity == bsWarning

    let critical = decide(resourceLimit("items", 8, 10), resourceUsage("items", 9, 1))
    check critical.allowed
    check critical.severity == bsCritical

    let blocked = decide(resourceLimit("items", 8, 10), resourceUsage("items", 10, 1))
    check not blocked.allowed
    check blocked.severity == bsOverLimit
    check blocked.remaining == 0

  test "summarizes multiple resources":
    let summary = decide(
      [resourceLimit("rows", 100, 120), resourceLimit("cache", 50, 60)],
      [resourceUsage("rows", 80, 10), resourceUsage("cache", 60, 1)],
    )
    check not summary.allowed
    check summary.severity == bsOverLimit
    check summary.decisionFor("rows").severity == bsOk
    check summary.decisionFor("cache").severity == bsOverLimit

  test "supports unbounded resources":
    let decision = decide(resourceLimit("items", -1, -1), resourceUsage("items", 1000, 1000))
    check decision.allowed
    check decision.severity == bsOk
    check decision.remaining == int64.high

  test "recommended cap respects hard limit":
    check recommendedCap(resourceLimit("items", 80, 100), 200) == 100
    check recommendedCap(resourceLimit("items", -1, -1), 200) == 200
