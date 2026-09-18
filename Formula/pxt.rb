# typed: false
# frozen_string_literal: true

class Pxt < Formula
  include Language::Python::Virtualenv

  desc "Declarative AI data infrastructure and application framework CLI"
  homepage "https://pixeltable.com"
  url "https://files.pythonhosted.org/packages/72/b7/2280764e0f6f68964827a077850dce2f453da520c7ff1f948381d863e848/pixeltable-0.7.8-py3-none-any.whl"
  sha256 "4b6a4faf1e634a22e842da15802f768e9117dd1904a8b896b06f750232af4435"
  license "Apache-2.0"

  livecheck do
    url "https://pypi.org/pypi/pixeltable/json"
    strategy :json do |json|
      json.dig("info", "version")
    end
  end

  depends_on "python@3.12"

  # `install` below rewrites vendored wheel dylib IDs to @rpath. This tells Homebrew's
  # relocator to leave those IDs alone instead of expanding them back to opt paths.
  preserve_rpath

  def install
    virtualenv_create(libexec, "python3.12")

    wheel = Dir["*.whl"].first
    if wheel.nil?
      wheel = buildpath/cached_download.basename.to_s.sub(/\A[0-9a-f]+--/, "")
      cp cached_download, wheel
    end

    system "python3.12", "-m", "pip",
           "--python=#{libexec}/bin/python",
           "install",
           "--no-warn-script-location",
           "--prefer-binary",
           "#{wheel}[serve]"

    # Pre-compiled wheels (Pillow, psycopg_binary, pyarrow) ship vendored Mach-O
    # libraries whose install names point at the wheel builder's staging prefix, e.g.
    # /DLC/libjpeg.9.dylib. Homebrew rewrites each such ID to this keg's opt path, which
    # is long enough to overflow the Mach-O header ("updated load commands do not fit in
    # the header"). Normalising the IDs to @rpath keeps them short; `preserve_rpath`
    # above then stops the relocator from touching them. Consumers already load these
    # through @loader_path, so only the ID changes.
    #
    # Match on the Mach-O type rather than the extension: maturin-built extensions are
    # dylibs named *.so, and a future wheel may ship one with an absolute ID.
    # FNM_DOTMATCH is required to reach delocate's hidden .dylibs directories.
    if OS.mac?
      Pathname.glob(libexec/"**/*.{dylib,so}", File::FNM_DOTMATCH).each do |file|
        next if file.symlink?

        macho = MachOPathname.wrap(file)
        next unless macho.dylib?

        dylib_id = macho.dylib_id
        next if dylib_id.nil? || dylib_id.start_with?("@rpath", "/usr/lib/swift")

        chmod "u+w", file
        unless quiet_system "/usr/bin/install_name_tool", "-id", "@rpath/#{file.basename}", file
          odie "install_name_tool -id failed for #{file}"
        end
        unless quiet_system "/usr/bin/codesign", "-f", "-s", "-", file
          odie "codesign failed for #{file}"
        end
      end
    end

    bin.install_symlink libexec/"bin/pxt"
  end

  def caveats
    <<~EOS
      pxt automatically manages its own background daemon (default port: 22089).
      Inspect daemon state and health at any time:
        pxt daemon status
        pxt status

      Manual daemon lifecycle controls:
        pxt daemon start
        pxt daemon stop
        pxt daemon restart

      pxt runs from a virtualenv bound to python@3.12. If pxt stops working after a
      python@3.12 upgrade or reinstall, rebuild the environment:
        brew reinstall pixeltable/tap/pxt

      If you prefer running pxt via dedicated Python tool runners:
        uv tool install "pixeltable[serve]"
        pipx install "pixeltable[serve]"
    EOS
  end

  test do
    ENV["PIXELTABLE_HOME"] = (testpath/".pixeltable").to_s
    # Never assume a fixed port: `pxt daemon stop -f` kills whatever holds it, which
    # would take out a developer's own daemon during `brew test`.
    ENV["PXT_PORT"] = free_port.to_s

    assert_match version.to_s, shell_output("#{bin}/pxt --version")
    assert_match "usage: pxt", shell_output("#{bin}/pxt --help")

    system bin/"pxt", "init"
    assert_path_exists testpath/"pixeltable.toml"

    # The [serve] extra is optional upstream but is what `pxt service` needs; the CLI
    # checks above pass without it, so assert it actually landed in the virtualenv.
    system libexec/"bin/python", "-c", "import fastapi, uvicorn"

    begin
      system bin/"pxt", "daemon", "start"
      daemon_status = shell_output("#{bin}/pxt daemon status")
      assert_match "PID", daemon_status
      assert_match "Service", daemon_status

      status_output = shell_output("#{bin}/pxt status")
      assert_match "total_tables", status_output
      assert_match "db_url", status_output
    ensure
      quiet_system bin/"pxt", "daemon", "stop", "-f"
    end
  end
end
