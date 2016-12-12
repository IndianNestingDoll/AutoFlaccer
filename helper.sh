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