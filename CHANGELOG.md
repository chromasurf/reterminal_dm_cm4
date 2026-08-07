# Changelog

This project does NOT follow semantic versioning. The version increases as
follows:

1. Major version updates are breaking updates to the build infrastructure.
   These should be very rare.
2. Minor version updates are made for every major Buildroot release. This
   may also include Erlang/OTP and Linux kernel updates. These are made four
   times a year shortly after the Buildroot releases.
3. Patch version updates are made for Buildroot minor releases, Erlang/OTP
   releases, and Linux kernel updates. They're also made to fix bugs and add
   features to the build infrastructure.

## v1.2.6

Fixes the web process crash around cross-site navigations. On this Mesa/fdo pair
the browser lost its compositor connection every third navigation between two
sites — long pauses, black frames, stuttering:

    wl_display#1: error 0: invalid object 12
    (WPEWebProcess:497): WPE-FDO-ERROR **: Failed to bind wl_compositor

WPEBackend-fdo offers `zwp_linux_dmabuf_v1` at version 4 but implements
`get_surface_feedback` as an empty stub, so no server-side resource exists for
the id the client allocated. Mesa 25.2 and newer use per-surface feedback and
destroy that object when a surface goes away, which makes libwayland-server post
`wl_display.error(invalid object)` — fatal for the whole connection, not just the
object. The next view target on that connection binds no `wl_compositor` and
aborts the web process.

Reproducible with bare Cog and two external sites; unrelated to any application
on top. The `vc4 swiotlb buffer is full` line that earlier notes tied to this
fires once at boot and never during navigation.

* Changes
  * `patches/wpebackend-fdo/0001-linux-dmabuf-implement-per-surface-feedback.patch`:
    answer per-surface feedback with the default feedback's tranches. The
    protocol allows it — per-surface feedback is an optimisation hint.
  * `nerves_defconfig`: `BR2_GLOBAL_PATCH_DIR` gained
    `$(NERVES_DEFCONFIG_DIR)/patches` so this system can carry patches of its
    own, as `nerves_system_sg2002` already does.
  * `mix.exs`: added `patches` to `package_files/0`, so patch-only changes
    invalidate the artifact checksum. Note that `package` and `external.mk` are
    still missing there — out-of-tree kernel module changes do not bump the
    checksum today.

See `docs/wpe-fdo-surface-feedback-crash.md` in the monorepo for the protocol
trace. The bug is still present upstream on WPEBackend-fdo `main`. Applications
carrying `--webprocess-failure=restart` as a workaround for this can revisit it.

## v1.2.5

Makes the browser fast by default. All three changes come out of profiling
`myelin_demo` scrolling on the reTerminal DM: image-heavy pages ran at ~30 fps
with the CPU rasterizing and the GPU idle; with these defaults the same pages
hold ~60 fps (p50 frame time 17 ms) and touch flicks feel fluid.

* Changes
  * `rootfs_overlay/etc/erlinit.config`: set `WEBKIT_SKIA_GPU_PAINTING_THREADS=4`
    system-wide. Without it, WPE WebKit 2.50's Skia paints on the CPU with
    `nCores/2` worker threads while the v3d GPU idles at ~2%. Every app that
    launches Cog inherits the variable through the BEAM's environment and can
    still override it per launch. Note for apps that set their own
    `config :nerves, :erlinit` overrides: Nerves merges against the system
    *source* in `deps/`, so those apps pick this default up once they depend on
    this release.
  * `linux-6.18.defconfig`: default the cpufreq governor to `performance`
    (`CONFIG_CPU_FREQ_DEFAULT_GOV_PERFORMANCE`). `schedutil` idles at 600 MHz
    and oscillates between 1.3 and 2.0 GHz under scroll load; measured p50
    frame time was 27 ms vs 17 ms with `performance`, with identical rendering
    settings — the ramp-up is what a touch flick from idle runs into. Kiosks on
    mains power have no reason to save that energy; `schedutil` remains
    available at runtime via sysfs.
  * `linux-6.18.defconfig`: enable `CONFIG_TRANSPARENT_HUGEPAGE`, which the v3d
    driver uses for Super Pages (fewer GPU-MMU TLB misses on large textures).
    The boot log's "Transparent Hugepage support is recommended" warning turns
    into "Using Transparent Hugepages".
  * `README.md`: new "Rendering Performance" section documenting the three
    defaults and a known WPE 2.50 limitation (`box-shadow` on scrolling content
    stalls the rendering pipeline regardless of settings — analysis in the
    chromasurf monorepo under `docs/wpe-box-shadow-raf-stall.md`).
    `examples/kiosk_drm.ex` notes that GPU painting needs no per-app env entry.

## v1.2.4

Makes a firmware that fails to boot say so. All three changes come out of
bringing up `myelin_demo` on this image, where a broken release was invisible
for a day because the console pointed at a display the browser had taken over.

* Changes
  * `rootfs_overlay/etc/erlinit.config`: send the IEx prompt to `ttyS0` instead
    of `tty1`. On a kiosk Cog owns the DRM device, so a prompt on `tty1` cannot
    be reached — and since everything the VM writes follows this setting, crash
    reports went there too. A firmware that died during boot was
    indistinguishable from one with a black screen. `-s /usr/bin/nbtty` now also
    matches what its own comment says it is for. Downstream can put it back with
    `config :nerves, :erlinit, ctty: "tty1"`.
  * `cmdline-a.txt` / `cmdline-b.txt`: `loglevel=0` → `loglevel=7`. At 0 even a
    kernel failure during early boot is silent, before Erlang starts and
    `nerves_logging`'s kmsg tailer can pick anything up. The kernel console is on
    `tty3`, so this does not reach the panel and the kiosk stays clean.
  * `README.md`: replace the `modprobe -r vc4` recommendation for a DSI panel
    that did not come up with a conditional `vc4-drm` unbind/bind. Unloading the
    module takes the framebuffer with it — including, by default, the one the
    Erlang console sits on — so calling it from a supervisor's `init/1` pulls the
    console out from under the VM mid-boot. Note `examples/kiosk.ex` still shows
    the modprobe cycle for the Weston setup.

## v1.2.3

Touch input fixes for the reTerminal DM (GT9271): report rate goes from
~43 Hz to ~96 Hz (median report interval 23.3 ms → 10.3 ms, measured via
evdev SYN_REPORT timestamps while swiping).

**Note on the published artifact:** the asset originally attached to the v1.2.3
release was built from a working tree with uncommitted README changes, so its
checksum (`E5674FF`) matched no published commit and consumers pinning
`tag: "v1.2.3"` could not resolve it. It was replaced with `07F6884`, built from
the tagged source. `README.md` is part of `package_files()`, so a documentation
change alone invalidates every artifact — never change it without a release.

* Changes
  * Ship `rootfs_overlay/lib/firmware/goodix_9271_cfg.bin` — a retuned
    GT9271 sensor config. The factory config scans at ~43 Hz regardless
    of the Refresh_Rate register (the scan itself took 23.3 ms). The new
    config raises Panel_BitFreq 2003 → 6600 Hz with drive-frequency
    factors reduced 88/90 → 27/25, keeping the drive frequencies in the
    panel-proven band (~170 kHz, ~400 kHz was measured to cause
    dropouts). The shorter integration (27 vs 88 carrier cycles) is
    compensated like TI's reference GT9271 config for the same panel
    class (DRA71x): Panel_Dump_Shift 3 → 4 (2× gain), touch/leave
    levels 100/70 → 80/50. Frequency-hopping window and segment factors
    are rescaled so their absolute frequencies stay unchanged. The
    factory config is kept next to it as `goodix_9271_cfg.factory.bin`
    for rollback (copy it over `goodix_9271_cfg.bin` in `/data/firmware`
    with the firmware search path pointed there, then rebind the
    driver — the controller persists whatever config it last received).
  * Kernel patch `linux/goodix_spurious_irq_fix.patch`: the mainline goodix
    driver no longer burns its 20 ms buffer-status timeout on the spurious
    interrupts the panel sends after finger-up. Those stalls halved the
    effective touch report rate (~43 Hz observed with the chip configured
    for 100 Hz).
  * `config.txt`: raise the touch bus (i2c_vc, behind the CSI/DSI mux) from
    the 100 kHz firmware default to the GT9271 datasheet maximum via
    `dtparam=i2c_vc_baudrate=400000`.
  * `config.txt`: drop the dead `tp_rotate=1` overlay parameter — the
    reTerminal-DM overlay has no `__overrides__`; touch axes come from the
    device tree / libinput calibration matrix.
  * `mix.exs`: include the `linux/` kernel patch directory in the artifact
    checksum so patch changes invalidate cached artifacts.

## v1.2.2

Build tooling — no functional changes to the image.

* Changes
  * macOS builds can now run in an Apple `container` Linux VM (no Docker or
    remote build server needed) via
    [nerves_container](https://github.com/chromasurf/nerves_container) — it is
    auto-selected on Apple Silicon and falls back to Docker otherwise. Upstream
    support is proposed in nerves-project/nerves#1190.

## v1.2.1

Documentation-only update — no functional changes to the image.

* Changes
  * README: add a device photo, correct the kernel documentation (Linux 6.18,
    `linux-6.18.defconfig`), document the OTP 29 / Elixir 1.20+ requirement,
    fix the dead Seeed wiki link, and clarify that an OOM-killed build resumes
    by re-running `mix compile`.

## v1.2.0

Minor update for a major Buildroot release: tracks `nerves_system_br` v1.34.0
and `kiosk_system_rpi4` v2.1.0, bringing a new Erlang/OTP, Linux kernel, and
toolchain.

**Breaking for downstream:** the image now ships Erlang/OTP 29, so consuming
projects must build with OTP 29 (Elixir 1.20+). Devices using a NervesKey /
ATECC608 must update `nerves_key_pkcs11` to `~> 1.3` to avoid a TLS segfault.

* Changes
  * Use Liberation fonts as the default sans-serif/serif/monospace families
    (fontconfig aliases, from `kiosk_system_rpi4` v2.1.0) — fixes rendering
    issues in WebKit.
  * Remove the `pigpio` package — dropped upstream in Buildroot 2026.05 (no
    longer maintained). Use `libgpiod` / `circuits_gpio` for GPIO.

* Updated dependencies
  * [nerves_system_br v1.34.0](https://github.com/nerves-project/nerves_system_br/releases/tag/v1.34.0)
    (Erlang/OTP 29.0.2, Buildroot 2026.05, GCC 15.3.0)
  * Linux kernel 6.18 (Raspberry Pi `stable_20260527` tag), RPi firmware 1.20260521

## v1.1.4

Security/bug fix update that tracks `nerves_system_br` v1.33.9 (up from
v1.33.4) and pulls in the relevant `kiosk_system_rpi4` v2.0.x refinements.

* Changes
  * Switch the runtime cgroup hierarchy to cgroup v2 — kernel config (PSI,
    CFS bandwidth) plus an `erlinit` `cgroup2` mount — and re-enable the memory
    controller with `cgroup_enable=memory cgroup_memory=1` on the kernel command
    line.
  * Trim unused Weston shells (fullscreen, IVI, screenshare) and the GStreamer
    WPE plugin to shrink the image; only the kiosk shell is used.
  * Enable `shared-mime-info` for WebKit web inspector support.

* Updated dependencies
  * [nerves_system_br v1.33.9](https://github.com/nerves-project/nerves_system_br/releases/tag/v1.33.9)
    (Erlang/OTP 28.5.0.1, Buildroot 2025.11.3, fwup 1.16.0, glibc 2.43
    compatibility fix, Raspberry Pi WiFi roaming patch)

## Earlier releases

Detailed notes for v1.1.3 and earlier live in the
[GitHub releases](https://github.com/chromasurf/reterminal-dm-cm4/releases):
v1.1.3, v1.1.2, v1.1.1, v1.1.0, v1.0.1, v1.0.0.
