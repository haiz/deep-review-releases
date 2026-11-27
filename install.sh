#!/bin/bash
# Deep Review installer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/haiz/deep-review-releases/main/install.sh | bash
#
# Contract: installs the latest release of /Applications/DeepReview.app (macOS 15+). Needs Node 22+ and
# Google Chrome; both are checked first and a missing one stops the install with the command to fix it.
# The script arrives on stdin, so every question is read from /dev/tty; with no terminal the answer is "no".
# Sourced with DEEPREVIEW_INSTALL_TEST=1 it only defines functions (see scripts/test-install-sh.sh).
#   DR_NODE_CANDIDATES  test only: colon-separated list that replaces the two Homebrew node paths.
#   DR_NVM_DIR          test only: replaces ~/.nvm/versions/node.
# Example of the helpers once sourced:
#   find_node                      # prints /opt/homebrew/bin/node, or fails when no Node 22+ exists
#   release_asset_url "$json" DeepReview.app.zip
set -euo pipefail

APP_NAME="Deep Review"
APP_BUNDLE="DeepReview.app"
APP_EXECUTABLE="DeepReview"
INSTALL_DIR="/Applications"
REPO="haiz/deep-review-releases"
MIN_NODE_MAJOR=22
MIN_MACOS_MAJOR=15

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

info()  { printf '%b\n' "${BLUE}==>${NC} $1"; }
ok()    { printf '%b\n' "${GREEN}==>${NC} $1"; }
warn()  { printf '%b\n' "${YELLOW}==>${NC} $1"; }
error() { printf '%b\n' "${RED}==>${NC} $1" >&2; exit 1; }

# Resolve one exact asset name out of a releases API payload. Matching the full filename (the `/` before
# it anchors the start) keeps "Other.zip" or "Not-DeepReview.app.zip" from standing in for the app zip.
# The trailing `|| true` keeps a no-match from tripping `set -o pipefail`: the caller reports it instead.
release_asset_url() {
    echo "$1" | grep -o "\"browser_download_url\": *\"[^\"]*/$2\"" | head -1 | cut -d'"' -f4 || true
}

# Major version of a node executable: `node_major /opt/homebrew/bin/node` -> 22. Fails, printing nothing,
# when the file is not runnable or does not answer "vX.Y.Z".
node_major() {
    local out
    out="$("$1" --version 2>/dev/null)" || return 1
    out="${out//[$'\r\n ']/}"
    [[ "$out" =~ ^v([0-9]+)\. ]] || return 1
    echo "${BASH_REMATCH[1]}"
}

# An executable file that reports major >= MIN_NODE_MAJOR.
node_qualifies() {
    local major
    [[ -f "$1" && -x "$1" ]] || return 1
    major="$(node_major "$1")" || return 1
    [[ "$major" -ge "$MIN_NODE_MAJOR" ]]
}

# What a login shell resolves for `node` (last non-empty output line), for Node installed some other way
# (fnm, volta, asdf...). Interactive zsh with stdin on /dev/null (stdin is this script when piped into
# bash) and `+m` (no job control, so it cannot take over the terminal). Killed after 5 s, a broken rc
# file must not hang the installer. Fails when nothing is printed.
shell_node_probe() {
    local out pid i=0 line
    out="$(mktemp)"
    /bin/zsh +m -lic 'command -v node' </dev/null >"$out" 2>/dev/null &
    pid=$!
    while kill -0 "$pid" 2>/dev/null && [[ "$i" -lt 50 ]]; do sleep 0.1; i=$((i + 1)); done
    if kill -0 "$pid" 2>/dev/null; then
        kill -9 "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        rm -f "$out"
        return 1
    fi
    wait "$pid" || { rm -f "$out"; return 1; }
    line="$(grep -v '^[[:space:]]*$' "$out" | tail -1 || true)"
    rm -f "$out"
    [[ -n "$line" ]] || return 1
    echo "$line"
}

# Prints a Node 22+ path, or fails. Same order as the app's NodeLocator.system (keep both in step):
# /opt/homebrew/bin/node, /usr/local/bin/node, nvm versions highest first (numeric: v22 > v9),
# then the login-shell probe. A candidate that is missing, not executable or too old falls through.
find_node() {
    local candidates="${DR_NODE_CANDIDATES-/opt/homebrew/bin/node:/usr/local/bin/node}"
    local nvm_dir="${DR_NVM_DIR:-$HOME/.nvm/versions/node}"
    local c version probed
    local -a paths=()
    IFS=: read -r -a paths <<<"$candidates"
    for c in ${paths[@]+"${paths[@]}"}; do
        [[ -n "$c" ]] || continue
        if node_qualifies "$c"; then echo "$c"; return 0; fi
    done
    if [[ -d "$nvm_dir" ]]; then
        for version in $(ls "$nvm_dir" | grep -E '^v[0-9]+(\.[0-9]+)*$' | sed 's/^v//' \
                         | sort -t. -k1,1nr -k2,2nr -k3,3nr); do
            c="$nvm_dir/v$version/bin/node"
            if node_qualifies "$c"; then echo "$c"; return 0; fi
        done
    fi
    probed="$(shell_node_probe || true)"
    if [[ -n "$probed" ]] && node_qualifies "$probed"; then echo "$probed"; return 0; fi
    return 1
}

# Google Chrome in /Applications or ~/Applications. Prints the bundle path, or fails.
find_chrome() {
    local dir
    for dir in "/Applications" "$HOME/Applications"; do
        if [[ -d "$dir/Google Chrome.app" ]]; then echo "$dir/Google Chrome.app"; return 0; fi
    done
    return 1
}

# True when a process named DeepReview runs its executable from inside the bundle `$1`.
# Copies of the app elsewhere (a dev build, ~/Downloads) are not ours to replace and do not count.
app_running() {
    local pid exe
    for pid in $(pgrep -x "$APP_EXECUTABLE" 2>/dev/null || true); do
        exe="$(ps -p "$pid" -o comm= 2>/dev/null || true)"
        [[ "$exe" == "$1/Contents/MacOS/"* ]] && return 0
    done
    return 1
}

# Asks to quit the running app (answer read from /dev/tty, no terminal means "no"), then waits for it.
quit_running_app() {
    local answer=""
    if ! { : </dev/tty; } 2>/dev/null; then
        error "${APP_NAME} is running and there is no terminal to ask you. Quit ${APP_NAME} and run the install command again."
    fi
    printf '%b' "${YELLOW}==>${NC} ${APP_NAME} is running. Quit ${APP_NAME} to install the new version? The running turn will be cancelled and rerun from the start after the app reopens. [y/N] " >/dev/tty
    read -r answer </dev/tty || answer=""
    case "$answer" in
        y|Y|yes|YES|Yes) ;;
        *) error "Installation stopped: ${APP_NAME} is still running. Quit ${APP_NAME} and run the install command again." ;;
    esac
    osascript -e "quit app \"${APP_NAME}\"" >/dev/null 2>&1 || true
    local i=0
    while app_running "$1" && [[ "$i" -lt 60 ]]; do sleep 0.5; i=$((i + 1)); done
    ! app_running "$1" || error "${APP_NAME} did not quit. Quit ${APP_NAME} and run the install command again."
}

# Swaps the staged bundle `$1` into `$2`, keeping the old one until the new one is in place so that a
# failure never leaves the Mac without an app. Both paths must be on the same volume (rename is atomic).
# A leftover `$2.old` with no `$2` (an earlier swap that was interrupted) is the only copy of the app,
# so it is restored first. Once the new app is in place, failing to delete `.old` is not a failure.
replace_app() {
    local staged="$1" target="$2" old="$2.old"
    if [[ ! -e "$target" && -e "$old" ]]; then
        mv "$old" "$target" || return 1
    fi
    rm -rf "$old"
    [[ ! -e "$old" ]] || return 1   # mv would nest the target inside a leftover .old directory
    if [[ -e "$target" ]]; then
        mv "$target" "$old" || return 1
    fi
    if ! mv "$staged" "$target"; then
        if [[ -e "$old" ]]; then mv "$old" "$target" || true; fi
        return 1
    fi
    rm -rf "$old" || true
}

TMPDIR_PATH=""

main() {
    [[ "$(uname -s)" == "Darwin" ]] || error "${APP_NAME} supports macOS only."
    local macos_version
    macos_version="$(sw_vers -productVersion)"
    [[ "${macos_version%%.*}" -ge "$MIN_MACOS_MAJOR" ]] \
        || error "macOS ${MIN_MACOS_MAJOR} or later is required. This Mac runs macOS ${macos_version}."

    info "Installing ${APP_NAME}..."

    # --- Prerequisites ---
    local node
    node="$(find_node)" \
        || error "Node ${MIN_NODE_MAJOR} or later not found. Install it with: brew install node"
    info "Node: ${node}"
    find_chrome >/dev/null \
        || error "Google Chrome not found in /Applications or ~/Applications. Download it from: https://www.google.com/chrome/"
    [[ -e "$HOME/Library/Preferences/com.claude-dashboard.app.plist" ]] \
        || warn "claude-dashboard not found. ChatGPT turns still run, but Claude turns will fail until you install claude-dashboard and log in."

    # --- Latest release ---
    info "Fetching the latest release..."
    local release_json version url
    release_json="$(curl -fsSL "https://api.github.com/repos/${REPO}/releases/latest")" \
        || error "Could not fetch release information. Check your Internet connection."
    version="$(echo "$release_json" | grep -o '"tag_name": *"[^"]*"' | head -1 | cut -d'"' -f4 || true)"
    url="$(release_asset_url "$release_json" "${APP_BUNDLE}.zip")"
    [[ -n "$url" ]] || error "The latest release has no ${APP_BUNDLE}.zip file."
    info "Found ${APP_NAME} ${version}"

    # --- Download and unpack into a temp dir, nothing in INSTALL_DIR yet ---
    TMPDIR_PATH="$(mktemp -d)"
    trap 'rm -rf "$TMPDIR_PATH"' EXIT
    info "Downloading..."
    curl -fSL --progress-bar -o "${TMPDIR_PATH}/${APP_BUNDLE}.zip" "$url" \
        || error "Download failed."
    ditto -xk "${TMPDIR_PATH}/${APP_BUNDLE}.zip" "${TMPDIR_PATH}/stage" \
        || error "Could not unzip the download."
    [[ -d "${TMPDIR_PATH}/stage/${APP_BUNDLE}" ]] \
        || error "The download does not contain ${APP_BUNDLE}."

    # --- Install ---
    local target="${INSTALL_DIR}/${APP_BUNDLE}"
    if app_running "$target"; then quit_running_app "$target"; fi

    info "Installing into ${INSTALL_DIR}..."
    local incoming="${INSTALL_DIR}/.${APP_BUNDLE}.new"
    rm -rf "$incoming"
    ditto "${TMPDIR_PATH}/stage/${APP_BUNDLE}" "$incoming" \
        || { rm -rf "$incoming"; error "Could not copy the app into ${INSTALL_DIR}. If permission is missing, run again from an administrator account."; }
    xattr -cr "$incoming" 2>/dev/null || true
    replace_app "$incoming" "$target" \
        || { rm -rf "$incoming"; error "Could not replace ${target}. The old version (if any) was kept."; }

    echo ""
    ok "Installed ${APP_NAME} ${version}."
    echo ""
    echo "  Open the app:  open ${target}"
    echo ""
}

# When sourced by a test, stop here: definitions only, nothing installed.
if [[ -n "${DEEPREVIEW_INSTALL_TEST:-}" ]]; then
    return 0 2>/dev/null || exit 0
fi

# Called last, so a truncated download never runs half a script.
main "$@"
