#!/bin/bash
# Transmission hook: filter torrents (works for torrents and magnets)
# https://github.com/ZiIlaGit104/tarr-blocker/tree/main
# Args: $1 = path to torrent file (may be empty for magnets)

#################
#START Variables#
#################

# Set the logfile name/location
LOGFILE="/config/filter.log"

# Transmission RPC credentials (Blank or set as required)
TR_USER=""
TR_PASS=""

# ARR Hosts/API credentials (Remove any you do not want/use from the 'FILTER_CATEGORIES' variable)
SONARR_HOST="http://<YourIP_or_Hostname>:8989"
SONARR_API="xxxx"
RADARR_HOST="http://<YourIP_or_Hostname>:7878"
RADARR_API="xxxx"
LIDARR_HOST="http://<YourIP_or_Hostname>:8686"
LIDARR_API="xxxx"
READARR_HOST="http://<YourIP_or_Hostname>:8787"
READARR_API="xxxx"

# Categories & Whitelist extensions (This is where you set the 'Category' per Arr app as it's set in the apps download client config)
	SONARR_CAT=Sonarr # Case Sensitive
	RADARR_CAT=Radarr # Case Sensitive
	LIDARR_CAT=Lidarr # Case Sensitive
	READARR_CAT=Readarr # Case Sensitive
	
	## Remove any Arr apps you don't want to filter. Remove, but otherwise do not edit the values.
	## Example for Sonarr and Radarr only: FILTER_CATEGORIES=("$SONARR_CAT" "$RADARR_CAT")
	FILTER_CATEGORIES=("$SONARR_CAT" "$RADARR_CAT" "$LIDARR_CAT" "$READARR_CAT")
	
	## Add or remove file types from these whitelists as you desire
	VIDEO_EXTENSIONS="mkv|mp4|avi|mov"
	SUBTITLE_EXTENSIONS="srt|ass|sub"
	AUDIO_EXTENSIONS="mp3|flac|aac|ogg|m4a|wav"
	BOOK_EXTENSIONS="epub|pdf|mobi|azw3|cbz|cbr|mp3|flac|aac|ogg|m4a|wav|m4b"

###############
#END Variables#
###############


####################
# Helper Functions #
####################
contains() {
    local e match="$1"
    shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}

arr_blocklist_by_hash() {
  local kind="$1" url key api="api/v3"
  case "$kind" in
    $SONARR_CAT) url="$SONARR_HOST"; key="$SONARR_API"; api="api/v3" ;;
    $RADARR_CAT) url="$RADARR_HOST"; key="$RADARR_API"; api="api/v3" ;;
    $LIDARR_CAT) url="$LIDARR_HOST"; key="$LIDARR_API"; api="api/v1" ;;
    $READARR_CAT) url="$READARR_HOST"; key="$READARR_API"; api="api/v1" ;;
    *) log "$TORRENT_ID" " -> No ARR mapping for '$kind'"; return 0 ;;
  esac

  local resp qid
  resp=$(curl -sS -H "X-Api-Key: $key" "$url/$api/queue?page=1&pageSize=1000") || { log "$TORRENT_ID" " -> $kind queue fetch failed"; return 1; }

  if command -v jq >/dev/null 2>&1; then
    qid=$(echo "$resp" | jq -r --arg h "$TORRENT_HASH_LOWER" '
      ( .records? // . )
      | map(select((.protocol|tostring|ascii_downcase)=="torrent"))
      | map(select((.downloadId|ascii_downcase)==$h))
      | .[0].id // empty
    ')
  else
    qid=$(echo "$resp" | tr -d '\n' | sed 's/},{/}\n{/g' \
      | grep -i "\"downloadId\":\"$TORRENT_HASH\"" \
      | head -n1 | grep -o '"id":[0-9]*' | head -n1 | grep -o '[0-9]*')
  fi

  if [ -n "$qid" ]; then
    curl -sS -X DELETE "$url/$api/queue/$qid?blocklist=true&removeFromClient=false" -H "X-Api-Key: $key" >/dev/null \
      && log "$TORRENT_ID" " -> Sent to $kind blocklist (queue id $qid)" \
      || log "$TORRENT_ID" " -> Failed to blocklist in $kind (queue delete error)"
  else
    log "$TORRENT_ID" " -> Could not find $kind queue item by hash; skipping blocklist."
  fi
}

# Torrent claim directory (for uniqueness control)
LOCK_DIR="/tmp/torrent_claims"
mkdir -p "$LOCK_DIR"

exec >> "$LOGFILE" 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] --- Torrent Filter Script Triggered ---"

# Helper logger
log() { echo "Torrent ID ${1}: > ${2}"; }

# Transmission helper
tr_cmd() {
  if [ -n "$TR_USER" ] || [ -n "$TR_PASS" ]; then
    transmission-remote -n ${TR_USER}:${TR_PASS} "$@"
  else
    transmission-remote "$@"
  fi
}

###########################################
# Torrent ID Negotiation and Lock Section #
###########################################
MAX_ATTEMPTS=30
MIN_BACKOFF_MS=200
MAX_BACKOFF_MS=900

sleep_time_ms=$(( (RANDOM % (MAX_BACKOFF_MS - MIN_BACKOFF_MS + 1)) + MIN_BACKOFF_MS ))
sleep "$(awk "BEGIN{print $sleep_time_ms/1000}")"

CLAIMED_TORRENT_ID=""
attempt=1

while [ $attempt -le $MAX_ATTEMPTS ] && [ -z "$CLAIMED_TORRENT_ID" ]; do
    RAW_LIST=$(tr_cmd -l 2>/dev/null || true)
    if [ -z "$RAW_LIST" ]; then
        log "N/A" "No response from transmission-remote -l (attempt $attempt)."
        sleep 0.3
        attempt=$((attempt+1))
        continue
    fi

    mapfile -t TOR_IDS < <(echo "$RAW_LIST" | sed '1d;$d' | awk '{print $1}' | grep -E '^[0-9]+$' | sort -n)
    if [ ${#TOR_IDS[@]} -eq 0 ]; then
        log "N/A" "No torrent IDs parsed (attempt $attempt)."
        sleep 0.3
        attempt=$((attempt+1))
        continue
    fi

    for (( idx=${#TOR_IDS[@]}-1; idx>=0; idx-- )); do
        id="${TOR_IDS[idx]}"
        CLAIM_DIR="${LOCK_DIR}/torrent_${id}"

        if mkdir "$CLAIM_DIR" 2>/dev/null; then
            echo "$$" > "${CLAIM_DIR}/pid"
            CLAIMED_TORRENT_ID="$id"
            break
        fi
    done

    [ -z "$CLAIMED_TORRENT_ID" ] && sleep 0.4
    attempt=$((attempt+1))
done

if [ -z "$CLAIMED_TORRENT_ID" ]; then
    echo "No unclaimed torrent ID could be negotiated after $MAX_ATTEMPTS attempts. Exiting."
    exit 0
fi

TORRENT_ID="$CLAIMED_TORRENT_ID"
CLAIM_DIR="${LOCK_DIR}/torrent_${TORRENT_ID}"
trap 'rm -rf "$CLAIM_DIR"' EXIT
log "$TORRENT_ID" "Locked for processing."

#######################################
# Wait for Metadata / File List Ready #
#######################################
FILE_COUNT=0

log "$TORRENT_ID" "Waiting for file list / metadata to become available..."

while [ "$FILE_COUNT" -eq 0 ]; do
    FILE_COUNT=$(tr_cmd -t "$TORRENT_ID" -f | tail -n +2 | head -n -1 | wc -l)
    sleep 2
done

log "$TORRENT_ID" "File list ready with $FILE_COUNT file(s)."

###########################
# Torrent Info Extraction #
###########################
TORRENT_NAME=$(tr_cmd -t "$TORRENT_ID" -i | grep "Name:" | sed 's/Name: *//' | xargs)
TORRENT_HASH=$(tr_cmd -t "$TORRENT_ID" -i | grep "Hash:" | awk '{print $2}')
TORRENT_HASH_LOWER=$(echo "$TORRENT_HASH" | tr '[:upper:]' '[:lower:]')
COMPLETED_PATH=$(tr_cmd -t "$TORRENT_ID" -i | grep "Location:" | sed 's/Location: *//')
CATEGORY=$(basename "$COMPLETED_PATH")

log "$TORRENT_ID" "Torrent Name: $TORRENT_NAME"
log "$TORRENT_ID" "Torrent Hash: $TORRENT_HASH"
log "$TORRENT_ID" "Download location: $COMPLETED_PATH"
log "$TORRENT_ID" "Raw folder name: $CATEGORY"

case "$CATEGORY" in
    Movies|$RADARR_CAT) CATEGORY="$RADARR_CAT" ;;
    TV|$SONARR_CAT) CATEGORY="$SONARR_CAT" ;;
    Music|$LIDARR_CAT) CATEGORY="$LIDARR_CAT" ;;
    Books|$READARR_CAT) CATEGORY="$READARR_CAT" ;;
    *) CATEGORY="" ;;
esac
log "$TORRENT_ID" "Inferred category: $CATEGORY"

###################
# Begin filtering #
###################
if contains "$CATEGORY" "${FILTER_CATEGORIES[@]}"; then
    log "$TORRENT_ID" "Filtering enabled for category: $CATEGORY"

    FILES=$(tr_cmd -t "$TORRENT_ID" -f | sed '1d' | grep -vE '^[[:space:]]*#|^$' | grep -vE '\([0-9]+ files?\):')
    VALID_COUNT=0

    log "$TORRENT_ID" "Raw file list:"
    echo "$FILES"

    while read -r line; do
        INDEX=$(echo "$line" | awk '{print $1}' | tr -cd '[:digit:]')
        [[ -z "$INDEX" ]] && continue
        FILE=$(echo "$line" | sed -E 's/^.*[0-9]+\.[0-9]+ (MB|GB) +//' | tr '[:upper:]' '[:lower:]')
        log "$TORRENT_ID" "Checking file index=$INDEX name='$FILE'"

        case "$CATEGORY" in
            "$SONARR_CAT"|"$RADARR_CAT")
                if [[ $FILE =~ \.($VIDEO_EXTENSIONS|$SUBTITLE_EXTENSIONS)$ ]]; then
                    log "$TORRENT_ID" " -> Valid media/subtitle file: $FILE"
                    VALID_COUNT=$((VALID_COUNT+1))
                else
                    tr_cmd -t "$TORRENT_ID" -G "$INDEX" >/dev/null
                    log "$TORRENT_ID" " -> Deselected irrelevant file: $FILE"
                fi
                ;;
            "$LIDARR_CAT")
                if [[ $FILE =~ \.($AUDIO_EXTENSIONS)$ ]]; then
                    log "$TORRENT_ID" " -> Valid audio file: $FILE"
                    VALID_COUNT=$((VALID_COUNT+1))
                else
                    tr_cmd -t "$TORRENT_ID" -G "$INDEX" >/dev/null
                    log "$TORRENT_ID" " -> Deselected irrelevant file: $FILE"
                fi
                ;;
            "$READARR_CAT")
                if [[ $FILE =~ \.($BOOK_EXTENSIONS)$ ]]; then
                    log "$TORRENT_ID" " -> Valid book file: $FILE"
                    VALID_COUNT=$((VALID_COUNT+1))
                else
                    tr_cmd -t "$TORRENT_ID" -G "$INDEX" >/dev/null
                    log "$TORRENT_ID" " -> Deselected irrelevant file: $FILE"
                fi
                ;;
        esac
    done <<< "$FILES"

    if [ "$VALID_COUNT" -gt 0 ]; then
        log "$TORRENT_ID" "Result: Torrent '$TORRENT_NAME' accepted. Valid files found: $VALID_COUNT"
    else
        log "$TORRENT_ID" "Result: Torrent '$TORRENT_NAME' rejected (no valid media files found)"
        tr_cmd -t "$TORRENT_ID" -r
        arr_blocklist_by_hash "$CATEGORY"
    fi
else
    log "$TORRENT_ID" "Category '$CATEGORY' not in filter list. Skipping filtering."
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] --- Torrent Filter Script Finished (Torrent ID: $TORRENT_ID) ---"
echo ""
exit 0
