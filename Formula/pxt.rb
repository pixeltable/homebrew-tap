# typed: false
# frozen_string_literal: true

class Pxt < Formula
  include Language::Python::Virtualenv

  desc "Declarative AI data infrastructure and application framework CLI"
  homepage "https://pixeltable.com"
  url "https://files.pythonhosted.org/packages/c7/a6/fe0620022c77dd5841f972852c631cdd623373b7c483d7ec008f09f61ebb/pixeltable-0.7.9-py3-none-any.whl"
  sha256 "1ef0a671b17be8f91cb07b9f773611f7637254eba502c1cbcb6d12824c6d1771"
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

  # Homebrew's cleaner deletes every dist-info RECORD and stamps INSTALLER=brew so pip
  # cannot touch keg-managed packages. pxt-pip exists precisely so users can add
  # packages to this virtualenv, and without RECORD pip aborts any install that must
  # upgrade or replace one of the ~90 packages the formula ships
  # ("uninstall-no-record-file"). Keep pip's metadata for the whole site dir.
  #
  # The `skip_clean` DSL is not enough: the cleaner walks `prefix.realpath`, but
  # `skip_clean?` compares `relative_path_from(prefix)`, and once the keg is opt-linked
  # (every `brew reinstall`) `prefix` is the opt symlink, so the relative path starts
  # with `../` and never matches. Compare real paths so it holds on reinstall too.
  def skip_clean?(path)
    site_packages = prefix.realpath/"libexec/lib/python3.12/site-packages"
    return true if path.realpath.to_s.start_with?(site_packages.to_s)

    super
  end

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

    # A stable name for the virtualenv's pip so optional packages have one
    # documented install path: `pxt-pip install openai`. The opt path is not
    # version-pathed, so the command survives upgrades and reinstalls.
    (bin/"pxt-pip").write <<~EOS
      #!/bin/sh
      exec "#{opt_libexec}/bin/python" -m pip "$@"
    EOS
    chmod 0755, bin/"pxt-pip"
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

      Optional AI features need extra packages in pxt's virtualenv:
        pxt-pip install openai        # pxt.functions.openai
        pxt-pip install tiktoken      # token counting in document_splitter
        pxt-pip install spacy         # document_splitter(separators="sentence")
        pxt-pip install scenedetect   # pxt.functions.video scene detection
      spaCy also needs a language model, e.g.:
        #{opt_libexec}/bin/python -m spacy download en_core_web_sm
      pxt-pip can also upgrade or replace packages the formula installed. If pxt
      stops working after such a change, `brew reinstall pixeltable/tap/pxt` resets
      the environment. Extras land inside the formula's keg, so `brew reinstall` or
      an upgrade removes them; re-run `pxt-pip install` afterwards.

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

    # Optional-package installs are documented via the generated shim; it must exec
    # the keg's virtualenv python through the stable opt path.
    assert_match "pip", shell_output("#{bin}/pxt-pip --version")

    # pxt-pip can only upgrade or replace formula-installed packages if their pip
    # RECORD survived Homebrew's cleaner (see skip_clean? above).
    site_packages = libexec/"lib/python3.12/site-packages"
    dist_info = Pathname(Dir[site_packages/"pixeltable-*.dist-info"].first)
    assert_path_exists dist_info/"RECORD"

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
