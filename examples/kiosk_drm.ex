defmodule Monitor.OS.KioskDrm do
  @moduledoc """
  Kiosk variant that runs Cog directly on KMS/DRM — no Weston compositor.

  Compared to the Weston setup (see `kiosk.ex`) this skips one composite
  pass per frame: measured 40 → ~56 fps scrolling on the reTerminal DM panel.
  Use the Weston variant when other Wayland surfaces must be composited
  alongside the browser (e.g. an on-screen keyboard).

  Notes:

    * The DSI panel is portrait-native (800x1280). Cog's default "modeset"
      renderer cannot rotate — the "gles" renderer rotates during its single
      fullscreen GL pass (`rotation=1` — 90° counter-clockwise).
    * Cog picks the first *connected* DRM connector. With
      `vc4.force_hotplug=1` an unplugged HDMI port still reports
      "connected" and would shadow the DSI panel, so force it off first.
    * Cog swaps the logical input size for rotated outputs but does not
      rotate the touch axes — a libinput calibration matrix (udev rule,
      written to volatile /run so a Weston boot never inherits a stale
      rule) supplies the missing input rotation. Matrices per 90°-CCW
      quarter turn: 1 → "0 1 0 -1 0 1", 2 → "-1 0 1 0 -1 1",
      3 → "0 -1 1 1 0 0".
    * udev must have enumerated input devices (see `setup_udev` in
      `kiosk.ex`) — Cog's DRM platform reads touch input via libinput.
    * Touch report rate is ~96 Hz (median interval 10.3 ms, measured at
      /dev/input via SYN_REPORT timestamps). The ~43 Hz previously noted
      here as a "hardware limit" was the factory GT9271 sensor config:
      its scan took 23.3 ms regardless of the 0x8056 refresh register.
      Fixed by the retuned config shipped in
      rootfs_overlay/lib/firmware/goodix_9271_cfg.bin (BitFreq 6600 Hz,
      drive factors 27/25, TI-style gain/threshold compensation),
      plus dtparam=i2c_vc_baudrate=400000 in config.txt and the
      spurious-interrupt patch under linux/.

  Quick start without a supervisor (IEx):

      File.write("/sys/class/drm/card0-HDMI-A-1/status", "off")
      :os.cmd(~c"XDG_RUNTIME_DIR=/run cog --platform=drm --platform-params=renderer=gles,rotation=1 http://localhost:4000")
  """
  use Supervisor

  @touch_device "Goodix Capacitive TouchScreen"

  # libinput calibration matrices per 90°-CCW quarter turn.
  @calibration_matrix %{
    1 => "0 1 0 -1 0 1",
    2 => "-1 0 1 0 -1 1",
    3 => "0 -1 1 1 0 0"
  }

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    rotation = opts[:rotation] || 1

    force_connectors_off(["HDMI-A-1", "HDMI-A-2"])
    apply_touch_rotation(rotation)

    children = [
      cog(opts[:dir], opts[:url] || "http://localhost:4000", rotation)
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  def cog(dir, url, rotation) do
    Supervisor.child_spec(
      {MuonTrap.Daemon,
       [
         "cog",
         [
           "--platform=drm",
           "--platform-params=renderer=gles,rotation=#{rotation}",
           "--bg-color=#cad6d2ff",
           url
         ],
         [
           env: [
             {"XDG_RUNTIME_DIR", "#{dir}/nerves_weston"},
             {"WEBKIT_INSPECTOR_HTTP_SERVER", "0.0.0.0:9222"}
           ]
         ]
       ]},
      id: Monitor.OS.KioskDrm.Cog,
      restart: :permanent
    )
  end

  # Force unused connectors off so Cog's first-connected pick lands on DSI-1.
  def force_connectors_off(names) do
    for name <- names,
        path <- Path.wildcard("/sys/class/drm/card*-#{name}/status") do
      File.write(path, "off")
    end
  end

  def apply_touch_rotation(rotation) do
    if matrix = @calibration_matrix[rotation] do
      rule =
        "SUBSYSTEM==\"input\", KERNEL==\"event*\", ATTRS{name}==\"#{@touch_device}\", " <>
          "ENV{LIBINPUT_CALIBRATION_MATRIX}=\"#{matrix}\"\n"

      File.mkdir_p!("/run/udev/rules.d")
      File.write!("/run/udev/rules.d/99-cog-drm-touch.rules", rule)
      System.cmd("udevadm", ["control", "--reload"])
      System.cmd("udevadm", ["trigger", "--subsystem-match=input", "--action=change"])
      System.cmd("udevadm", ["settle", "--timeout=5"])
    end

    :ok
  end
end
