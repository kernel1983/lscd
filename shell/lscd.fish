# lscd wrapper for Fish shell
#   source /path/to/lscd.fish
#   or copy the function below into your config file
function l
    set -l output (command /PATH_TO/lscd $argv)
    if test $status -eq 0
        if test -d "$output"
            cd "$output"
        else if test -f "$output"
            switch (string split -r -m1 . -- "$output")[-1]
                case mkv avi mp4 m4a mp3
                    ffplay "$output" &>/dev/null &
                case '*'
                    vim "$output"
            end
        end
    end
    echo ""
end
