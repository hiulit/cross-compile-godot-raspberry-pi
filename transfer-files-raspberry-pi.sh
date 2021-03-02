#!/usr/bin/env bash
# transfer-files-raspberry-pi.sh
#
# Transfer files to a Raspberry Pi.
# A script to easily transfer files from a host machine to a Raspberry Pi using rsync.
#
# Author: hiulit
# Repository: https://github.com/hiulit/cross-compile-godot-raspberry-pi
# License: MIT https://github.com/hiulit/cross-compile-godot-raspberry-pi/blob/master/LICENSE
#
# Requirements:
# - SSH key pair
# - SSH passwordless login (optional, but preferable) (https://linuxize.com/post/how-to-setup-passwordless-ssh-login/)
# - Static IP on the Raspberry Pi (optional, but preferable).
#
# Dependencies
# - rsync


# Globals ########################################

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname $0)" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_FULL="$SCRIPT_DIR/$SCRIPT_NAME"
readonly SCRIPT_TITLE="Transfer files to a Raspberry Pi"
readonly SCRIPT_DESCRIPTION="A script to easily transfer files from a host machine to a Raspberry Pi using rsync."
readonly SCRIPT_CFG="$SCRIPT_DIR/transfer-files-raspberry-pi.cfg"
readonly LOG_DIR="$SCRIPT_DIR/logs/transfer-files-raspberry-pi"
readonly LOG_FILE="$LOG_DIR/$(date +%F-%T).log"


# Variables #####################################

GODOT_COMPILED_BINARIES_DIR="$SCRIPT_DIR/compiled-binaries"
REMOTE_DIR="/home/pi/godot-binaries/" # Note the trailing slash.

REMOTE_USERNAME=""
REMOTE_IP=""
GODOT_VERSIONS=""
GODOT_COMMITS=""
RASPBERRY_PI_VERSIONS=""
BINARIES=""

HOST_FILES=()

# Functions #####################################

function usage() {
  echo
  underline "$SCRIPT_TITLE"
  echo "$SCRIPT_DESCRIPTION"
  echo
  echo "USAGE: $0 [OPTIONS]"
  echo
  echo "Use '$0 --help' to see all the options."
}


function underline() {
  if [[ -z "$1" ]]; then
    echo "ERROR: '$FUNCNAME' function (at ${BASH_LINENO}) needs an argument!" >&2
    exit 1
  fi
  local dashes
  local message="$1"
  echo "$message"
  for ((i=1; i<="${#message}"; i+=1)); do [[ -n "$dashes" ]] && dashes+="-" || dashes="-"; done
  echo "$dashes"
}


function check_argument() {
  # This method doesn't accept arguments starting with '-'.
  if [[ -z "$2" || "$2" =~ ^- ]]; then
    echo >&2
    echo "ERROR: '$1' is missing an argument." >&2
    echo >&2
    echo "Try '$0 --help' for more info." >&2
    echo >&2
    return 1
  fi
}


function set_config() {
  local config_name
  local config_param
  config_name="$1"
  config_param="${@:2}"

  if grep -q "$config_name" "$SCRIPT_CFG"; then
    sed -i "s|^\($config_name\s*=\s*\).*|\1\"$config_param\"|" "$SCRIPT_CFG"
    if [[ "$?" -eq 0 ]]; then
      echo "'$config_name' set to '$config_param' in the config file."
    else
      log "ERROR: Something went wrong when setting '$config_name' to '$config_param'." >&2
    fi
  else
    log "ERROR: Can't set '$config_name'. It doesn't exist in the config file." >&2
  fi
}


function check_config() {
  # Variable names must be the same as the config settings.
  while IFS= read -r line; do
    local config_name
    local config_param

    # Continue if the line starts with "H".
    [[ "$line" =~ ^\# ]] && continue
    # Continue if the line is blank.
    [[ -z "$line" ]] && continue

    # Get everything before " =".
    config_name="$(echo "$line" | sed 's/ =.*//')"
    # Uppercase the name.
    config_name="${config_name^^}"

    # Get everything after "= ".
    config_param="$(echo "$line" | sed 's/.*= //')"
    # Remove leading and trailing double quotes.
    config_param="${config_param%\"}"
    config_param="${config_param#\"}"

    if [[ -n "$config_param" ]]; then
      eval "$config_name"="\$config_param"
      # echo "${config_name}"
      # echo "${!config_name}"
    fi
  done < "$SCRIPT_CFG"
}


function log() {
  echo "$*" >> "$LOG_FILE"
  echo "$*"
}


function ctrl_c() {
  log >&2
  log "Cancelled by user." >&2
  exit 1
}


function get_options() {
  if [[ -z "$1" ]]; then
    usage
    exit 0
  fi

  while [[ -n "$1" ]]; do
    case "$1" in
#H -h, --help                           Prints the help message.
      -h|--help)
        echo
        underline "$SCRIPT_TITLE"
        echo "$SCRIPT_DESCRIPTION"
        echo
        echo "USAGE: $0 [OPTIONS]"
        echo
        echo "OPTIONS:"
        echo
        sed '/^#H /!d; s/^#H //' "$0"
        echo
        exit 0
        ;;
#H -v, --version                        Prints the script version.
      -v|--version)
        echo "$SCRIPT_VERSION"
        exit 0
        ;;
#H -bd, --binaries-dir [path]           Sets the Godot compiled binaries directory.
#H                                        Default: "./compiled-binaries".
      -bd|--binaries-dir)
        check_argument "$1" "$2" || exit 1
        local option="$1"
        shift

        if ! [[ -d "$1" ]]; then
          echo "ERROR: The folder for '$option' ('$1') doesn't exist." >&2
          exit 1
        fi

        GODOT_COMPILED_BINARIES_DIR="$1"
        set_config "godot_compiled_binaries_dir" "$GODOT_COMPILED_BINARIES_DIR"
        ;;
#H -rd, --remote-dir [path]             Sets the Raspberry Pi directory where the files will be transfered.
#H                                        Default: "/home/pi/godot-binaries/". Note the trailing slash.
      -rd|--remote-dir)
        check_argument "$1" "$2" || exit 1
        local option="$1"
        shift

        REMOTE_DIR="$1"

        # Check if the path endS with "/".
        if ! [[ "$REMOTE_DIR" =~ \/$ ]]; then
          # Add a trailing "/" if not present.
          REMOTE_DIR+="/"
        fi

        set_config "remote_dir" "$REMOTE_DIR"
        ;;
#H -ru, --remote-username [username]    Sets the username of the Raspberry Pi.
      -ru|--remote-username)
        check_argument "$1" "$2" || exit 1
        shift

        REMOTE_USERNAME="$1"
        set_config "remote_username" "$REMOTE_USERNAME"
        ;;
#H -ri, --remote-ip [IP]                Sets the IP of the Raspberry Pi.
      -ri|--remote-ip)
        check_argument "$1" "$2" || exit 1
        shift

        REMOTE_IP="$1"
        set_config "remote_ip" "$REMOTE_IP"
        ;;
#H -gv, --godot-versions [version/s]    Sets the Godot version/s to transfer.
#H                                        Version/s must end with the suffix "-stable".
      -gv|--godot-versions)
        check_argument "$1" "$2" || exit 1
        shift

        local temp_array="$1"
        local suffix="-stable"

        # Convert a string separated by blank spaces to an array.
        IFS=" " read -r -a temp_array <<< "${temp_array[@]}"
        for version in "${temp_array[@]}"; do
          # Append the necessary suffix "-stable" if it's not present.
          if ! [[ "$version" =~ "$suffix" ]]; then
            version+="$suffix " # Note the trailing blank space.
          fi
          GODOT_VERSIONS+="$version"
        done

        # Remove trailing blank space.
        GODOT_VERSIONS="$(echo "$GODOT_VERSIONS" | sed 's/ *$//g')"

        set_config "godot_versions" "$GODOT_VERSIONS"
        ;;
#H -gc, --godot-commits [commit/s]      Sets the Godot commit/s to transfer.
#H                                        Commit/s: SHA-1 hash/es.
      -gc|--godot-commits)
        check_argument "$1" "$2" || exit 1
        shift

        GODOT_COMMITS="$1"

        set_config "godot_commits" "$GODOT_COMMITS"
        ;;
#H -rv, --rpi-versions [version/s]      Sets the Raspberry Pi version/s to transfer.
#H                                        Version/s: "0 1 2 3 4".
      -rv|--rpi-versions)
        check_argument "$1" "$2" || exit 1
        shift

        RASPBERRY_PI_VERSIONS="$1"

        set_config "raspberry_pi_versions" "$RASPBERRY_PI_VERSIONS"
        ;;
#H -b, --binaries [binary type/s]       Sets the different types of Godot binaries to transfer.
#H                                        Binary type/s: "editor export-template headless server".
      -b|--binaries)
        check_argument "$1" "$2" || exit 1
        shift

        BINARIES="$1"

        set_config "binaries" "$BINARIES"
        ;;
#H -a, --auto                           Starts compiling taking the settings in the config file.
      -a|--auto)
        check_config
        ;;
      *)
        echo "ERROR: Invalid option '$1'." >&2
        exit 2
        ;;
    esac
    shift
  done
}


function main() {
  get_options "$@"

  mkdir -p "$LOG_DIR"

  find "$LOG_DIR" -type f | sort | head -n -9 | xargs -d '\n' --no-run-if-empty rm

  trap ctrl_c INT

  log
  log "----------"
  log "Godot compiled binaries directory: $GODOT_COMPILED_BINARIES_DIR"
  log "Raspberry Pi directory: $REMOTE_DIR"
  log "Raspberry Pi username: $REMOTE_USERNAME"
  log "Raspberry Pi IP: $REMOTE_IP"
  log "Godot version/s to transfer: $GODOT_VERSIONS"
  log "Godot commit/s to transfer: $GODOT_COMMITS"
  log "Binaries to transfer: $BINARIES"
  log "Raspberry Pi version/s to transfer: $RASPBERRY_PI_VERSIONS"
  log "----------"
  log

  # Concatenate versions and commits.
  GODOT_VERSIONS+=("$GODOT_COMMITS")

  for file in "$GODOT_COMPILED_BINARIES_DIR"/*; do
    file="$(basename "$file")"

    IFS=" " read -r -a RASPBERRY_PI_VERSIONS <<< "${RASPBERRY_PI_VERSIONS[@]}"
    for rpi_version in "${RASPBERRY_PI_VERSIONS[@]}"; do
      IFS=" " read -r -a GODOT_VERSIONS <<< "${GODOT_VERSIONS[@]}"
      for godot_version in "${GODOT_VERSIONS[@]}"; do
        IFS=" " read -r -a BINARIES <<< "${BINARIES[@]}"
        for binary in "${BINARIES[@]}"; do
          if [[ "$file" =~ "rpi$rpi_version" ]] && [[ "$file" =~ "$godot_version" ]] && [[ "$file" =~ "$binary" ]]; then
            HOST_FILES+=("$file")
          fi
        done
      done
    done
  done

  if [[ -z "$HOST_FILES" ]]; then
    echo "Couldn't find any file with the current settings." >&2
    exit 1
  fi

  for file in "${HOST_FILES[@]}"; do
    log ">> Transfering '$file' ..."
    rsync -a -P --rsync-path="mkdir -p $REMOTE_DIR && rsync -a -P" "$GODOT_COMPILED_BINARIES_DIR"/"$file" "$REMOTE_USERNAME"@"$REMOTE_IP":"$REMOTE_DIR"
    if ! [[ "$?" -eq 0 ]]; then
      log "ERROR: Something went wrong when transfering '$file'." >&2
      continue
    fi
    log "> Done!"

    log
    log "'$file' was transfered successfully!"
    log
    log "You can find it at '$REMOTE_DIR$file'."
    log
  done
}

main "$@"
