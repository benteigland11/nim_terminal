## Generic resource budget decisions.
##
## Evaluates current usage against caller-provided soft and hard limits.
## The widget is intentionally domain-neutral: quantities can represent
## bytes, rows, sessions, cached items, or any other countable resource.

type
  BudgetSeverity* = enum
    bsOk
    bsWarning
    bsCritical
    bsOverLimit

  ResourceLimit* = object
    name*: string
    softLimit*: int64
    hardLimit*: int64

  ResourceUsage* = object
    name*: string
    current*: int64
    requested*: int64

  BudgetDecision* = object
    name*: string
    current*: int64
    requested*: int64
    projected*: int64
    softLimit*: int64
    hardLimit*: int64
    severity*: BudgetSeverity
    allowed*: bool
    remaining*: int64

  BudgetSummary* = object
    decisions*: seq[BudgetDecision]
    severity*: BudgetSeverity
    allowed*: bool

func resourceLimit*(name: string, softLimit, hardLimit: int64): ResourceLimit =
  ## Create a limit pair. Negative limits mean "unbounded".
  ResourceLimit(name: name, softLimit: softLimit, hardLimit: hardLimit)

func resourceUsage*(name: string, current: int64, requested: int64 = 0): ResourceUsage =
  ## Create a usage record. `requested` is added to `current` for admission.
  ResourceUsage(name: name, current: max(0'i64, current), requested: max(0'i64, requested))

func maxSeverity*(a, b: BudgetSeverity): BudgetSeverity =
  if ord(a) >= ord(b): a else: b

func decide*(limit: ResourceLimit, usage: ResourceUsage): BudgetDecision =
  ## Evaluate one resource against its limits.
  let projected = usage.current + usage.requested
  let hasSoft = limit.softLimit >= 0
  let hasHard = limit.hardLimit >= 0
  var severity = bsOk
  if hasHard and projected > limit.hardLimit:
    severity = bsOverLimit
  elif hasHard and projected == limit.hardLimit:
    severity = bsCritical
  elif hasSoft and projected >= limit.softLimit:
    severity = bsWarning

  let remaining =
    if hasHard: max(0'i64, limit.hardLimit - projected)
    else: int64.high

  BudgetDecision(
    name: limit.name,
    current: usage.current,
    requested: usage.requested,
    projected: projected,
    softLimit: limit.softLimit,
    hardLimit: limit.hardLimit,
    severity: severity,
    allowed: severity != bsOverLimit,
    remaining: remaining,
  )

func decide*(limits: openArray[ResourceLimit], usages: openArray[ResourceUsage]): BudgetSummary =
  ## Evaluate many resources. Missing usage is treated as zero.
  result.allowed = true
  result.severity = bsOk
  for limit in limits:
    var usage = resourceUsage(limit.name, 0)
    for item in usages:
      if item.name == limit.name:
        usage = item
        break
    let decision = decide(limit, usage)
    result.decisions.add decision
    result.severity = maxSeverity(result.severity, decision.severity)
    result.allowed = result.allowed and decision.allowed

func decisionFor*(summary: BudgetSummary, name: string): BudgetDecision =
  ## Return the named decision, or an unbounded zero decision when absent.
  for decision in summary.decisions:
    if decision.name == name:
      return decision
  decide(resourceLimit(name, -1, -1), resourceUsage(name, 0))

func recommendedCap*(limit: ResourceLimit, requestedDefault: int64): int64 =
  ## Choose a safe configured cap bounded by the hard limit when present.
  let requested = max(0'i64, requestedDefault)
  if limit.hardLimit >= 0:
    min(requested, limit.hardLimit)
  else:
    requested
