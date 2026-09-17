#!/usr/bin/env bash
#
# Assert that every Mach-O library in the installed pxt keg carries a relocatable
# install name.
#
# Homebrew rewrites any absolute dylib ID to this keg's opt path. Vendored wheel
# libraries ship IDs from the wheel builder's staging prefix (e.g. /DLC/libjpeg.9.dylib),
# and the rewritten path is long enough to overflow the Mach-O header:
#
#   install_name_tool: updated load commands do not fit in the header
#
# Formula/pxt.rb normalises those IDs to @rpath during `install`. A dependency bump can
# introduce a library the normalisation misses, so run this after `brew install` to catch
# it in CI rather than in a user's terminal.

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

error: the install names above would be rewritten to long opt paths by Homebrew and
overflow the Mach-O header. Widen the normalisation loop in Formula/pxt.rb to cover them.
MSG
  exit 1
fi

echo "All install names are @rpath-relative or system Swift. Relocation is safe."
