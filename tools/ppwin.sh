#!/bin/bash
# ppwin.sh focus|rect|wid — PlayPort Chrome window helpers
case "$1" in
  focus)
    osascript -e 'tell application "System Events"
  tell process "Google Chrome"
    repeat with w in windows
      try
        if value of attribute "AXMinimized" of w is true then set value of attribute "AXMinimized" of w to false
      end try
    end repeat
  end tell
end tell' >/dev/null 2>&1
    osascript -e 'tell application "Google Chrome"
  repeat with w in windows
    set titles to title of every tab of w
    repeat with i from 1 to (count of titles)
      if (item i of titles) contains "PlayPort" then
        set active tab index of w to i
        set index of w to 1
        exit repeat
      end if
    end repeat
  end repeat
end tell' >/dev/null
    osascript -e 'tell application "Google Chrome" to activate' >/dev/null
    ;;
  rect)
    printf '%s' 'import Cocoa
import CoreGraphics
guard let wl = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { exit(1) }
for w in wl {
  let owner = w[kCGWindowOwnerName as String] as? String ?? ""
  let name = w[kCGWindowName as String] as? String ?? ""
  if owner == "Google Chrome" && name.contains("PlayPort") {
    let b = w[kCGWindowBounds as String] as? [String: Any] ?? [:]
    print("\(b["X"] as? Int ?? -1) \(b["Y"] as? Int ?? -1) \(b["Width"] as? Int ?? -1) \(b["Height"] as? Int ?? -1)")
    exit(0)
  }
}' | swift -
    ;;
  wid)
    printf '%s' 'import Cocoa
import CoreGraphics
guard let wl = CGWindowListCopyWindowInfo(.optionAll, kCGNullWindowID) as? [[String: Any]] else { exit(1) }
for w in wl {
  let owner = w[kCGWindowOwnerName as String] as? String ?? ""
  let name = w[kCGWindowName as String] as? String ?? ""
  if owner == "Google Chrome" && name.contains("PlayPort") {
    print(w[kCGWindowNumber as String] as? Int ?? -1); exit(0)
  }
}' | swift -
    ;;
esac
