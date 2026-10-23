# bazel-linux

A Bazel workspace for the [okLinux](https://github.com/sevki/okLinux) kernel,
generated nightly.

[`bazelify.yml`](.github/workflows/bazelify.yml) clones ChromeOS's
`chromeos-6.6` kernel, configures it exactly as okLinux's `build.sh` does,
and runs [makers-bazel-plugin](https://github.com/sevki/makers-bazel-plugin)
in `mode=kbuild` over it. The plugin runs inside Kbuild's own makes (as a dry
run of `vmlinux bzImage`) and writes `MODULE.bazel`, a `BUILD.bazel` with a
`//:kernel` target, and `kbuild/*.bzl` with one Bazel action per Kbuild target.
The job then runs `bazel build //:kernel` on the result, so the tree it
proposes is one that built.

The whole tree, build files included, is committed to [`kernel/`](kernel) on a
branch named `bazelify/<release>-<kernel sha>-<plugin sha>`, and the job opens a
pull request from it against `main`. It is the tree as the build saw it: the
kernel's `.config`, the headers and host tools `make prepare` writes (they are
inputs to the Bazel actions), `BUILD.bazel`, `MODULE.bazel` and `kbuild/`. A
branch that already exists means that kernel and plugin were already proposed,
so the job pushes nothing.

## Build it

```sh
cd kernel
bazel build //:kernel   # vmlinux, arch/x86/boot/bzImage
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

Daily cron and manual dispatch (`plugin_ref` builds another plugin ref).
Pull requests that touch the workflow or `scripts/` run the generation and the
Bazel build but open no pull request. The job needs `contents: write` and
`pull-requests: write`, and the repository setting "Allow GitHub Actions to
create and approve pull requests".
