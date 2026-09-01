#!/bin/bash
# Fetches the city list and this month's prayer schedule for every city from
# kogdanamaz.ru and writes them into this repo (raw server wire format).
# The iOS app reads these files through jsDelivr when the origin is unreachable.
# Run monthly (GitHub Action) or by hand. Runtime: ~20 min (polite pacing).
set -uo pipefail
cd "$(dirname "$0")"

BASE="https://www.kogdanamaz.ru"

APPID=$(curl -sf --max-time 20 "$BASE/yananiqabulitu.php?YANGA_QULLANICI=BISMILLAAHIRRAXMAANIRRAXIIM&source=ios" | tail -1 | tr -d '\r')
if [ -z "${APPID}" ]; then
  echo "registration failed"
  exit 1
fi
echo "appID: $APPID"

for LANG in 1 2; do
  SUFFIX=$([ "$LANG" = "1" ] && echo ru || echo en)
  curl -sf --max-time 30 "$BASE/shaharlarisemlege.php?APPLICATION_ID=$APPID&LANG=$LANG&source=ios" \
    -o "cities_snapshot_$SUFFIX.txt" || echo "places fetch failed for $SUFFIX"
done

COUNT=$(head -1 cities_snapshot_ru.txt | tr -d '\r')
if ! echo "$COUNT" | grep -qE '^[0-9]+$'; then
  echo "city count line is garbage: $COUNT"
  exit 1
fi
echo "cities: $COUNT"

mkdir -p schedules/ru schedules/en
FAILED=0
DONE=0

# Lines 2..2N+1 hold N id/name pairs; ids sit on even absolute lines.
IDS=$(sed -n "2,$((2*COUNT+1))p" cities_snapshot_ru.txt | awk 'NR % 2 == 1' | tr -d '\r')

for ID in $IDS; do
  for LANG in 1 2; do
    SUFFIX=$([ "$LANG" = "1" ] && echo ru || echo en)
    BODY=$(curl -sf --max-time 20 "$BASE/waqitcibaru.php?APPLICATION_ID=$APPID&CITY=$ID&MONTH_BEGIN=true&LANG=$LANG&source=ios" | tr -d '\r')
    # Sanity: the first line must be a bare number (the ads count)
    if [ -n "$BODY" ] && echo "$BODY" | head -1 | grep -qE '^[0-9]+$'; then
      echo "$BODY" > "schedules/$SUFFIX/$ID.txt"
      DONE=$((DONE+1))
    else
      FAILED=$((FAILED+1))
      echo "skip $SUFFIX/$ID (bad answer)"
    fi
    sleep 0.1
  done
done

echo "done: $DONE files, failed: $FAILED"
