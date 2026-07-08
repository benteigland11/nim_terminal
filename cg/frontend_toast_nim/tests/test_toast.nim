import std/unittest
import toast_lib

suite "toast queue":
  test "push assigns increasing ids":
    var q = newToastQueue()
    check q.push("first", now = 0.0) == 1
    check q.push("second", now = 0.0) == 2

  test "active while within ttl+fade window":
    var q = newToastQueue()
    q.push("hi", now = 0.0, ttl = 2.0, fade = 0.5)
    check q.hasActive(now = 1.0)
    check q.hasActive(now = 2.4)
    check not q.hasActive(now = 2.5)

  test "prune drops fully expired toasts":
    var q = newToastQueue()
    q.push("a", now = 0.0, ttl = 1.0, fade = 0.0)
    q.push("b", now = 5.0, ttl = 1.0, fade = 0.0)
    q.prune(now = 5.0)
    check q.items.len == 1
    check q.items[0].text == "b"

  test "visible toasts are newest-first and capped":
    var q = newToastQueue(maxVisible = 2)
    q.push("a", now = 0.0, ttl = 10.0)
    q.push("b", now = 0.0, ttl = 10.0)
    q.push("c", now = 0.0, ttl = 10.0)
    let vis = q.visibleToasts(now = 1.0)
    check vis.len == 2
    check vis[0].text == "c"
    check vis[1].text == "b"

  test "alpha stays full then fades to zero":
    var q = newToastQueue()
    let id = q.push("x", now = 0.0, ttl = 2.0, fade = 1.0)
    check id == 1
    let t = q.items[0]
    check toastAlpha(t, now = 1.0) == 1.0
    check toastAlpha(t, now = 2.5) > 0.0
    check toastAlpha(t, now = 2.5) < 1.0
    check toastAlpha(t, now = 3.0) == 0.0
