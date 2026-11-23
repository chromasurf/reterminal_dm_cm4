defmodule ReterminalDmCm4.MixProject do
  use Mix.Project

  @github_organization "chromasurf"
  @app :reterminal_dm_cm4
  @source_url "https://github.com/#{@github_organization}/#{@app}"
  @version Path.join(__DIR__, "VERSION")
           |> File.read!()
           |> String.trim()

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.17",
      compilers: Mix.compilers() ++ [:nerves_package],
      nerves_package: nerves_package(),
      description: description(),
      package: package(),
      deps: deps(),
      aliases: [
        compile: [&generate_fwup_conf/1, "compile"],
        generate_fwup_conf: &generate_fwup_conf/1
      ],
      docs: docs()
    ]
  end

  def cli do
    [
      preferred_envs: %{docs: :docs, "hex.build": :docs, "hex.publish": :docs},
      default_target: :target
    ]
  end

  def application do
    []
  end

  defp nerves_package do
    [
      type: :system,
      artifact_sites: [
        {:github_releases, "#{@github_organization}/#{@app}"}
      ],
      # 8 jobs keep ~9 concurrent WebCore TUs (2-4 GB each) within the VM's RAM.
      # At -j13 on a 32 GB host the compiler was OOM-killed.
      build_runner_config: [cpus: 8, memory: :host],
      build_runner_opts: build_runner_opts(),
      platform: Nerves.System.BR,
      platform_config: [
        defconfig: "nerves_defconfig"
      ],
      # The :env key is an optional experimental feature for adding environment
      # variables to the crosscompile environment. These are intended for
      # llvm-based tooling that may need more precise processor information.
      env: [
        {"TARGET_ARCH", "aarch64"},
        {"TARGET_CPU", "cortex_a72"},
        {"TARGET_OS", "linux"},
        {"TARGET_ABI", "gnu"},
        {"TARGET_GCC_FLAGS",
         "-mabi=lp64 -fstack-protector-strong -mcpu=cortex-a72 -fPIE -pie -Wl,-z,now -Wl,-z,relro"}
      ],
      checksum: source_finger_print_files()
    ]
  end

  defp deps do
    [
      {:nerves, "~> 1.15 or ~> 2.0 or ~> 2.0.0-dev", runtime: false},
      {:nerves_system_br, "1.35.3", runtime: false},
      {:nerves_toolchain_aarch64_nerves_linux_gnu, "~> 15.3.1", runtime: false},
      {:nerves_system_linter, "~> 0.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.22", only: :docs, runtime: false}
    ]
  end

  defp description do
    "Chromasurf Nerves System — reTerminal DM (CM4, aarch64)"
  end

  defp docs do
    [
      extras: ["README.md", "CHANGELOG.md"],
      main: "readme",
      assets: %{"assets" => "./assets"},
      source_ref: "v#{@version}",
      source_url: @source_url,
      skip_undefined_reference_warnings_on: ["CHANGELOG.md"]
    ]
  end

  defp package do
    [
      files: package_files(),
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp package_files do
    ["fwup.conf" | source_finger_print_files()]
  end

  # fwup.conf is rendered from fwup.conf.eex, so the checksum covers only the template.
  defp source_finger_print_files do
    [
      "app.txt",
      "config/config.exs",
      "fwup_include",
      "package",
      "rootfs_overlay",
      "CHANGELOG.md",
      "cmdline-a.txt",
      "cmdline-b.txt",
      "config.txt",
      "fwup-ops.conf",
      "fwup_include/fwup-common.conf",
      "fwup_include/provisioning.conf",
      "fwup.conf.eex",
      "LICENSE",
      "linux",
      "linux-6.18.defconfig",
      "mix.exs",
      "nerves_defconfig",
      "patches",
      "Config.in",
      "busybox_defconfig",
      "post-build.sh",
      "post-createfs.sh",
      "ramoops-pi4-overlay.dts",
      "README.md",
      "VERSION"
    ]
  end

  defp build_runner_opts() do
    # Download source files first to get download errors right away.
    [make_args: primary_site() ++ ["source", "all", "legal-info"]]
  end

  defp primary_site() do
    case System.get_env("BR2_PRIMARY_SITE") do
      nil -> []
      primary_site -> ["BR2_PRIMARY_SITE=#{primary_site}"]
    end
  end

  defp generate_fwup_conf(_args) do
    template_path = Path.join(__DIR__, "fwup.conf.eex")
    output_path = Path.join(__DIR__, "fwup.conf")

    content = EEx.eval_file(template_path)

    # The build VM has no Elixir, so fwup.conf is rendered on the host before every build.
    if File.read(output_path) != {:ok, content} do
      File.write!(output_path, content)
      Mix.shell().info("Generated #{output_path}")
    end
  end
end
