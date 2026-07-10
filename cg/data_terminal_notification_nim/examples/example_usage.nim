import terminal_notification_lib

let n9 = parseOsc9Notification("Claude compact finished")
doAssert n9.ok
doAssert toastText(n9.note) == "Claude compact finished"

var asmbl = newNotificationAssembler()
discard asmbl.feedOsc99("i=job:d=0;Build")
let n99 = asmbl.feedOsc99("i=job:p=body;ok")
doAssert n99.ok
doAssert toastText(n99.note) == "Build — ok"

let n777 = parseOsc777Notification("notify;Status;Ready")
doAssert n777.ok

echo "terminal-notification example ok"
