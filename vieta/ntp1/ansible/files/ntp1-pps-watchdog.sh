#!/bin/sh
# chrony accepts a pulse only while the clock is within width/2 = 25 us of it, so once chrony has
# lost PPS for long (no pulses, a restart without the bootstrap) it can never get back on its own.
set -eu
state=/run/ntp1-pps-watchdog
if chronyc -n -c tracking 2>/dev/null | awk -F, '$2 == "PPS" && $14 == "Normal" { ok = 1 } END { exit !ok }'; then
  rm -f "$state"
  exit 0
fi
if [ ! -f "$state" ]; then
  date +%s > "$state"
  exit 0
fi
since=$(cat "$state")
if [ $(( $(date +%s) - since )) -lt 300 ]; then
  exit 0
fi
logger -t ntp1-pps-watchdog "chrony off PPS for 5 minutes, re-running the clock bootstrap"
systemctl stop gpsdo chrony
systemctl restart ntp1-clock-bootstrap
systemctl start chrony gpsdo
rm -f "$state"
