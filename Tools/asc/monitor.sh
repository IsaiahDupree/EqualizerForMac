#!/bin/zsh -l
# monitor.sh — poll App Store Connect for Sonance EQ's review state and post a macOS notification
# whenever it CHANGES (version state, attached build, or review-submission state). Designed to run
# unattended from a launchd agent (see com.isaiahdupree.sonance-asc-watch.plist). Logs every check.
#
#   Tools/asc/monitor.sh            # one check; notify + log on change
#
# State is fingerprinted to ~/.sonance-asc-state; the log is ~/.sonance-asc-watch.log.
set -uo pipefail
REPO="$HOME/Documents/Software/EqualizerForMac"
cd "$REPO" || exit 1
source Tools/asc/env.sh >/dev/null 2>&1

STATE_FILE="$HOME/.sonance-asc-state"
LOG="$HOME/.sonance-asc-watch.log"
TS="$(date '+%Y-%m-%d %H:%M:%S')"

# Compact fingerprint: versionState | attachedBuild | newest review-submission state.
FP="$(python3 - <<'PY' 2>/dev/null
import sys,time; sys.path.insert(0,"Tools/asc")
import api as A
def retry(fn,n=6,d=2):
    for i in range(n):
        try: return fn()
        except Exception:
            if i==n-1: raise
            time.sleep(d)
try:
    a=retry(A.get_app); aid=a["id"]
    v=retry(lambda: A.api("GET",f"/v1/apps/{aid}/appStoreVersions?limit=1")["data"][0])
    vs=v["attributes"]["appStoreState"]
    att=retry(lambda: A.api("GET",f"/v1/appStoreVersions/{v['id']}/relationships/build").get("data"))
    bv="none"
    if att: bv=retry(lambda: A.api("GET",f"/v1/builds/{att['id']}")["data"]["attributes"]["version"])
    subs=retry(lambda: A.api("GET",f"/v1/reviewSubmissions?filter[app]={aid}&limit=5")["data"])
    ss=subs[0]["attributes"]["state"] if subs else "none"
    print(f"{vs}|build{bv}|{ss}")
except Exception as e:
    print("ERROR")
PY
)"

if [ -z "$FP" ] || [ "$FP" = "ERROR" ]; then
  echo "$TS  check failed (network/auth) — will retry next run" >> "$LOG"
  exit 0
fi

PREV="$(cat "$STATE_FILE" 2>/dev/null || echo '')"
echo "$TS  $FP" >> "$LOG"

if [ "$FP" != "$PREV" ]; then
  echo "$FP" > "$STATE_FILE"
  if [ -n "$PREV" ]; then
    MSG="Sonance EQ review: $PREV → $FP"
    osascript -e "display notification \"$FP\" with title \"Sonance EQ — App Store\" subtitle \"changed from ${PREV}\" sound name \"Glass\"" >/dev/null 2>&1
    echo "$TS  ⟶ CHANGE: $MSG" >> "$LOG"
  else
    echo "$TS  (baseline recorded: $FP)" >> "$LOG"
  fi
fi
