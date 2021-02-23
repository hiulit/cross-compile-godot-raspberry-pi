#!/usr/bin/env bash
# cross-compile-godot-raspberry-pi.sh

# Cross-compile Godot for the Raspberry Pi.
# A script to easily cross-compile Godot binaries for the Raspberry Pi (from Linux x86_64).
#
# Author: hiulit
# Repository: https://github.com/hiulit/cross-compile-godot-raspberry-pi
# License: MIT https://github.com/hiulit/cross-compile-godot-raspberry-pi/blob/master/LICENSE
#
# Requirements:
# - Godot source files (https://github.com/godotengine/godot)
# - Godot dependecies to compile for X11 Linux (https://docs.godotengine.org/en/stable/development/compiling/compiling_for_x11.html)
# - Godot toolchains to cross-compile for ARM (https://download.tuxfamily.org/godotengine/toolchains/linux/arm-godot-linux-gnueabihf_sdk-buildroot.tar.bz2)
# - curl
# - git
# - jq
# - tar
# - wget
# - zip

# Globals ########################################

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname $0)" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_FULL="$SCRIPT_DIR/$SCRIPT_NAME"
readonly SCRIPT_TITLE="Cross-compile Godot for the Raspberry Pi"
readonly SCRIPT_DESCRIPTION="A script to easily cross-compile Godot binaries for the Raspberry Pi (from Linux x86_64)."
readonly SCRIPT_CFG="$SCRIPT_DIR/cross-compile-godot-raspberry-pi.cfg"
readonly LOG_DIR="$SCRIPT_DIR/logs"
readonly LOG_FILE="$LOG_DIR/$(date +%F-%T).log"


# Variables #####################################

GODOT_SOURCE_FILES_DIR="$SCRIPT_DIR/godot"
GODOT_TOOLCHAINS_DIR="$SCRIPT_DIR/arm-godot-linux-gnueabihf_sdk-buildroot"
GODOT_COMPILED_BINARIES_DIR="$SCRIPT_DIR/compiled-binaries"
GODOT_VERSIONS=()
GODOT_COMMITS=()
RASPBERRY_PI_VERSIONS=()
BINARIES_TO_COMPILE=()
SCONS_JOBS="1"
USE_LTO="no"
GCC_VERBOSE="yes"

AUDIO_FIX="no"
GCC_VERBOSE="no"

CCFLAGS=""
GODOT_TOOLS=""
GODOT_TARGET=""
GODOT_PLATFORM=""
GODOT_BINARY_NAME=""


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
  # [[ "$GUI_FLAG" -eq 1 ]] && log "$message" || echo "$message"
  echo "$message"
  for ((i=1; i<="${#message}"; i+=1)); do [[ -n "$dashes" ]] && dashes+="-" || dashes="-"; done
  # [[ "$GUI_FLAG" -eq 1 ]] && log "$dashes" || echo "$dashes"
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


function version() {
  echo "$@" | awk -F. '{ printf("%d%03d%03d%03d\n", $1,$2,$3,$4); }'
}


function set_config() {
  local config_name
  local config_param
  config_name="$1"
  config_param="${@:2}"
  sed -i "s|^\($config_name\s*=\s*\).*|\1\"$config_param\"|" "$SCRIPT_CFG"
  if [[ "$?" -eq 0 ]]; then
    echo "'$config_name' set to '$config_param' in the config file."
  else
    log "ERROR: Something went wrong when setting '$config_name' to '$config_param'." >&2
  fi
}


function get_config() {
  local config
  config="$(grep -Po "(?<=^$1 = ).*" "$SCRIPT_CFG")"
  config="${config%\"}"
  config="${config#\"}"
  echo "$config"
}


function check_config() {
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
      # Assign the config param to the dynamic config name.
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
#H -gt, --get-tags                      Prints the Godot tags from GitHub (to be used with --godot-versions).
      -gt|--get-tags)
        curl -sL https://api.github.com/repos/godotengine/godot/tags | jq -r ".[].name" | grep -E '^[3-9].[1-9]'
        exit 0
        ;;
#H -gj, --get-jobs                      Prints the number of jobs/CPUs (to be used with --scons-jobs).
      -gj|--get-jobs)
        lscpu | egrep 'CPU\(s\)'
        exit 0
        ;;
#H -d, --download [file] [path]         Downloads the Godot source files or the Godot toolchains.
#H                                          Files: "godot-source-files" or "godot-toolchains".
#H                                          Default path: Same folder as this script.
      -d|--download)
        check_argument "$1" "$2" || exit 1
        local option="$1"
        shift

        if [[ "$1" != "godot-source-files" ]] && [[ "$1" != "godot-toolchains" ]]; then
          echo "ERROR: Argument for '$option' ('"$1"') must be 'godot-source-files' or 'godot-toolchains'." >&2
          exit 1
        fi

        if [[ "$1" == "godot-source-files" ]]; then
          if [[ -n "$2" ]]; then
            GODOT_SOURCE_FILES_DIR="$2"
            set_config "godot_source_files_dir" "$GODOT_SOURCE_FILES_DIR"
          fi

          git clone https://github.com/godotengine/godot.git "$GODOT_SOURCE_FILES_DIR"
        fi

        if [[ "$1" == "godot-toolchains" ]]; then
          if [[ -n "$2" ]]; then
            GODOT_TOOLCHAINS_DIR="$2"
            set_config "godot_toolchains_dir" "$GODOT_TOOLCHAINS_DIR"
          fi

          wget -P "$GODOT_TOOLCHAINS_DIR" -q --show-progress https://download.tuxfamily.org/godotengine/toolchains/linux/arm-godot-linux-gnueabihf_sdk-buildroot.tar.bz2
          tar -xvf "$GODOT_TOOLCHAINS_DIR"/arm-godot-linux-gnueabihf_sdk-buildroot.tar.bz2 --strip-components 1 -C "$GODOT_TOOLCHAINS_DIR"
          rm "$GODOT_TOOLCHAINS_DIR"/arm-godot-linux-gnueabihf_sdk-buildroot.tar.bz2
          "$GODOT_TOOLCHAINS_DIR"/relocate-sdk.sh
        fi

        exit 0
        ;;
#H -sd, --source-dir [path]             Sets the Godot source files directory.
#H                                          Default: Same folder as this script.
      -sp|--source-dir)
        check_argument "$1" "$2" || exit 1
        local option="$1"
        shift

        if ! [[ -d "$1" ]]; then
          echo "ERROR: The folder for '$option' ('$1') doesn't exist." >&2
          exit 1
        fi

        GODOT_SOURCE_FILES_DIR="$1"
        set_config "godot_source_files_dir" "$GODOT_SOURCE_FILES_DIR"
        ;;
#H -td, --toolchains-dir [path]         Sets the Godot toolchains directory.
#H                                          Default: Same folder as this script.
      -tp|--toolchains-dir)
        check_argument "$1" "$2" || exit 1
        local option="$1"
        shift

        if ! [[ -d "$1" ]]; then
          echo "ERROR: The folder for '$option' ('$1') doesn't exist." >&2
          exit 1
        fi

        GODOT_TOOLCHAINS_DIR="$1"
        set_config "godot_toolchains_dir" "$GODOT_TOOLCHAINS_DIR"
        ;;
#H -bd, --binaries-dir [path]           Sets the Godot compiled binaries directory.
#H                                          Default: Same folder as this script.
      -bp|--binaries-dir)
        check_argument "$1" "$2" || exit 1
        local option="$1"
        shift

        if ! [[ -d "$1" ]]; then
          echo "ERROR: The path for '$option' ('$1') doesn't exist." >&2
          exit 1
        fi

        GODOT_COMPILED_BINARIES_DIR="$1"
        set_config "godot_compiled_binaries_dir" "$GODOT_COMPILED_BINARIES_DIR"
        ;;
#H -gv, --godot-versions [version/s]        Sets the Godot version/s to be compiled.
#H                                          Version/s: Use '-gt' or '--get-tags' to see the available versions.
      -gv|--godot-versions)
        check_argument "$1" "$2" || exit 1
        shift

        for argument in $@; do
          if [[ "$argument" =~ ^- ]]; then
            break
          fi

          GODOT_VERSIONS+=("$argument")
        done

        set_config "godot_versions" "${GODOT_VERSIONS[@]}"
        ;;
#H -gc, --godot-commits [SHA-1 hash/es]      Sets the Godot commit/s to be compiled.
#H                                          Commit/s: SHA-1 hash/es.
      -gc|--godot-commits)
        check_argument "$1" "$2" || exit 1
        shift

        for argument in $@; do
          if [[ "$argument" =~ ^- ]]; then
            break
          fi

          GODOT_COMMITS+=("$argument")
        done

        set_config "godot_commits" "${GODOT_COMMITS[@]}"
        ;;
#H -rv, --rpi-versions [version/s]      Sets the Raspberry Pi version/s to compile.
#H                                          Version/s: "0" "1" "2" "3" "4".
      -rv|--rpi-versions)
        check_argument "$1" "$2" || exit 1
        shift

        for argument in $@; do
          if [[ "$argument" =~ ^- ]]; then
            break
          fi

          RASPBERRY_PI_VERSIONS+=("$argument")
        done

        set_config "raspberry_pi_versions" "${RASPBERRY_PI_VERSIONS[@]}"
        ;;
#H -c, --compile [binary type/s]        Sets the different types of Godot binaries to compile.
#H                                          Binary type/s: "editor" "export-template" "headless" "server".
      -c|--compile)
        check_argument "$1" "$2" || exit 1
        shift

        for argument in $@; do
          if [[ "$argument" =~ ^- ]]; then
            break
          fi

          BINARIES_TO_COMPILE+=("$argument")
        done

        set_config "binaries_to_compile" "${BINARIES_TO_COMPILE[@]}"
        ;;
#H -j, --scons-jobs [number]            Sets the jobs (CPUs) to use in SCons.
#H                                          Number: "1-∞".
#H                                          Default: "1".
      -j|--scons-jobs)
        check_argument "$1" "$2" || exit 1
        local option="$1"
        shift

        if ! [[ "$1" =~ ^[0-9]+$ ]]; then
          echo "ERROR: Argument for '$option' ('"$1"') must be a number." >&2
          exit 1
        fi

        SCONS_JOBS="$1"
        set_config "scons_jobs" "$SCONS_JOBS"
        ;;
#H -l, --use-lto [option]               Enables using Link Time Optimization (LTO) when compiling.
#H                                          Options: "yes" or "no".
#H                                          Default: "no".
      -l|--use-lto)
        check_argument "$1" "$2" || exit 1
        local option="$1"
        shift

        if [[ "$1" != "yes" ]] && [[ "$1" != "no" ]]; then
          echo "ERROR: Argument for '$option' ('"$1"') must be 'yes' or 'no'." >&2
          exit 1
        fi

        USE_LTO="$1"
        set_config "use_lto" "$USE_LTO"
        ;;
#H -a, --auto                           Stars compiling with the settings in the config file.
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

  local errors=0

  if [[ -z "$GODOT_VERSIONS" ]] && [[ -z "$GODOT_COMMITS" ]]; then
    log >&2
    log "ERROR: At least one version of Godot or one commit must be set to compile." >&2
    log "Use '-gv' or '--godot-versions' [version/s]" >&2
    log "Version/s: Use '-gt' or '--get-tags' to see the available versions." >&2
    log "Use '-gc' or '--godot-commits' [commit/s]" >&2
    log "Commit/s: SHA-1 hash/es." >&2
    ((errors+=1))
  fi

  if [[ -z "$BINARIES_TO_COMPILE" ]]; then
    log >&2
    log "ERROR: At least one type of Godot binary must be set to compile." >&2
    log "Use '-c' or '--compile' [binary type/s]" >&2
    log "Binary type/s: 'editor' 'export-template' 'headless' 'server'." >&2
    ((errors+=1))
  fi

  if [[ -z "$RASPBERRY_PI_VERSIONS" ]]; then
    log >&2
    log "ERROR: At least one version of Raspberry Pi must be set to compile." >&2
    log "Use '-rv' or '--rpi-versions' [version/s]" >&2
    log "Version/s: '0' '1' '2' '3' '4." >&2
    ((errors+=1))
  fi

  [[ "$errors" -gt 0 ]] && exit 1

  log
  log "----------"
  log "Godot source files directory: $GODOT_SOURCE_FILES_DIR"
  log "Godot toolchains directory: $GODOT_TOOLCHAINS_DIR"
  log "Godot compiled binaries directory: $GODOT_COMPILED_BINARIES_DIR"
  log "Godot version/s to compile: ${GODOT_VERSIONS[@]}"
  log "Godot commit/s to compile: $GODOT_COMMITS"
  log "Binaries to compile: ${BINARIES_TO_COMPILE[@]}"
  log "Raspberry Pi version/s to compile: ${RASPBERRY_PI_VERSIONS[@]}"
  log "SCons jobs: $SCONS_JOBS"
  log "Use LTO: $USE_LTO"
  log "GCC verbose: $GCC_VERBOSE"
  log "----------"
  log

  mkdir -p "$GODOT_COMPILED_BINARIES_DIR"

  # Concatenate versions and commits.
  GODOT_VERSIONS+=("${GODOT_COMMITS[@]}")

  for rpi_version in "${RASPBERRY_PI_VERSIONS[@]}"; do
    case "$rpi_version" in
      0|1)
        CCFLAGS="-mcpu=arm1176jzf-s -mtune=arm1176jzf-s mfpu=vfp -mfloat-abi=hard -mlittle-endian -munaligned-access"
        ;;
      2)
        CCFLAGS="-mcpu=cortex-a7 -mtune=cortex-a7 -mfpu=neon-vfpv4 -mfloat-abi=hard -mlittle-endian -munaligned-access"
        ;;
      3)
        CCFLAGS="-mcpu=cortex-a53 -mtune=cortex-a53 -mfpu=neon-fp-armv8 -mfloat-abi=hard -mlittle-endian -munaligned-access"
        ;;
      4)
        CCFLAGS="-mcpu=cortex-a72 -mtune=cortex-a72 -mfpu=neon-fp-armv8 -mfloat-abi=hard -mlittle-endian -munaligned-access"
        ;;
    esac

    if [[ "$GCC_VERBOSE" == "no" ]]; then
      CCFLAGS+=" -w -fcompare-debug-second"
    fi

    for godot_version in "${GODOT_VERSIONS[@]}"; do
      cd "$GODOT_SOURCE_FILES_DIR"

      log ">> Checking out version $godot_version ..."
      git checkout "$godot_version"

      if [[ "$(version "$godot_version")" -lt "$(version 3.2.4-stable)" ]]; then
        # Apply audio fix. See https://github.com/godotengine/godot/pull/43928.
        AUDIO_FIX="yes"
        sed -i "s/uint8_t/int16_t/gi" "$GODOT_SOURCE_FILES_DIR/drivers/alsa/audio_driver_alsa.cpp"
      fi

      for binary_type in "${BINARIES_TO_COMPILE[@]}"; do
        case "$binary_type" in
          "editor")
            GODOT_TOOLS="yes"
            GODOT_TARGET="release_debug"
            GODOT_PLATFORM="x11"
            GODOT_BINARY_NAME="godot.x11.opt.tools.64"
            ;;
          "export-template")
            GODOT_TOOLS="no"
            GODOT_TARGET="release"
            GODOT_PLATFORM="x11"
            GODOT_BINARY_NAME="godot.x11.opt.64"
            ;;
          "headless")
            GODOT_TOOLS="yes"
            GODOT_TARGET="release_debug"
            GODOT_PLATFORM="server"
            GODOT_BINARY_NAME="godot_server.x11.opt.tools.64"
            ;;
          "server")
            GODOT_TOOLS="no"
            GODOT_TARGET="release"
            GODOT_PLATFORM="server"
            GODOT_BINARY_NAME="godot_server.x11.opt.64"
            ;;
        esac

        log "$(underline "GODOT '${binary_type^^}' ('$godot_version') FOR THE RASPBERRY PI '$rpi_version'")"

        cd "$GODOT_SOURCE_FILES_DIR"

        log ">> Cleaning SCons ..."
        scons --clean platform="$GODOT_PLATFORM" tools="$GODOT_TOOLS" target="$GODOT_TARGET"
        if ! [[ "$?" -eq 0 ]]; then
          log "ERROR: Something went wrong when cleaning generated files for the '$GODOT_PLATFORM' platform." >&2
          exit 1
        fi
        log "> Done!"

        log ">> Compiling Godot ..."
        PATH="$GODOT_TOOLCHAINS_DIR"/bin/:$PATH \
        scons \
        -j"$SCONS_JOBS" \
        platform="$GODOT_PLATFORM" \
        tools="$GODOT_TOOLS" \
        target="$GODOT_TARGET" \
        use_lto="$USE_LTO" \
        use_static_cpp=yes \
        CCFLAGS="$CCFLAGS" \
        CC=arm-godot-linux-gnueabihf-gcc \
        CXX=arm-godot-linux-gnueabihf-g++ \
        module_denoise_enabled=no module_raycast_enabled=no module_webm_enabled=no module_theora_enabled=no
        if ! [[ "$?" -eq 0 ]]; then
          log "ERROR: Something went wrong when compiling Godot." >&2
          exit 1
        fi
        log "> Done!"

        cd "$GODOT_SOURCE_FILES_DIR/bin"

        log ">> Moving '$GODOT_BINARY_NAME' to '$GODOT_COMPILED_BINARIES_DIR' ..."
        log ">> Renaming '$GODOT_BINARY_NAME' to 'godot_${godot_version}_rpi${rpi_version}_${binary_type}.bin' ..."
        mv "$GODOT_BINARY_NAME" "$GODOT_COMPILED_BINARIES_DIR/godot_${godot_version}_rpi${rpi_version}_${binary_type}.bin"
        if ! [[ "$?" -eq 0 ]]; then
          log "ERROR: Something went wrong when moving or renaming '$GODOT_BINARY_NAME'." >&2
          exit 1
        fi
        log "> Done!"

        log ">> Stripping debug symbols for 'godot_${godot_version}_rpi${rpi_version}_${binary_type}.bin' ..."
        "$GODOT_TOOLCHAINS_DIR"/bin/arm-godot-linux-gnueabihf-strip "$GODOT_COMPILED_BINARIES_DIR/godot_${godot_version}_rpi${rpi_version}_${binary_type}.bin"
        if ! [[ "$?" -eq 0 ]]; then
          log "ERROR: Something went wrong when stripping the debug symbols of 'godot_${godot_version}_rpi${rpi_version}_${binary_type}.bin'." >&2
          exit 1
        fi
        log "> Done!"

        log ">> Compressing 'godot_${godot_version}_rpi${rpi_version}_${binary_type}.bin' ..."
        zip "$GODOT_COMPILED_BINARIES_DIR/godot_${godot_version}_rpi${rpi_version}_${binary_type}.zip" "$GODOT_COMPILED_BINARIES_DIR/godot_${godot_version}_rpi${rpi_version}_${binary_type}.bin"
        if [[ "$?" -eq 0 ]]; then
          rm "$GODOT_COMPILED_BINARIES_DIR/godot_${godot_version}_rpi${rpi_version}_${binary_type}.bin"
        else
          log "ERROR: Something went wrong when compressing 'godot_${godot_version}_rpi${rpi_version}_${binary_type}.bin'." >&2
          exit 1
        fi
        log "> Done!"

        log
        log "The Godot '$binary_type' ('$godot_version') for the Raspberry Pi '$rpi_version' was compiled successfully!"
        log "You can find it at '$GODOT_COMPILED_BINARIES_DIR/godot_${godot_version}_rpi${rpi_version}_${binary_type}.zip'."
        log
      done

      if [[ "$AUDIO_FIX" == "yes" ]]; then
        # Revert the audio fix to prevent git issues.
        AUDIO_FIX="no"
        sed -i "s/int16_t/uint8_t/gi" "$GODOT_SOURCE_FILES_DIR/drivers/alsa/audio_driver_alsa.cpp"
      fi

    done
  done
}

main "$@"