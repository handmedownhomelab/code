# m - the Homelab Menu. Hand-Me-Down Homelab, section 2.5.
#
# Add this function to ~/.zshrc, and put ssh-menu.sh (and audit.sh) in
# ~/bin with chmod +x. It runs the one command ssh-menu.sh prints, in THIS
# shell, and adds it to your history.
#
# In bash, use the same function with the two `print` lines replaced by:
#     printf '%s\n' "> $cmd"
#     history -s "$cmd"
m() {
  local cmd
  cmd=$(~/bin/ssh-menu.sh "$@") || return $?
  [[ -z $cmd ]] && return 0
  print -r -- "> $cmd"
  print -s -- "$cmd"
  eval "$cmd"
}
