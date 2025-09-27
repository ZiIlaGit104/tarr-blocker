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
	BOOK_EXTENSIONS="epub|pdf|mobi|azw3|cbz|cbr|mp3|flac|aac|ogg|m4a|wav"

###############
#END Variables#
###############

exec >> "$LOGFILE" 2>&1
echo "[$(date '+%Y-%m-%d %H:%M:%S')] --- Torrent Filter Script Triggered ---"
TORRENT_FILE="$1"

# Determine the latest torrent ID (assume last added)
TORRENT_ID=$(transmission-remote -n ${TR_USER}:${TR_PASS} -l | tail -n +2 | head -n -1 | awk '{print $1}' | sort -n | tail -1)
if [ -z "$TORRENT_ID" ]; then
    echo "ERROR: Could not determine torrent ID. Exiting."
    exit 1
fi
echo "Detected torrent ID: $TORRENT_ID"

# Wait until the file list is available (handles magnets)
FILE_COUNT=0
echo "Waiting for file list / metadata... files detected: $FILE_COUNT"
while [ "$FILE_COUNT" -eq 0 ]; do
    FILE_COUNT=$(transmission-remote -n ${TR_USER}:${TR_PASS} -t "$TORRENT_ID" -f | tail -n +2 | head -n -1 | wc -l)
    #echo "Waiting for file list / metadata... files detected: $FILE_COUNT"
    sleep 2
done

echo "File list ready with $FILE_COUNT file(s)."

# Get torrent name & hash
TORRENT_NAME=$(transmission-remote -n ${TR_USER}:${TR_PASS} -t "$TORRENT_ID" -i | grep "Name:" | sed 's/Name: *//' | xargs)
TORRENT_HASH=$(transmission-remote -n ${TR_USER}:${TR_PASS} -t "$TORRENT_ID" -i | grep "Hash:" | awk '{print $2}')
TORRENT_HASH_LOWER=$(echo "$TORRENT_HASH" | tr '[:upper:]' '[:lower:]')
echo "Torrent Name: $TORRENT_NAME"
echo "Torrent Hash: $TORRENT_HASH"

# Infer category from download path
COMPLETED_PATH=$(transmission-remote -n ${TR_USER}:${TR_PASS} -t "$TORRENT_ID" -i | grep "Location:" | sed 's/Location: *//')
CATEGORY=$(basename "$COMPLETED_PATH")
echo "Download location: $COMPLETED_PATH"
echo "Raw folder name: $CATEGORY"

# Map folder names to ARR categories
case "$CATEGORY" in
	Movies|$RADARR_CAT) CATEGORY="$RADARR_CAT" ;;
    TV|$SONARR_CAT) CATEGORY="$SONARR_CAT" ;;
    Music|$LIDARR_CAT) CATEGORY="$LIDARR_CAT" ;;
    Books|$READARR_CAT) CATEGORY="$READARR_CAT" ;;
    *) CATEGORY="" ;;
esac
echo "Inferred category: $CATEGORY"

contains() {
    local e match="$1"
    shift
    for e; do [[ "$e" == "$match" ]] && return 0; done
    return 1
}

# ARR blocklist function
arr_blocklist_by_hash () {
  local kind="$1" url key api="api/v3"
  case "$kind" in
    $SONARR_CAT) url="$SONARR_HOST"; key="$SONARR_API"; api="api/v3" ;;
    $RADARR_CAT) url="$RADARR_HOST"; key="$RADARR_API"; api="api/v3" ;;
    $LIDARR_CAT) url="$LIDARR_HOST"; key="$LIDARR_API"; api="api/v1" ;;
    $READARR_CAT) url="$READARR_HOST"; key="$READARR_API"; api="api/v1" ;;
    *) echo " -> No ARR mapping for '$kind'"; return 0 ;;
  esac

  local resp qid
  resp=$(curl -sS -H "X-Api-Key: $key" "$url/$api/queue?page=1&pageSize=1000") || { echo " -> $kind queue fetch failed"; return 1; }

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
    if curl -sS -X DELETE "$url/$api/queue/$qid?blocklist=true&removeFromClient=false" -H "X-Api-Key: $key" >/dev/null; then
      echo " -> Sent to $kind blocklist (queue id $qid)"
    else
      echo " -> Failed to blocklist in $kind (queue delete error)"
    fi
  else
    echo " -> Could not find $kind queue item by hash; skipping blocklist."
  fi
}

# Begin filtering
if contains "$CATEGORY" "${FILTER_CATEGORIES[@]}"; then
    echo "Filtering enabled for category: $CATEGORY"

    FILES=$(transmission-remote -n ${TR_USER}:${TR_PASS} -t "$TORRENT_ID" -f | sed '1d' | grep -vE '^[[:space:]]*#|^$' | grep -vE '\([0-9]+ files?\):')
    VALID_COUNT=0

    echo "Raw file list:"
    echo "$FILES"

    while read -r line; do
        INDEX=$(echo "$line" | awk '{print $1}' | tr -cd '[:digit:]')
		[[ -z "$INDEX" ]] && continue
        
		FILE=$(echo "$line" | sed -E 's/^.*[0-9]+\.[0-9]+ (MB|GB) +//' | tr '[:upper:]' '[:lower:]')

        echo "Checking file index=$INDEX name='$FILE'"
		
        case "$CATEGORY" in
            "$SONARR_CAT"|"$RADARR_CAT")
                if [[ $FILE =~ \.($VIDEO_EXTENSIONS|$SUBTITLE_EXTENSIONS)$ ]]; then
                    echo " -> Valid media/subtitle file: $FILE"
                    VALID_COUNT=$((VALID_COUNT+1))
                else
					transmission-remote -n ${TR_USER}:${TR_PASS} -t "$TORRENT_ID" -f -G "$INDEX" >/dev/null
                    echo " -> Deselected irrelevant file: $FILE"
                fi
                ;;
            "$LIDARR_CAT")
                if [[ $FILE =~ \.($AUDIO_EXTENSIONS)$ ]]; then
                    echo " -> Valid audio file: $FILE"
                    VALID_COUNT=$((VALID_COUNT+1))
                else
					transmission-remote -n ${TR_USER}:${TR_PASS} -t "$TORRENT_ID" -f -G "$INDEX" >/dev/null
                    echo " -> Deselected irrelevant file: $FILE"
                fi
                ;;
            "$READARR_CAT")
                if [[ $FILE =~ \.($BOOK_EXTENSIONS)$ ]]; then
                    echo " -> Valid book file: $FILE"
                    VALID_COUNT=$((VALID_COUNT+1))
                else
					transmission-remote -n ${TR_USER}:${TR_PASS} -t "$TORRENT_ID" -f -G "$INDEX" >/dev/null
                    echo " -> Deselected irrelevant file: $FILE"
                fi
                ;;
        esac
    done <<< "$FILES"

    if [ "$VALID_COUNT" -gt 0 ]; then
        echo "Result: Torrent '$TORRENT_NAME' accepted. Valid files found: $VALID_COUNT"
    else
        echo "Result: Torrent '$TORRENT_NAME' rejected (no valid media files found)"
		transmission-remote -n ${TR_USER}:${TR_PASS} -t "$TORRENT_ID" -r
        arr_blocklist_by_hash "$CATEGORY"
    fi
else
    echo "Category '$CATEGORY' not in filter list. Skipping filtering."
fi

echo "[$(date '+%Y-%m-%d %H:%M:%S')] --- Torrent Filter Script Finished ---"
echo ""
exit 0
