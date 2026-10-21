#!/usr/bin/env bash
# Turn a ChromeOS kernel checkout into a Bazel workspace, using the
# makers-bazel-plugin in `mode=wrap`.
#
#   bazelify.sh <kernel-dir> <okLinux-dir> <plugin.wasm>
#
# The kernel configuration is okLinux's own: the `prepareconfig`,
# `scripts/config` and `make olddefconfig` lines are lifted out of
# <okLinux-dir>/build.sh and replayed here, so the two cannot drift. `make`
# must be makers' build with the plugin host (`--features wasmtime`); set
# MAKERS_MAKE to its path (default: `make`).
set -euo pipefail

kernel=$(realpath "${1:?usage: bazelify.sh <kernel-dir> <okLinux-dir> <plugin.wasm>}")
oklinux=$(realpath "${2:?missing okLinux dir}")
plugin=$(realpath "${3:?missing plugin.wasm}")
makers_make=${MAKERS_MAKE:-make}

# --- Configure exactly as okLinux does -------------------------------------
config_lines=$(grep -E '^(CHROMEOS_KERNEL_FAMILY=.*prepareconfig |scripts/config |make olddefconfig$)' \
  "$oklinux/build.sh" || true)
if ! grep -q prepareconfig <<<"$config_lines" || ! grep -q 'make olddefconfig' <<<"$config_lines"; then
  echo "error: could not find okLinux's kernel configuration in $oklinux/build.sh" >&2
  exit 1
fi
(cd "$kernel" && bash -euo pipefail -c "$config_lines")

# --- Generate MODULE.bazel and BUILD.bazel ----------------------------------
# `make -n help` is a goal that does not recurse, so the plugin loads once
# instead of once per Kbuild directory.
(
  cd "$kernel"
  MAKERS_PLUGIN_VERBOSE=1 \
  MAKERS_PLUGINS="bazel=$plugin" \
  MAKERS_PLUGIN_ARGS='bazel:mode=wrap;bazel:name=kernel;bazel:outs=vmlinux,arch/x86/boot/bzImage;bazel:goals=vmlinux bzImage' \
    "$makers_make" -n help >/dev/null
  test -f MODULE.bazel && test -f BUILD.bazel
)
echo "bazelified: $kernel"
