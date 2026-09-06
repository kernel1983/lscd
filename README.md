# lscd

An interactive `ls` + `cd` for your terminal. List a directory, navigate with the
arrow keys, filter by typing, and `cd` into the directory you pick — without ever
leaving the shell.

<img width="682" height="213" alt="screenshot" src="https://github.com/user-attachments/assets/dc392778-8e43-4676-bbce-6a061902e12d" />

No fullscreen UI (no alternate screen buffer). The list renders inline, exactly
like `ls` output, and stays on screen after you exit.

## Why this exists

This idea came first, then research turned up `ls-interactive`. Trying it out
showed it didn't fit the need: it only **opens** files and cannot change into a
directory — and it tends to wind up selecting the parent directory. `lscd` is
designed around directory navigation instead.

It is written in **Nim**, whose compiler first translates code to C and then
compiles that, so the binary is roughly the same size as an equivalent C build.
Here the result is just **~120 KB** — versus the ~8 MB binary of the Rust-based
`ls-interactive`. Nim's standard library also keeps this dependency-free.

The `shell/lscd.sh` wrapper lets you customize behavior in `bash` without
touching the Rust/Nim source: it branches on whether the returned path is a
directory or a file (and you can further match file extensions) to run whatever
action you want.

## Features

- **Zero dependencies** — no external libraries; only the Nim standard library.
- **Inline, non-fullscreen** TUI that persists after exit, like `ls`.
- **Multi-column layout**: columns auto-adjust based on terminal width for efficient use of space.
- **`ls`-style listing**: directories first (shown in yellow), files (green).
  A trailing `/` marks directories and `*` marks executables.
- **Navigation**: Up/Down/Left/Right arrows, Home/End to jump to first/last entry.
- **Filter by typing**: letters/numbers/`._- ` filter the list by prefix (case-insensitive).
- **Drill into subdirectories** with `Enter` (*one* invocation can descend
  multiple levels — no need to re-run `lscd`).
- **`.` always lists first** — it represents the current directory; `Enter` on it
  commits the current path.
- **Backspace** clears the filter, or climbs to the parent directory.
- **Esc** cancels (no output); **Ctrl+C** quits.
- **Clean stdout**: only the final chosen path (no ANSI codes) is printed, so a
  shell wrapper can safely capture it.

## Requirements

- [Nim](https://nim-lang.org/) >= 2.2.6
- A POSIX terminal (Linux/macOS) — it uses `termios`/`posix` for raw input.

## Install & build

```bash
git clone <repo-url> lscd
cd lscd
nimble build
```

`nimble build` compiles with `-d:release` in `src/lscd.nim` and outputs the
`lscd` binary in the current directory.

Optionally copy the binary into your PATH:

```bash
mkdir -p ~/.local/bin
cp lscd ~/.local/bin/
```

Make sure `~/.local/bin` is in your `PATH` (add the line below to `~/.bashrc`,
`~/.bash_profile`, or `~/.profile`):

```bash
export PATH="$HOME/.local/bin:$PATH"
```

## Shell integration

The binary only prints the chosen path. To make it actually `cd`, source the
provided wrapper function:

```bash
# add to ~/.bashrc or ~/.bash_profile or ~/.profile
source /path/to/lscd/shell/lscd.sh
```

The wrapper forks on the returned path: directories are `cd`-ed into, and files
run an action chosen by extension — e.g. `shell/lscd.sh` plays media files with
`ffplay`. Copy the function into your rc file and adjust it to your needs.

Then use `l` instead of `lscd`:

- If the selected path is a **directory**, it `cd`s into it.
- If it's a **file**, it opens it with `$EDITOR` (defaults to `vi`).

```bash
l /some/start/directory
```

### Customize the action

The wrapper is intentionally minimal so you can branch on the returned path and
run whatever you like — for example, choosing an action by file extension:

```bash
l() {
  local output
  if output=$(command lscd "$@") && [[ -n "$output" ]]; then
    if [[ -d "$output" ]]; then
      cd "$output"
    else
      case "${output##*.}" in
        mp4|m4a|mp3) ffplay "$output" ;;
        md|txt) ${EDITOR:-vi} "$output" ;;
        py|js|nim) ${EDITOR:-vi} "$output" ;;
        *) echo "$output" ;;
      esac
    fi
  fi
  echo ""
}
```

## Usage

```text
lscd [directory]
```

Omitting the directory starts from the current directory.

### Keys

| Key         | Action                                              |
|-------------|-----------------------------------------------------|
| `Up`/`Down` | Move cursor up/down (between rows)                |
| `Left`/`Right` | Move cursor left/right (between columns)        |
| `Home`/`End`| Jump to first / last entry                         |
| `Enter`     | On a dir: drill in · on `.`: commit current · on file: pick it |
| `Backspace` | Clear filter, or go to parent directory            |
| `Esc`       | Quit without selection                             |
| `Ctrl+C`    | Force quit                                         |
| A-Z, 0-9, `._-`, space | Filter by prefix (case-insensitive) |

## How it works

- Raw terminal input is handled manually via `termios`; escape sequences are
  parsed to read arrow keys.
- Rendering goes to **stderr**, so **stdout carries only the final path**.
- Cursor position is queried (`ESC[6n`) to anchor the list; the list reserves
  space so it never runs past the screen bottom (no spurious terminal scrolling).
- The `.` entry is forced to sort first in the comparison function.

## License

MIT
