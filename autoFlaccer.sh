#!/usr/bin/env bash

userAgent="AutoFlacer/0.1"

checkConfig() {
    # Check if config file exists
    if [[ ! -f "config.sh" ]]; then
		_err "Config file not found. Please create a default one using the -c option.\nDon't forget to add your Discogs API info to the config file."
    fi
    # Source the config file
    source "./config.sh"
    # Check if values are set
    [[ -z "${discogsKey}" ]] && _err "discogsKey not set in config. Please fix."
    [[ -z "${discogsSecret}" ]] && _err "discogsSecret not set in config. Please fix."
    [[ -z "${startFolder}" ]] && _err "startFolder not set in config. Please fix."
	
	# Check if site config file exists
	if [[ ! -f "config.${curSite}.sh" ]]; then
		_err "Site config file for '${curSite}' not found. Please create a default one using the -c -s '${curSite}' options. Don't forget to add your Discogs API info to the config file."
	fi
}

createConfig() {
	if [[ ! -f "config.sh" ]]; then
		cp "config.default" "config.sh" && _info "Edit the config.sh file and retry." || _err "There was a problem with creating the default config."
	fi
	if [[ ! -f "config.${curSite}.sh" ]] && [[ ! -z "${curSite}" ]]; then
		cp "config.${curSite}" "config.${curSite}.sh" && _info "Edit the config.${curSite}.sh file and retry." || _err "There was a problem with creating the default config for '${curSite}'"
	fi
	# Exit because user has to edit values
    exit 0
}

checkDeps() {
    # Check if mktorrent suppors the source string
    mktorrentTest=$(mktorrent -h | grep 'source string')
    [[ "${mktorrentTest}" == *"source string"* ]] || _err "You need to install mktorrent or update it to at least v1.0"
    # Check if jq is installed
    jqTest=$(type jq)
    [[ "${jqTest}" == *"jq is"* ]] || _err "You need to install jq"
	# Check if flac is installed
	flacTest=$(type flac)
	[[ "${flacTest}" == *"flac is"* ]] || _err "You need to install flac"
	# Check if metaflac is installed
	metaTest=$(type metaflac)
	[[ "${metaTest}" == *"metaflac is"* ]] || _err "You need to install metaflac"
	# Check if lame is installed
	lameTest=$(type lameflac)
	[[ "${lameTest}" == *"lameTest is"* ]] || _err "You need to install lameTest"
}

supplyDiscogsId() {
    while true; do
        read -p "Manually enter Discogs ID: " reply
        if [[ "${reply}" != *[!0-9]* ]]; then
            _info "ID entered: ${reply}"; discogsId="${reply}"; break;
        else
            _info "Please enter ID.";
        fi
    done
}

fetchDiscogsList() {
    unset discogsId
    unset idArr
    unset curOptions
    _info "Searching Discogs for '${lookupQuery}'"
    _echo ""
    response=$(curl -s -G "https://api.discogs.com/database/search" --user-agent "${userAgent}" \
        --data-urlencode "q=${lookupQuery}" \
        --data-urlencode "key=${discogsKey}" \
        --data-urlencode "secret=${discogsSecret}" \
        --data-urlencode "per_page=10" \
        --data-urlencode "page=1")

    _info "Please select the according entry:"
    for i in {0..9}; do
        curTitle=$(jq --raw-output ".results[${i}] .title" <<< $response)
        curYear=$(jq --raw-output ".results[${i}] .year" <<< $response)
        curLabel=$(jq --raw-output ".results[${i}] .label[0]" <<< $response)
        curSource=$(jq --raw-output ".results[${i}] .format[0]" <<< $response)
        curId=$(jq --raw-output ".results[${i}] .id" <<< $response)
        curType=$(jq --raw-output ".results[${i}] .type" <<< $response)
        idArr[$i]="${curId}"
        # Filter out entries with no ID and Master type
        if [[ "${curTitle}" != "null" && "$curType" != "master" ]]; then
            curOptions="${curOptions}${i}"
            idArr[$i]="${curId}"
            _echo "$type (${i}) ${curTitle}  -  ${curYear}  -  ${curLabel}  -  ${curSource}  -  https://www.discogs.com/release/${curId}"
        fi
    done

    while true; do
        read -p "Enter valid option or I/i (for manual ID) or N/n (for new lookup) or S/s (for skipping this album): " reply
        case ${reply} in
            [${curOptions}] ) _info "Option ${reply} selected"; discogsId="${idArr[${reply}]}"; break;;
            [Ii] ) _info "Please supply ID"; supplyDiscogsId; break;;
            [Nn] ) _info "Please enter new lookup query"; break;;
			[Ss] ) _info "Skipped this album."; skipAlbum="1"; break;;
            * ) _info "Please answer with option or I/i or N/n or S/s ";;
        esac
    done
}

fetchDiscogsRelease() {
    response=$(curl -s -G "https://api.discogs.com/releases/${discogsId}" --user-agent "${userAgent}")
	label=$(jq --raw-output ".labels[0] .name" <<< $response)
	catno=$(jq --raw-output ".labels[0] .catno" <<< $response)
	year=$(jq --raw-output ".year" <<< $response)
	genres=$(jq -r ".styles[]" <<< $response)
	title=$(jq --raw-output ".title" <<< $response)
	source=$(jq --raw-output ".formats[0] .name" <<< $response)
    artists=$(jq -r ".artists[]" <<< $response)
	tracklist=$(jq -r ".tracklist[] | {position: .position, title: .title, duration: .duration, artists: .artists, extraartists: .extraartists}" <<< $response)
	
	# Build artist
	buildArtist
	# Build tracklist according to settings format
	buildTrackList
	# Build description field
	buildDescription
	# Build artists tags arrays
	buildArtistsTags
	
}

supplyLookupQuery() {
    while true; do
        read -p "Enter lookup query (usually artist, album, year): " reply
        case ${reply} in
            '' ) _info "Please enter lookup query. ";;
            * ) _info "Using new lookup query '${reply}'"; lookupQuery="${reply}"; break;;
        esac
    done

}

loopThroughFolders() {
    # Loop through the folder
    for curDir in "${startFolder}/"*; do
		curFlacFolder="${curDir##*/}"
        # Check if it's a directory
        if [[ -d "${curDir}" ]]; then
            # Set some vars to break loop
            isSet=0
            needNewLookupQuery=0
			skipAlbum=0
			# Fetch album info from discogs
            while [[ "${isSet}" -eq 0 ]] && [[ "${skipAlbum}" -eq 0 ]]; do
                # Check if a new lookup is needed
                if [[ ${needNewLookupQuery} -eq 0 ]]; then
                    lookupQuery="${curFlacFolder}"
                else
                    # Prompt for new lookup info
                    supplyLookupQuery
                fi
                # Make the lookup
                fetchDiscogsList
                if test "${discogsId}"; then
                    # An entry was selected, break the loop
                    isSet=1
                    # Fetch the release info
                    fetchDiscogsRelease
                elif [[ "${skipAlbum}" -eq 0 ]]; then
                    info_ "Retry with new lookup."
                    needNewLookupQuery=1
                fi
            done
			# Create .torrent; Move/Rename original folder if necessary; create transcodes
			# finally, upload stuff to site
			if [[ "${skipAlbum}" -eq 0 ]]; then
				# Create Flac Folder Name if necessary and check for illegal chars
				buildFlacFolder
				# Copy or Move or Rename the folder
				createDestFlacFolder
				# Create torrent for Flac
				createTorrent "${destFlacFolder}" "Flac"
				# Transcode Flac to 320 / V0
				for curTranscode in "${transcodeArr[@]}"; do
					buildTranscodeFolder
					# Transcode
					transcodeFlac
					# Create torrent for Transcode
					createTorrent "" "${curTranscode}"
				done
			fi
            exit;
        fi
    done
}

main() {
	# Load helper functions
	source "./helper.sh"
	
	# Check if site handle was submitted
	if [[ -z "${curSite}" ]]; then
		_err "Missing site info. Please add the '-s \"site handle\"' option."
	fi
	
	# Create missing configs
	if [[ "${missingConfig}" -eq 1 ]]; then
		createConfig
	fi
	
    # Make some checks
    checkDeps
    checkConfig

	# Load the site config
	source "./config.${curSite}.sh"
	
    # Start with looping through folders in start dir
    loopThroughFolders
}

# Create an associative array for the transcode settings
unset transcodeArr
declare -A transcodeArr

# Loop through the options
while getopts ":c30s:" opt; do
    case "${opt}" in
         c) missingConfig=1 ;;
         3) transcodeArr["320"]="320" ;;
         0) transcodeArr["v0"]="v0" ;;
		 s) curSite="${OPTARG}" ;;
        \?) _err "Invalid option '-$OPTARG'. Abort."; exit 1 ;;
    esac
done

# Set max. number of concurrent jobs
maxnum=$(grep -c '^processor' /proc/cpuinfo)
maxnum=$((maxnum+2)) # Add another 2 cores so that it won't stall because of full jobs

# Start main function
main
