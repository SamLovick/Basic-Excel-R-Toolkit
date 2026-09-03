# Modernisation roadmap

This is the plan for bringing BERT up to date after the `r4-support` branch,
which makes the R controller work with R 4.x. It records what changed in R
and in the toolchain since the 2018 release, what has been done about each
change, and what is still to do, in a suggested order.

## Where the tree stands

* Native projects build with the v145 toolset in Visual Studio 2026, take
  protobuf 5.29.5 from vcpkg in manifest mode, and have ARM64EC
  configurations alongside x64.
* `ControlR.exe` is a single binary built against R 4.5.2. It checks the R
  version at startup instead of demanding exactly 3.5, and switches console
  output handling on the 4.2.0 change of native encoding. It starts under
  R 3.5.0, 4.2.2 and 4.5.2. Only 4.5.2 has been used with Excel.
* The console (on the `console-upgrade` branch) runs on Electron 44,
  TypeScript 7, Monaco 0.56, xterm 6, rxjs 7 and google-protobuf 4, with
  the smaller libraries current too. It keeps its architecture: Node in
  the renderer, `@electron/remote` for the few main-process calls. It has
  been used inside Excel: pipes connect, the editor and the R shell work.
  Left over from that work: the code is compiled with strict mode off
  and would benefit from being made strict-clean; Monaco is still loaded
  through its AMD loader, which in an Electron renderer uses Node's `vm`
  module (Electron warns about it), and the way out is bundling Monaco as
  ES modules; the page has no content security policy; the protobuf
  JavaScript is generated code from the 3.21 generator running on the 4.0
  runtime, and can be regenerated with protoc-gen-js 4.0.
* The Julia controllers target Julia 0.6 and 0.7 and are untouched. They
  cannot host Julia 1.x.
* The installer still bundles R 3.5.0.
* There are no automated tests, and nothing runs in CI.

## What changed in R since 3.5, and what it means here

| R | Change | Effect on BERT |
| --- | --- | --- |
| 4.0.0 | `stringsAsFactors` defaults to `FALSE` | R-level code in `Module/` and `Build/startup/startup.R` should be audited for reliance on the old default |
| 4.1.0 | Graphics engine 14: `DevDesc` gains pattern, clip-path and mask callbacks and a `deviceVersion` field | A device that leaves `deviceVersion` at 0 is treated as pre-4.1 and the new callbacks are never called. The two BERT devices do not set it, so this depends on the descriptor being zero-initialised. Set it explicitly (see below) |
| 4.2.0 | Native encoding becomes UTF-8 on Windows; UCRT runtime; 32-bit builds dropped; `Rstart` gains `RstartVersion` and `R_DefParamsEx`; graphics engine 15 (groups, stroke and fill paths) | Output encoding handled at runtime on this branch. The controller still calls `R_DefParams`, which leaves the version at 0 and keeps the binary loadable under older R. Win32 configurations no longer have an R to link against |
| 4.3.0 | `Rcomplex` becomes a union with a `_Complex` member | Not compilable by MSVC; `R_LEGACY_RCOMPLEX` selects the old layout. See `BUILDING.md` |
| 4.4.0 | Graphics engine 16 (glyph rendering) | Same as 4.1: opt in by version, or leave it |
| 4.5.0 | `Rstart` boolean fields become `int`; R starts hiding entry points that are not part of the API | The tree compiles against 4.5.2 headers so the struct matches. The controller is an embedding front end and uses the documented front-end entry points. `controlr_common.h` also declares four internal symbols by hand (`R_Visible`, `Rf_PrintWarnings`, `R_RestoreGlobalEnvFromFile`, `R_SaveGlobalEnvToFile`); none is referenced, so the declarations can go |

## Encoding: correct Unicode on every R

The 4.2.0 switch to UTF-8 is the change most likely to produce wrong
characters rather than a crash, and it cuts both ways: code written for
code-page R mangles UTF-8, and code written for UTF-8 R mangles code-page
strings. The branch handles one path, console output. The remaining paths
in `ControlR/src/rinterface_common.cc` and `controlr.cc` are:

1. **R strings out to Excel and the console.** `CHAR(Rf_asChar(x))` is
   passed through a validity heuristic and converted from the code page if
   it fails. Replace with `Rf_translateCharUTF8`, which honours the encoding
   mark each string carries and is correct on every version. This removes
   the heuristic.
2. **Strings in from Excel and the console.** `Rf_mkString` builds a
   native-encoded string from what are UTF-8 bytes, which is only right from
   4.2.0. Use `Rf_mkCharCE(s, CE_UTF8)` with `Rf_ScalarString` or
   `SET_STRING_ELT`, which is right everywhere. There are 28 call sites.
3. **Console input.** `R_ReadConsole` hands R the UTF-8 the console sent.
   Before 4.2.0 R expects the code page; convert when `r_console_utf8` is
   false, mirroring the output side.
4. **Paths.** The R home, the functions directory and file names cross the
   process boundary as narrow strings. Check what encoding the add-in sends
   and that the controller passes it on as R expects for its version.

After 1 to 3, `ValidUTF8` and `WindowsCPToUTF8` only serve the pre-4.2 path.

## Graphics devices

`console_graphics_device.cc` and `spreadsheet_graphics_device.cc` fill in a
`DevDesc` and hand it to `GEaddDevice2`. Since 4.1.0 R reads
`deviceVersion` to decide which callbacks exist. Set it explicitly to
`R_GE_definitions` (13) to declare the pre-4.1 surface the devices actually
implement, and confirm the descriptor is zero-initialised so the unset
callbacks are null. Implementing the 4.1 and later callbacks (patterns, clip
paths, masks, groups, glyphs) is optional; without them R falls back to
plain fills, which is what happens today.

## Toolchain and libraries

* **Protobuf.** Done. Keep `protoc` and `libprotobuf` at the same version:
  the generated C++ refuses to compile against any other. Regenerate with
  the `protoc` from the vcpkg install
  (`ControlR/vcpkg_installed/x64-windows/tools/protobuf/protoc.exe`).
  `PB/build.sh` still points at a protoc 3.5 checkout and needs updating.
  The JavaScript generator was split out of the main project after 3.21, so
  the console's `google-protobuf` stays on 3.21 until the console moves to
  the `protobuf-javascript` package.
* **Stale project settings.** `BERT.vcxproj` and the Win32 configurations
  of `ControlR.vcxproj` still list `../protobuf-3.5.0` and `E:\BERT2` paths
  that vcpkg has made irrelevant. Remove them. Decide whether to keep the
  Win32 configurations at all: 32-bit Excel users would need R 4.1 or
  older, and the controllers would have to be built against that R.
* **Console.** Every dependency is several major versions behind. Electron
  is the hard part: current Electron isolates the renderer from Node by
  default (`contextIsolation`, no `remote` module), and the console is
  written against direct Node access in the renderer. The order that keeps
  each step buildable is TypeScript first (compile-only changes), then
  xterm, monaco and rxjs one at a time (each has API changes), and Electron
  last, since it forces the main/renderer restructuring. Take a fresh look
  at whether the console should instead be rebuilt on a current stack once
  the R side is settled; the console's job is well defined and its
  protobuf interface is stable.
* **Julia.** The 0.6 and 0.7 embedding API does not exist in Julia 1.x, so
  supporting current Julia is a rewrite of the controller, not an upgrade.
  Decide whether to drop it. Either way it is separate from the R work.
* **Installer.** The NSIS script bundles R 3.5.0 and removes older bundled
  copies. Change it to use an R already installed (the registry key
  `HKLM\SOFTWARE\R-core\R\InstallPath` gives the current one) and write
  the chosen home into `bert-config.json`, or bundle a current R. Bundling
  is what tied BERT to one R version in the first place.
* **CI.** A GitHub Actions workflow on a Windows runner can build `ControlR`
  and the add-in with MSBuild and cache the vcpkg install. The hosted image
  may not carry the v145 toolset; `/p:PlatformToolset` can override it for
  the CI build.
* **Tests.** The controller can be driven without Excel: start
  `ControlR.exe -p <pipe> -r <R home>`, connect to the pipe, send an exec
  message from the protobuf schema and check the reply. A small harness that
  does this, in Node or Python, gives a smoke test for every R version on
  the machine and a place to put encoding round-trip tests. It would run in
  CI.

## Suggested order

1. Land `r4-support`.
2. Encoding, items 1 to 3 above. Small, high value, and the harness in the
   next step is the way to test it.
3. The smoke-test harness, then CI running it against the R versions the
   runner can install.
4. The graphics device `deviceVersion` change.
5. Remove the stale project settings and Win32 configurations; decide on
   Julia.
6. The console.
7. The installer.
