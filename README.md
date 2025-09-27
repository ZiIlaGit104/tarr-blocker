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
- **'Category'** must be set in the download client configuration of each Arr app, case sensitive (Adjust 'FILTER_CATEGORIES' variable as required)
  - Example: Sonarr DL Client config Category = **'Sonarr'**
  - 'FILTER_CATEGORIES' essentially sets which arr apps to watch for torrents from, and what the downloads completed folder should be. If you don't want one filtered, remove it from the variable or change the category in the Arr app so it no longer lines up.

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
                
    [2025-09-05 15:42:36] --- Torrent Filter Script Triggered ---
    Detected torrent ID: 2
    Waiting for file list / metadata... files detected: 0
    File list ready with 1 file(s).
    Torrent Name: Some.Show.S27E04.1080p.x265-ELiTE
    Torrent Hash: ad4d9426545b8a84521676517c37a17f2a7ab07b
    Download location:   /downloads/complete/Sonarr
    Raw folder name: Sonarr
    Inferred category: Sonarr
    Filtering enabled for category: Sonarr
    Raw file list:
      0:   0% Normal   Yes 872.3 MB   Some.Show.S27E04.1080p.x265-ELiTE/Some.Show.S27E04.1080p.x265-ELiTE.iso
    Checking file index=0 name='some.show.s27e04.1080p.x265-elite/some.show.s27e04.1080p.x265-elite.iso'
     -> Deselected irrelevant file: some.show.s27e04.1080p.x265-elite/some.show.s27e04.1080p.x265-elite.iso
    Result: Torrent 'Some.Show.S27E04.1080p.x265-ELiTE' rejected (no valid media files found)
    localhost:9091/transmission/rpc/ responded: success
     -> Sent to Sonarr blocklist (queue id 787476292)
    [2025-09-05 15:42:41] --- Torrent Filter Script Finished ---
    
    [2025-09-05 15:59:57] --- Torrent Filter Script Triggered ---
    Detected torrent ID: 3
    Waiting for file list / metadata... files detected: 0
    File list ready with 1 file(s).
    Torrent Name: some.show.s27e04.1080p.web.h264-successfulcrab[EZTVx.to].mkv
    Torrent Hash: 2e31b658b225ea282e5c663b23cfbdc96102afdb
    Download location:   /downloads/complete/Sonarr
    Raw folder name: Sonarr
    Inferred category: Sonarr
    Filtering enabled for category: Sonarr
    Raw file list:
      0:   0% Normal   Yes 790.5 MB   some.show.s27e04.1080p.web.h264-successfulcrab[EZTVx.to].mkv
    Checking file index=0 name='some.show.s27e04.1080p.web.h264-successfulcrab[eztvx.to].mkv'
     -> Valid media/subtitle file: some.show.s27e04.1080p.web.h264-successfulcrab[eztvx.to].mkv
    Result: Torrent 'some.show.s27e04.1080p.web.h264-successfulcrab[EZTVx.to].mkv' accepted. Valid files found: 1
    [2025-09-05 15:59:59] --- Torrent Filter Script Finished ---


## 🚀 Roadmap
- TBD

## 📜 License
- MIT
  
## 💰 Donate
- I'm good! Please consider supporting the Arr server team and Transmission projects!
