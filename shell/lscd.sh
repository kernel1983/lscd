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
      case "${output##*.}" in
      mkv | avi | mp4 | m4a | mp3)
        ffplay "$output" &>/dev/null &
        ;;
      *)
        vim "$output"
        ;;
      esac
    fi
  fi
  echo ""
}
