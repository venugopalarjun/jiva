#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Jiva — one-command installer.
#
#   curl -fsSL https://jiva.works/install.sh | bash
#
# This is a STATE-CONVERGER, not a linear "download then install" script. Run it
# in any of these situations and it finishes the job from wherever you are:
#   • nothing downloaded yet
#   • the .dmg already sitting in ~/Downloads or ~/Desktop
#   • the .dmg already mounted (double-clicked)
#   • Jiva.app already dragged to Applications but Gatekeeper won't open it
#   • an older Jiva already installed
#   • the latest Jiva already installed (then it just re-launches it)
#
# It is idempotent and safe to re-run. It installs to ~/Applications (no admin
# password needed), clears the download quarantine so the un-notarized build
# opens, quits + replaces any older/stray copy, and launches Jiva — whose
# onboarding window then downloads the speech + language models (Parakeet for
# dictation/live transcription first).
#
# It NEVER re-signs the app (that would reset your macOS permission grants) and
# it verifies the download against the published SHA-256 before touching anything.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

SITE="https://jiva.works"
BUNDLE_ID="io.jiva.app"
APP_NAME="Jiva.app"
DEST_DIR="$HOME/Applications"
DEST="$DEST_DIR/$APP_NAME"

# Locations an already-installed copy might live in (checked for clean-upgrade).
APP_LOCATIONS=("$HOME/Applications/$APP_NAME" "/Applications/$APP_NAME")

# ── tiny output helpers ──────────────────────────────────────────────────────
if [ -t 1 ]; then B=$'\033[1m'; D=$'\033[2m'; R=$'\033[0m'; else B=""; D=""; R=""; fi
step() { printf '\n%s── %s ──%s\n' "$B" "$*" "$R"; }
say()  { printf '   %s\n' "$*"; }
warn() { printf '   %s⚠ %s%s\n' "$B" "$*" "$R"; }
die()  { printf '\n%s✗ %s%s\n' "$B" "$*" "$R" >&2; exit 1; }

# ── temp + cleanup ───────────────────────────────────────────────────────────
WORK="$(mktemp -d)"
MOUNTED=""       # a volume WE mounted, to detach on exit
cleanup() {
  [ -n "$MOUNTED" ] && hdiutil detach "$MOUNTED" >/dev/null 2>&1 || true
  rm -rf "$WORK" 2>/dev/null || true
}
trap cleanup EXIT

# ── preflight ────────────────────────────────────────────────────────────────
[ "$(uname -s)" = "Darwin" ] || die "Jiva is macOS-only."
command -v curl   >/dev/null 2>&1 || die "curl is required (it ships with macOS)."
command -v shasum >/dev/null 2>&1 || die "shasum is required (it ships with macOS)."
command -v hdiutil >/dev/null 2>&1 || die "hdiutil is required (it ships with macOS)."
PY="/usr/bin/python3"; [ -x "$PY" ] || PY="$(command -v python3 || true)"

if [ "$(uname -m)" != "arm64" ]; then
  die "Jiva needs an Apple-silicon Mac (M1 or later). This looks like an Intel Mac."
fi
OSVER="$(sw_vers -productVersion 2>/dev/null || echo 0)"
OSMAJ="$(printf '%s' "$OSVER" | cut -d. -f1)"
if [ "${OSMAJ:-0}" -lt 26 ] 2>/dev/null; then
  warn "Jiva targets macOS 26+; you're on $OSVER. Continuing, but it may not launch."
fi

# ── learn what "latest" is ───────────────────────────────────────────────────
step "Checking the latest Jiva release"
META="$(curl -fsSL "$SITE/latest.json" 2>/dev/null || true)"
[ -n "$META" ] || die "Couldn't reach $SITE. Check your connection and try again."

json() {  # json <key>  — read a top-level string field from $META
  if [ -n "$PY" ]; then
    printf '%s' "$META" | "$PY" -c "import sys,json;print(json.load(sys.stdin).get('$1',''))" 2>/dev/null || true
  else
    printf '%s' "$META" | sed -n "s/.*\"$1\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" | head -1
  fi
}
LATEST_VER="$(json version)"
LATEST_BUILD="$(json build)"
DMG_SHA="$(json dmg_sha256)"
DMG_URL="$(json dmg)"
[ -n "$DMG_SHA" ] && [ -n "$DMG_URL" ] || die "Release metadata at $SITE/latest.json looks malformed."
say "Latest is Jiva v${LATEST_VER:-?} (build ${LATEST_BUILD:-?})."

installed_build() {  # installed_build <app path> -> CFBundleVersion or empty
  [ -d "$1" ] || { echo ""; return; }
  /usr/bin/defaults read "$1/Contents/Info.plist" CFBundleVersion 2>/dev/null || echo ""
}
sha_of() { shasum -a 256 "$1" 2>/dev/null | awk '{print $1}'; }

# ── short-circuit: is the latest build already installed? ────────────────────
CUR_BUILD="$(installed_build "$DEST")"
if [ -n "$LATEST_BUILD" ] && [ "$CUR_BUILD" = "$LATEST_BUILD" ]; then
  step "Jiva v$LATEST_VER (build $LATEST_BUILD) is already installed"
  say "Nothing to download — clearing the Gatekeeper quarantine and launching."
  xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
  LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
  [ -x "$LSREG" ] && "$LSREG" -f "$DEST" >/dev/null 2>&1 || true
  step "Launching Jiva"
  open "$DEST" || die "Couldn't launch $DEST."
  say "The Welcome window will download the models it needs (dictation first)."
  exit 0
fi

# ── find a source Jiva.app without re-downloading if we can ──────────────────
# Order: an explicit local app (the .command sets JIVA_SRC_APP to the copy inside
# the mounted DMG) → a local .dmg whose checksum matches → download.
SRC_APP=""     # a ready-to-copy Jiva.app
SRC_DMG=""     # a .dmg we still need to mount

if [ -n "${JIVA_SRC_APP:-}" ] && [ -d "$JIVA_SRC_APP" ]; then
  B_SRC="$(installed_build "$JIVA_SRC_APP")"
  if [ -z "$LATEST_BUILD" ] || [ "$B_SRC" = "$LATEST_BUILD" ]; then
    SRC_APP="$JIVA_SRC_APP"
    say "Using the Jiva you already opened (build ${B_SRC:-?}) — no download needed."
  else
    say "The disk image you opened is build ${B_SRC:-?}, older than the latest — fetching the latest instead."
  fi
fi

if [ -z "$SRC_APP" ]; then
  step "Looking for an already-downloaded Jiva disk image"
  for d in "$HOME/Downloads" "$HOME/Desktop" "$PWD"; do
    [ -d "$d" ] || continue
    while IFS= read -r cand; do
      [ -f "$cand" ] || continue
      if [ "$(sha_of "$cand")" = "$DMG_SHA" ]; then SRC_DMG="$cand"; break; fi
    done < <(ls -t "$d"/Jiva*.dmg 2>/dev/null || true)
    [ -n "$SRC_DMG" ] && break
  done
  if [ -n "$SRC_DMG" ]; then
    say "Reusing $SRC_DMG (checksum matches the latest — no re-download)."
  else
    say "None found locally — downloading (~285 MB)."
    step "Downloading Jiva"
    curl -fL --progress-bar -o "$WORK/Jiva.dmg" "$DMG_URL" || die "Download failed from $DMG_URL"
    GOT="$(sha_of "$WORK/Jiva.dmg")"
    [ "$GOT" = "$DMG_SHA" ] || die "Checksum mismatch (expected $DMG_SHA, got $GOT). Not installing."
    say "Checksum verified."
    SRC_DMG="$WORK/Jiva.dmg"
  fi
fi

# Mount the .dmg if that's our source.
if [ -z "$SRC_APP" ]; then
  step "Opening the disk image"
  MOUNTED="$(hdiutil attach "$SRC_DMG" -nobrowse -noautoopen 2>/dev/null | grep -Eo '/Volumes/.*' | head -1)"
  [ -n "$MOUNTED" ] && [ -d "$MOUNTED/$APP_NAME" ] || die "Couldn't mount $SRC_DMG or find $APP_NAME inside it."
  SRC_APP="$MOUNTED/$APP_NAME"
fi

# ── clean upgrade: quit + remove any running/old/stray copy ──────────────────
step "Clearing the way for the new build"
osascript -e 'tell application id "io.jiva.app" to quit' >/dev/null 2>&1 || true
osascript -e 'tell application "Jiva" to quit' >/dev/null 2>&1 || true
killall JivaApp jiva-capture jiva-transcribe jiva-diarize jiva-aec jiva-asr >/dev/null 2>&1 || true
sleep 1

for loc in "${APP_LOCATIONS[@]}"; do
  [ -e "$loc" ] || continue
  if rm -rf "$loc" 2>/dev/null; then
    say "Removed old copy at $loc"
  else
    warn "Couldn't remove $loc (needs admin). Remove it manually: sudo rm -rf \"$loc\""
  fi
done

# Warn about stray copies elsewhere (Downloads/Desktop) and eject other Jiva DMGs.
if command -v mdfind >/dev/null 2>&1; then
  while IFS= read -r stray; do
    [ -n "$stray" ] || continue
    case "$stray" in
      "$DEST"|"") : ;;
      /Volumes/*) hdiutil detach "$(printf '%s' "$stray" | sed -E 's#(/Volumes/[^/]+).*#\1#')" >/dev/null 2>&1 || true ;;
      *) warn "Another Jiva copy is at: $stray — consider deleting it so macOS doesn't open the wrong one." ;;
    esac
  done < <(mdfind "kMDItemCFBundleIdentifier == '$BUNDLE_ID'" 2>/dev/null || true)
fi

# ── install ──────────────────────────────────────────────────────────────────
step "Installing Jiva to ~/Applications"
mkdir -p "$DEST_DIR"
ditto "$SRC_APP" "$DEST" || die "Copy failed."
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true   # so the un-notarized build opens
LSREG="/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister"
[ -x "$LSREG" ] && "$LSREG" -f "$DEST" >/dev/null 2>&1 || true

# ── verify + launch ──────────────────────────────────────────────────────────
NEW_BUILD="$(installed_build "$DEST")"
if [ -n "$LATEST_BUILD" ] && [ "$NEW_BUILD" != "$LATEST_BUILD" ]; then
  warn "Installed build is $NEW_BUILD but the latest is $LATEST_BUILD — something's off. Launching anyway."
else
  say "Installed Jiva v$LATEST_VER (build ${NEW_BUILD:-?})."
fi

step "Launching Jiva"
open "$DEST" || die "Installed OK but couldn't launch it. Open it from ~/Applications."

printf '\n%s✓ Jiva is installed and open.%s\n' "$B" "$R"
say "The Welcome window grants permissions and downloads the models it needs"
say "(Parakeet for dictation + live transcription downloads first)."
say "Jiva lives in your menu bar — look for the lotus icon, top-right."
