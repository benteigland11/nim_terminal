## Example usage of Toast.

import toast_lib

var toasts = newToastQueue(maxVisible = 3)

# The host passes its own clock in. Here we simulate seconds.
toasts.push("Copied id", now = 0.0, ttl = 2.5, fade = 0.4)

# While active, the host keeps redrawing and renders the visible toasts.
assert toasts.hasActive(now = 1.0)
let live = toasts.visibleToasts(now = 1.0)
assert live.len == 1
assert toastAlpha(live[0], now = 1.0) == 1.0

# After the ttl + fade window, nothing is active and the host can stop drawing.
toasts.prune(now = 3.0)
assert not toasts.hasActive(now = 3.0)
assert toasts.visibleToasts(now = 3.0).len == 0
