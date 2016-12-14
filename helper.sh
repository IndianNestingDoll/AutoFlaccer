#!/usr/bin/env bash

_green=$'\e[1;32m'
_red=$'\e[1;31m'
_yellow=$'\e[33m'
_end=$'\e[0m'

_info() {
    printf "${_green}%s: ${_end}%s\n" "Info" "${1}"
}

_echo() {
    printf "      %s\n" "${1}"
}

_err() {
    printf "${_red}%s: ${_end}%s\n" "Error" "${1}"
	exit 1
}

buildArtist() {
	# Build 'main artist' by joining the different artists and their joining var
	artist=$(jq -r ".name, .join" <<< ${artists})
	artist=${artist//$'\n'/ }
	_info "'${artist}'"
}

buildTrackList() {
	# Build the tracklist according to format
	curTracks=$(jq -r ".position, .title, .duration" <<< ${tracklist})
	i=1
	while read -r line; do
		case "${i}" in 
			1)  tmp="${_description_tracks}"
				tmp="${tmp/(trackNumber)/${line}}"
				;;
			2) 	tmp="${tmp/(trackTitle)/${line}}" ;;
			3) 	tmp="${tmp/(trackDuration)/${line}}" ;;
		esac
		i=$((i+1))
		if [[ "${i}" -eq 4 ]]; then
			curTrackList="${curTrackList}${tmp}
"
			i=1
		fi
	done <<< "${curTracks}"
}

buildDescription() {
	# Build the description field according to format
	footer="${_description_footer/(discogsId)/${discogsId}}"
	description="${_description_title}
${curTrackList}
${footer}
"
	_info "${description}"
}

buildArtistsTags() {
	unset artistsMain
	unset artistsGuest
	unset artistsComposer
	unset artistsConductor
	unset artistsCompiler
	unset artistsRemixer
	unset artistsProducer
	declare -A artistsMain
	declare -A artistsGuest   # Missing discogs tag
	declare -A artistsComposer
	declare -A artistsConductor   # Missing discogs tag
	declare -A artistsCompiler   # Missing discogs tag
	declare -A artistsRemixer
	declare -A artistsProducer

	# Add main artists
	artist=$(jq -r ".name" <<< ${artists})
	while read -r line; do
		if [[ "${line}" != "Various" ]]; then
			artistsMain["${line}"]="${line}"
		fi
	done <<< "${artist}"

	# Loop through tracklist to find other artists
	curArtists=$(jq -r ".extraartists[] | .name, .role" <<< ${tracklist})
	i=1
	while read -r line; do
		case "${i}" in
			1)  name="${line}" ;;
			2) 	role="${line}" ;;
		esac
		i=$((i+1))
		if [[ "${i}" -eq 3 ]]; then
			case "${role}" in
				*Mixed*)	artistsMain["${name}"]="${name}" ;;&
				*Producer*)	artistsProducer["${name}"]="${name}" ;;&
				*Remix*)	artistsRemixer["${name}"]="${name}" ;;&
				*Written*)	artistsComposer["${name}"]="${name}" ;;
			esac
			i=1
		fi
	done <<< "${curArtists}"

	_info "artistsMain"
	printf '%s\n' "${artistsMain[@]}"
	_info "artistsGuest"
	printf '%s\n' "${artistsGuest[@]}"
	_info "artistsComposer"
	printf '%s\n' "${artistsComposer[@]}"
	_info "artistsConductor"
	printf '%s\n' "${artistsConductor[@]}"
	_info "artistsCompiler"
	printf '%s\n' "${artistsCompiler[@]}"
	_info "artistsRemixer"
	printf '%s\n' "${artistsRemixer[@]}"
	_info "artistsProducer"
	printf '%s\n' "${artistsProducer[@]}"
}

checkIllegalChars() {
	tmpData="${1}"
	for (( i=0; i<${#illegalChars}; i++)); do
		curChar="${illegalChars:${i}:1}"
		if [[ "${tmpData}" == *"${curChar}"* ]]; then
			_err "'${curChar}' found. Aborting. Please fix and retry."
		fi
	done
	_info "No illegal characters found."
}

buildFlacFolder() {
	# If FLAC Folder should be renamed, make new name according to format
	if [[ "${_folder_rename_flac}" -eq 1 ]]; then
		destFlacFolderName="${_folder_foldername_flac}"
		destFlacFolderName="${destFlacFolderName/(artist)/${artist}}"
		destFlacFolderName="${destFlacFolderName/(year)/${year}}"
		destFlacFolderName="${destFlacFolderName/(title)/${title}}"
		destFlacFolderName="${destFlacFolderName/(label)/${label}}"
		destFlacFolderName="${destFlacFolderName/(catno)/${catno}}"
		destFlacFolderName="${destFlacFolderName/(source)/${source}}"
		destFlacFolderName="${destFlacFolderName/(format)/FLAC}"
	fi
	# Check foldername for illegal chars
	_info "Testing '${destFlacFolderName}' for illegal chars"
	checkIllegalChars "${destFlacFolderName}"
	# Check files in curFolder for illegal chars
	foundFiles=$(find "${curDir}" -type f)
	while read -r line; do
		_info "Testing '${line}' for illegal chars"
		checkIllegalChars "${line}"
	done <<< "${foundFiles}"
	# Check folder length
	curLen="${#destFlacFolderName}"
	if [[ "${curLen}" -gt "${charLimit}" ]]; then
		_err "'${destFlacFolderName}' exceeds the limit of ${charLimit} characters. Aborting."
	fi
}