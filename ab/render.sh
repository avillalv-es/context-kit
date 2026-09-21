#!/bin/sh
# Screenshot each chart. The window is 40px taller than the SVG because a
# viewport sized exactly to the art clips the last row of labels.
cd "$(dirname "$0")/report" || exit 1
for f in *.html; do
  c="${f%.html}"
  [ "$c" = "summary" ] && continue
  W=$(grep -o 'width="[0-9]*"' "$c.svg" | head -1 | grep -o '[0-9]*')
  H=$(grep -o 'height="[0-9]*"' "$c.svg" | head -1 | grep -o '[0-9]*')
  /opt/pw-browsers/chromium-1194/chrome-linux/chrome --headless --no-sandbox --disable-gpu \
    --hide-scrollbars --window-size="$W,$((H+40))" --screenshot="$c.png" \
    --virtual-time-budget=3000 "file://$PWD/$c.html" 2>/dev/null
  printf '  %s.png %sx%s\n' "$c" "$W" "$((H+40))"
done
