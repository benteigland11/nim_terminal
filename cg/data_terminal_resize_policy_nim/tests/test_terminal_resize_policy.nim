import std/unittest
import ../src/terminal_resize_policy_lib

suite "terminal resize policy":
  test "healthy desired size applies when changed":
    let plan = planTerminalResize(80, 24, 80, 20, minCols = 40, minRows = 8)
    check plan.apply
    check plan.cols == 80 and plan.rows == 24
    check not plan.undersized
    check not plan.heldLastGood

  test "unchanged size is a no-op":
    let plan = planTerminalResize(80, 24, 80, 24, minCols = 40, minRows = 8)
    check not plan.apply
    check not plan.undersized

  test "undersized pane holds last good TUI size":
    let plan = planTerminalResize(10, 4, 80, 24, minCols = 40, minRows = 8)
    check not plan.apply
    check plan.undersized
    check plan.heldLastGood
    check plan.cols == 80 and plan.rows == 24

  test "undersized with no healthy current clamps up to floor":
    let plan = planTerminalResize(5, 3, 5, 3, minCols = 40, minRows = 8)
    check plan.apply
    check plan.undersized
    check plan.cols == 40 and plan.rows == 8

  test "rate limit suppresses apply until interval elapses":
    var limit = newResizeRateLimit(0.05)
    limit.markApplied(1.0)
    let blocked = planWithRateLimit(limit, 1.02, 100, 30, 80, 24)
    check blocked.cols == 100
    check not blocked.apply
    let allowed = planWithRateLimit(limit, 1.06, 100, 30, 80, 24)
    check allowed.apply

  test "pending flag tracks activity":
    var limit = newResizeRateLimit()
    check not limit.shouldRunResizePass
    limit.noteResizeActivity()
    check limit.shouldRunResizePass
    check takePending(limit)
    check not limit.shouldRunResizePass
