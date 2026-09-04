#!/bin/bash
# lscd shell wrapper - add to ~/.bashrc or ~/.zshrc:
#   source /path/to/lscd.sh
#   or copy the function below into your rc file

l() {
  local output
  if output=$(command lscd "$@") && [[ -n "$output" ]]; then
    cd "$output"
  fi
  echo ""
}
