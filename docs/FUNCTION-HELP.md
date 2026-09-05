# Describing your functions to Excel

Excel can show a description of a function and of each of its arguments.
BERT passes both through from R, so an exported function can document
itself. This describes how to write the descriptions, where Excel shows
them, and how to get the argument tooltip that Excel otherwise reserves for
its own functions.

## Writing the descriptions

Descriptions are attributes on the function. The `description` attribute is
a character vector: the first element describes the function, and the rest
describe the arguments in order.

```r
TestAdd <- function(a, b) {
  a + b
}

attr(TestAdd, "description") <- c(
  "Adds two numbers",
  "the first number",
  "the second number")

attr(TestAdd, "category") <- "My Functions"
```

A function description on its own is fine:

```r
attr(EigenValues, "description") <- "Eigenvalues of a matrix, as a vector"
```

To describe a later argument but not an earlier one, leave the earlier one
empty:

```r
attr(Interpolate, "description") <- c("Interpolates a series", "", "", "the method to use")
```

`category` sets the group the function appears under in the Insert Function
dialog. Without it, functions are grouped as "Exported R Functions".

Nothing else is needed. BERT re-reads the file when you save it and
re-registers the functions with their descriptions.

### What you get without writing anything

Arguments with a default value are described as "Default `<value>`", so
`function(x, n = 10)` documents `n` on its own. Argument names always
appear, whether or not there are descriptions.

## Where Excel shows them

**The Insert Function dialog**, reached with the fx button beside the
formula bar. It lists your functions under their category and shows the
function description.

**The Function Arguments dialog**, which is the useful one. Type
`=R.TestAdd(` in a cell and press Ctrl+A, or click fx, and Excel shows a
box per argument with that argument's description underneath as you move
between them.

**Not the inline tooltip.** The grey tooltip that appears as you type past
the open bracket, listing the arguments, is drawn by Excel only for its own
built-in functions. No add-in can produce it, whether it is written as an
XLL like BERT or in VBA. The next section is the way around that.

## The argument tooltip, through Excel-DNA IntelliSense

[Excel-DNA IntelliSense](https://github.com/Excel-DNA/IntelliSense) exists
to fill exactly this gap. It is a separate add-in that watches the formula
editor and draws its own tooltip, so user-defined functions get argument
help as you type. It is open source and MIT licensed.

It reads function descriptions from an XML file. BERT writes that file,
named `BERT-IntelliSense.intellisense.xml`, into its own directory
(`%LOCALAPPDATA%\BERT2`) every time it registers functions, so it always
matches the functions you have loaded.

The IntelliSense add-in finds the file by looking beside each loaded
workbook or workbook add-in, and it deliberately ignores XLL add-ins like
BERT. `BERT-IntelliSense.xlam` bridges that gap: it is an empty add-in whose
only job is to be the file the XML sits beside.

The installer offers this as "Function help in the formula bar", a tick box
on its components page, off by default. Selecting it installs both add-ins
and switches them on in Excel. Running the installer again with the box
cleared removes them, and uninstalling BERT removes them too. For scripted
installs, `/HELP-FEATURE` and `/NO-HELP-FEATURE` set it from the command
line.

Then type `=R.` and one of your function names in a cell. The tooltip
appears as you type past the open bracket, showing the signature with the
current argument in bold, the function description, and the description of
the argument you are on. It follows the argument as you type commas.

To add or remove it by hand instead, the two add-ins live in
`%LOCALAPPDATA%\BERT2` and are loaded through File > Options > Add-ins >
Manage Excel Add-ins > Browse.

The help add-in looks for the descriptions as Excel starts, and ignores the
file if it is not there yet. On a brand-new installation BERT has not
written one, so the installer lays down a starter file describing the two
example functions; BERT replaces it with your own the first time it
registers them.

If a tooltip does not appear, check first that the function is registered at
all: start typing its name in a cell and see whether Excel offers it in the
autocomplete list. A function that has been renamed, or whose file has left
your functions directory, has nothing to describe.

Checked with IntelliSense 1.9.0 and 64-bit Excel from Microsoft 365 on
Windows 11, against functions described as above.

Two things to weigh, which is why it is off by default. The IntelliSense
add-in is not code-signed, so Excel and SmartScreen may warn about it, and
it is a second add-in in your setup that BERT does not control. If you
would rather not, leave the box clear: the dialogs described above need
nothing extra.

## Longer help: a page of it

The descriptions above are one line each, which is all Excel's dialogs have
room for. For anything longer -- what the function actually does, the
assumptions behind it, an example -- write a comment block above the
function, in the style roxygen2 uses:

```r
#' Compound annual growth rate
#'
#' The constant rate of growth that would take `StartValue` to `EndValue`
#' over `NumberOfYears` periods. The result is a rate, so format the cell
#' as a percentage.
#'
#' @param StartValue value at the start of the first period
#' @param EndValue value at the end of the last period
#' @param NumberOfYears number of periods between the two values
#'
#' @details Both values must have the same sign and neither may be zero.
#' @return The growth rate per period, as a decimal fraction.
#'
#' @examples
#' =R.CAGR(100, 150, 5)     ' 0.0845
#'
#' @seealso FiniteTerminalValue
CAGR <- function(StartValue, EndValue, NumberOfYears) {
  (EndValue / StartValue) ^ (1 / NumberOfYears) - 1
}
```

BERT renders that into a page and registers it as the function's help topic.
**Help on this function**, at the bottom left of the Function Arguments
dialog, opens it; so does the link in the IntelliSense tooltip, if you have
that installed.

The block does double duty: the first paragraph becomes the function's
one-line description and each `@param` becomes that argument's, so a
documented function needs no `description` attribute. An explicit
`attr(f, "description")` still wins if you have both, which is useful when
the dialog wants shorter wording than the page.

Recognized tags are `@param`, `@return` (or `@returns`), `@details`,
`@examples`, `@seealso`, `@category` and `@url`. Anything else is treated as
description text rather than an error, so a function documented for
roxygen2 loads unchanged. Within the text, `` `code` `` and `**bold**` are
rendered.

The same text can go on the function instead of above it, which suits
functions that are generated rather than typed:

```r
attr(CAGR, "help") <- c(
  "Compound annual growth rate",
  "",
  "@param StartValue value at the start of the first period")
```

To point at documentation you already have somewhere else, give the address
instead, and no page is generated:

```r
attr(CAGR, "help.url") <- "https://example.com/docs/cagr.html"
```

`@url` in a comment block does the same thing.

### Where the pages live

In `%LOCALAPPDATA%\BERT2\help`: one self-contained html file per documented
function, rewritten every time BERT registers functions, so an edit to a
comment shows up as soon as you save the file. Pages for functions that no
longer have documentation are removed.

Excel will not open a help topic from a file path -- the topic has to be a
URL or a `.chm`, which is Excel's rule, not BERT's. So the add-in serves the
pages itself, from a listener bound to `127.0.0.1` on a port Windows picks,
started only if some function has help and shut down with Excel. Nothing
outside the machine can reach it, and it serves nothing but those generated
pages.

A comment block is not part of the function object -- R keeps source
references for the body, not for what sits above the definition -- so BERT
reads the file itself, after loading it, and matches each block to the
definition that follows it. A block followed by anything else is ignored.

## How it travels

Worth knowing when something does not appear where you expect.

The descriptions live on the R function. `BERT$list.functions` reads them
with `attributes`, the controller turns them into the function descriptor it
sends to the add-in, and the add-in passes them to Excel's `xlfRegister`,
which takes a function description and one help string per argument. BERT
registers room for 22 of those, so a function with more arguments than that
still works, but the arguments past the 22nd are not described.

The same descriptors produce the IntelliSense XML, so both routes always
agree.

Long-form help travels the same way, in two more fields on the descriptor:
`help_url` for an address the function carries, `help_file` for a page
`startup.R` generated. The add-in turns whichever it gets into the help
topic it registers, appending `!0` -- the context id Excel's topic format
requires.
