# Running BERT without the ribbon

BERT ships two binaries that Excel loads: `BERT64.xll`, the add-in proper,
and `BERTRibbon2x64.dll`, a COM add-in that draws the BERT tab. The tab is
optional, and this describes what you get without it, why you might want
that, and the one thing that had to change to make it work.

## Why bother

The XLL is loaded by Excel from a file path and needs no registration. The
ribbon is a COM add-in: it has to be registered with `regsvr32`, it appears
in Excel's COM add-ins list where Excel can disable it after a crash, and
it is the only part of the install that touches anything outside BERT's own
directory. In a locked-down environment, or when you simply want fewer
moving parts, dropping it leaves a smaller install with the same
capabilities.

## What you lose

The tab itself, and with it the console button, and any buttons your R code
adds with `BERT$AddUserButton` -- those are ribbon controls, so there is
nowhere to draw them. `AddUserButton` still returns an id and BERT holds the
button, so if the ribbon is installed later the buttons appear.

That is the whole list. Functions in cells, the console, graphics, Excel
references, the `EXCEL` object in R and function help all work.

## Opening the console, and getting it back

The console button lives on the ribbon, so without the tab you need another
way in. There are four; the first two cover most of it.

**At startup.** Set this in `bert-config.json`:

```json
"BERT": {
  "openConsole": true
}
```

and the console opens with Excel. `EXCEL.EXE /x:BERT` does the same for a
single run.

**CONTROL+SHIFT+R**, which is the shortcut BERT registers the console
command with.

**By name.** `BERT.Console` is a registered Excel command, so
`Application.Run "BERT.Console"` runs it from VBA, from the Immediate
window, or from a shape you draw on a sheet and assign a macro to. The same
name can be typed into the macro dialog (ALT+F8) and run: Excel hides XLL
commands from that list, but as its own documentation puts it, their names
"can be entered anywhere a valid command name is required".

**From R**, which suits a workbook that should open the console itself:

```r
ShowConsole <- function() EXCEL$Application$Run("BERT.Console")
```

### Closing it is not closing it

Clicking the X on the console hides the window. The process stays running
with R attached, so any of the routes above brings it back with the shell
history and open files intact. If the process really has gone -- killed from
Task Manager, say -- `BERT.Console` starts a new one.

Verified with the ribbon disabled: the console opened with Excel, closing it
with the X left the window hidden and the process alive, and running
`BERT.Console` made it visible again. The keyboard shortcut is the one part
not tested here, because the test harness cannot press keys.

## Turning the ribbon off on an install you already have

Excel: **File > Options > Add-ins**, set *Manage* to **COM Add-ins**, click
**Go**, and clear **BERT2 Ribbon Menu**. That leaves it registered but not
loaded, and Excel remembers the choice. The same switch lives in the
registry at
`HKCU\Software\Microsoft\Office\Excel\Addins\BERT2Ribbon.Connect`, where
`LoadBehavior` is 3 for loaded and 0 for off.

Note what that does *not* do on a normal install: the ribbon is what loads
the xll, so turning it off there leaves you with no BERT at all until the
xll is registered with Excel directly (File > Options > Add-ins, *Manage*
**Excel Add-ins**, Browse to `BERT64.xll`). An install done the way the next
section describes has already done that for you.

## Installing this way

The installer's components page has a **BERT tab on the ribbon** box,
selected by default. Clear it for an XLL-only install; clear it on a later
run over an existing install and the ribbon is unregistered and removed.
For scripted installs, `/NO-RIBBON` and `/RIBBON` set it from the command
line, alongside the existing `/HELP-FEATURE` and `/NO-HELP-FEATURE`:

```
BERT-Installer-2.4.3-rNN-x64.exe /S /NO-RIBBON
```

## What had to change

Drawing into a sheet and the `EXCEL` object in R both need Excel's
`Application` object, and the add-in had no way of its own to get one: the
ribbon passed it in as it loaded, through `BERT_SetPointers`. Without the
ribbon the pointer stayed null, `BERTGraphics::CreateDeviceTarget` took its
`if (application_pointer)` branch, and plotting from a cell quietly drew
nothing at all.

The add-in now asks Excel for the pointer itself when nobody has handed one
over: find this process's Excel frame window (`XLMAIN`, matched against
`xlGetHwnd`), walk down to the sheet pane (`XLDESK` then `EXCEL7`), and call
`AccessibleObjectFromWindow` on it with `OBJID_NATIVEOM`. That returns the
window's object model, and `Application` hangs off it. This is the standard
route for an add-in with no COM component of its own; Excel-DNA does the
same thing.

It is acquired lazily, on first use rather than at load, because the pane
window does not exist while Excel is still starting up. With the ribbon
installed nothing changes: it hands the pointer over first and the fallback
never runs.
