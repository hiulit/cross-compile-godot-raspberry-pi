#!/usr/bin/env bash
# cross-compile-godot-raspberry-pi.sh

# Cross-compile Godot for the Raspberry Pi.
# A script to easily cross-compile Godot binaries for the Raspberry Pi from Linux x86_64.
#
# Author: hiulit
# Repository: https://github.com/hiulit/cross-compile-godot-raspberry-pi
# License: MIT https://github.com/hiulit/cross-compile-godot-raspberry-pi/blob/master/LICENSE
#
# Requirements:
# - Godot source files (https://github.com/godotengine/godot) (can be downloaded with this script)
# - Godot dependecies to compile for Linux (https://docs.godotengine.org/en/3.6/development/compiling/compiling_for_x11.html)
# - Godot toolchain to cross-compile for ARM (can be downloaded with this script).
#   - 32 bits (https://github.com/godotengine/buildroot/releases/download/godot-2023.08.x-4/arm-godot-linux-gnueabihf_sdk-buildroot.tar.bz2)
#   - 64 bits (https://github.com/godotengine/buildroot/releases/download/godot-2023.08.x-4/aarch64-godot-linux-gnu_sdk-buildroot.tar.bz2)
#
# Dependencies
# - curl
# - git
# - jq
# - tar
# - wget
# - zip
#
# Limitations
#
# The toolchain this script uses has a few limitations at the moment:
#
# - Only supports cross-compilation for Raspberry Pi versions >= `3`.
# - Can't compile Godot "2.x" because it requires "gcc < 6" and the toolchain only has "gcc 10.2".
#
# Other limitations:
#
# - Raspberry Pi versions "0", "1" and "2" can't be compiled using Link Time Optimization (LTO).


# Globals ########################################

readonly SCRIPT_VERSION="1.0.0"
readonly SCRIPT_DIR="$(cd "$(dirname $0)" && pwd)"
readonly SCRIPT_NAME="$(basename "$0")"
readonly SCRIPT_FULL="$SCRIPT_DIR/$SCRIPT_NAME"
readonly SCRIPT_TITLE="Cross-compile Godot for the Raspberry Pi"
readonly SCRIPT_DESCRIPTION="A script to easily cross-compile Godot binaries for the Raspberry Pi from Linux x86_64."
readonly SCRIPT_CFG="$SCRIPT_DIR/cross-compile-godot-raspberry-pi.cfg"
readonly LOG_DIR="$SCRIPT_DIR/logs/cross-compile-godot-raspberry-pi"
readonly LOG_FILE="$LOG_DIR/$(date +%F-%T).log"

readonly GODOT_AUDIO_FIX_FILE="drivers/alsa/audio_driver_alsa.cpp"
readonly GODOT_VHACD_ICHULL_FIX_FILE="thirdparty/vhacd/inc/vhacdICHull.h"


# Variables #####################################

GODOT_SOURCE_FILES_DIR="$SCRIPT_DIR/godot"
GODOT_TOOLCHAIN_ARM_BASE_URL="https://github.com/godotengine/buildroot/releases/download/godot-2023.08.x-4"
GODOT_TOOLCHAIN_ARM_BITS="32"
GODOT_TOOLCHAIN_ARM_32_NAME="arm-godot-linux-gnueabihf"
GODOT_TOOLCHAIN_ARM_64_NAME="aarch64-godot-linux-gnu"
GODOT_TOOLCHAIN_ARM_32_DIR="$SCRIPT_DIR/${GODOT_TOOLCHAIN_ARM_32_NAME}_sdk-buildroot"
GODOT_TOOLCHAIN_ARM_64_DIR="$SCRIPT_DIR/${GODOT_TOOLCHAIN_ARM_64_NAME}_sdk-buildroot"
GODOT_TOOLCHAIN_ARM_DIR="$GODOT_TOOLCHAIN_ARM_32_DIR"
GODOT_TOOLCHAIN_ARM_NAME="$GODOT_TOOLCHAIN_ARM_32_NAME"
GODOT_COMPILED_BINARIES_DIR="$SCRIPT_DIR/compiled-binaries"
GODOT_VERSIONS=""
GODOT_COMMITS=""
RASPBERRY_PI_VERSIONS=""
BINARIES=""
SCONS_JOBS="1"
USE_LTO="no"
PACK="no"

GCC_VERBOSE="yes"
VERSIONS_SUFFIX="-stable"

CCFLAGS=""
GODOT_TOOLS=""
GODOT_TARGET=""
GODOT_PLATFORM=""
GODOT_BINARY_NAME=""
PACK_DIR=""

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
    echo "ERROR: '$1' is missing an argument." >&2
    echo "Try '$0 --help' for more info." >&2
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


function get_config() {
  local config
  config="$(grep -Po "(?<=^$1 = ).*" "$SCRIPT_CFG")"
  config="${config%\"}"
  config="${config#\"}"
  echo "$config"
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
      if [[ "$config_name" == "GODOT_TOOLCHAIN_BITS" ]]; then
        if [[ "$config_param" == "32" ]]; then
          GODOT_TOOLCHAIN_ARM_DIR="$GODOT_TOOLCHAIN_ARM_32_DIR"
          GODOT_TOOLCHAIN_ARM_NAME="$GODOT_TOOLCHAIN_ARM_32_NAME"
        fi

        if [[ "$config_param" =~ "64" ]]; then
          GODOT_TOOLCHAIN_ARM_DIR="$GODOT_TOOLCHAIN_ARM_64_DIR"
          GODOT_TOOLCHAIN_ARM_NAME="$GODOT_TOOLCHAIN_ARM_64_NAME"
        fi

        GODOT_TOOLCHAIN_ARM_BITS="$config_param"
      fi

      if [[ "$config_name" == "SCONS_JOBS" ]] && [[ "$config_param" == "all" ]]; then
        config_param="$(nproc)"
      fi

      if [[ "$config_name" == "GODOT_VERSIONS" ]]; then
        local temp_array="$config_param"
        local temp_config_param

        # Convert a string separated by blank spaces to an array.
        IFS=" " read -r -a temp_array <<< "${temp_array[@]}"
        for version in "${temp_array[@]}"; do
          if [[ "$version" != "master" ]]; then
            # Append the necessary suffix "-stable" if it's not present.
            if ! [[ "$version" =~ "$VERSIONS_SUFFIX" ]]; then
              version+="$VERSIONS_SUFFIX"
            fi
          fi
          temp_config_param+="$version " # Note the trailing blank space!
        done

        config_param="$temp_config_param"

        # Remove trailing blank space.
        config_param="$(echo "$config_param" | sed 's/ *$//g')"
      fi

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
  remove_audio_fix
  remove_vhacdICHull_fix

  log >&2
  log "Cancelled by user." >&2
  exit 1
}


function apply_audio_fix() {
  # Apply audio fix. See https://github.com/godotengine/godot/pull/43928.
  if [[ "$godot_version" != "master" ]] && [[ "$(version "$godot_version")" -lt "$(version 3.2.4-stable)" ]]; then
    sed -i "s/uint8_t/int16_t/gi" "$GODOT_SOURCE_FILES_DIR/$GODOT_AUDIO_FIX_FILE"
  fi
}


function remove_audio_fix() {
  # Revert the audio fix to prevent git issues.
  if [[ "$godot_version" != "master" ]] && [[ "$(version "$godot_version")" -lt "$(version 3.2.4-stable)" ]]; then
    sed -i "s/int16_t/uint8_t/gi" "$GODOT_SOURCE_FILES_DIR/$GODOT_AUDIO_FIX_FILE"
  fi
}


function apply_vhacdICHull_fix() {
  if [[ ! -f "$GODOT_SOURCE_FILES_DIR/$GODOT_VHACD_ICHULL_FIX_FILE" ]]; then
    return 1
  fi

  # We need to add the 'include' manually for versions lower than 3.5.1.
  # It seems it has to do with the newer versions of gcc that the new toolchains use.
  if [[ "$godot_version" != "master" ]] && [[ "$(version "$godot_version")" -lt "$(version 3.5.1-stable)" ]]; then
    if ! grep -q "#include <cstdint>" "$GODOT_SOURCE_FILES_DIR/$GODOT_VHACD_ICHULL_FIX_FILE"; then
      sed -i '/^#include/{ :a; n; /^#include/ba; i\#include <cstdint>
}' "$GODOT_SOURCE_FILES_DIR/$GODOT_VHACD_ICHULL_FIX_FILE"
    fi
  fi
}

function remove_vhacdICHull_fix() {
  if [[ ! -f "$GODOT_SOURCE_FILES_DIR/$GODOT_VHACD_ICHULL_FIX_FILE" ]]; then
    return 1
  fi

  if [[ "$godot_version" != "master" ]] && [[ "$(version "$godot_version")" -lt "$(version 3.5.1-stable)" ]]; then
    if grep -q "#include <cstdint>" "$GODOT_SOURCE_FILES_DIR/$GODOT_VHACD_ICHULL_FIX_FILE"; then
      sed -i '/#include <cstdint>/d' "$GODOT_SOURCE_FILES_DIR/$GODOT_VHACD_ICHULL_FIX_FILE"
    fi
  fi
}

function get_options() {
  if [[ -z "$1" ]]; then
    usage
    exit 0
  fi

  while [[ -n "$1" ]]; do
    case "$1" in
#H -h, --help                          Prints the help message.
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
#H -v, --version                       Prints the script version.
      -v|--version)
        echo "$SCRIPT_VERSION"
        exit 0
        ;;
#H -gt, --get-tags                     Prints the Godot tags from GitHub available to be compiled.
      -gt|--get-tags)
        curl -sL https://api.github.com/repos/godotengine/godot/tags | jq -r ".[].name" | grep -E '^[3-9].[1-9]'
        exit 0
        ;;
#H -gj, --get-jobs                     Prints the number of available jobs/CPUs.
      -gj|--get-jobs)
        nproc
        exit 0
        ;;
#H -d, --download [file] [path]        Downloads the Godot source files or the Godot toolchain.
#H                                        File: "godot-source-files" or "godot-toolchain-arm-[32|64]".
#H                                        Path (optional): Path to the directory where the files will be stored.
#H                                        Default path: Same folder as this script.
      -d|--download)
        check_argument "$1" "$2" || exit 1
        local option="$1"
        shift

        if [[ "$1" != "godot-source-files" ]] && [[ "$1" != "godot-toolchain-arm-32" ]] && [[ "$1" != "godot-toolchain-arm-64" ]]; then
          echo "ERROR: Argument for '$option' ('"$1"') must be 'godot-source-files' or 'godot-toolchain-arm-[32|64]'." >&2
          exit 1
        fi

        if [[ "$1" == "godot-source-files" ]]; then
          if [[ -n "$2" ]]; then
            GODOT_SOURCE_FILES_DIR="$2"
            set_config "godot_source_files_dir" "$GODOT_SOURCE_FILES_DIR"
          fi

          git clone https://github.com/godotengine/godot.git "$GODOT_SOURCE_FILES_DIR"
        fi

        if [[ "$1" =~ "godot-toolchain-arm" ]]; then
          if [[ "$1" =~ "32" ]]; then
            if [[ -n "$2" ]]; then
              GODOT_TOOLCHAIN_ARM_32_DIR="$2"
              set_config "godot_toolchain_dir" "$GODOT_TOOLCHAIN_ARM_32_DIR"
            fi

            GODOT_TOOLCHAIN_ARM_DIR="$GODOT_TOOLCHAIN_ARM_32_DIR"
            GODOT_TOOLCHAIN_ARM_NAME="$GODOT_TOOLCHAIN_ARM_32_NAME"
          fi

          if [[ "$1" =~ "64" ]]; then
            if [[ -n "$2" ]]; then
              GODOT_TOOLCHAIN_ARM_64_DIR="$2"
              set_config "godot_toolchain_dir" "$GODOT_TOOLCHAIN_ARM_64_DIR"
            fi

            GODOT_TOOLCHAIN_ARM_DIR="$GODOT_TOOLCHAIN_ARM_64_DIR"
            GODOT_TOOLCHAIN_ARM_NAME="$GODOT_TOOLCHAIN_ARM_64_NAME"
          fi

          wget -P "$GODOT_TOOLCHAIN_ARM_DIR" -q --show-progress "$GODOT_TOOLCHAIN_ARM_BASE_URL"/"${GODOT_TOOLCHAIN_ARM_NAME}"_sdk-buildroot.tar.bz2
          tar -xvf "$GODOT_TOOLCHAIN_ARM_DIR"/"${GODOT_TOOLCHAIN_ARM_NAME}"_sdk-buildroot.tar.bz2 --strip-components 1 -C "$GODOT_TOOLCHAIN_ARM_DIR"
          rm "$GODOT_TOOLCHAIN_ARM_DIR"/"${GODOT_TOOLCHAIN_ARM_NAME}"_sdk-buildroot.tar.bz2
          "$GODOT_TOOLCHAIN_ARM_DIR"/relocate-sdk.sh
        fi

        exit 0
        ;;
#H -sd, --source-dir [path]            Sets the Godot source files directory.
#H                                        Default: "./godot".
      -sd|--source-dir)
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
#H -tb, --toolchain-bits [bits]        Sets the Godot toolchain bits.
#H                                        Bits: "32 64".
#H                                        Default: "32".
      -tb|--toolchain-bits)
        check_argument "$1" "$2" || exit 1
        local option="$1"
        shift

        for bits in $1; do
          if [[ "$bits" != "32" ]] && [[ "$bits" != "64" ]]; then
            echo "ERROR: The number for '$option' ('$bits') must be 32 or 64." >&2
            exit 1
          fi
        done

        GODOT_TOOLCHAIN_ARM_BITS="$1"

        set_config "godot_toolchain_bits" "$GODOT_TOOLCHAIN_ARM_BITS"
        ;;
#H -td, --toolchain-dir [path]         Sets the Godot toolchain directory.
#H                                        Default: "./arm-godot-linux-gnueabihf_sdk-buildroot".
      -td|--toolchain-dir)
        check_argument "$1" "$2" || exit 1
        local option="$1"
        shift

        if ! [[ -d "$1" ]]; then
          echo "ERROR: The folder for '$option' ('$1') doesn't exist." >&2
          exit 1
        fi

        GODOT_TOOLCHAIN_ARM_DIR="$1"
        set_config "godot_toolchain_dir" "$GODOT_TOOLCHAIN_ARM_DIR"
        ;;
#H -bd, --binaries-dir [path]          Sets the Godot compiled binaries directory.
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
#H -gv, --godot-versions [version(s)]   Sets the Godot version(s) to compile.
#H                                        Version(s): Use '--get-tags' to see the available versions.
#H                                        Version(s) must end with the suffix "-stable", except for "master".
      -gv|--godot-versions)
        check_argument "$1" "$2" || exit 1
        shift

        local temp_array="$1"

        # Convert a string separated by blank spaces to an array.
        IFS=" " read -r -a temp_array <<< "${temp_array[@]}"
        for version in "${temp_array[@]}"; do
          if [[ "$version" != "master" ]]; then
            # Append the necessary suffix "-stable" if it's not present.
            if ! [[ "$version" =~ "$VERSIONS_SUFFIX" ]]; then
              version+="$VERSIONS_SUFFIX"
            fi
          fi
          GODOT_VERSIONS+="$version " # Note the trailing blank space!
        done

        # Remove trailing blank space.
        GODOT_VERSIONS="$(echo "$GODOT_VERSIONS" | sed 's/ *$//g')"

        set_config "godot_versions" "$GODOT_VERSIONS"
        ;;
#H -gc, --godot-commits [commit(s)]     Sets the Godot commit(s) to compile.
#H                                        Commit(s): SHA-1 hashes.
      -gc|--godot-commits)
        check_argument "$1" "$2" || exit 1
        shift

        GODOT_COMMITS="$1"

        set_config "godot_commits" "$GODOT_COMMITS"
        ;;
#H -rv, --rpi-versions [version(s)]     Sets the Raspberry Pi version(s) to compile.
#H                                        Version(s): "3 4 5 portable".
      -rv|--rpi-versions)
        check_argument "$1" "$2" || exit 1
        shift

        RASPBERRY_PI_VERSIONS="$1"

        set_config "raspberry_pi_versions" "$RASPBERRY_PI_VERSIONS"
        ;;
#H -b, --binaries [binary type(s)]      Sets the different types of Godot binaries to compile.
#H                                        Binary type(s): "editor export-template headless server".
      -b|--binaries)
        check_argument "$1" "$2" || exit 1
        shift

        BINARIES="$1"

        set_config "binaries" "$BINARIES"
        ;;
#H -j, --scons-jobs [number|string]    Sets the jobs (CPUs) to use in SCons.
#H                                        Number: "1-∞".
#H                                        String: "all" (use all the available CPUs).
#H                                        Default: "1".
      -j|--scons-jobs)
        check_argument "$1" "$2" || exit 1
        local option="$1"
        shift

        if [[ "$1" == "all" ]]; then
          SCONS_JOBS="$(nproc)"
        elif [[ "$1" =~ ^[0-9]+$ ]]; then
          SCONS_JOBS="$1"
        else
          echo "ERROR: Argument for '$option' ('"$1"') must be a number or 'all'." >&2
          exit 1
        fi

        set_config "scons_jobs" "$SCONS_JOBS"
        ;;
#H -L, --use-lto                       Enables Link Time Optimization (LTO).
      -L|--use-lto)
        USE_LTO="yes"
        set_config "use_lto" "$USE_LTO"
        ;;
#H -P, --pack                          Packs all the binaries of the same Godot version and the same Raspberry Pi version.
      -P|--pack)
        PACK="yes"
        set_config "pack" "$PACK"
        ;;
#H -a, --auto                          Starts compilation using the settings from the config file.
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

  # Check for mandatory arguments.
  local errors=0

  log >&2

  if [[ -z "$GODOT_VERSIONS" ]] && [[ -z "$GODOT_COMMITS" ]]; then
    log "ERROR: At least one version of Godot or one commit must be set to compile." >&2
    ((errors+=1))
  fi

  if [[ -z "$BINARIES" ]]; then
    log "ERROR: At least one type of Godot binary must be set to compile." >&2
    ((errors+=1))
  fi

  if [[ -z "$RASPBERRY_PI_VERSIONS" ]]; then
    log "ERROR: At least one version of Raspberry Pi must be set to compile." >&2
    ((errors+=1))
  fi

  log >&2

  if [[ "$errors" -gt 0 ]]; then
    log "Use '$0 --help' to see all the options." >&2
    exit 1
  fi

  log
  log "----------"
  log "Godot source files directory: \"$GODOT_SOURCE_FILES_DIR\""
  log "Godot toolchain bits: \"$GODOT_TOOLCHAIN_ARM_BITS\""
  log "Godot toolchain directory: \"$GODOT_TOOLCHAIN_ARM_DIR\""
  log "Godot compiled binaries directory: \"$GODOT_COMPILED_BINARIES_DIR\""
  log "Godot version(s) to compile: \"$GODOT_VERSIONS\""
  log "Godot commit(s) to compile: \"$GODOT_COMMITS\""
  log "Binaries to compile: \"$BINARIES\""
  log "Raspberry Pi version(s) to compile: \"$RASPBERRY_PI_VERSIONS\""
  log "SCons jobs: \"$SCONS_JOBS\""
  log "Use LTO: \"$USE_LTO\""
  log "Pack: \"$PACK\""
  log "----------"
  log

  cd "$GODOT_SOURCE_FILES_DIR"

  echo "Fetching Godot source files..."
  git fetch --quiet

  if [[ -n "$(git status --porcelain)" ]]; then
      git status
      exit 1
  else
      git pull --dry-run
      if ! [[ "$?" -eq 0 ]]; then
        echo "Updating Godot source files..."
        git pull
      fi
  fi

  mkdir -p "$GODOT_COMPILED_BINARIES_DIR"

  # Concatenate versions and commits.
  GODOT_VERSIONS+=("$GODOT_COMMITS")

  IFS=" " read -r -a GODOT_TOOLCHAIN_ARM_BITS <<< "${GODOT_TOOLCHAIN_ARM_BITS[@]}"
  for toolchain_bits in "${GODOT_TOOLCHAIN_ARM_BITS[@]}"; do
    case "$toolchain_bits" in
      32)
        GODOT_TOOLCHAIN_ARM_DIR="$GODOT_TOOLCHAIN_ARM_32_DIR"
        GODOT_TOOLCHAIN_ARM_NAME="$GODOT_TOOLCHAIN_ARM_32_NAME"
        GODOT_TOOLCHAIN_ARM_BITS="32"
        ;;
      64)
        GODOT_TOOLCHAIN_ARM_DIR="$GODOT_TOOLCHAIN_ARM_64_DIR"
        GODOT_TOOLCHAIN_ARM_NAME="$GODOT_TOOLCHAIN_ARM_64_NAME"
        GODOT_TOOLCHAIN_ARM_BITS="64"
        ;;
    esac

    IFS=" " read -r -a RASPBERRY_PI_VERSIONS <<< "${RASPBERRY_PI_VERSIONS[@]}"
    for rpi_version in "${RASPBERRY_PI_VERSIONS[@]}"; do
      case "$rpi_version" in
        3)
          if [[ "$GODOT_TOOLCHAIN_ARM_BITS" == "32" ]]; then
            CCFLAGS="-mcpu=cortex-a53 -mtune=cortex-a53 -mfpu=neon-fp-armv8 -mfloat-abi=hard"
          else
            CCFLAGS="-mcpu=cortex-a53 -mtune=cortex-a53"
          fi
          ;;
        4)
          if [[ "$GODOT_TOOLCHAIN_ARM_BITS" == "32" ]]; then
            CCFLAGS="-mcpu=cortex-a72 -mtune=cortex-a72 -mfpu=neon-fp-armv8 -mfloat-abi=hard"
          else
            CCFLAGS="-mcpu=cortex-a72 -mtune=cortex-a72"
          fi
          ;;
        5)
          if [[ "$GODOT_TOOLCHAIN_ARM_BITS" == "32" ]]; then
            CCFLAGS="-mcpu=cortex-a76 -mtune=cortex-a76 -mfpu=neon-fp-armv8 -mfloat-abi=hard"
          else
            CCFLAGS="-mcpu=cortex-a76 -mtune=cortex-a76"
          fi
          ;;
        portable)
          if [[ "$GODOT_TOOLCHAIN_ARM_BITS" == "32" ]]; then
            CCFLAGS="-march=armv8-a -mfpu=neon-fp-armv8 -mfloat-abi=hard"
          else
            CCFLAGS="-march=armv8-a"
          fi
          ;;
        *)
          log "Unsupported Raspberry Pi version: $rpi_version" >&2
          log >&2
          continue
          ;;
      esac

      local rpi_suffix="$rpi_version"

      if [[ "$rpi_version" == "portable" ]]; then
        rpi_suffix="_portable"
      fi

      # Disable all gcc output (+ warnings and notes).
      if [[ "$GCC_VERBOSE" == "no" ]]; then
        CCFLAGS+=" -w -fcompare-debug-second"
      fi

      IFS=" " read -r -a GODOT_VERSIONS <<< "${GODOT_VERSIONS[@]}"
      for godot_version in "${GODOT_VERSIONS[@]}"; do
        cd "$GODOT_SOURCE_FILES_DIR"

        git checkout --quiet "$godot_version"
        if ! [[ "$?" -eq 0 ]]; then
          log "ERROR: Something went wrong when checking out to '$godot_version'." >&2
          log >&2
          exit 1
        fi

        apply_audio_fix
        apply_vhacdICHull_fix

        # Create a folder to pack all the binaries of the same Godot version and the same Raspberry Pi version.
        if [[ "$PACK" == "yes" ]]; then
          PACK_DIR="$GODOT_COMPILED_BINARIES_DIR/godot_${godot_version}_rpi${rpi_suffix}_${GODOT_TOOLCHAIN_ARM_BITS}"
          mkdir -p "$PACK_DIR"
        fi

        # As of Godot 4.0, the Linux platform changed from "x11" to "linuxbsd".
        local godot_platform
        if [[ "$(version "$godot_version")" -ge "$(version 4.0-stable)" ]] || [[ "$godot_version" == "master" ]]; then
          godot_platform="linuxbsd"
        else
          godot_platform="x11"
        fi

        IFS=" " read -r -a BINARIES <<< "${BINARIES[@]}"
        for binary_type in "${BINARIES[@]}"; do
          case "$binary_type" in
            "editor")
              GODOT_TOOLS="yes"
              GODOT_TARGET="release_debug"
              if [[ "$(version "$godot_version")" -ge "$(version 4.0-stable)" ]] || [[ "$godot_version" == "master" ]]; then
                GODOT_TARGET="editor"
              fi
              GODOT_PLATFORM="$godot_platform"
              GODOT_BINARY_NAME="godot.${godot_platform}.opt.tools.64"
              ;;
            "export-template")
              GODOT_TOOLS="no"
              GODOT_TARGET="release"
              GODOT_PLATFORM="$godot_platform"
              GODOT_BINARY_NAME="godot.${godot_platform}.opt.64"
              ;;
            "headless")
              GODOT_TOOLS="yes"
              GODOT_TARGET="release_debug"
              GODOT_PLATFORM="server"
              GODOT_BINARY_NAME="godot_server.${godot_platform}.opt.tools.64"
              ;;
            "server")
              GODOT_TOOLS="no"
              GODOT_TARGET="release"
              GODOT_PLATFORM="server"
              GODOT_BINARY_NAME="godot_server.${godot_platform}.opt.64"
              ;;
          esac

          log "$(underline "GODOT '${binary_type^^}' ('$godot_version') FOR THE RASPBERRY PI '$rpi_version' ('$GODOT_TOOLCHAIN_ARM_BITS bits')")"

          cd "$GODOT_SOURCE_FILES_DIR"

          log ">> Cleaning SCons ..."
          scons \
          -j"$SCONS_JOBS" \
          builtin_freetype=yes \
          --clean platform="$GODOT_PLATFORM" tools="$GODOT_TOOLS" target="$GODOT_TARGET"
          if ! [[ "$?" -eq 0 ]]; then
            log "ERROR: Something went wrong when cleaning generated files for the '$GODOT_PLATFORM' platform." >&2
            log >&2
            remove_audio_fix
            remove_vhacdICHull_fix
            continue
          fi
          log "> Done!"

          local lto_option
          if [[ "$godot_version" != "master" ]] && [[ "$(version "$godot_version")" -lt "$(version 3.6-stable)" ]]; then
            lto_option="use_lto=$USE_LTO"
          else
            if [[ "$USE_LTO" == "yes" ]]; then
              lto_option="lto=full"
            else
              lto_option="lto=none"
            fi
          fi

          log ">> Compiling Godot ..."
          PATH="$GODOT_TOOLCHAIN_ARM_DIR"/bin/:$PATH \
          scons \
          -j"$SCONS_JOBS" \
          platform="$GODOT_PLATFORM" \
          tools="$GODOT_TOOLS" \
          target="$GODOT_TARGET" \
          builtin_freetype=yes \
          "$lto_option" \
          use_static_cpp=yes \
          CCFLAGS="$CCFLAGS" \
          CC="$GODOT_TOOLCHAIN_ARM_NAME"-gcc \
          CXX="$GODOT_TOOLCHAIN_ARM_NAME"-g++ \
          module_denoise_enabled=no module_raycast_enabled=no module_webm_enabled=no module_theora_enabled=no
          if ! [[ "$?" -eq 0 ]]; then
            log "ERROR: Something went wrong when compiling Godot." >&2
            log >&2
            remove_audio_fix
            remove_vhacdICHull_fix
            continue
          fi
          log "> Done!"

          cd "$GODOT_SOURCE_FILES_DIR/bin"

          local binary_name
          if [[ "$USE_LTO" == "yes" ]]; then
            binary_name="godot_${godot_version}_rpi${rpi_suffix}_${GODOT_TOOLCHAIN_ARM_BITS}_${binary_type}_lto"
          else
            binary_name="godot_${godot_version}_rpi${rpi_suffix}_${GODOT_TOOLCHAIN_ARM_BITS}_${binary_type}"
          fi

          log ">> Moving '$GODOT_BINARY_NAME' to '$GODOT_COMPILED_BINARIES_DIR' ..."
          log ">> Renaming '$GODOT_BINARY_NAME' to '$binary_name.bin' ..."
          mv "$GODOT_BINARY_NAME" "$GODOT_COMPILED_BINARIES_DIR/$binary_name.bin"
          if ! [[ "$?" -eq 0 ]]; then
            log "ERROR: Something went wrong when moving or renaming '$GODOT_BINARY_NAME'." >&2
            log >&2
            remove_audio_fix
            remove_vhacdICHull_fix
            continue
          fi
          log "> Done!"

          log ">> Stripping debug symbols for '$binary_name.bin' ..."
          "$GODOT_TOOLCHAIN_ARM_DIR"/bin/"$GODOT_TOOLCHAIN_ARM_NAME"-strip "$GODOT_COMPILED_BINARIES_DIR/$binary_name.bin"
          if ! [[ "$?" -eq 0 ]]; then
            log "ERROR: Something went wrong when stripping the debug symbols of '$binary_name.bin'." >&2
            log >&2
            remove_audio_fix
            remove_vhacdICHull_fix
          else
            log "> Done!"
          fi

          # Prepare the binaries of the same Godot version and the same Raspberry Pi version to be packed.
          if [[ "$PACK" == "yes" ]]; then
            mv "$GODOT_COMPILED_BINARIES_DIR/$binary_name.bin" "$PACK_DIR"
          # Zip each binary separately.
          else
            log ">> Compressing '$binary_name.bin' ..."
            zip -j "$GODOT_COMPILED_BINARIES_DIR/$binary_name.zip" "$GODOT_COMPILED_BINARIES_DIR/$binary_name.bin"
            if [[ "$?" -eq 0 ]]; then
              rm "$GODOT_COMPILED_BINARIES_DIR/$binary_name.bin"
              log "> Done!"
              log
              log "You can find it at '$GODOT_COMPILED_BINARIES_DIR/$binary_name.zip'."
            else
              log "ERROR: Something went wrong when compressing '$binary_name.bin'." >&2
              log >&2
              remove_audio_fix
              remove_vhacdICHull_fix
            fi
          fi

          log
          log "The Godot '$binary_type' ('$godot_version') for the Raspberry Pi '$rpi_version' ('$GODOT_TOOLCHAIN_ARM_BITS bits') was compiled successfully!"
          log
        done

        # Pack all the binaries of the same Godot version and the same Raspberry Pi version (if the folder is not empty).
        if [[ "$PACK" == "yes" ]] && [[ "$(ls -A $PACK_DIR)" ]]; then
          log "##################################################"
          log
          log ">> Packing all the binaries for Godot '$godot_version' and the Raspberry Pi '$rpi_version' ..."
          zip -j -r "$PACK_DIR.zip" "$PACK_DIR"
          if [[ "$?" -eq 0 ]]; then
            rm -rf "$PACK_DIR"
            log "> Done!"
            log
            log "You can find them at '$PACK_DIR.zip'."
            log
            log "##################################################"
          else
            log "ERROR: Something went wrong when packing the binaries for Godot '$godot_version' and the Raspberry Pi '$rpi_version'." >&2
          fi

          log
        fi

        remove_audio_fix
        remove_vhacdICHull_fix
      done
    done
  done
}

main "$@"
