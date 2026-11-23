defmodule Monitor.OS.KioskDrm do
  @moduledoc """
  Runs Cog directly on KMS/DRM, without Weston. Scrolling on the reTerminal DM panel: ~56 fps, 40 fps
  with Weston (`kiosk.ex`). For an on-screen keyboard or other Wayland surfaces next to the browser, use
  the Weston setup.

  Notes:

    * Platform, rotation and `XDG_RUNTIME_DIR` come from `/etc/erlinit.config`, the touch matrix for
      `rotation=3` from `/etc/udev/rules.d/99-touchscreen.rules`. See README, "Rotation and Touch", for
      another rotation.
    * `video=HDMI-A-1:d` in the kernel command line switches off the HDMI port that
      `vc4.force_hotplug=1` reports as connected, so Cog takes DSI-1.
    * Touch reports arrive at ~96 Hz (median interval 10.3 ms, SYN_REPORT timestamps at /dev/input).
      The rate comes from the retuned GT9271 config in rootfs_overlay/lib/firmware/goodix_9271_cfg.bin
      (BitFreq 6600 Hz, drive factors 27/25), dtparam=i2c_vc_baudrate=400000 in config.txt and the
      spurious-interrupt patch under linux/. The factory config scanned for 23.3 ms (~43 Hz).

  Quick start without a supervisor (IEx):

      :os.cmd(~c"cog http://localhost:4000")
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(opts) do
    children = [cog(opts[:url] || "http://localhost:4000")]
    Supervisor.init(children, strategy: :one_for_one)
  end

  def cog(url) do
    Supervisor.child_spec(
      {MuonTrap.Daemon,
       [
         "cog",
         ["--bg-color=#cad6d2ff", url],
         # The system environment (/etc/erlinit.config) reaches Cog through the BEAM's; entries here
         # override it.
         [env: [{"WEBKIT_INSPECTOR_HTTP_SERVER", "0.0.0.0:9222"}]]
       ]},
      id: Monitor.OS.KioskDrm.Cog,
      restart: :permanent
    )
  end
end
