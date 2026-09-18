#!/usr/bin/env bash
#
# Assert that every Mach-O library in the installed pxt keg carries a relocatable
# install name, and that no load command references a foreign absolute path.
#
# Homebrew rewrites any absolute dylib ID to this keg's opt path. Vendored wheel
# libraries ship IDs from the wheel builder's staging prefix (e.g. /DLC/libjpeg.9.dylib),
# and the rewritten path is long enough to overflow the Mach-O header:
#
#   install_name_tool: updated load commands do not fit in the header
#
# Formula/pxt.rb normalises those IDs to @rpath during `install`. A dependency bump can
# introduce a library the normalisation misses, so run this after `brew install` to catch
# it in CI rather than in a user's terminal. The load-command pass covers the symmetric
# case the ID pass cannot see: `otool -D` reports nothing for MH_BUNDLE extensions, but
# a bundle can still carry an absolute LC_LOAD_DYLIB into the keg that Homebrew would
# rewrite the same way.

set -euo pipefail

os_name="$(uname -s)"
if [[ "${os_name}" != "Darwin" ]]
then
  echo "Not macOS: no Mach-O install names to check."
  exit 0
fi

libexec="$(brew --prefix pixeltable/tap/pxt)/libexec"
if [[ ! -d "${libexec}" ]]
then
  echo "error: ${libexec} not found. Install the formula first." >&2
  exit 1
fi

checked=0
bad=0

brew_prefix="$(brew --prefix)"

while IFS= read -r -d '' file
do
  checked=$((checked + 1))
  while IFS= read -r install_name
  do
    case "${install_name}" in
      @rpath/* | /usr/lib/swift/*)
        continue
        ;;
      *)
        echo "non-relocatable install name: ${install_name}"
        echo "                          in: ${file#"${libexec}"/}"
        bad=$((bad + 1))
        ;;
    esac
  done < <(otool -D "${file}" 2>/dev/null | tail -n +2 | grep -v ':$' | grep -v '^[[:space:]]*$' || true)

  # Load commands: flag any absolute reference that is not a system path and not
  # already inside the Homebrew prefix (the opt-path form the relocator writes).
  while IFS= read -r load_name
  do
    case "${load_name}" in
      @* | /usr/lib/* | /System/* | "${brew_prefix}"/* | "")
        continue
        ;;
      /*)
        echo "non-relocatable load command: ${load_name}"
        echo "                        in: ${file#"${libexec}"/}"
        bad=$((bad + 1))
        ;;
      *)
        ;;
    esac
  done < <(otool -L "${file}" 2>/dev/null | tail -n +2 | grep -v ':$' | grep -v '^[[:space:]]*$' | awk '{print $1}' || true)
done < <(find "${libexec}" \( -name '*.dylib' -o -name '*.so' \) -type f -print0 || true)

# A silent `find` failure would otherwise read as a clean pass.
if [[ "${checked}" -eq 0 ]]
then
  echo "error: found no Mach-O files under ${libexec}; the search failed." >&2
  exit 1
fi

echo "Checked ${checked} Mach-O files under ${libexec}."

if [[ "${bad}" -ne 0 ]]
then
  cat >&2 <<'MSG'

error: the names above would be rewritten to long opt paths by Homebrew and overflow
the Mach-O header. Widen the normalisation in Formula/pxt.rb to cover them (-id for
install names, -change for load commands).
MSG
  exit 1
fi

echo "All install names and load commands are relocatable. Relocation is safe."
