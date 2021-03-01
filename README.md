# Cross-compile Godot binaries for the Raspberry Pi

![GitHub release (latest by date)](https://img.shields.io/github/v/release/hiulit/cross-compile-godot-raspberry-pi?&style=flat-square) ![GitHub license](https://img.shields.io/github/license/hiulit/cross-compile-godot-raspberry-pi?&style=flat-square)

A script to easily cross-compile Godot binaries for the Raspberry Pi from Linux x86_64.

## Requirements:

- [Godot source files](https://github.com/godotengine/godot) (can be downloaded with this script)
- [Godot dependecies to compile for X11 Linux](https://docs.godotengine.org/en/stable/development/compiling/compiling_for_x11.html)
- [Godot toolchains to cross-compile for ARM](https://download.tuxfamily.org/godotengine/toolchains/linux/arm-godot-linux-gnueabihf_sdk-buildroot.tar.bz2) (can be downloaded with this script)
- `curl`
- `libfreetype-dev` (only to compile versions `3.1-stable` and `3.1.1-stable`)
- `git`
- `jq`
- `tar`
- `wget`
- `zip`

## Limitations

- Unable to compile Godot 2.x because it requires gcc < 6 and this toolchain only has gcc 10.2.

## 🛠️ Setup

### Install the script

```
git clone https://github.com/hiulit/cross-compile-godot-raspberry-pi.git
cd cross-compile-godot-raspberry-pi
sudo chmod +x cross-compile-godot-raspberry-pi.sh
```

### Update the script

```
cd cross-compile-godot-raspberry-pi
git pull
```

## 🚀 Usage

```
./cross-compile-godot-raspberry-pi.sh [OPTIONS]
```

If no options are passed, you will be prompted with a usage example:

```
USAGE: ./cross-compile-godot-raspberry-pi.sh [OPTIONS]

Use './cross-compile-godot-raspberry-pi.sh --help' to see all the options.
```

Log files are stored in `logs/`.

## 📖 Options

- `--help`: Prints the help message.
- `--version`: Prints the script version.
- `--get-tags`: Prints the Godot tags from GitHub available to be compiled.
- `--get-jobs`: Prints the number of available jobs/CPUs.
- `--download [file] [path]`: Downloads the Godot source files or the Godot toolchain.
  - File: `godot-source-files` or `godot-toolchain`.
  - Path (optional): Path to the directory where the files will be stored.
  - Default path: Same folder as this script.
- `--source-dir [path]`: Sets the Godot source files directory.
  - Default: Same folder as this script.
- `--toolchain-dir [path]`: Sets the Godot toolchain directory.
  - Default: Same folder as this script.
- `--binaries-dir [path]`: Sets the Godot compiled binaries directory.
  - Default: Same folder as this script.
- `--godot-versions [version/s]`: Sets the Godot version/s to be compiled.
  - Version/s: Use `--get-tags` to see the available versions.
- `--godot-commits [commit/s]`: Sets the Godot commit/s to be compiled.
  - Commit/s: SHA-1 hash/es.
- `--rpi-versions [version/s]`: Sets the Raspberry Pi version/s to compile.
  - Version/s: `0 1 2 3 4`.
- `--binaries [binary type/s]`: Sets the different types of Godot binaries to compile.
  - Binary type/s: `editor export-template headless server`.
- `--scons-jobs [number]`: Sets the jobs (CPUs) to use in SCons.
  - Number: `1-∞`.
  - Default: `1`.
- `--use-lto [option]`: Enables using Link Time Optimization (LTO) when compiling.
  - Options: `yes` or `no`.
  - Default: `no`.
- `--auto`: Starts compiling taking the settings in the [config file](#config-file).

## 💁 Examples

- Compile:
  - The Godot `editor` (version `3.2.3-stable`).
  - For the Raspberry Pi `4`.
  - Using `4` CPU cores.

```
./cross-compile-godot-raspberry-pi.sh --godot-versions "3.2.3-stable" --rpi-versions "4" --binaries "editor" --scons-jobs "4"
```

- Compile:
  - The Godot `editor` (version `3.2.3-stable`) and the `4f891b706027dc800f6949bec413f448defdd20d` commit (which is `3.2.4 RC 3`).
  - For the Raspberry Pi `4`.
  - Using `4` CPU cores.

```
./cross-compile-godot-raspberry-pi.sh --godot-versions "3.2.3-stable" --godot-commits "4f891b706027dc800f6949bec413f448defdd20d" --rpi-versions "4" --binaries "editor" --scons-jobs "4"
```

- Compile:
  - The Godot `editor` (version `3.2.3-stable`).
  - For the Raspberry Pi `3` and `4`.
  - Using `8` CPU cores.
  - With `LTO enabled`.


```
./cross-compile-godot-raspberry-pi.sh --godot-versions "3.2.3-stable" --rpi-versions "3 4" --binaries "editor" --scons-jobs "4" --use-lto "yes"
```

- Compile:
  - The Godot `editor` and the `export templates` (versions `3.1.2-stable` and `3.2.3-stable`).
  - For the Raspberry Pi `3` and `4`.
  - Using `8` CPU cores.
  - With LTO `enabled`.

```
./cross-compile-godot-raspberry-pi.sh --godot-versions "3.1.2-stable 3.2.3-stable" --rpi-versions "3 4" --binaries "editor export-template" --scons-jobs "8" --use-lto "yes"
```

- Compile:
  - The Godot `editor` and the `export templates` (versions `3.1.2-stable` and `3.2.3-stable`).
  - For the Raspberry Pi `3` and `4`.
  - Using `8` CPU cores.
  - With `LTO enabled`.
  - Where the Godot source files are located in `/path/to/the/godot/source/files`.

```
./cross-compile-godot-raspberry-pi.sh --source-dir "/path/to/the/godot/source/files" --godot-versions "3.1.2-stable 3.2.3-stable" --rpi-versions "3 4" --binaries "editor export-template" --scons-jobs "8" --use-lto "yes"
```

## Config file

You can edit this file directly, instead of passing all the options mentioned above, and then run:

```
./cross-compile-godot-raspberry-pi.sh --auto
```

```
# Settings for "cross-compile-godot-raspberry-pi.sh".

# Godot source files directory.
# Default: Same folder as this script.
godot_source_files_dir = ""

# Godot toolchain directory.
# Default: Same folder as this script.
godot_toolchain_dir = ""

# Godot compiled binaries directory.
# Default: Same folder as this script.
godot_compiled_binaries_dir = ""

# Godot version/s to be compiled (separated by blank spaces).
# Use "--get-tags" to see the available versions.
godot_versions = ""

# Godot commit/s to be compiled (separated by blank spaces).
# Commit/s: SHA-1 hash/es.
godot_commits = ""

# Raspberry Pi version/s to compile (separated by blank spaces).
# Version/s: "0 1 2 3 4".
raspberry_pi_versions = ""

# Types of Godot binaries to compile (separated by blank spaces).
# Binary type/s: "editor export-template headless server".
binaries_to_compile = ""

# Jobs (CPUs) to use in SCons.
# Number: "1-∞".
# Default: "1".
scons_jobs = ""

# Use Link Time Optimization (LTO) when compiling.
# Options: "yes" or "no".
# Default: "no".
use_lto = ""
```

## 🗒️ Changelog

See [CHANGELOG](/CHANGELOG.md).

## 👤 Author

**hiulit**

- Twitter: [@hiulit](https://twitter.com/hiulit)
- GitHub: [@hiulit](https://github.com/kefhiulitranabg)

## 🤝 Contributing

Feel free to:

- [Open an issue](https://github.com/hiulit/RetroPie-Godot-Game-Engine-Emulator/issues) if you find a bug.
- [Create a pull request](https://github.com/hiulit/RetroPie-Godot-Game-Engine-Emulator/pulls) if you have a new cool feature to add to the project.
- [Start a new discussion]() about a feature request.

## 🙌 Supporting this project

If you love this project or find it helpful, please consider supporting it through any size donations to help make it better ❤️.

[![Become a patron](https://img.shields.io/badge/Become_a_patron-ff424d?logo=Patreon&style=for-the-badge&logoColor=white)](https://www.patreon.com/hiulit)

[![Suppor me on Ko-Fi](https://img.shields.io/badge/Support_me_on_Ko--fi-F16061?logo=Ko-fi&style=for-the-badge&logoColor=white)](https://ko-fi.com/F2F7136ND)

[![Buy me a coffee](https://img.shields.io/badge/Buy_me_a_coffee-FFDD00?logo=buy-me-a-coffee&style=for-the-badge&logoColor=black)](https://www.buymeacoffee.com/hiulit)

[![Donate Paypal](https://img.shields.io/badge/PayPal-00457C?logo=PayPal&style=for-the-badge&label=Donate)](https://www.paypal.com/paypalme/hiulit)

If you can't, consider sharing it with the world...

[![](https://img.shields.io/badge/Share_on_Twitter-1DA1F2?style=for-the-badge&logo=twitter&logoColor=white)](https://twitter.com/intent/tweet?url=https%3A%2F%2Fgithub.com%2Fhiulit%2Fcross-compile-godot-raspberry-pi&text=Cross-compile+Godot+binaries+for+the+Raspberry+Pi%3A%0D%0AA+script+to+easily+cross-compile+Godot+binaries+for+the+Raspberry+Pi+from+Linux+x86_64+by+%40hiulit)

... or giving it a [star ⭐️](https://github.com/hiulit/cross-compile-godot-raspberry-pi/stargazers).

## 👏 Credits

Thanks to:

- [Hein-Pieter van Braam-Stewart](https://github.com/hpvb) - For the [Godot Engine buildroot](https://github.com/godotengine/buildroot), which is the base of this script.

## 📝 Licenses

- Source code: [MIT License](/LICENSE).
