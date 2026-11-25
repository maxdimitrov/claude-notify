# Sourced by tests: copies fixtures to a temp dir that is NOT inside a worktree
# (a /.claude/worktrees/ path would be cut by cn_repo_root), sets FIX and fx().
_fixsrc=$(cd "$(dirname "$0")" && pwd)/fixtures
_fixtmp="${TMPDIR:-${TEMP:-/tmp}}"
# Windows-style TEMP (backslashes) under a POSIX shell without TMPDIR: convert.
if command -v cygpath >/dev/null 2>&1; then _fixtmp=$(cygpath -u "$_fixtmp"); fi
FIXROOT="$_fixtmp/cn-fix-$$"
mkdir -p "$FIXROOT" && cp -R "$_fixsrc" "$FIXROOT/fixtures"
FIX="$FIXROOT/fixtures"
fx() { sed "s#@FIXTURES@#$FIX#g" "$FIX/$1"; }
