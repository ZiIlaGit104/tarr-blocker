# tarr-blocker
A Transmission torrent-add hook to filter unwanted/malicious torrents and blocklist them in any combo of Sonarr, Radarr, Lidarr, and Readarr.

## ✨ Features
- Runs automatically as a Transmission "on torrent add" hook script.
  - This runs on the host/container running Transmission
- Filters torrents by file extensions (Unselects unwanted files from the torrent for download).
- If no valid/wanted file types are found in the torrent, it is marked invalid.
- Removes invalid torrents from Transmission.
- Blocklists the release at the origin (Sonarr/Radarr/Lidarr/Readarr) so it won’t grab it again.
- Only Filters based on inferred category, so non-arr torrents are not filtered.

## 🛠 Requirements
- **Transmission** with RPC enabled (Standard/default behavior)
- **One or more of the Arr apps**:
  - [Sonarr](https://sonarr.tv/)
  - [Radarr](https://radarr.video/)
  - [Lidarr](https://lidarr.audio/)
  - [Readarr](https://readarr.com/)
- **'Category'** must be set in the download client configuration of each Arr app, case sensitive (Adjust the 'xxxARR_CAT' variables as required)
  - Example: Sonarr DL Client config Category = **'Sonarr'**, so set 'SONARR_CAT' to 'Sonarr'
  - 'FILTER_CATEGORIES' essentially sets which arr apps to watch for torrents from. If you don't want one filtered, remove it from the variable.

## ⚙️ Setup

  1. Save the 'tarr-blocker.sh' script to /config/tarr-blocker.sh
  
  2. Edit the script and set your credentials, Host info, API keys, desired extensions, and filtering categories:
        ```sh
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
  
  4. Make the script executable:
  
          chmod +x /config/tarr-blocker.sh
  
  5. Configure Transmission to run the script on torrent add:
   - STOP Transmission and then add this to your Transmission config (settings.json)
     - (Settings will be overwritten if Transmission isn't stopped when the settings are updated):
  
            "script-torrent-added-enabled": true,
            "script-torrent-added-filename": "/config/tarr-blocker.sh"
  
  6. Start Transmission.

## 📋 Example Filtering

By default, the script checks file extensions of the files in the torrent and deselects unwanted ones (e.g., images, .txt, .nfo, .exe, .iso, .rar), if it's in a filtered Category.
When a torrent has no valid media files:
- It is removed from Transmission.
- The release is blocklisted in Sonarr/Radarr/Lidarr/Readarr.

Filtering log example:
                
    [2025-10-12 00:43:06] --- Torrent Filter Script Triggered ---
    Torrent ID 15: > Locked for processing.
    Torrent ID 15: > Waiting for file list / metadata to become available...
    Torrent ID 15: > File list ready with 1 file(s).
    Torrent ID 15: > Torrent Name: Some.Show.S27E06.1080p.x265-ELiTE.scr
    Torrent ID 15: > Torrent Hash: 248450dc486b67b0f51e1027b667034cb60ca7b8
    Torrent ID 15: > Download location:   /downloads/complete/Sonarr
    Torrent ID 15: > Raw folder name: Sonarr
    Torrent ID 15: > Inferred category: Sonarr
    Torrent ID 15: > Filtering enabled for category: Sonarr
    Torrent ID 15: > Raw file list:
      0:  21% Normal   Yes 1.27 GB    Some.Show.S27E06.1080p.x265-ELiTE.scr
    Torrent ID 15: > Checking file index=0 name='some.show.s27e06.1080p.x265-elite.scr'
    Torrent ID 15: >  -> Deselected irrelevant file: some.show.s27e06.1080p.x265-elite.scr
    Torrent ID 15: > Result: Torrent 'Some.Show.S27E06.1080p.x265-ELiTE.scr' rejected (no valid media files found)
    localhost:9091/transmission/rpc/ responded: success
    Torrent ID 15: >  -> Sent to Sonarr blocklist (queue id 665030521)
    [2025-10-12 00:43:10] --- Torrent Filter Script Finished (Torrent ID: 15) ---

    [2025-10-12 00:56:58] --- Torrent Filter Script Triggered ---
    Torrent ID 18: > Locked for processing.
    Torrent ID 18: > Waiting for file list / metadata to become available...
    Torrent ID 18: > File list ready with 1 file(s).
    Torrent ID 18: > Torrent Name: Another.Show.S03E04.1080p.HEVC.x265-MeGusta[EZTVx.to].mkv
    Torrent ID 18: > Torrent Hash: 6447f9b2e9b9e56a2735e073e40e0758a218f582
    Torrent ID 18: > Download location:   /downloads/complete/Sonarr
    Torrent ID 18: > Raw folder name: Sonarr
    Torrent ID 18: > Inferred category: Sonarr
    Torrent ID 18: > Filtering enabled for category: Sonarr
    Torrent ID 18: > Raw file list:
      0:   0% Normal   Yes 368.9 MB   Another.Show.S03E04.1080p.HEVC.x265-MeGusta[EZTVx.to].mkv
    Torrent ID 18: > Checking file index=0 name='another.show.s03e04.1080p.hevc.x265-megusta[eztvx.to].mkv'
    Torrent ID 18: >  -> Valid media/subtitle file: another.show.s03e04.1080p.hevc.x265-megusta[eztvx.to].mkv
    Torrent ID 18: > Result: Torrent 'Another.Show.S03E04.1080p.HEVC.x265-MeGusta[EZTVx.to].mkv' accepted. Valid files found: 1
    [2025-10-12 00:57:02] --- Torrent Filter Script Finished (Torrent ID: 18) ---

## 🚀 Roadmap
- TBD

## 📜 License
- MIT
  
## 💰 Donate
- I'm good! Please consider supporting the Arr server team and Transmission projects!
