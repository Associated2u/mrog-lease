#!/usr/bin/env bash
# ~/mrog/input/aim.sh - look before you click.
#
# WHY THIS EXISTS. FLEET-CB2 2026-09-05: a drill clicked (892,1165) at Open
# WebUI's send button, whose centre is (893,1155) with a ~17px radius. It
# caught the bottom edge, did nothing, and the drill carried on believing the
# message had been sent. Chris spotted it. The click landed on empty chrome
# that time; 10px the other way is a different control.
#
# The root cause is `mrog-input moveclick`, which fuses the move and the click
# with no chance to look in between. mrog-input already gates `move` and
# `click` as SEPARATE verbs, so the fix needs no new privilege at all:
#
#     aim.sh at <x> <y>      move there, then show me what is under the pointer
#     aim.sh grid            full screenshot with a labelled coordinate grid
#     aim.sh click [btn]     click WITHOUT moving - only after `at` looked
#
# A miss now costs a no-op I can see, instead of a click I cannot take back.
set -euo pipefail
export DISPLAY="${DISPLAY:-:0}"
OUT="${MROG_AIM_DIR:-/tmp/claude-1000/aim}"
mkdir -p "$OUT"

need() { command -v "$1" >/dev/null || { echo "aim: missing $1" >&2; exit 2; }; }
need ffmpeg; need xdotool

geo()  { xdotool getdisplaygeometry | tr ' ' 'x'; }

case "${1:-}" in
  at)
    x="${2:?x}"; y="${3:?y}"
    # move is scope=click and gated by mrog-input; no click is issued here.
    mrog-input move "$x" "$y" >/dev/null
    # Crosshair box: 240x160 centred on the target, clamped to the screen.
    G=$(geo); W=${G%x*}; H=${G#*x}
    cx=$(( x - 120 )); cy=$(( y - 80 ))
    (( cx < 0 )) && cx=0; (( cy < 0 )) && cy=0
    (( cx + 240 > W )) && cx=$(( W - 240 ))
    (( cy + 160 > H )) && cy=$(( H - 160 ))
    raw="$OUT/aim-raw.png"; out="$OUT/aim-at-${x}x${y}.png"
    ffmpeg -hide_banner -loglevel error -f x11grab -video_size "$G" \
           -i "$DISPLAY" -frames:v 1 -y "$raw"
    # Crop, scale 3x so a 17px control is 51px and unmistakable, then draw a
    # crosshair at the exact click point.
    px=$(( (x - cx) * 3 )); py=$(( (y - cy) * 3 ))
    ffmpeg -hide_banner -loglevel error -i "$raw" -vf \
      "crop=240:160:$cx:$cy,scale=720:480:flags=neighbor,\
drawbox=x=$((px-30)):y=$py:w=60:h=1:color=red@0.9:t=fill,\
drawbox=x=$px:y=$((py-30)):w=1:h=60:color=red@0.9:t=fill,\
drawbox=x=$((px-9)):y=$((py-9)):w=18:h=18:color=red@0.9:t=2" \
      -y "$out"
    echo "$out"
    echo "pointer now at $(xdotool getmouselocation --shell | sed -n 's/^[XY]=//p' | paste -sd,)"
    ;;

  grid)
    G=$(geo); W=${G%x*}; H=${G#*x}
    raw="$OUT/grid-raw.png"; out="$OUT/grid.png"
    ffmpeg -hide_banner -loglevel error -f x11grab -video_size "$G" \
           -i "$DISPLAY" -frames:v 1 -y "$raw"
    # Minor lines every 50px, major every 200px with a printed label.
    f=""
    for ((gx=0; gx<W; gx+=50)); do
      if (( gx % 200 == 0 )); then
        f+="drawbox=x=$gx:y=0:w=1:h=$H:color=red@0.55:t=fill,"
        f+="drawtext=text='$gx':x=$((gx+3)):y=4:fontsize=18:fontcolor=red:box=1:boxcolor=black@0.6,"
      else
        f+="drawbox=x=$gx:y=0:w=1:h=$H:color=cyan@0.20:t=fill,"
      fi
    done
    for ((gy=0; gy<H; gy+=50)); do
      if (( gy % 200 == 0 )); then
        f+="drawbox=x=0:y=$gy:w=$W:h=1:color=red@0.55:t=fill,"
        f+="drawtext=text='$gy':x=4:y=$((gy+3)):fontsize=18:fontcolor=red:box=1:boxcolor=black@0.6,"
      else
        f+="drawbox=x=0:y=$gy:w=$W:h=1:color=cyan@0.20:t=fill,"
      fi
    done
    ffmpeg -hide_banner -loglevel error -i "$raw" -vf "${f%,}" -y "$out"
    echo "$out"
    ;;

  click)
    # Deliberately does NOT move. Use only after `at` has shown the target.
    mrog-input click "${2:-1}"
    ;;

  *)
    sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
    ;;
esac
