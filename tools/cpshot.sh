#!/bin/bash
# cpshot.sh <outfile>  — window-targeted CarPlay canvas still (804x452, crop of PlayPort window at 604,255)
set -e
D="$(cd "$(dirname "$0")/.." && pwd)"
W=$(bash "$D/tools/ppwin.sh" wid)
[ -z "$W" ] && { echo "NO PLAY PORT WINDOW"; exit 1; }
screencapture -x -o -l"$W" /tmp/_cpfull.png
/tmp/crop2 /tmp/_cpfull.png "$1" 604 255 804 452 2 >/dev/null
echo "saved $1"
