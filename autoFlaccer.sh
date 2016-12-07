#!/usr/bin/env bash

# Required stuff:
# jq
# latest mktorrent: https://github.com/Rudde/mktorrent

userAgent="AutoFlacer/0.1"

#Request Token URL	https://api.discogs.com/oauth/request_token
#Authorize URL		https://www.discogs.com/oauth/authorize
#Access Token URL	https://api.discogs.com/oauth/access_token

#curl https://api.discogs.com/releases/249504 --user-agent "${userAgent}"

checkConfig() {
    # Check if config file exists
    if [[ ! -f "config.sh" ]]; then
        echo "Config file not found. Please create a default one using the -c option".
        echo "Don't forget to add your Discogs API info to the config file."
        exit 1;
    fi
    # Source the config file
    source "./config.sh"
    # Check if values are set
    [[ -z "${discogsKey}" ]] && echo "discogsKey not set in config. Please fix." && exit 1
    [[ -z "${discogsSecret}" ]] && echo "discogsSecret not set in config. Please fix." && exit 1
    [[ -z "${startFolder}" ]] && echo "startFolder not set in config. Please fix." && exit 1
}

createConfig() {
    cp "config.default" "config.sh"
    echo "Edit the config.sh file and retry."
    exit 0
}


checkDeps() {
    # Check if mktorrent suppors the source string
    mktorrentTest=$(mktorrent -h | grep 'source string')
    [[ "${mktorrentTest}" != *"source string"* ]] && echo "You need to install mktorrent or update it to at least v1.0" && exit 1
    # Check if jq is installed
    jqTest=$(type jq)
    [[ "${jqTest}" != *"jq is"* ]] && echo "You need to install jq" && exit 1
}

supplyDiscogsId() {
    while true; do
        read -p "Manually enter Discogs ID: " reply
        if [[ "${reply}" != *[!0-9]* ]]; then
            echo "ID entered: ${reply}"; discogsId="${reply}"; break;
        else
            echo "Please enter ID.";
        fi
    done
}

fetchDiscogsList() {
    unset discogsId
    unset idArr
    unset curOptions
    echo "Searching Discogs for '${lookupQuery}'"
    echo ""
    echo ""
    response=$(curl -s -G "https://api.discogs.com/database/search" --user-agent "${userAgent}" \
        --data-urlencode "q=${lookupQuery}" \
        --data-urlencode "key=${discogsKey}" \
        --data-urlencode "secret=${discogsSecret}" \
        --data-urlencode "per_page=10" \
        --data-urlencode "page=1")

    echo "Please select the according entry:"
    echo ""
    for i in {0..9}; do
        curTitle=$(jq --raw-output ".results[${i}] .title" <<< $response)
        curYear=$(jq --raw-output ".results[${i}] .year" <<< $response)
        curLabel=$(jq --raw-output ".results[${i}] .label[0]" <<< $response)
        curFormat=$(jq --raw-output ".results[${i}] .format[0]" <<< $response)
        curId=$(jq --raw-output ".results[${i}] .id" <<< $response)
        curType=$(jq --raw-output ".results[${i}] .type" <<< $response)
        idArr[$i]="${curId}"
        # Filter out entries with no ID and Master type
        if [[ "${curTitle}" != "null" && "$curType" != "master" ]]; then
            curOptions="${curOptions}${i}"
            idArr[$i]="${curId}"
            echo "(${i}) ${curTitle}  -  ${curYear}  -  ${curLabel}  -  ${curFormat}  -  https://www.discogs.com/release/${curId}"
        fi
    done

    while true; do
        read -p "Enter valid option or I/i (for manual ID) or N/n (for new lookup): " reply
        case ${reply} in
            [${curOptions}] ) echo "Option ${reply} selected"; discogsId="${idArr[${reply}]}"; break;;
            [Ii] ) echo "Please supply ID"; supplyDiscogsId; break;;
            [Nn] ) echo "Please enter new lookup query"; break;;
            * ) echo "Please answer with option or I/i or N/n ";;
        esac
    done
}

fetchDiscogsRelease() {
    response=$(curl -s -G "https://api.discogs.com/releases/${discogsId}" --user-agent "${userAgent}")
    label=$(jq --raw-output ".labels[0] .name" <<< $response)
    catno=$(jq --raw-output ".labels[0] .catno" <<< $response)
    year=$(jq --raw-output ".year" <<< $response)
    genres=$(jq --raw-output ".genres" <<< $response)
    title=$(jq --raw-output ".title" <<< $response)
    format=$(jq --raw-output ".formats[0] .name" <<< $response)
    artists=$(jq --raw-output ".artists[] .name" <<< $response)
    tracklist=$(jq -r ".tracklist[] | .title" <<< $response)
    echo "$label - $catno - $year - $genres - $title - $format"
    echo ""
    echo ""
    echo $artists
    echo ""
    echo ""
    echo $tracklist
}

supplyLookupQuery() {
    while true; do
        read -p "Enter lookup query (usually artist, album, year); " reply
        case ${reply} in
            '' ) echo "Please enter lookup query. ";;
            * ) echo "Using new lookup query '${reply}'"; lookupQuery="${reply}"; break;;
        esac
    done

}

loopThroughFolders() {
    # Loop through the folder
    for curDir in "${startFolder}/"*; do
        # Check if it's a directory
        if [[ -d "${curDir}" ]]; then
            # Set some vars to break loop
            isSet=0
            needNewLookupQuery=0
            while [[ ${isSet} -eq 0 ]]; do
                # Check if a new lookup is needed
                if [[ ${needNewLookupQuery} -eq 0 ]]; then
                    lookupQuery="${curDir##*/}"
                else
                    # Prompt for new lookup info
                    supplyLookupQuery
                fi
                # Make the lookup
                fetchDiscogsList;
                if test "${discogsId}"; then
                    # An entry was selected, break the loop
                    isSet=1
                    # Fetch the release info
                    fetchDiscogsRelease
                else
                    echo "Retry with new lookup."
                    needNewLookupQuery=1
                fi
            done
            exit;
        fi
    done
}

main() {
    # Make some checks
    checkConfig
    checkDeps

    # Start with looping through folders in start dir
    loopThroughFolders
}

# Create an associative array for the transcode settings
declare -A transcodeArr

while getopts ":c30" opt; do
    case "${opt}" in
         c) createConfig ;;
         3) transcodeArr["320"]="320" ;;
         0) transcodeArr["v0"]="v0" ;;
        \?) echo "Invalid option '-$OPTARG'. Abort."; exit 1 ;;
    esac
done


# Start main function
main
