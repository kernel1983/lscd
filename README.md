# lscd

An interactive `ls` + `cd` for your terminal. List a directory, navigate with the
arrow keys, filter by typing, and `cd` into the directory you pick — without ever
leaving the shell.

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
- **`ls`-style listing**: directories first (shown in blue), executables (green).
  A trailing `/` marks directories and `*` marks executables.
- **Navigation**: Up/Down arrows, Home/End to jump to first/last entry.
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
nim c -d:release -d:strip -o:lscd src/lscd.nim
```

Optionally install into your PATH:

```bash
install -m755 lscd /usr/local/bin/lscd
```

## Shell integration

The binary only prints the chosen path. To make it actually `cd`, source the
provided wrapper function:

```bash
# ~/.bashrc or ~/.zshrc
source /path/to/lscd/shell/lscd.sh
```

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
        md|txt) ${EDITOR:-vi} "$output" ;;
        png|jpg|gif) xdg-open "$output" ;;
        py|sh|rs|nim) ${EDITOR:-vi} "$output" ;;
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
| `Up`/`Down` | Move cursor                                        |
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