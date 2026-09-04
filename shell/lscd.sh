#!/bin/bash
# lscd shell wrapper - add to ~/.bashrc or ~/.zshrc:
#   source /path/to/lscd.sh
#   or copy the function below into your rc file

l() {
  local output
  if output=$(command /PATH_TO/lscd "$@"); then
    if [[ -d "$output" ]]; then
      cd "$output"
    elif [[ -f "$output" ]]; then
      vim "$output"
    fi
  fi
  echo ""
}
