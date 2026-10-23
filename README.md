# bazel-linux

A Bazel workspace for the [okLinux](https://github.com/sevki/okLinux) kernel,
generated nightly.

[`bazelify.yml`](.github/workflows/bazelify.yml) clones ChromeOS's
`chromeos-6.6` kernel, configures it exactly as okLinux's `build.sh` does,
and runs [makers-bazel-plugin](https://github.com/sevki/makers-bazel-plugin)
in `mode=kbuild` over it. The plugin runs inside Kbuild's own makes (as a dry
run of `vmlinux bzImage`) and writes `MODULE.bazel`, a `BUILD.bazel` with a
`//:kernel` target, and `kbuild/*.bzl` with one Bazel action per Kbuild target.
The job then runs `bazel build //:kernel` on the result, so the files it
proposes are ones that built.

Only the generated files are committed, to [`oklinux/`](oklinux) on the branch
`bazelify/chromeos-6.6`; the job opens (or updates) a pull request from that
branch against `main`, and does nothing if `oklinux/` is already current.
`oklinux/KERNEL` records the kernel commit and plugin revision they were
generated from.

## Use the files

Copy `oklinux/` over a checkout of the kernel commit named in `oklinux/KERNEL`:

```sh
git clone https://chromium.googlesource.com/chromiumos/third_party/kernel kernel
git -C kernel checkout <commit from oklinux/KERNEL>
cp -r oklinux/. kernel/
cd kernel
bazel build //:kernel   # vmlinux, arch/x86/boot/bzImage
```

The kernel must be configured as okLinux configures it (see below): the
actions assume the `.config` and the generated headers that `make prepare`
writes, which `scripts/bazelify.sh` produces.

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
Pull requests that touch the workflow or `scripts/` run the whole pipeline and
attach the generated files as an artifact instead of opening a pull request.
The job needs `contents: write` and `pull-requests: write`, and the repository
setting "Allow GitHub Actions to create and approve pull requests".
