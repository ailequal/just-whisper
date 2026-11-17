#!/usr/bin/env bash
# Check the local dependencies and optionally install the missing ones: scripts/deps.sh [check|install]
#   (no argument)  report, then offer to install what is missing (the question is asked only in a terminal)
#   check          report only; exit status 1 when something required is missing
#   install        report, then install what is missing without asking
#
# Homebrew is a hard requirement and is never installed here: without it the script stops. With it, the
# script can install the formulas (just, uv, cmake, ffmpeg, plus sdl2 and shellcheck as optional) and the
# Python pinned in .python-version through uv. The whisper.cpp checkout, its build and the models are the
# job of `just clone`, `just build` and `just models` (all three: `just setup`).
# Works before just is installed: scripts/deps.sh install
# shellcheck source=lib/common.sh
source "$(dirname "$0")/lib/common.sh"

mode="${1:-ask}"
case "$mode" in
  ask|check|install) ;;
  *) die "usage: scripts/deps.sh [check|install]" ;;
esac

required_formulas="just uv cmake ffmpeg"
optional_formulas="sdl2 shellcheck"
min_just="1.27"

status=0            # 1 when something required is missing
to_install=()       # Homebrew formulas to install
to_upgrade=()       # Homebrew formulas too old
python_todo=0       # 1 when the pinned Python or the .venv is missing

ok()   { printf '  ok        %-11s %s\n' "$1" "$2"; }
miss() { printf '  missing   %-11s %s\n' "$1" "$2"; }
warn() { printf '  warning   %-11s %s\n' "$1" "$2"; }

# The command that proves a formula is installed, and a one-line version for the report.
tool_command() { case "$1" in sdl2) echo sdl2-config ;; *) echo "$1" ;; esac; }
tool_version() {
  case "$1" in
    just) just --version 2>/dev/null | cut -d' ' -f2 ;;
    uv) uv --version 2>/dev/null | cut -d' ' -f2 ;;
    cmake) cmake --version 2>/dev/null | head -1 | cut -d' ' -f3 ;;
    ffmpeg) ffmpeg -version 2>/dev/null | head -1 | cut -d' ' -f3 ;;
    sdl2) sdl2-config --version 2>/dev/null ;;
    shellcheck) shellcheck --version 2>/dev/null | sed -n 's/^version: //p' ;;
  esac
}
tool_purpose() {
  case "$1" in
    just) echo "runs the recipes" ;;
    uv) echo "installs and runs Python" ;;
    cmake) echo "builds whisper.cpp" ;;
    ffmpeg) echo "records, converts and plays audio" ;;
    sdl2) echo "optional: whisper-stream for \`just live\`" ;;
    shellcheck) echo "optional: \`just lint\`" ;;
  esac
}
# True when "$1" (major.minor[.patch]) is at least "$2" (major.minor).
version_at_least() {
  awk -v v="$1" -v m="$2" 'BEGIN { split(v, a, "."); split(m, b, "."); exit !(a[1] + 0 > b[1] + 0 || (a[1] + 0 == b[1] + 0 && a[2] + 0 >= b[2] + 0)) }'
}

# --- platform: macOS on Apple Silicon, native terminal ----------------------------------------------
echo "platform"
[ "$(uname -s)" = Darwin ] || die "  this project targets macOS on Apple Silicon; $(uname -s) $(uname -m) is not supported"
macos="$(sw_vers -productVersion)"
if on_apple_silicon; then
  ok macos "$macos on $(sysctl -n machdep.cpu.brand_string 2>/dev/null || echo 'Apple Silicon')"
else
  warn macos "$macos on $(uname -m): this project targets Apple Silicon, the build would lack Metal"; status=1
fi
version_at_least "$macos" 26.0 || warn macos "this project was tested only on macOS 26; older versions are untested"
if under_rosetta; then
  die "  this terminal runs under Rosetta (x86_64): open a native arm64 terminal (\`arch\` must print arm64), Homebrew would install Intel binaries"
fi
case "${SHELL:-}" in
  */zsh) shell_name=zsh; profile="$HOME/.zprofile" ;;
  */bash) shell_name=bash; profile="$HOME/.bash_profile" ;;
  *) shell_name="${SHELL:-unknown}"; profile='your login shell profile' ;;
esac
ok shell "$shell_name login shell; the scripts run in bash whatever the login shell is"
if clt="$(xcode-select -p 2>/dev/null)"; then
  ok xcode-clt "$clt ($(git --version 2>/dev/null | cut -d' ' -f3 | sed 's/^/git /'))"
else
  miss xcode-clt "Xcode Command Line Tools: run \`xcode-select --install\`, accept the dialog, then run this again"; status=1
fi

# --- Homebrew: hard requirement -----------------------------------------------------------------
brew_bin="$(command -v brew 2>/dev/null || true)"
[ -n "$brew_bin" ] || [ ! -x /opt/homebrew/bin/brew ] || brew_bin=/opt/homebrew/bin/brew
if [ -z "$brew_bin" ]; then
  miss homebrew "not installed, and this script does not install it"
  die "Homebrew is required: install it from https://brew.sh (it also installs the Xcode Command Line Tools), add the shellenv line it prints to $profile, open a new terminal and run this again."
fi
brew_prefix="$("$brew_bin" --prefix)"
[ "$brew_prefix" = /opt/homebrew ] || die "  $brew_bin has prefix $brew_prefix: that is the Intel Homebrew; on Apple Silicon install the one in /opt/homebrew (https://brew.sh)"
ok homebrew "$("$brew_bin" --version 2>/dev/null | head -1 | cut -d' ' -f2) at $brew_prefix (Apple Silicon prefix)"
case ":$PATH:" in
  *":$brew_prefix/bin:"*) ;;
  *)
    # installed, but its bin directory is not on the PATH of this shell: use it for this run, say how to fix the profile
    export PATH="$brew_prefix/bin:$brew_prefix/sbin:$PATH"
    warn homebrew "$brew_prefix/bin is not on the PATH: add 'eval \"\$($brew_prefix/bin/brew shellenv)\"' to $profile ($shell_name), then open a new terminal" ;;
esac

# --- Homebrew formulas ------------------------------------------------------------------------------
echo "tools (Homebrew)"
for formula in $required_formulas $optional_formulas; do
  if command -v "$(tool_command "$formula")" >/dev/null 2>&1; then
    ok "$formula" "$(tool_version "$formula") ($(tool_purpose "$formula"))"
  else
    miss "$formula" "$(tool_purpose "$formula"): brew install $formula"
    to_install+=("$formula")
    case " $required_formulas " in *" $formula "*) status=1 ;; esac
  fi
done
if command -v just >/dev/null 2>&1 && ! version_at_least "$(tool_version just)" "$min_just"; then
  warn just "$(tool_version just) is older than $min_just, needed for the recipe groups: brew upgrade just"
  to_upgrade+=(just); status=1
fi
node_wanted="$(cat .nvmrc)"
if command -v node >/dev/null 2>&1; then
  node_major="$(node -v | sed -E 's/^v([0-9]+).*/\1/')"
  if [ "$node_major" -ge "$node_wanted" ]; then
    ok node "$(node -v) (optional: Prettier for \`just format-docs\`)"
  else
    warn node "$(node -v) is older than the $node_wanted LTS line in .nvmrc; it still works for Prettier, \`nvm install\` here updates it"
  fi
else
  warn node "not found (optional, only \`just format-docs\` and \`just check-docs\`): nvm install (reads .nvmrc), or brew install node"
fi

# --- Python through uv --------------------------------------------------------------------------------
echo "python (uv)"
pin="$(cat .python-version)"
if ! command -v uv >/dev/null 2>&1; then
  miss python "$pin: installed by uv once uv is there (\`just python\`)"; python_todo=1; status=1
elif ! uv python find "$pin" >/dev/null 2>&1; then
  miss python "$pin is not installed: uv python install && uv sync (\`just python\`)"; python_todo=1; status=1
elif [ ! -x .venv/bin/python ]; then
  miss python ".venv is missing for $pin: uv sync (\`just python\`)"; python_todo=1; status=1
else
  ok python "$(uv run --no-sync python -VV 2>/dev/null | cut -d' ' -f2) (pinned $pin, .venv in place)"
fi

# --- whisper.cpp: reported, installed by the other recipes --------------------------------------------
echo "whisper.cpp (not installed by this script: just clone, just build, just models, or just setup)"
if whisper_checkout_present; then
  ok checkout "$(whisper_version) at $WHISPER_DIR"
  latest="$(whisper_latest_release)"
  if [ -n "$latest" ] && [ "$latest" != "$(whisper_version)" ]; then warn release "$latest is available upstream (checkout $(whisper_version)): just upgrade $latest, then just pin"; fi
else
  miss checkout "$WHISPER_DIR: just clone"
fi
if [ -x "$whisper_cli" ]; then ok whisper-cli "$whisper_cli"; else miss whisper-cli "just build"; fi
if [ -f "$model_file" ] && [ -f "$vad_file" ]; then ok models "$model_file and $vad_file"; else miss models "just models"; fi

# --- install what is missing --------------------------------------------------------------------------
todo=$(( ${#to_install[@]} + ${#to_upgrade[@]} + python_todo ))
if [ "$todo" = 0 ]; then
  echo "dependencies: all installed"
  exit "$status"
fi

echo
echo "to install: ${to_install[*]-}${to_upgrade[*]:+ upgrade: ${to_upgrade[*]}}$([ "$python_todo" = 1 ] && echo " python $pin (uv)")"
case "$mode" in
  check)
    echo "run \`scripts/deps.sh install\` (or \`just deps install\`) to install them"
    exit "$status" ;;
  ask)
    if [ -t 0 ]; then
      printf 'install them now with Homebrew and uv? [y/N] '
      read -r answer
      case "$answer" in y|Y|yes|YES) ;; *) echo "nothing installed"; exit "$status" ;; esac
    else
      echo "not a terminal, nothing installed: run \`scripts/deps.sh install\` (or \`just deps install\`)"
      exit "$status"
    fi ;;
esac

[ ${#to_install[@]} = 0 ] || brew install "${to_install[@]}"
[ ${#to_upgrade[@]} = 0 ] || brew upgrade "${to_upgrade[@]}"
if [ "$python_todo" = 1 ]; then
  uv python install
  uv sync
fi
echo
echo "installed; checking again"
exec "$0" check
