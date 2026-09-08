import std/[os, strutils, algorithm, posix, termios, terminal, exitprocs]
import std/times as dtimes

type
  EntryKind = enum
    ekDir, ekFile
  Entry = object
    name: string
    kind: EntryKind
    isExec: bool

var
  entries: seq[Entry]
  filtered: seq[int]
  cursor: int
  top: int
  filter: string
  currentDir: string
  termW, termH: int
  origTermios: Termios

proc setupRawMode() =
  let fd = getFileHandle(stdin)
  discard tcGetAttr(fd, addr origTermios)
  var raw = origTermios
  raw.c_iflag = raw.c_iflag and not Cflag(BRKINT or ICRNL or INPCK or ISTRIP or IXON)
  # keep OPOST/ONLCR enabled so \n advances to a fresh column (no stray indentation)
  raw.c_cflag = (raw.c_cflag and not Cflag(CSIZE or PARENB)) or CS8
  raw.c_lflag = raw.c_lflag and not Cflag(ECHO or ICANON or IEXTEN or ISIG)
  raw.c_cc[VMIN] = 1.cchar
  raw.c_cc[VTIME] = 0.cchar
  discard tcSetAttr(fd, TCSAFLUSH, addr raw)

proc restoreTerminal() =
  let fd = getFileHandle(stdin)
  discard tcSetAttr(fd, TCSAFLUSH, addr origTermios)

var cleaned = false

proc cleanupForExit() =
  if cleaned: return
  cleaned = true
  restoreTerminal()
  showCursor(stderr)
  stderr.resetAttributes()
  flushFile(stderr)

proc readKey(): int =
  var ch: char
  let n = readBuffer(stdin, addr ch, 1)
  if n == 0: return -1
  let c = ord(ch)
  if c == 27: # ESC
    var buf: array[4, char]
    let n2 = readBuffer(stdin, addr buf[0], 1)
    if n2 == 0: return 27
    if buf[0] == '[':
      let n3 = readBuffer(stdin, addr buf[1], 1)
      if n3 == 0: return 27
      case buf[1]
      of 'A': return 1000 # Up
      of 'B': return 1001 # Down
      of 'C': return 1005 # Right
      of 'D': return 1006 # Left
      of 'H': return 1002 # Home
      of 'F': return 1003 # End
      of 'Z': return 1004 # Shift-Tab
      else: discard
    return 27
  return c

proc scanDir(dir: string) =
  entries = @[]
  entries.add Entry(name: ".", kind: ekDir, isExec: false)
  for kind, path in walkDir(dir):
    let name = lastPathPart(path)
    var ek: EntryKind
    case kind
    of pcDir, pcLinkToDir: ek = ekDir
    of pcFile, pcLinkToFile: ek = ekFile
    var isExec = false
    if ek == ekFile:
      try:
        let perms = getFilePermissions(path)
        isExec = fpUserExec in perms or fpGroupExec in perms or fpOthersExec in perms
      except CatchableError:
        discard
    entries.add Entry(name: name, kind: ek, isExec: isExec)

  entries.sort(proc(a, b: Entry): int =
    if a.name == "." : return -1
    if b.name == "." : return 1
    if a.kind == ekDir and b.kind != ekDir: return -1
    if a.kind != ekDir and b.kind == ekDir: return 1
    cmpIgnoreCase(a.name, b.name)
  )

proc applyFilter() =
  filtered = @[]
  for i, e in entries:
    if filter.len == 0 or toLowerAscii(e.name).startsWith(toLowerAscii(filter)):
      filtered.add i
  if cursor >= filtered.len:
    cursor = max(0, filtered.len - 1)
  top = 0

var listTopRow = 1

proc queryCursorRow(): int =
  # Ask the terminal for the cursor's absolute row: ESC[6n -> ESC[r;cR
  # Use the raw fd (not File's buffered stdin) with non-blocking reads + timeout.
  let fd = getFileHandle(stdin)
  let oldFlags = fcntl(fd, F_GETFL, 0)
  discard fcntl(fd, F_SETFL, oldFlags or O_NONBLOCK)
  stderr.write "\x1b[6n"
  flushFile(stderr)
  var buf = ""
  var ch: char
  let deadline = epochTime() + 0.2
  while epochTime() < deadline:
    let n = posix.read(fd, addr ch, 1)
    if n == 1:
      buf.add ch
      if ch == 'R': break
      if buf.len > 32: break
    else:
      sleep(2)
  discard fcntl(fd, F_SETFL, oldFlags)
  let semi = buf.find(';')
  if semi < 0: return 0
  try:
    result = parseInt(buf[2 ..< semi])
  except ValueError:
    result = 0

var
  nCols = 1
  colWidth = 1
  colPadding = 2

proc adjustViewport(maxVisible: int) =
  # Keep cursor inside the visible window [top, top+maxVisible) in row-space.
  if maxVisible <= 0: top = 0; return
  let curRow = if nCols > 0: cursor div nCols else: 0
  if curRow < top:
    top = curRow
  elif curRow >= top + maxVisible:
    top = curRow - maxVisible + 1

proc listMaxRows(): int =
  # We want to use as much of the screen as possible for entries. Reserve 1
  # row for the header and 1 row for the hint; the entry window uses the rest.
  result = max(1, termH - 2)

proc calcLayout() =
  # Calculate column width from the longest visible entry name.
  var maxNameLen = 0
  for idx in filtered:
    let e = entries[idx]
    var len = e.name.len
    if e.kind == ekDir: len += 1
    elif e.isExec: len += 1
    if len > maxNameLen: maxNameLen = len
  colWidth = maxNameLen + 2  # 2 chars padding between columns
  nCols = max(1, termW div colWidth)

proc visibleRows(): int =
  ## How many rows the grid occupies.
  max(1, (filtered.len + nCols - 1) div nCols)

proc render() =
  calcLayout()
  let maxVisible = listMaxRows()
  let totalRows = visibleRows()
  adjustViewport(maxVisible)
  let visibleCount = min(totalRows - top, maxVisible)

  let blockH = visibleCount + 2
  if listTopRow + blockH - 1 > termH:
    listTopRow = max(1, termH - blockH + 1)

  stderr.write "\x1b[" & $listTopRow & ";1H"
  stderr.write "\x1b[0J"

  let pathStr = " " & currentDir & " "
  let filterStr = if filter.len > 0: " /" & filter & " " else: ""
  let statusStr = " " & $filtered.len & "/" & $entries.len & " "

  stderr.setForegroundColor(fgWhite)
  stderr.setBackgroundColor(bgBlue)
  stderr.styledWriteLine(styleBright, pathStr, " ".repeat(max(0, termW - pathStr.len - filterStr.len - statusStr.len)), filterStr, statusStr, resetStyle)
  stderr.setBackgroundColor(bgDefault)

  if filtered.len > 0:
    for row in 0 ..< visibleCount:
      let absRow = top + row
      stderr.write "\x1b[" & $(listTopRow + 1 + row) & ";1H"
      stderr.write "\x1b[0K"
      for col in 0 ..< nCols:
        let idx = absRow * nCols + col
        if idx >= filtered.len: break
        let realIdx = filtered[idx]
        let e = entries[realIdx]
        let isCursor = realIdx == cursor
        let prefix = if isCursor: ">" else: " "
        let suffix = case e.kind
          of ekDir: "/"
          of ekFile:
            if e.isExec: "*"
            else: ""

        stderr.write "\x1b[" & $(col * colWidth + 1) & "G"
        stderr.write prefix
        case e.kind
        of ekDir: stderr.setForegroundColor(fgYellow)
        of ekFile: stderr.setForegroundColor(fgGreen)
        stderr.write e.name
        stderr.setForegroundColor(fgBlack, true)
        stderr.write suffix
        let pad = colWidth - (e.name.len + suffix.len + 1)
        if pad > 0: stderr.write " ".repeat(pad)
        stderr.resetAttributes()
  else:
    stderr.setForegroundColor(fgYellow)
    stderr.writeLine "  (no matches)"

  stderr.write "\x1b[" & $(listTopRow + visibleCount + 1) & ";1H"
  stderr.write "\x1b[0K"
  stderr.setForegroundColor(fgBlack, true)
  stderr.write " Up/Down/Left/Right:move  Enter:enter/choose  Backspace:up  Esc:quit  type:filter "
  stderr.resetAttributes()
  flushFile(stderr)

proc handleInput() =
  while true:
    calcLayout()
    let key = readKey()
    case key
    of 1000: # Up
      if cursor >= nCols: cursor.dec nCols
    of 1001: # Down
      if cursor + nCols < filtered.len: cursor.inc nCols
    of 1005: # Right
      if cursor + 1 < filtered.len: cursor.inc
    of 1006: # Left
      if cursor > 0: cursor.dec
    of 1002: # Home
      cursor = 0
    of 1003: # End
      cursor = max(0, filtered.len - 1)
    of 13, 10: # Enter
      if filtered.len > 0:
        let e = entries[filtered[cursor]]
        if e.kind == ekDir and e.name != ".":
          # Drill into a subdirectory instead of exiting, so one invocation
          # can descend several levels.
          currentDir = try: expandFilename(currentDir / e.name)
                       except OSError: currentDir / e.name
          filter = ""
          cursor = 0
          top = 0
          scanDir(currentDir)
          applyFilter()
        else:
          # '.' commits the current directory; a file prints its own path.
          let rawPath = if e.name == ".": currentDir
                        else: currentDir / e.name
          let absPath = try: expandFilename(rawPath)
                        except OSError: rawPath
          cleanupForExit()
          stdout.write absPath
          flushFile(stdout)
          quit(0)
    of 127, 8: # Backspace
      if filter.len > 0:
        filter = filter[0 .. ^2]
        applyFilter()
      else:
        let parent = parentDir(currentDir)
        if parent != currentDir:
          currentDir = parent
          scanDir(currentDir)
          applyFilter()
    of 27: # Escape
      cleanupForExit()
      quit(0)
    of 3: # Ctrl+C
      cleanupForExit()
      quit(1)
    else:
      let ch = char(key)
      if ch in {'a'..'z', 'A'..'Z', '0'..'9', '.', '_', '-', ' '}:
        filter.add ch
        applyFilter()

    render()

proc main() =
  let args = commandLineParams()
  if args.len > 0 and args[0] in ["-h", "--help"]:
    echo "lscd - interactive ls + cd"
    echo ""
    echo "Usage: lscd [directory]"
    echo ""
    echo "Keys:"
    echo "  Up/Down       Move cursor up/down"
    echo "  Left/Right    Move cursor left/right"
    echo "  Home/End      Jump to first/last"
    echo "  Enter         Select and print path"
    echo "  Backspace     Clear filter or go to parent"
    echo "  Esc           Quit without selection"
    echo "  Any letter    Filter by prefix"
    quit(0)

  currentDir = if args.len > 0 and args[0].len > 0:
    try:
      expandFilename(args[0])
    except OSError:
      args[0].normalizedPath
  else:
    getCurrentDir()

  if not dirExists(currentDir):
    stderr.writeLine "Error: " & currentDir & " is not a directory"
    quit(1)

  hideCursor(stderr)
  setupRawMode()
  let (w, h) = terminalSize()
  termW = w
  termH = h

  stderr.write "\n" # move to a fresh line, like ls
  flushFile(stderr)
  let row = queryCursorRow()
  listTopRow = if row > 0: row else: 1

  scanDir(currentDir)
  applyFilter()
  render()
  handleInput()

addExitProc proc() =
  cleanupForExit()

when isMainModule:
  main()
