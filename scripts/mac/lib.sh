#!/bin/sh
# claude-notify macOS helpers (sourced). POSIX sh, pure ASCII.

cn_mdir() { printf '%s' "${TMPDIR:-/tmp}/claude-notify"; }

cn_log() {
  mkdir -p "$(cn_mdir)" 2>/dev/null || return 0
  printf '%s %s\n' "$(date '+%Y-%m-%dT%H:%M:%S' 2>/dev/null)" "$*" >> "$(cn_mdir)/mac.log" 2>/dev/null
  return 0
}

# Window titles use " - " or " <em dash> " (em dash built at runtime to keep files ASCII).
CN_EM=$(printf '\342\200\224')
CN_ELL=$(printf '\342\200\246')

# cn_norm_title <title> -> title with em-dash separators turned into " - "
cn_norm_title() { printf '%s' "$1" | sed "s/ $CN_EM / - /g"; }

# cn_first_seg <title> -> first segment, trailing "..." / ellipsis / "." removed
cn_first_seg() {
  _t=$(cn_norm_title "$1"); _f=${_t%% - *}
  _f=${_f%"$CN_ELL"}; _f=${_f%...}; _f=${_f%.}
  printf '%s' "$_f"
}

# cn_has_seg <title> <root>: true if a segment AFTER the first equals root
cn_has_seg() {
  _t=$(cn_norm_title "$1")
  case "$_t" in *" - "*) ;; *) return 1 ;; esac
  _r=${_t#* - }
  while :; do
    _s=${_r%% - *}
    [ -n "$2" ] && [ "$_s" = "$2" ] && return 0
    case "$_r" in *" - "*) _r=${_r#* - } ;; *) return 1 ;; esac
  done
}

# cn_has_any_seg <title> <root>: true if ANY segment (incl. first) equals root
cn_has_any_seg() {
  [ "$(cn_first_seg "$1")" = "$2" ] && return 0
  [ "$(cn_norm_title "$1" | sed 's/ - .*//')" = "$2" ] && return 0
  cn_has_seg "$1" "$2"
}

# cn_icon <scripts/mac dir> -> image for terminal-notifier -contentImage (-appIcon is ignored
# on current macOS). The Claude app's icon, converted once into the log dir and again when the
# app's icon is newer (the logo is not shipped in this repo); else the plugin's bell.
# CLAUDE_NOTIFY_CLAUDE_APP overrides the app path (tests).
cn_icon() {
  _app=${CLAUDE_NOTIFY_CLAUDE_APP:-/Applications/Claude.app}
  _png="$(cn_mdir)/claude.png"
  _ic=$(defaults read "$_app/Contents/Info" CFBundleIconFile 2>/dev/null)
  if [ -n "$_ic" ]; then
    _icns="$_app/Contents/Resources/${_ic%.icns}.icns"
    if [ -f "$_icns" ]; then
      if [ ! -s "$_png" ] || [ "$_icns" -nt "$_png" ]; then
        mkdir -p "$(cn_mdir)" 2>/dev/null
        sips -s format png -Z 256 "$_icns" --out "$_png" >/dev/null 2>&1 || rm -f "$_png" 2>/dev/null
      fi
      [ -s "$_png" ] && { printf '%s' "$_png"; return 0; }
    fi
  fi
  _bell="$(cd "$1/../.." 2>/dev/null && pwd)/assets/icon.png"
  [ -f "$_bell" ] && printf '%s' "$_bell"
  return 0
}

# cn_q <value> -> value wrapped in single quotes, embedded ' escaped as '\''
cn_q() {
  _bs='\'
  _e=$(printf '%s' "$1" | sed "s/'/'${_bs}${_bs}''/g")
  printf "'%s'" "$_e"
}
