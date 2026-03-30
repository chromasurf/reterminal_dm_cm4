# Chromasurf — reTerminal DM CM4

Custom Nerves system for the [Seeed Studio reTerminal DM](https://wiki.seeedstudio.com/reTerminal-DM-Getting-Started/) (CM4, aarch64).

Built on `nerves_system_br` (Buildroot) with WPE WebKit/Cog browser, GPU acceleration (Mesa V3D), and hardware drivers for all reTerminal DM peripherals.

## Hardware

- 10.1" 800x1280 DSI display with 270° rotation
- Capacitive touchscreen (Goodix GT9271)
- Audio codec (TLV320AIC3104) with speaker/mic
- USB-serial adapter (CH34x)
- CAN bus controller (MCP251XFD via SPI)
- Ambient light sensor (LTR-303ALS)
- RTC (PCF8563W) with hardware watchdog
- Crypto co-processor (ATECC608A)
- TPM 2.0 (Infineon SLB9670)
- EEPROM (24C32 + 24C256)
- User LED, buzzer (via PCA9535 GPIO expander)
- Camera CSI connector
- Gigabit Ethernet, WiFi/BT (disabled by default)
- Ramoops crash logging

## Usage

```bash
# In your Nerves app's mix.exs:
{:chromasurf_reterminal_dm_cm4, github: "chromasurf/reterminal-dm-cm4", runtime: false, targets: :reterminal_dm_cm4}

# Build firmware
MIX_TARGET=reterminal_dm_cm4 MIX_ENV=prod mix deps.get
MIX_TARGET=reterminal_dm_cm4 MIX_ENV=prod mix firmware
```

## Building the system

Prebuilt artifacts are published as GitHub releases. To build from source:

```bash
mix deps.get
mix compile
mix nerves.artifact
```

WebKit compilation is slow and memory-hungry — retry on OOM.

## DSI Display

The DSI display might not start by itself on some units. Forcing a modprobe cycle after udev setup helps:

```elixir
:os.cmd(~c"modprobe -r vc4")
:os.cmd(~c"modprobe vc4")
```

## Backlight

Pin 13 (backlight) is pulled up to full brightness via dtoverlay. Brightness can be controlled via hardware PWM if the overlay is disabled.

## License

Apache-2.0
