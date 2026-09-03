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

To try it:

1. Download `ExcelDna.IntelliSense64.xll` from the
   [releases page](https://github.com/Excel-DNA/IntelliSense/releases) and
   load it in Excel, through File > Options > Add-ins > Manage Excel
   Add-ins > Browse.
2. Load `%LOCALAPPDATA%\BERT2\BERT-IntelliSense.xlam` the same way.
3. Type `=R.` and one of your function names in a cell. The tooltip appears
   as you type past the open bracket, and moves through your argument
   descriptions as you type commas.

This is a prototype. It has not been tested against every version of Excel,
and it adds a second add-in to your setup, which is a real cost. If you do
not want the tooltip, skip it: the dialogs described above work with no
extra add-ins.

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
