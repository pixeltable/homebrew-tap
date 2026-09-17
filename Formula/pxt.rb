# typed: false
# frozen_string_literal: true

class Pxt < Formula
  include Language::Python::Virtualenv

  desc "Declarative AI data infrastructure and application framework CLI"
  homepage "https://pixeltable.com"
  url "https://files.pythonhosted.org/packages/72/b7/2280764e0f6f68964827a077850dce2f453da520c7ff1f948381d863e848/pixeltable-0.7.8-py3-none-any.whl"
  sha256 "4b6a4faf1e634a22e842da15802f768e9117dd1904a8b896b06f750232af4435"
  license "Apache-2.0"
  head "https://github.com/pixeltable/pixeltable.git", branch: "main"

  livecheck do
    url :stable
    strategy :pypi
  end

  depends_on "python@3.12"

  def preserve_rpath?
    true
  end

  def install
    virtualenv_create(libexec, "python3.12")

    wheel = Dir["*.whl"].first
    if wheel.nil?
      wheel = buildpath/"pixeltable-#{version}-py3-none-any.whl"
      cp cached_download, wheel
    end

    system "python3.12", "-m", "pip",
           "--python=#{libexec}/bin/python",
           "install",
           "--no-warn-script-location",
           "--prefer-binary",
           "#{wheel}[serve]"

    # Pre-compiled Python wheels (psycopg_binary, PIL, etc.) contain vendored dylibs with
    # /DLC/ IDs. Change their IDs to @rpath to fit within Mach-O headers and preserve them
    # during Homebrew's relocation phase. Use File::FNM_DOTMATCH to traverse hidden .dylibs.
    Pathname.glob(libexec/"**/*.dylib", File::FNM_DOTMATCH).each do |dylib|
      next if dylib.symlink?

      chmod 0644, dylib
      quiet_system "/usr/bin/install_name_tool", "-id", "@rpath/#{dylib.basename}", dylib.to_s
      quiet_system "/usr/bin/codesign", "-f", "-s", "-", dylib.to_s
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

      If you prefer running pxt via dedicated Python tool runners:
        uv tool install "pixeltable[serve]"
        pipx install "pixeltable[serve]"
    EOS
  end

  test do
    ENV["PIXELTABLE_HOME"] = (testpath/".pixeltable").to_s
    ENV["PXT_PORT"] = "22099"

    assert_match version.to_s, shell_output("#{bin}/pxt --version")
    assert_match "usage: pxt", shell_output("#{bin}/pxt --help")

    system bin/"pxt", "init"
    assert_path_exists testpath/"pixeltable.toml"

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
