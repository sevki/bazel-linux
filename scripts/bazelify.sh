#!/usr/bin/env bash
# Turn a ChromeOS kernel checkout into a Bazel workspace, using the
# makers-bazel-plugin in `mode=kbuild`: the plugin runs inside Kbuild's own
# makes and writes a Bazel action per file.
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
# The plugin needs a prepared tree: generated headers that already exist are
# inputs, not rules.
(cd "$kernel" && "$makers_make" -j"$(nproc)" prepare >/dev/null)

# The plugin runs as a dry run of the real goals. A dry run still executes a
# recipe line that starts a make, and two of those are not wanted here:
#   * the `vmlinux` link (scripts/link-vmlinux.sh) would really link, and
#     needs every object; it is stubbed for the run and restored after. Kbuild
#     runs `fixdep` on the link's dependency file right after it, so the stub
#     leaves a minimal one. It also starts the one make the real script does
#     (`init/version-timestamp.o`, which writes include/generated/utsversion.h
#     for arch/x86/boot's version.o), so the plugin sees that make's rules;
#   * `vmlinux.o` and `.vmlinux.export.o` are built by recipes that start
#     makes of their own; a MAKEFILES stand-in gives them empty rules.
# The stand-in is itself a makefile every make reads, so the plugin is told to
# skip it when it works out which run it is in (`skip-makefiles`).
standin=$(mktemp)
trap 'rm -f "$standin"; [ -f "$kernel/scripts/link-vmlinux.sh.orig" ] && mv "$kernel/scripts/link-vmlinux.sh.orig" "$kernel/scripts/link-vmlinux.sh"' EXIT
printf '%%:\n\t@:\nvmlinux.o .vmlinux.export.o:\n' >"$standin"
mv "$kernel/scripts/link-vmlinux.sh" "$kernel/scripts/link-vmlinux.sh.orig"
printf '#!/bin/sh\necho "vmlinux: Makefile" > .vmlinux.d\n"${MAKE}" -f "${srctree}/scripts/Makefile.build" obj=init init/version-timestamp.o\n' >"$kernel/scripts/link-vmlinux.sh"
# The plugin works out which variables a script reads by reading it, and it
# reads this stand-in; the real script, as comments, tells it the rest.
sed 's/^/# /' "$kernel/scripts/link-vmlinux.sh.orig" >>"$kernel/scripts/link-vmlinux.sh"
chmod +x "$kernel/scripts/link-vmlinux.sh"

goals='vmlinux bzImage'
# The plugin's registry of makes is appended to by each make; start clean.
rm -rf "$kernel/kbuild" "$kernel/BUILD.bazel" "$kernel/MODULE.bazel"
(
  cd "$kernel"
  MAKEFILES="$standin" \
  MAKERS_PLUGIN_VERBOSE=1 \
  MAKERS_PLUGIN_ALLOW='bazel:expand-variables,read-file-content,read-environment' \
  MAKERS_PLUGINS="bazel=$plugin" \
  MAKERS_PLUGIN_ARGS="bazel:mode=kbuild;bazel:name=kernel;bazel:outs=vmlinux,arch/x86/boot/bzImage;bazel:goals=$goals;bazel:out.build-files=$kernel;bazel:skip-makefiles=$standin;bazel:fuel=${PLUGIN_FUEL:-20000000000}" \
    "$makers_make" -n $goals >/dev/null
  test -f MODULE.bazel && test -f BUILD.bazel && test -f kbuild/rules.bzl
  # What the stubbed link left behind is not a build product.
  rm -f .vmlinux.d .vmlinux.cmd
)
echo "bazelified: $kernel"
