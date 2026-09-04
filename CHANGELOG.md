# BERT changelog

Releases of this fork ([SamLovick/Basic-Excel-R-Toolkit](https://github.com/SamLovick/Basic-Excel-R-Toolkit/releases)),
which carries BERT 2.4.3 forward to current R, a current toolchain and a
current console. Upstream (sdllc) has not released since 2018; the whole set
of changes is offered back as pull request
[sdllc#220](https://github.com/sdllc/Basic-Excel-R-Toolkit/pull/220).

Newest first. The console shows this file under Help ▸ Release Notes, and
opens it by itself the first time you run a new version.

## 2.4.3-r8

Found by measuring the paths that run most often: a cell function being
recalculated, and a keystroke in the console.

### The console stopped answering when a reply was large

Node hands the console at most 64k per read, and the reader assumed every read
held whole messages -- there was a `FIXME` saying as much. A larger reply
arrived in pieces, the first piece failed to parse, was dropped, and the rest
was read as garbage; the request it belonged to never completed, so the shell
waited for an answer that was never coming.

It showed up as completion: a token matching 3,000 symbols answered in 26 ms,
while 4,000 hung indefinitely. The reader now keeps the remainder of a split
frame and waits for the rest. Replies of 340 kB, five reads and more, now
arrive intact in about half a second.

### Completion offers at most 500 matches

A list of several thousand is no use to read and made every keystroke carry a
large reply. Long lists are trimmed.

### Completions are asked for once typing pauses

The console asked R for completions on every keystroke, and the answer costs R
around 10 ms on an empty workspace and 28 ms on one holding 5,000 objects. A
fast typist queued one request per character. It now waits 90 ms for a pause
and asks once.

### Release notes showed the previous version's text

Open tabs are restored from a cache rather than re-read, which is right for a
file you are editing and wrong for the release notes: after an upgrade they
showed the notes you had already read. Rendered documents -- the notes and the
welcome page, neither of them editable here -- are now read from the file when
a tab is restored or reopened.

### Monaco no longer loads through node's vm module

The editor's loader took its node path in the renderer, pulling in node's `vm`
module, and Electron warned on every start that vm is unsupported there, that
crashes are likely, and that it may be removed. The loader has a switch for
this case: `preferScriptTags` keeps it on script tags. The warning is gone,
and the editor -- 92 languages, syntax colouring, undo, find -- is unchanged.

### For the record, what the measurements showed

A cell function costs **0.3 ms** end to end -- about 3,000 recalculations a
second; 60 cells recalculate in 24 ms. A 1,000-cell range argument costs
0.5 ms, a 20,000-cell range 3.7 ms, a 400-cell array result 0.5 ms. Console
evaluation round trips take 0.2-0.5 ms, and printing costs about 0.25 ms a
line with no slowdown as the scrollback fills. Functions are registered
non-volatile, so Excel recalculates them only when their inputs change.

Before r7 every cell function took **1,012 ms**, all of it a stray `Sleep`.

## 2.4.3-r7

### Excel froze whenever R called back into it

Any spreadsheet function that called back into Excel deadlocked: Excel showed
"Calculating" and stopped responding, R sat idle, and neither recovered. That
took out **R graphics entirely**, since the graphics device asks Excel which
cell it was called from and how big its shape is.

The add-in decides where to handle a callback by testing an event: signaled
means "a console call, switch context through COM", unsignaled means "the main
thread is blocked in a spreadsheet call, hand it over". The event was only
cleared a second after the call was sent (there was a leftover `Sleep(1000)`),
but R answers in about a millisecond, so callbacks were pushed through COM into
an Excel that was mid-calculation and could never service them.

The add-in now records Excel's main thread when it loads, clears the event
before the call goes out rather than after, and drops the sleep. Which branch a
callback takes is decided by the thread that made the call instead of by
timing. Verified with the worked example from
[bert-toolkit.com/r-graphics-in-excel](https://bert-toolkit.com/r-graphics-in-excel):
cell-linked and named devices, rotated text, transparency, rasters and UTF-8
labels all draw, and console callbacks still round-trip.

This is upstream code, untouched by the R 4.x work; it would have affected
anyone using `xlfCaller` or graphics from a cell.

### Console autocomplete broke on R 4.3 and later

`startup.R` compared a whole vector in `if (n == "" || ...)`. R has rejected a
length-2 condition since 4.3, so asking for a function's arguments printed
`'length = 2' in coercion to 'logical(1)'` into the shell. Now compares `n[1]`,
which is what the surrounding code already assumes and what R before 4.2 did
implicitly — same results on 3.5.0, 4.2.2 and 4.5.2.

### Closing a modified file asks first

Closing an edited file discarded the changes without a word; the source had
carried a `FIXME: warn if dirty` since 2018. It now offers Save, Don't Save or
Cancel, from the File menu and from the tab's close button alike. Saving can
fail (an unnamed file opens Save As, which you can cancel), and the file stays
open when it does. Close All and Close Others ask one file at a time and stop
at the first file you keep.

### Console completion degrades instead of erroring

The completion code borrows R's internal machinery — `utils:::.CompletionEnv`,
`.win32consoleCompletion` and a dozen more — which is not public API and
carries no promise between versions. Both entry points now sit behind a single
`tryCatch`, so a future R that renames or reshapes one of those costs you the
argument hints rather than printing an error into the shell on every keystroke.
One wrapper each, not one per candidate: measured at about five microseconds
against the eight milliseconds the completion search itself takes.

### Other fixes

- The console came back blank when you opened it a second time from the ribbon
  in the same session. It is now shown and restored rather than recreated, and
  restarted if the process has gone.
- Install Packages stalled on "loading packages" after you picked a mirror: the
  package list URL was built wrongly for repositories given as a list, and the
  failure was silent. The list also now reads as two fixed columns, name and
  description.
- The package list kept scrolling after the mouse wheel stopped, to the end of
  the list, because Chromium's scroll anchoring fought the virtual list.
- An alert that opened while another was fading out was hidden by the fade,
  leaving a dialog nobody could answer. Alert buttons are also spaced now, so
  three answers no longer read as one run of words.
- Release notes (this file) are shipped and shown in the console, which
  previously offered only the generic welcome page.
- `DebugOut` can be compiled into a release build with `BERT_TRACE`, and the
  callback handshake has named trace points, so a stall in the field can be
  traced with a debug-output viewer instead of guesswork.

## 2.4.3-r6

- **Function help in the formula bar.** Typing `=R.YourFunction(` shows the
  function's arguments, a description of the function and of the argument you
  are on, taken from `attr(f, "description")` in your R code. Excel gives
  add-ins no way to draw that tooltip itself, so the add-in writes an
  Excel-DNA IntelliSense file and the installer offers the IntelliSense add-in
  as an optional component, off by default. See `docs/FUNCTION-HELP.md`.
- Single-string `description` attributes were dropped when registering
  functions; only the vector form was read. Both work now, and feed Excel's
  Insert Function and Function Arguments dialogs.
- The installer registers and unregisters the help add-ins itself, filling the
  first free slot in Excel's add-in list and closing the gap on removal.
- R detection widened: per-user and per-machine registry entries, per-version
  subkeys, then Program Files, keeping the newest. It only warns when it finds
  no R, or nothing newer than 4.2.
- Cut, copy and paste work again in the editor, from the keyboard, the context
  menu and the Edit menu. Monaco 0.56 registers no clipboard actions of its
  own, and Electron 44 has no renderer clipboard module.

## 2.4.3-r5

- Protobuf and its dependencies are linked statically. The r4 binaries needed
  the Visual C++ redistributable, so on a machine without it the add-in failed
  to load: every function gave `#NAME?` and the console never appeared. The
  shipped binaries now import only system DLLs.

**2.4.3-r4 was withdrawn** for the fault above.

## 2.4.3-r4

First release of this fork.

- **Works with current R.** One `ControlR.exe` built against R 4.5.2, with a
  runtime version gate (floor 3.5) instead of a hard-coded 3.5 test. R is no
  longer bundled; the installer finds the R you have.
- **Unicode end to end.** The controller runs with the UTF-8 code page, picks
  its console encoding at runtime from the hosted R version (R 4.2 changed
  what R hands over), converts strings explicitly rather than assuming the
  native code page, and sends console text by length instead of relying on a
  terminator. `x <- "café"; nchar(x)` gives 4, and text survives the round trip
  between a cell, R and the console.
- **Current toolchain.** v145 toolset, protobuf 5.29 (C++) and 3.21
  (JavaScript), vcpkg manifest mode, ARM64EC configurations that link.
- **Current console.** Electron 44, TypeScript 7, Monaco 0.56, xterm 6, rxjs 7,
  chokidar 4, built with npm.
- **64-bit installer** that installs over an existing BERT 2 without touching
  `bert-config.json`, `user-stylesheet.less` or `Documents\BERT2`.
- The update check no longer points development builds at upstream's 2.4.4
  download page.
- Package names from CRAN no longer carry markup into the console.
- `docs/BUILDING.md` and `docs/MODERNISATION.md` describe the build, the R
  version policy and what is still outstanding.

## 2.4.4 and earlier

See the [upstream project](https://github.com/sdllc/Basic-Excel-R-Toolkit) and
[bert-toolkit.com](https://bert-toolkit.com).
