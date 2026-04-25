import std/unittest
import ../src/windows_handle_lib

suite "windows handle manager":

  test "automatic closing on destruction":
    var closedValue = 0
    proc mockCloser(h: int) = closedValue = h
    
    block:
      let h = wrap(123, mockCloser)
      check h.isValid
      check h.value == 123
    
    # h is now out of scope; mockCloser should have been called
    check closedValue == 123

  test "manual closing":
    var closedValue = 0
    proc mockCloser(h: int) = closedValue = h
    
    var h = wrap(456, mockCloser)
    h.close()
    check h.isValid == false
    check closedValue == 456
    
    # Reset and ensure it doesn't close twice
    closedValue = 0
    h.close()
    check closedValue == 0

  test "claiming ownership":
    var closedValue = 0
    proc mockCloser(h: int) = closedValue = h
    
    var rawValue = 0
    block:
      var h = wrap(789, mockCloser)
      rawValue = h.claim()
      check h.isValid == false
    
    # h is out of scope, but because we claimed it, closer should NOT be called
    check rawValue == 789
    check closedValue == 0
