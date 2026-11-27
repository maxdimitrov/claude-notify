# Sourced by tests. path_without <cmd> <workdir> -> $PATH with <cmd> (and <cmd>.exe)
# unreachable but every other command still found. A dir that holds <cmd> is not
# dropped (macOS ships jq in /usr/bin beside sed, tr and head): it is replaced by a
# dir under <workdir> that links every other entry of it.
path_without() {
  _pw_out=; _pw_n=0
  _pw_ifs=$IFS; IFS=:
  for _pw_d in $PATH; do
    if [ -x "$_pw_d/$1" ] || [ -x "$_pw_d/$1.exe" ]; then
      _pw_n=$((_pw_n+1)); _pw_s="$2/no-$1-$_pw_n"
      mkdir -p "$_pw_s"
      for _pw_f in "$_pw_d"/*; do
        case "${_pw_f##*/}" in "$1"|"$1.exe") continue ;; esac
        ln -s "$_pw_f" "$_pw_s/" 2>/dev/null
      done
      _pw_d=$_pw_s
    fi
    _pw_out="${_pw_out:+$_pw_out:}$_pw_d"
  done
  IFS=$_pw_ifs
  printf '%s' "$_pw_out"
}
