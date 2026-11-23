# Chromasurf — reTerminal DM CM4

<img src="assets/images/reterminal-dm.jpg" alt="Seeed Studio reTerminal DM" width="480">

<sub>Image: © [Seeed Studio](https://wiki.seeedstudio.com/reterminal-dm/)</sub>

**Chromasurf** is an industrial IoT platform built on [Elixir](https://elixir-lang.org) and [Nerves](https://nerves-project.org), developed by [Formrausch](https://formrausch.com). It provides the firmware foundation for connected HMI terminals, gateways, and sensor nodes — with automatic network clustering, over-the-air updates, real-time messaging, and full hardware abstraction built in. Designed for production use in manufacturing, process control, and industrial automation.

This repository contains the Nerves base system image for the [Seeed Studio reTerminal DM](https://wiki.seeedstudio.com/reterminal-dm/) (CM4, aarch64). It includes the Linux kernel, bootloader, 10.1" DSI display and Goodix touch drivers, audio codec, CAN bus, and all hardware support needed to run Chromasurf applications on this device. Built on `nerves_system_br` (Buildroot) with WPE WebKit/Cog browser and GPU acceleration (Mesa V3D).

## Using

Add the system as a dependency in your Nerves app and set `MIX_TARGET=reterminal_dm_cm4`:

```elixir
# mix.exs
{:reterminal_dm_cm4, github: "chromasurf/reterminal_dm_cm4", runtime: false, targets: :reterminal_dm_cm4}
```

```bash
export MIX_TARGET=reterminal_dm_cm4
mix deps.get
mix firmware
mix burn
```

The system ships Erlang/OTP 29 — your application needs Elixir ≥ 1.20. When using NervesKey/ATECC608A, depend on `nerves_key_pkcs11 ~> 1.3`.

## Hardware Overview

| Peripheral | Chip | Bus | Address | sysfs / Device |
|---|---|---|---|---|
| DSI display | GJX101c7 | MIPI DSI | — | 800x1280, rotate=270 |
| Touchscreen | Goodix GT9271 | I2C | 0x5D | `/dev/input/event*` |
| Audio codec | TLV320AIC3104 | I2C1 | 0x18 | ALSA card `seeed2micvoicec` |
| Light sensor | LTR-303ALS | I2C1 | 0x29 | `/sys/bus/iio/devices/iio:device0/` |
| CAN bus | MCP251XFD | SPI0 | — | `can0` (via SocketCAN) |
| USB-serial | CH34x | USB | — | `/dev/ttyUSB*` |
| RTC | PCF8563W | I2C3 | 0x51 | `/dev/rtc0` (watchdog: 120s) |
| Crypto | ATECC608A | I2C3 | 0x60 | via NervesKey library |
| GPIO expander | PCA9535 | I2C1 | 0x21 | User LED, buzzer, display power |
| EEPROM | AT24C32 + AT24C256 | I2C3 | 0x50, 0x57 | `/sys/bus/i2c/devices/` |
| TPM 2.0 | SLB9670 | SPI | — | `/dev/tpm0` |

## Sensors

### Light Sensor (LTR-303ALS)

```elixir
# Read ambient light in lux
{lux, _} =
  File.read!("/sys/bus/iio/devices/iio:device0/in_illuminance_input")
  |> String.trim()
  |> Integer.parse()
```

### CPU Temperature

```elixir
{temp, _} = File.read!("/sys/class/thermal/thermal_zone0/temp") |> Integer.parse()
temp_c = temp / 1000
```

## User Interface

### LED

One user LED via PCA9535 GPIO expander:

```elixir
File.write("/sys/class/leds/usr-led/brightness", "1")
File.write("/sys/class/leds/usr-led/brightness", "0")
```

### Buzzer

```elixir
# Beep for 100ms
File.write("/sys/class/leds/usr-buzzer/brightness", "1")
:timer.sleep(100)
File.write("/sys/class/leds/usr-buzzer/brightness", "0")
```

## Boot

`/usr/sbin/early_modules` runs as erlinit `pre_run_exec` and loads kernel
modules before the Erlang VM starts. Without it nerves_uevent coldplugs them
~1.4 s after the VM launches, one at a time, and vc4 binds only once its last
component is there. Measured on a reTerminal DM:

| | nerves_uevent only | early_modules |
|---|---|---|
| vc4 (panel) | 5.03 s | 2.97 s |
| v3d (GPU) | ~5.1 s | 3.04 s |
| `/dev/fb0` | 5.31 s | 3.38 s |

The script loads `vc4`, `pwm-bcm2835` and `i2c-mux-pinctrl` first, then every
device modalias except v3d: each driver that binds makes the kernel retry the
deferred vc4. v3d follows once `/sys/class/drm/card0` exists. vc4 and v3d
otherwise register in either order, so the panel was `card0` on some boots and
`card1` on others; with the script it is `/dev/dri/card0`.

busybox here has no sub-second `sleep`; the script waits with `read -t 0.02`
on an empty FIFO made by `mknod`.

An app that sets its own `pre_run_exec` (a splash script, for example) replaces
this one and calls `/usr/sbin/early_modules` from it; the script returns at once.
Without it nerves_uevent still loads every module, in the old order.

## Display

### DSI Configuration

The 10.1" 800x1280 DSI display is configured with 270 degree rotation. Kernel cmdline includes `video=DSI-1:800x1280@60,rotate=270`. HDMI output is disabled by default.

### Display Initialization

After a warm reboot the DSI panel may fail to come up (vc4 can leave the DSI PHY in
a bad state). If that happens, rebind the vc4-drm driver — but only after checking
that the panel is actually down, since a rebind briefly blanks a working display:

```elixir
if dsi_connected?() do
  :ok
else
  # "gpu" is the platform device the vc4-drm driver binds to.
  File.write("/sys/bus/platform/drivers/vc4-drm/unbind", "gpu")
  Process.sleep(200)
  File.write("/sys/bus/platform/drivers/vc4-drm/bind", "gpu")
  System.cmd("udevadm", ["settle", "--timeout=10"])
end

defp dsi_connected? do
  Path.wildcard("/sys/class/drm/card*-DSI-1/status")
  |> Enum.any?(&match?({:ok, "connected\n"}, File.read(&1)))
end
```

Do not use `modprobe -r vc4` for this: unloading the module takes the framebuffer —
and with it the Erlang console — down as well. A rebind re-probes every display
component without touching the module.

### Backlight

Pin 13 controls backlight via PWM. Currently pulled up to full brightness via dtoverlay.

```elixir
# Set brightness (0–255)
File.write("/sys/class/backlight/lcd_backlight/brightness", "128")

# Read current brightness
File.read!("/sys/class/backlight/lcd_backlight/brightness")
```

### Kiosk Mode (Weston + Cog)

The system includes Weston compositor and Cog WebKit browser for kiosk applications. See `examples/kiosk.ex` for a full supervisor setup. Quick start:

```elixir
# Start Weston
:os.cmd(~c"seatd &")
:os.cmd(~c"XDG_RUNTIME_DIR=/run weston -B drm &")

# Open a URL in fullscreen
:os.cmd(~c"XDG_RUNTIME_DIR=/run WAYLAND_DISPLAY=wayland-1 cog http://localhost:4000")
```

Remote WebKit Inspector is available on port 9222 when `WEBKIT_INSPECTOR_HTTP_SERVER=0.0.0.0:9222` is set.

### Rendering Performance

The system ships with four performance defaults; apps do not need to configure anything:

- **GPU painting**: `/etc/erlinit.config` sets `WEBKIT_SKIA_GPU_PAINTING_THREADS=4`, so
  WPE WebKit's Skia rasterizes on the v3d GPU instead of the CPU — roughly twice the
  frame rate when scrolling image-heavy pages. Override per launch via the `env:`
  option of the process that starts Cog.
- **CPU governor**: the kernel defaults to `performance`; `schedutil` costs frame
  deadlines under scroll load.
- **Transparent Hugepages**: enabled, which lets the v3d driver use Super Pages.
- **Malloc arenas**: `/etc/erlinit.config` sets `MALLOC_ARENA_MAX=2` for the BEAM and the
  programs it starts. With glibc's default of up to 32 arenas, a BEAM with the Emerge
  renderer settled at 380 MB RSS in a soak test instead of 190 MB.

Known limitation: content with `box-shadow` on scrolling surfaces stalls WPE 2.50's
rendering pipeline regardless of these settings — avoid soft shadows in kiosk UIs.

## Audio

TLV320AIC3104 codec with speaker and microphone support. ALSA card name: `seeed2micvoicec`.

```elixir
# List audio devices
cmd("aplay -l")

# Play a test tone
cmd("aplay -D plughw:seeed2micvoicec /usr/share/sounds/test.wav")

# Record audio
cmd("arecord -D plughw:seeed2micvoicec -f S16_LE -r 16000 -d 5 /data/recording.wav")
```

## CAN Bus

MCP251XFD controller on SPI0 with 40MHz oscillator. Available as SocketCAN interface `can0`:

```elixir
# Configure CAN bus at 500kbit/s
cmd("ip link set can0 type can bitrate 500000")
cmd("ip link set can0 up")
```

## Security

### ATECC608A

Microchip crypto co-processor at I2C3 address 0x60. Use [NervesKey](https://hex.pm/packages/nerves_key) for provisioning and certificate management:

```elixir
{:ok, i2c} = ATECC508A.Transport.I2C.init([])
info = NervesKey.default_info(i2c)
serial = info.manufacturer_sn
```

### TPM 2.0

Infineon SLB9670. Available at `/dev/tpm0`. The system includes `tpm2-pkcs11` for PKCS#11 integration.

## RTC

NXP PCF8563W at I2C3 address 0x51 with hardware watchdog (120s timeout):

```elixir
# Read hardware clock
:os.cmd(~c"hwclock -r")

# Set system time from RTC
:os.cmd(~c"hwclock -s")
```

The watchdog auto-reboots the device if not pinged within 120 seconds. Managed by the RTC driver.

## Camera

Supports official Raspberry Pi camera modules via [`libcamera`](https://libcamera.org/):

```elixir
cmd("libcamera-jpeg -n -v -o /data/test.jpeg")
```

## Crash Logging (Ramoops)

The DM includes the `ramoops` overlay for preserving crash information across reboots in DRAM via the `pstore` driver.

## Supported WiFi Devices

The onboard Raspberry Pi CM4 WiFi module (`brcmfmac` driver) is included but **disabled by default** via `dtoverlay=disable-wifi` and `dtoverlay=disable-bt` in `config.txt`. Remove these overlays to re-enable.

## Provisioning

Key-value store outside any filesystem for device identity:

```elixir
# Set serial number (persists across firmware updates)
cmd("fw_setenv nerves_serial_number 12345678")

# Or at burn time:
# NERVES_SERIAL_NUMBER=12345678 fwup firmware.fw
```

## Building the System

Prebuilt artifacts are published as GitHub releases. To build from source:

```bash
mix deps.get
mix compile
mix nerves.artifact
```

WebKit compilation is slow and memory-hungry. If the build gets OOM-killed, simply run `mix compile` again — Buildroot resumes where it left off.

## Linux Kernel

Kernel: Linux 6.18 (Raspberry Pi fork, tag `stable_20260527`)
Config: `linux-6.18.defconfig` (stripped-down for Nerves)

---

<img src="assets/images/fr_io_logo_signet_red.svg" alt="formrausch logo" height="24" align="top"> [formrausch](https://formrausch.com) /ˈfɔʁmˌʁaʊ̯ʃ/ is a creative studio uniting designers and developers to build beautiful, functional digital products.

## License

Apache-2.0
