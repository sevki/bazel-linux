# bazel-linux

A Bazel workspace for the [okLinux](https://github.com/sevki/okLinux) kernel,
generated nightly.

[`bazelify.yml`](.github/workflows/bazelify.yml) clones ChromeOS's
`chromeos-6.6` kernel, configures it exactly as okLinux's `build.sh` does,
and runs [makers-bazel-plugin](https://github.com/sevki/makers-bazel-plugin)
in `mode=kbuild` over it. The plugin runs inside Kbuild's own makes (as a dry
run of `vmlinux bzImage`) and writes `MODULE.bazel`, a `BUILD.bazel` with a
`//:kernel` target, and `kbuild/*.bzl` with one Bazel action per Kbuild target.
The job then runs `bazel build //:kernel` on
the result, so a published tree is one that built, and attaches the workspace
as a release (`bazel-kernel-<release>-<sha>`) along with the `bzImage` it
produced. A release already exists for a kernel commit? The job stops there.

## Use a release

```sh
tar --zstd -xf oklinux-kernel-bazel-*.tar.zst
cd oklinux-kernel-bazel-*
bazel build //:kernel --action_env=PATH   # vmlinux, arch/x86/boot/bzImage
```

Every object, archive and link step is its own Bazel action, so a source change
rebuilds only what depends on it.

## Generate one locally

```sh
git clone --depth 1 -b chromeos-6.6 \
  https://chromium.googlesource.com/chromiumos/third_party/kernel kernel
git clone https://github.com/sevki/okLinux
MAKERS_MAKE=/path/to/makers/make \
  scripts/bazelify.sh kernel okLinux /path/to/makers_bazel_plugin.wasm
```

`MAKERS_MAKE` is a makers `make` built with `--features wasmtime`; the plugin is
built with `cargo component build --release --features kbuild`. The
configuration comes from okLinux's `build.sh` (its `prepareconfig`,
`scripts/config` and `make olddefconfig` lines are replayed), so changing the
config there changes it here.

## Triggers

Daily cron and manual dispatch (`force` republishes an existing kernel;
`plugin_ref` builds another plugin ref). Pull requests that touch the workflow
or `scripts/` run the whole pipeline and attach the workspace as an artifact
instead of releasing.
