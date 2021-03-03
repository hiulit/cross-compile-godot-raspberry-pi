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
# - Godot dependecies to compile for Linux (https://docs.godotengine.org/en/stable/development/compiling/compiling_for_x11.html)
# - Godot toolchain to cross-compile for ARM (https://download.tuxfamily.org/godotengine/toolchains/linux/arm-godot-linux-gnueabihf_sdk-buildroot.tar.bz2) (can be downloaded with this script)
#
# Dependencies
# - curl
# - libfreetype-dev (only to compile versions "3.1-stable" and "3.1.1-stable")
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
# - Only supports cross-compilation for "32 bit" binaries.
# - Can't compile Godot "2.x" because it requires "gcc < 6" and the toolchain only has "gcc 10.2".
# - Godot "3.1-stable" and "3.1.1-stable" need an extra dependency ("libfreetype-dev") to be able to be compiled.
#
# Other limitations:
#
# - Raspberry Pi versions "0", "1" and "2" can't be compiled using Link Time Optimization (LTO)


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


# Variables #####################################

GODOT_SOURCE_FILES_DIR="$SCRIPT_DIR/godot"
GODOT_TOOLCHAIN_DIR="$SCRIPT_DIR/arm-godot-linux-gnueabihf_sdk-buildroot"
GODOT_COMPILED_BINARIES_DIR="$SCRIPT_DIR/compiled-binaries"
GODOT_VERSIONS=""
GODOT_COMMITS=""
RASPBERRY_PI_VERSIONS=""
BINARIES=""
SCONS_JOBS="1"
USE_LTO="no"

GCC_VERBOSE="yes"

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

  log >&2
  log "Cancelled by user." >&2
  exit 1
}


function apply_audio_fix() {
  # Apply audio fix. See https://github.com/godotengine/godot/pull/43928.
  if [[ "$(version "$godot_version")" -lt "$(version 3.2.4-stable)" ]]; then
    sed -i "s/uint8_t/int16_t/gi" "$GODOT_SOURCE_FILES_DIR/$GODOT_AUDIO_FIX_FILE"
    # if [[ "$?" -eq 0 ]]; then
    #   echo "Audio fix applied."
    # fi
  fi
}


function remove_audio_fix() {
  # Revert the audio fix to prevent git issues.
  if [[ "$(version "$godot_version")" -lt "$(version 3.2.4-stable)" ]]; then
    sed -i "s/int16_t/uint8_t/gi" "$GODOT_SOURCE_FILES_DIR/$GODOT_AUDIO_FIX_FILE"
    # if [[ "$?" -eq 0 ]]; then
    #   echo "Audio fix removed."
    # fi
  fi
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
#H -gt, --get-tags                      Prints the Godot tags from GitHub available to be compiled.
      -gt|--get-tags)
        curl -sL https://api.github.com/repos/godotengine/godot/tags | jq -r ".[].name" | grep -E '^[3-9].[1-9]'
        exit 0
        ;;
#H -gj, --get-jobs                      Prints the number of available jobs/CPUs.
      -gj|--get-jobs)
        nproc
        exit 0
        ;;
#H -d, --download [file] [path]         Downloads the Godot source files or the Godot toolchain.
#H                                        File: "godot-source-files" or "godot-toolchain".
#H                                        Path (optional): Path to the directory where the files will be stored.
#H                                        Default path: Same folder as this script.
      -d|--download)
        check_argument "$1" "$2" || exit 1
        local option="$1"
        shift

        if [[ "$1" != "godot-source-files" ]] && [[ "$1" != "godot-toolchain" ]]; then
          echo "ERROR: Argument for '$option' ('"$1"') must be 'godot-source-files' or 'godot-toolchain'." >&2
          exit 1
        fi

        if [[ "$1" == "godot-source-files" ]]; then
          if [[ -n "$2" ]]; then
            GODOT_SOURCE_FILES_DIR="$2"
            set_config "godot_source_files_dir" "$GODOT_SOURCE_FILES_DIR"
          fi

          git clone https://github.com/godotengine/godot.git "$GODOT_SOURCE_FILES_DIR"
        fi

        if [[ "$1" == "godot-toolchain" ]]; then
          if [[ -n "$2" ]]; then
            GODOT_TOOLCHAIN_DIR="$2"
            set_config "godot_toolchain_dir" "$GODOT_TOOLCHAIN_DIR"
          fi

          wget -P "$GODOT_TOOLCHAIN_DIR" -q --show-progress https://download.tuxfamily.org/godotengine/toolchains/linux/arm-godot-linux-gnueabihf_sdk-buildroot.tar.bz2
          tar -xvf "$GODOT_TOOLCHAIN_DIR"/arm-godot-linux-gnueabihf_sdk-buildroot.tar.bz2 --strip-components 1 -C "$GODOT_TOOLCHAIN_DIR"
          rm "$GODOT_TOOLCHAIN_DIR"/arm-godot-linux-gnueabihf_sdk-buildroot.tar.bz2
          "$GODOT_TOOLCHAIN_DIR"/relocate-sdk.sh
        fi

        exit 0
        ;;
#H -sd, --source-dir [path]             Sets the Godot source files directory.
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
#H -td, --toolchain-dir [path]          Sets the Godot toolchain directory.
#H                                        Default: "./arm-godot-linux-gnueabihf_sdk-buildroot".
      -td|--toolchain-dir)
        check_argument "$1" "$2" || exit 1
        local option="$1"
        shift

        if ! [[ -d "$1" ]]; then
          echo "ERROR: The folder for '$option' ('$1') doesn't exist." >&2
          exit 1
        fi

        GODOT_TOOLCHAIN_DIR="$1"
        set_config "godot_toolchain_dir" "$GODOT_TOOLCHAIN_DIR"
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
#H -gv, --godot-versions [version/s]    Sets the Godot version/s to compile.
#H                                        Version/s: Use '--get-tags' to see the available versions.
#H                                        Version/s must end with the suffix "-stable", except for "master".
      -gv|--godot-versions)
        check_argument "$1" "$2" || exit 1
        shift

        local temp_array="$1"
        local suffix="-stable"

        # Convert a string separated by blank spaces to an array.
        IFS=" " read -r -a temp_array <<< "${temp_array[@]}"
        for version in "${temp_array[@]}"; do
          if [[ "$version" != "master" ]]; then
            # Append the necessary suffix "-stable" if it's not present.
            if ! [[ "$version" =~ "$suffix" ]]; then
              version+="$suffix " # Note the trailing blank space.
            fi
          fi
          GODOT_VERSIONS+="$version"
        done

        # Remove trailing blank space.
        GODOT_VERSIONS="$(echo "$GODOT_VERSIONS" | sed 's/ *$//g')"

        set_config "godot_versions" "$GODOT_VERSIONS"
        ;;
#H -gc, --godot-commits [commit/s]      Sets the Godot commit/s to compile.
#H                                        Commit/s: SHA-1 hash/es.
      -gc|--godot-commits)
        check_argument "$1" "$2" || exit 1
        shift

        GODOT_COMMITS="$1"

        set_config "godot_commits" "$GODOT_COMMITS"
        ;;
#H -rv, --rpi-versions [version/s]      Sets the Raspberry Pi version/s to compile.
#H                                        Version/s: "0 1 2 3 4".
      -rv|--rpi-versions)
        check_argument "$1" "$2" || exit 1
        shift

        RASPBERRY_PI_VERSIONS="$1"

        set_config "raspberry_pi_versions" "$RASPBERRY_PI_VERSIONS"
        ;;
#H -b, --binaries [binary type/s]       Sets the different types of Godot binaries to compile.
#H                                        Binary type/s: "editor export-template headless server".
      -b|--binaries)
        check_argument "$1" "$2" || exit 1
        shift

        BINARIES="$1"

        set_config "binaries" "$BINARIES"
        ;;
#H -j, --scons-jobs [number|string]     Sets the jobs (CPUs) to use in SCons.
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
#H -l, --use-lto [option]               Enables using Link Time Optimization (LTO) when compiling.
#H                                        Options: "yes" or "no".
#H                                        Default: "no".
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

  # Check for mandatory arguments.
  local errors=0

  if [[ -z "$GODOT_VERSIONS" ]] && [[ -z "$GODOT_COMMITS" ]]; then
    log >&2
    log "ERROR: At least one version of Godot or one commit must be set to compile." >&2
    ((errors+=1))
  fi

  if [[ -z "$BINARIES" ]]; then
    log >&2
    log "ERROR: At least one type of Godot binary must be set to compile." >&2
    ((errors+=1))
  fi

  if [[ -z "$RASPBERRY_PI_VERSIONS" ]]; then
    log >&2
    log "ERROR: At least one version of Raspberry Pi must be set to compile." >&2
    ((errors+=1))
  fi

  if [[ "$errors" -gt 0 ]]; then
    log >&2
    log "Use '$0 --help' to see all the options." >&2
    exit 1
  fi

  log
  log "----------"
  log "Godot source files directory: $GODOT_SOURCE_FILES_DIR"
  log "Godot toolchain directory: $GODOT_TOOLCHAIN_DIR"
  log "Godot compiled binaries directory: $GODOT_COMPILED_BINARIES_DIR"
  log "Godot version/s to compile: $GODOT_VERSIONS"
  log "Godot commit/s to compile: $GODOT_COMMITS"
  log "Binaries to compile: $BINARIES"
  log "Raspberry Pi version/s to compile: $RASPBERRY_PI_VERSIONS"
  log "SCons jobs: $SCONS_JOBS"
  log "Use LTO: $USE_LTO"
  log "----------"
  log

  mkdir -p "$GODOT_COMPILED_BINARIES_DIR"

  # Concatenate versions and commits.
  GODOT_VERSIONS+=("$GODOT_COMMITS")

  IFS=" " read -r -a RASPBERRY_PI_VERSIONS <<< "${RASPBERRY_PI_VERSIONS[@]}"
  for rpi_version in "${RASPBERRY_PI_VERSIONS[@]}"; do
    case "$rpi_version" in
      0|1)
        CCFLAGS="-mcpu=arm1176jzf-s -mtune=arm1176jzf-s -mfpu=vfp -mfloat-abi=hard -mlittle-endian -munaligned-access"
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

    local use_lto="$USE_LTO"

    # Disable LTO for some Raspberry Pi versions.
    if [[ "$rpi_version" -lt 3 ]] && [[ "$USE_LTO" == "yes" ]]; then
      use_lto="no"
    fi

    if [[ "$GCC_VERBOSE" == "no" ]]; then
      # Disable warnings and notes.
      CCFLAGS+=" -w -fcompare-debug-second"
    fi

    IFS=" " read -r -a GODOT_VERSIONS <<< "${GODOT_VERSIONS[@]}"
    for godot_version in "${GODOT_VERSIONS[@]}"; do
      cd "$GODOT_SOURCE_FILES_DIR"

      git checkout --quiet "$godot_version"
      if ! [[ "$?" -eq 0 ]]; then
        log "ERROR: Something went wrong when checking out to '$godot_version'." >&2
        continue
      fi

      apply_audio_fix

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
            GODOT_PLATFORM="$godot_platform"
            GODOT_BINARY_NAME="godot.$GODOT_PLATFORM.opt.tools.64"
            ;;
          "export-template")
            GODOT_TOOLS="no"
            GODOT_TARGET="release"
            GODOT_PLATFORM="$godot_platform"
            GODOT_BINARY_NAME="godot.$GODOT_PLATFORM.opt.64"
            ;;
          "headless")
            GODOT_TOOLS="yes"
            GODOT_TARGET="release_debug"
            GODOT_PLATFORM="server"
            GODOT_BINARY_NAME="godot_server.$GODOT_PLATFORM.opt.tools.64"
            ;;
          "server")
            GODOT_TOOLS="no"
            GODOT_TARGET="release"
            GODOT_PLATFORM="server"
            GODOT_BINARY_NAME="godot_server.$GODOT_PLATFORM.opt.64"
            ;;
        esac

        log "$(underline "GODOT '${binary_type^^}' ('$godot_version') FOR THE RASPBERRY PI '$rpi_version'")"

        cd "$GODOT_SOURCE_FILES_DIR"

        log ">> Cleaning SCons ..."
        scons --clean platform="$GODOT_PLATFORM" tools="$GODOT_TOOLS" target="$GODOT_TARGET"
        if ! [[ "$?" -eq 0 ]]; then
          log "ERROR: Something went wrong when cleaning generated files for the '$GODOT_PLATFORM' platform." >&2
          remove_audio_fix
          continue
        fi
        log "> Done!"

        log ">> Compiling Godot ..."
        PATH="$GODOT_TOOLCHAIN_DIR"/bin/:$PATH \
        scons \
        -j"$SCONS_JOBS" \
        platform="$GODOT_PLATFORM" \
        tools="$GODOT_TOOLS" \
        target="$GODOT_TARGET" \
        use_lto="$use_lto" \
        use_static_cpp=yes \
        CCFLAGS="$CCFLAGS" \
        CC=arm-godot-linux-gnueabihf-gcc \
        CXX=arm-godot-linux-gnueabihf-g++ \
        module_denoise_enabled=no module_raycast_enabled=no module_webm_enabled=no module_theora_enabled=no
        if ! [[ "$?" -eq 0 ]]; then
          log "ERROR: Something went wrong when compiling Godot." >&2
          remove_audio_fix
          continue
        fi
        log "> Done!"

        cd "$GODOT_SOURCE_FILES_DIR/bin"

        local binary_name

        if [[ "$use_lto" == "yes" ]]; then
          binary_name="godot_${godot_version}_rpi${rpi_version}_${binary_type}_lto"
        else
          binary_name="godot_${godot_version}_rpi${rpi_version}_${binary_type}"
        fi

        log ">> Moving '$GODOT_BINARY_NAME' to '$GODOT_COMPILED_BINARIES_DIR' ..."
        log ">> Renaming '$GODOT_BINARY_NAME' to '$binary_name.bin' ..."
        mv "$GODOT_BINARY_NAME" "$GODOT_COMPILED_BINARIES_DIR/$binary_name.bin"
        if ! [[ "$?" -eq 0 ]]; then
          log "ERROR: Something went wrong when moving or renaming '$GODOT_BINARY_NAME'." >&2
          remove_audio_fix
          continue
        fi
        log "> Done!"

        log ">> Stripping debug symbols for '$binary_name.bin' ..."
        "$GODOT_TOOLCHAIN_DIR"/bin/arm-godot-linux-gnueabihf-strip "$GODOT_COMPILED_BINARIES_DIR/$binary_name.bin"
        if ! [[ "$?" -eq 0 ]]; then
          log "ERROR: Something went wrong when stripping the debug symbols of '$binary_name.bin'." >&2
          remove_audio_fix
        else
        log "> Done!"
        fi

        log ">> Compressing '$binary_name.bin' ..."
        zip -j "$GODOT_COMPILED_BINARIES_DIR/$binary_name.zip" "$GODOT_COMPILED_BINARIES_DIR/$binary_name.bin"
        if [[ "$?" -eq 0 ]]; then
          rm "$GODOT_COMPILED_BINARIES_DIR/$binary_name.bin"
          log "> Done!"
        else
          log "ERROR: Something went wrong when compressing '$binary_name.bin'." >&2
          remove_audio_fix
        fi

        log
        log "The Godot '$binary_type' ('$godot_version') for the Raspberry Pi '$rpi_version' was compiled successfully!"
        log
        log "You can find it at '$GODOT_COMPILED_BINARIES_DIR/$binary_name.zip'."
        log
      done

      remove_audio_fix
    done
  done
}

main "$@"
