# BERT changelog

Releases of this fork ([SamLovick/Basic-Excel-R-Toolkit](https://github.com/SamLovick/Basic-Excel-R-Toolkit/releases)),
which carries BERT 2.4.3 forward to current R, a current toolchain and a
current console. Upstream (sdllc) has not released since 2018; the whole set
of changes is offered back as pull request
[sdllc#220](https://github.com/sdllc/Basic-Excel-R-Toolkit/pull/220).

Newest first. The console shows this file under Help ▸ Release Notes, and
opens it by itself the first time you run a new version.

## Which R versions this works with

**R 3.5 through 4.6, all of it.** Cell functions, the console, Excel
references, graphics and function help work on every version the controller
runs on.

| Your R | Functions in cells | Console | Excel references | Graphics | Function help |
| --- | --- | --- | --- | --- | --- |
| 4.6.x | yes | yes | yes | yes | yes |
| 4.5.x | yes | yes | yes | yes | yes |
| 4.4.x | yes | yes | yes | yes* | yes |
| 4.3.x | yes | yes | yes | yes* | yes |
| 4.2.x | yes | yes | yes | yes | yes |
| 3.5.x | yes | yes | yes | yes | yes |

Tested in Excel on 4.6.1, 4.5.2, 4.2.2 and 3.5.0. \* 4.3 and 4.4 ship modules
built and checked on CI but are not tested in Excel here, for want of those R
versions on the build machine; they work by the same mechanism as the four
that are tested.

### How it works, and what to watch for

One `ControlR.exe` hosts every version of R from 3.5 up. The part that does
not travel between versions is `BERTModule`, a compiled R package providing
the graphics devices, the `xlReference` class used for Excel references, and
a few helpers. R checks a module's **graphics engine version** whenever a
graphics device is created, and that version changes between R series -- 4.2
is `R_GE_group`, 4.5 is `R_GE_glyphs`, 4.6 is `R_GE_fontVar` -- so a module
built for one series cannot draw on another.

The install therefore ships one module per series in
`module/<major>.<minor>`, and `startup.R` loads the one matching the R it is
hosted in. All six are about 3 MB together, so there is nothing to choose at
install time and no reason to ship separate downloads per R version: upgrade
your R and BERT picks up the matching module by itself.

If you run an R with no module -- a future series, say -- BERT falls back to
another module, which still loads and still provides references and the
helpers; only drawing is lost, and the console says so at startup.

## Unreleased

### The release notes read better

Presentation only, in the console's rendered markdown -- these notes and the
welcome page. Subheadings were indented further than the text beneath them,
so they now share the paragraph indent. A table has no left padding of its
own, so its first column started to the left of the surrounding text: it now
lines up, with cell padding and a rule under the header row. List items ran
together, and now sit a paragraph's space apart.

## 2.4.3-r12

### Complex numbers lost all but six digits on the way to Excel

Excel has no complex type, so a complex value crosses as text in the `a+bi`
form Excel's own engineering functions use -- `IMREAL`, `IMABS` and the rest
read it directly, and it is byte-identical to what Excel's `COMPLEX()`
produces. But the conversion used default stream formatting, which is six
significant figures, so

    314159.2653589793 + 2.718281828459045i

arrived in the cell as `314159+2.71828i`. Everything past six digits was gone,
silently. Ordinary doubles were never affected: they cross as binary doubles.

Now formatted with 15 significant digits, which is what Excel itself keeps and
what R prints. `IMREAL` of a value returned from R, minus the same number
computed in the sheet, is now exactly zero.

## 2.4.3-r11

### Graphics and Excel references now work on every supported R

r10 shipped modules for 4.5 and 4.6 only, so on 4.2 to 4.4 you lost drawing,
and on 3.5 you lost Excel references as well. Modules now ship for **3.5,
4.2, 4.3, 4.4, 4.5 and 4.6** -- the whole range the controller runs on. All
six are 3 MB together.

The obstacle was never the code: it was that building a module for a series
needs that R and its matching Rtools on the build machine, well over a
gigabyte of downloads per series. A workflow now builds them on runners
instead, one job per series, each checking that the module it produced really
was built for the R it claims. `build-release.ps1 -FetchModules` takes the
modules from the last successful run of that workflow, verifying the same
thing again before packaging.

Verified in Excel: drawing and Excel references both work on R 3.5.0 and
4.2.2, which is what r10 could not do, and 4.5.2 and 4.6.1 are unchanged.

## 2.4.3-r10

### R 4.6 works

`Rf_isFrame` was removed in R 4.6; the one place that used it now calls
`Rf_inherits(sexp, "data.frame")`, which does the same job and has been
stable API since long before 3.5. That was the only source change 4.6 needed:
the controller compiles against 4.6's headers, links against the existing
import libraries, and runs.

### Graphics now works on more than one R series

`BERTModule` carries the graphics devices, and R checks its graphics engine
version whenever a device is created. That version changes between R series
-- 4.2 is `R_GE_group`, 4.5 is `R_GE_glyphs`, 4.6 is `R_GE_fontVar` -- so a
module built for one series cannot draw on another. It fails with "Graphics
API version mismatch".

Until now one module was built and shipped, so **graphics only ever worked on
the series it happened to be built against**: r9 shipped a 4.5 module, and
plotting from a cell failed on R 4.2 exactly as it did on 4.6. That was not
noticed because the build machine runs 4.5.

The install now ships one module per series in `module/<major>.<minor>` and
loads the one matching your R, falling back to any other module when there is
no match -- a module from another series still provides the `xlReference`
class and the helpers, so everything except drawing keeps working. Modules
ship for R 4.5 and 4.6. The console says at startup when graphics will not be
available and why.

### Elsewhere

- The version gate accepts 4.6 without complaint, and warns above it.
- `build-release.ps1 -ModuleRHomes` takes the R installations to build
  modules against. It cleans `Module/src` between them: `R CMD INSTALL` will
  otherwise relink from object files compiled against another R, producing a
  module that claims to be built for one series and behaves as another.

## 2.4.3-r9

Two build-correctness fixes and a clearer refusal. Nothing in how BERT behaves
day to day changes; if r8 works for you, this is not urgent.

### The controller only built against a hand-edited R header

`R_ReadConsole` was declared with R 3.5's signature, `char *buf`. R 4.2
changed that callback's buffer to `unsigned char *`, so against a stock R 4.2
or later the assignment to `Rp->ReadConsole` does not compile. It built here
only because the R tree this repository is built against had `RStartup.h`
edited by hand to say `char *` -- which means every binary up to r8 was
compiled against a modified R header, and nobody could build the controller
from a clean checkout with an R from CRAN.

The callback now follows whichever headers it is compiled against. Verified
against stock R 4.5.2 and stock R 4.2.2.

### R 4.6 is refused clearly rather than attempted quietly

The runtime version gate only compared the major version, so R 4.6 passed it
without comment and the first sign of trouble would have come later and less
clearly. It now compares the minor version too and says the version is not
supported yet. **R 4.6 is not supported**: it removed `Rf_isFrame` and changed
the ReadConsole callback signature.

### The vcpkg baseline is pinned for every project

`vcpkg-configuration.json`, which pins the registry baseline, sat only beside
the add-in's manifest. Building the controller or the ribbon on its own took
whatever baseline the local vcpkg defaulted to, which could resolve a protobuf
incompatible with the checked-in generated code. All three manifests now pin
the same baseline.

### Elsewhere

- `AddUserButton` tested `id == 0` without establishing that `id` is one
  value, the same shape that stopped completion working on R 4.3.
- There is a build on GitHub Actions now: the console, and `startup.R` against
  four R versions. It is what found the first two items above.

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
