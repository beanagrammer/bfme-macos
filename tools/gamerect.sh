#!/bin/zsh
# Print the game window's macOS bounds as "x,y,w,h" for screencapture -R.
"${0:A:h}/winlist" 2>/dev/null \
  | grep -i "Battle for Middle-earth" | grep -vi arena | head -1 \
  | python3 -c '
import sys, re
line = sys.stdin.read()
if not line.strip():
    sys.exit(1)
d = {k: int(v) for k, v in re.findall(r"\"(X|Y|Width|Height)\": (-?\d+)", line)}
if len(d) < 4:
    sys.exit(1)
print("%d,%d,%d,%d" % (d["X"], d["Y"], d["Width"], d["Height"]))
'
