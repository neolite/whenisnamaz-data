#!/bin/bash
# Fetches the city list and this month's prayer schedule for every city from
# kogdanamaz.ru and writes them into this repo (raw server wire format).
# The apps read these files through jsDelivr when the origin is unreachable.
# Run monthly (GitHub Action) or by hand. Runtime: ~25 min (polite pacing).
set -uo pipefail
cd "$(dirname "$0")"

# The same server by two roads: www (through the Cloudflare edge when it is
# proxied) and the apex, straight to the origin.
BASES=("https://www.kogdanamaz.ru" "https://kogdanamaz.ru")
TRIES=3

# fetch <path-with-query> <outfile> ; prints "code bytes base" of the first
# answer that looks like a server answer, empty on total failure.
fetch() {
  local query="$1" out="$2" attempt base code bytes first
  for attempt in $(seq 1 $TRIES); do
    for base in "${BASES[@]}"; do
      code=$(curl -s --max-time 30 -A "whenisnamaz-mirror/1 (+github actions)" \
                  -o "$out.raw" -w '%{http_code}' "$base/$query")
      tr -d '\r' < "$out.raw" > "$out"
      bytes=$(wc -c < "$out" | tr -d ' ')
      first=$(head -1 "$out")
      if [ "$code" = "200" ] && [ "$bytes" -gt 0 ] && echo "$first" | grep -qE '^[0-9]+$'; then
        echo "$code $bytes $base"
        return 0
      fi
      LAST_WHY="code=$code bytes=$bytes first=$(echo "$first" | cut -c1-40)"
    done
    sleep $((attempt * 2))
  done
  echo ""
  return 1
}

APPID=$(curl -sf --max-time 30 "${BASES[0]}/yananiqabulitu.php?YANGA_QULLANICI=BISMILLAAHIRRAXMAANIRRAXIIM&source=ios" | tail -1 | tr -d '\r')
if [ -z "${APPID}" ]; then
  APPID=$(curl -sf --max-time 30 "${BASES[1]}/yananiqabulitu.php?YANGA_QULLANICI=BISMILLAAHIRRAXMAANIRRAXIIM&source=ios" | tail -1 | tr -d '\r')
fi
if [ -z "${APPID}" ]; then
  echo "registration failed on every road"
  exit 1
fi
echo "registered: id of ${#APPID} chars"

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

for LANG in 1 2; do
  SUFFIX=$([ "$LANG" = "1" ] && echo ru || echo en)
  if OUT=$(fetch "shaharlarisemlege.php?APPLICATION_ID=$APPID&LANG=$LANG&source=ios" "$TMP/cities"); then
    cp "$TMP/cities" "cities_snapshot_$SUFFIX.txt"
    echo "cities $SUFFIX: $OUT"
  else
    echo "places fetch failed for $SUFFIX ($LAST_WHY)"
  fi
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
REPORTED=0

# Lines 2..2N+1 hold N id/name pairs; ids sit on even absolute lines.
IDS=$(sed -n "2,$((2*COUNT+1))p" cities_snapshot_ru.txt | awk 'NR % 2 == 1' | tr -d '\r')

for ID in $IDS; do
  for LANG in 1 2; do
    SUFFIX=$([ "$LANG" = "1" ] && echo ru || echo en)
    if fetch "waqitcibaru.php?APPLICATION_ID=$APPID&CITY=$ID&MONTH_BEGIN=true&LANG=$LANG&source=ios" "$TMP/body" > /dev/null; then
      cp "$TMP/body" "schedules/$SUFFIX/$ID.txt"
      DONE=$((DONE+1))
    else
      FAILED=$((FAILED+1))
      # The first few failures of each kind carry the reason; the rest are counted.
      if [ "$REPORTED" -lt 10 ]; then
        echo "skip $SUFFIX/$ID ($LAST_WHY)"
        REPORTED=$((REPORTED+1))
      fi
    fi
    sleep 0.1
  done
done

echo "done: $DONE files, failed: $FAILED"
