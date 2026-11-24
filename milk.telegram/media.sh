#!/bin/sh
# media.sh pause|resume : pause whatever is playing (MPRIS players) while dictating, resume exactly those after.
state="${XDG_RUNTIME_DIR:-/tmp}/milk-telegram-paused"
P=/org/mpris/MediaPlayer2; I=org.mpris.MediaPlayer2.Player
case "$1" in
  pause)
    : > "$state"
    for n in $(busctl --user list --no-legend 2>/dev/null | awk '/^org\.mpris\.MediaPlayer2\./ {print $1}'); do
      case "$(busctl --user get-property "$n" $P $I PlaybackStatus 2>/dev/null)" in
        *Playing*) busctl --user call "$n" $P $I Pause >/dev/null 2>&1 && echo "$n" >> "$state" ;;
      esac
    done
    [ -s "$state" ] && sleep 0.25   # let the room go quiet before recording
    ;;
  resume)
    [ -f "$state" ] || exit 0
    while read -r n; do busctl --user call "$n" $P $I Play >/dev/null 2>&1; done < "$state"
    rm -f "$state"
    ;;
esac
exit 0
