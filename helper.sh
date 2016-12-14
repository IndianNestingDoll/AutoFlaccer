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
	else
		# Or just leave it at current name
		destFlacFolderName="${curFlacFolder}"
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

createDestFlacFolder() {
	case "${_folder_move_flac}" in
		0)  destFlacFolder="${startFolder}/${destFlacFolderName}"  # don't touch, but maybe rename
			mv "${curDir}" "${destFlacFolder}"		
		    ;;
		1)  destFlacFolder="${_folder_data_flac}/${destFlacFolderName}" # move
			mkdir -p "${_folder_data_flac}"
			mv "${curDir}" "${destFlacFolder}"
			;;
		2)  destFlacFolder="${_folder_data_flac}/${destFlacFolderName}" # copy
			mkdir -p "${_folder_data_flac}"
			cp -a "${curDir}" "${destFlacFolder}"
			;;
	esac
    _info "Album now at '${destFlacFolder}'"
}

createTorrent() {
	dataFolder="${1}"
	dataFormat="${2}"
	case "${dataFormat}" in
		Flac)	destTorrentFolder="${_folder_torrent_flac}" ;;
		320)	destTorrentFolder="${_folder_torrent_320}" ;;
		v0)		destTorrentFolder="${_folder_torrent_v0}" ;;
	esac
	mktorrent 	-a "${_announce}" \
				-c "created by ${userAgent}" \
				-s "${_source}" \
				-o "${destTorrentFolder}/${dataFolder}.torrent" \
				"${dataFolder}"
	_info ".torrent located at '${destTorrentFolder}/${dataFolder}.torrent'"
}

buildTranscodeFolder() {
	case "${curTranscode}" in
		320)	destTransFolderName="${_folder_foldername_320}"
				bitrate="-b"
				;;
		v0)		destTransFolderName="${_folder_foldername_v0}"
				bitrate="-v"
				;;
	esac
	destTransFolderName="${destTransFolderName/(artist)/${artist}}"
	destTransFolderName="${destTransFolderName/(year)/${year}}"
	destTransFolderName="${destTransFolderName/(title)/${title}}"
	destTransFolderName="${destTransFolderName/(label)/${label}}"
	destTransFolderName="${destTransFolderName/(catno)/${catno}}"
	destTransFolderName="${destTransFolderName/(source)/${source}}"
	destTransFolderName="${destTransFolderName/(format)/${curTranscode}}"

	# Check foldername for illegal chars
	_info "Testing '${destTransFolderName}' for illegal chars"
	checkIllegalChars "${destTransFolderName}"
	# Check folder length
	curLen="${#destTransFolderName}"
	if [[ "${curLen}" -gt "${charLimit}" ]]; then
		_err "'${destTransFolderName}' exceeds the limit of ${charLimit} characters. Aborting."
	fi
	# Create folder structure
	cd "${startFolder}" || _err "Couldn't change to '${startFolder}"
	find "${curFlacFolder}" -type d -exec mkdir -p "${destTransFolderName}/{}" \;
	# Copy files with according extensions
	for curExt in "${copyExts[@]}"; do
		find "${curFlacFolder}" -type d -iname "*.${curExt}" -exec cp -a "${destTransFolderName}/{}" \;
	done
	# Loop through flacs
	while read curFlacFile; do
		# Check if there are free cpus
		until [[ $((jobs | wc -l)) > ${maxnum} ]]; do
			sleep 1
		done
		curFlacFileBase="${curFlacFile##*.}"
		# Get the meta info from flacs
		tags=(TITLE TRACKNUMBER GENRE DATE ARTIST ALBUM)
		flacTitle=$(metaflac --show-tag="TITLE" "${curFlacFile}")
		flacTitle="${flacTitle}/TITLE=/}"
		flacTracknumber=$(metaflac --show-tag="TRACKNUMBER" "${curFlacFile}")
		flacTracknumber="${flacTracknumber}/TRACKNUMBER=/}"
		flacGenre=$(metaflac --show-tag="GENRE" "${curFlacFile}")
		flacGenre="${flacGenre}/GENRE=/}"
		flacDate=$(metaflac --show-tag="DATE" "${curFlacFile}")
		flacDate="${flacDate}/DATE=/}"
		flacArtist=$(metaflac --show-tag="ARTIST" "${curFlacFile}")
		flacArtist="${flacArtist}/ARTIST=/}"
		flacAlbum=$(metaflac --show-tag="ALBUM" "${curFlacFile}")
		flacAlbum="${flacAlbum}/ALBUM=/}"
		# Convert the flac to mp3 and put it into background
		nice flac -dcs "${curFlacFile}" | lame ${bitrate} ${curTranscode} \
											--tt "${flacTitle}" \
											--tn "{flacTracknumber}" \
											--tg "${flacGenre}" \
											--ty "${flacDate}"
											--ta "${flacArtist}"
											--tl "${flacAlbum}" \
											- "${destTransFolderName}/${curFlacFileBase}.mp3" &>/dev/null &
	done < <(nice find "${curFlacFolder}" -iname '*.flac' )
	_info "Converted Flacs to ${curTranscode} mp3s"
	# Create Torrent
	createTorrent "${destTransFolderName}" "${curTranscode}"
}
