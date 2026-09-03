# Building BERT

These notes describe the build as it stands on the `r4-support` branch. The
"Requirements (Building)" section of the top-level README describes the
original 2018 setup and is kept for reference.

## Layout

| Directory | What it is |
| --- | --- |
| `BERT/` | The Excel add-in (`BERT64.xll`), the solution file, and the vcpkg configuration shared by the native projects |
| `ControlR/` | The R language controller, `ControlR.exe`. Hosts R out of process and talks to the add-in and the console over named pipes |
| `ControlJulia/`, `ControlJulia-0.7/` | The Julia language controllers, for Julia 0.6 and 0.7 |
| `Ribbon/` | The Excel ribbon COM add-in |
| `Console/` | The Electron console (editor and shell) |
| `PB/` | The protobuf schema for all inter-process messages, and the generated C++ |
| `Common/` | Code shared by the native projects |
| `Module/` | The `BERTModule` R package installed into the hosted R |
| `Install/` | The NSIS installer |
| `Build/` | Build output. Everything built lands here, next to the runtime configuration files that are checked in |

## Prerequisites

* Visual Studio 2026 (version 18) with the "Desktop development with C++"
  workload. The projects use the v145 toolset and the latest installed
  Windows SDK. For the ARM64EC configurations, add the ARM64/ARM64EC build
  tools component.
* vcpkg, as installed by Visual Studio. The native projects use vcpkg in
  manifest mode: each has a `vcpkg.json` naming its dependencies (protobuf),
  and `BERT/vcpkg-configuration.json` pins the registry baseline. The first
  build of each project installs the dependencies into a `vcpkg_installed/`
  directory beside it, which is ignored by git and can be deleted freely.
* An R installation. The tree is currently built against R 4.5.2; see
  "The R installation" below.
* The Excel SDK, for the add-in project only.
* Node and yarn, for the console only.
* NSIS, for the installer only.

## The R installation

`ControlR` compiles against R's headers and links against import libraries
generated from R's DLLs. Both come from one R installation, named by the
MSBuild property `BertRHome`.

`BertRHome` defaults to `R-4.5.2` in the repository root, which is ignored
by git. Either copy your R installation there or point a junction at it:

```powershell
New-Item -ItemType Junction -Path R-4.5.2 -Target "C:\Program Files\R\R-4.5.2"
```

To build against an R installed elsewhere, set the property on the command
line instead:

```powershell
msbuild ControlR\ControlR.vcxproj /p:Configuration=Release /p:Platform=x64 /p:BertRHome="C:\Program Files\R\R-4.5.2"
```

### Import libraries

`ControlR/lib/` holds the import libraries the controller links against, and
the `.def` export lists they were generated from, so that a change in the
export list is visible in review:

| File | Purpose |
| --- | --- |
| `R64.def`, `RGraphApp64.def` | Export lists of `R.dll` and `RGraphApp.dll`, taken from R 4.5.2 |
| `R64.lib`, `RGraphApp64.lib` | x64 import libraries built from those lists |
| `R64arm.lib`, `RGraphApp64arm.lib` | ARM64X import libraries built from the same lists, for the ARM64EC configurations |

To regenerate them from a different R, run `RebuildLibs.ps1` from a Visual
Studio developer PowerShell (it needs `dumpbin` and `lib`):

```powershell
cd ControlR\lib
.\RebuildLibs.ps1 -R "C:\Program Files\R\R-4.5.2" -def -x64 -ARM64
```

R for Windows has shipped x64 binaries only since 4.2.0, so the ARM64X
libraries are built from the x64 export lists, and the `-x86` switch is only
useful with an R old enough to include an i386 build.

### Why `R_LEGACY_RCOMPLEX` is defined

From 4.3.0, `R_ext/Complex.h` defines `Rcomplex` as a union whose second
member is a C99 `double _Complex`. MSVC does not implement `_Complex`, so the
header does not compile under MSVC without `R_LEGACY_RCOMPLEX`, which selects
the older two-`double` struct. The memory layout is the same either way, and
this code only reads and writes the `r` and `i` members. The define is set in
every `ControlR` configuration.

## Building

The full solution:

```powershell
msbuild BERT\BERT.sln /p:Configuration=Release /p:Platform=x64
```

Just the R controller, which is all you need when working on the R side:

```powershell
msbuild ControlR\ControlR.vcxproj /p:Configuration=Release /p:Platform=x64
```

`msbuild` is at `C:\Program Files\Microsoft Visual Studio\18\Community\MSBuild\Current\Bin\MSBuild.exe`
if it is not on your path. x64 output goes to `Build\`; the ARM64EC configurations write to `ControlR\ARM64EC\<Configuration>\` instead.

The console is built separately with yarn, from `Console/`:

```powershell
yarn install
yarn build
yarn package
```

The console's dependencies are pinned by `yarn.lock` to the versions the
code was written against, which are old; see `MODERNISATION.md`.

## Running against your own R

BERT reads `Build\bert-languages.json` (installed as `bert-languages.json`
in the BERT directory) for the list of languages. Its default R home,
`%BERT_HOME%\R-3.5.0`, is the R that the installer used to bundle. To use
another R, set the home and library in `bert-config.json`, which lives in the
directory next to `BERT64.xll`, the directory BERT exports as `%BERT_HOME%`:

```json
"BERT": {
  "R": {
    "home": "C:\\Program Files\\R\\R-4.5.2",
    "lib": "C:\\Users\\you\\AppData\\Local\\R\\win-library\\4.5"
  }
}
```

Restart Excel after changing this section.

## Which versions of R the controller accepts

The controller checks the version reported by the loaded `R.dll` at startup
(`main` in `ControlR/src/controlr.cc`). It refuses to start under R older
than 3.5, warns but continues under a major series newer than 4, and
otherwise runs. The floor is the oldest series this code has been built
against; the reason there is no ceiling is that the loader resolves the
import libraries before `main` runs, so an R lacking a symbol the controller
needs has already failed to start by the time the check happens.

What has actually been exercised on this branch:

| R | Status |
| --- | --- |
| 4.5.2 | Built against. Used with Excel and the console |
| 4.2.2 | `ControlR.exe` starts under it and reports the version correctly. Not used with Excel |
| 3.5.0 | `ControlR.exe` starts under it and reports the version correctly. Not used with Excel |
| 3.5 to 4.1 generally | Expected to work, untested |

The one behavioural difference the controller keys off the version is
console output encoding. R for Windows switched its native encoding to
UTF-8 in 4.2.0; before that, console output arrived in the Windows code
page and the controller converts it to UTF-8. See `R_WriteConsoleEx` in
`ControlR/src/rinterface_win.cc`.
