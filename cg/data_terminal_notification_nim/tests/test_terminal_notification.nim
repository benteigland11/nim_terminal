import std/unittest
import ../src/terminal_notification_lib

suite "terminal desktop notifications":
  test "OSC 9 message is a notification":
    let n = parseOsc9Notification("Build finished")
    check n.ok
    check n.note.body == "Build finished"
    check n.note.source == "osc9"

  test "OSC 9 progress form is rejected":
    check not parseOsc9Notification("4;1;50").ok
    check not parseOsc9Notification("4").ok

  test "OSC 777 notify title body":
    let n = parseOsc777Notification("notify;Done;All tests passed")
    check n.ok
    check n.note.title == "Done"
    check n.note.body == "All tests passed"
    check toastText(n.note) == "Done — All tests passed"

  test "OSC 777 notify single message":
    let n = parseOsc777Notification("notify;hello")
    check n.ok
    check n.note.body == "hello"

  test "OSC 99 simple payload":
    var a = newNotificationAssembler()
    let n = a.feedOsc99(";Hello world")
    check n.ok
    check n.note.title == "Hello world"

  test "OSC 99 title then body chunks":
    var a = newNotificationAssembler()
    let first = a.feedOsc99("i=1:d=0;Hello")
    check not first.ok
    let second = a.feedOsc99("i=1:p=body;This is cool")
    check second.ok
    check second.note.title == "Hello"
    check second.note.body == "This is cool"
