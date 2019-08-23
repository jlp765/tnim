## **TNim** (TinyNim) is a quasi-interactive REPL
##
## It is a stop-gap replacement for the
## functionality that was in old versions of Nim, and
## is now
## ``nim secret``
## (note: nim secret uses the VM in Nim, so it only allows the import of a subset of modules)
##
## It compiles and runs code similar to the
## way you would do this, and does this using a shell
## command in the background (
## ``nim c -r --verbosity:0 --hints:off <file>`` )
##
##  *Warning: this is SLOW!!.  It is a quick and dirty
##  interactive tool, not a sleek and shiny speed demon.*
##
## If you need to work with blocks of code as part of some project, then TNim can be primed with this code
## prior to being run (rather than having to paste chunks of code into TNim).  Add this code to
## the `SavedFileName<#SavedFileName>`_ (tnim_dat.dat), then run TNim.
##
## If the buffers are not cleared (``\qc`` or ``\c``), then the code will remain in
## the `SavedFileName<#SavedFileName>`_, and
## will be available next time TNim is run.
##
## Commands:
## ---------
## .. code-block:: Nim
##
##  \?,  \h, \help             this information.
##  \l,  \list                 list the previous code history (w/ line nr's)
##  \ln, \listnn               list with No (line) Numbers (raw code listing).
##  \c,  \clear                clear the current history buffer.
##  \d,  \delete [f [t]]       delete lines(s) [f [optionally to t]].
##                             delete last line if none specified.
##  \e,  \eval                 force the eval (compile/run) of the code buffer.
##  \ec, \edconfig <editor>    define the path/name to an external editor
##                             (if not defined, uses notepad (win) or vi)
##  \ed, \edit                 edit code in the code buffer.
##                             (then reloads the code buffer, lists the code,
##                              and evals (compile/run) the code)
##  \r,  \read <filename>      read code from <filename> and run.
##                             Saved history is read on startup.
##                             data from file is auto evaluated after reading.
##  \s,  \set [<option=value>] set {maxBlocks,indent}
##  \v,  \version              display the name and version.
##  \w,  \write [<filename>]   write code history [to <filename>].
##                             \w by itself overwrites saved history (tnim_dat.dat).
##                             \c followed by \w clears saved history.
##  \q,  \quit                 quit, saving code history to tnim_dat.dat file.
##  \qc, \quitclear            quit, clearing code history in tnim_dat.dat file.
##
## Vars and Consts
## -----
## The Vars and Consts Sections is included to provide clues about the TNim internal settings.
##
import strutils, tables, os, osproc, rdstdin

const
  TnimName*      = "TNim"
  TnimVersion*   = 2.03
  TnimStart*     = "nim> "         ## the TNim prompt
  TnimContinue*  = ".... "         #  add "..".repeat(n) before this
  SavedFileName* = "tnim_dat.dat"  ## this file will hold the code you have typed (until cleared), or you can add code
                                   ## to this before file prior to running TNim

# run-time Configurable but effectively const Config variables
var
  maxBlocks*  = 100_000   ##  code blocks, or lines of code not in a code block
  indentSize* = 2
  editorPath* = ""        ## set this via \ec command

type
  CodeBlock = object   ## blocks of code (a block is the outer scope level)
    lines: seq[string]
    compiles: bool
    firstOutput: string
    lastOutput: string

  CodeBlocks = seq[CodeBlock]
  #PCodeBlocks = ptr CodeBlocks

  EvalOutput = object
    msg: seq[string]
    output: seq[string]

  EvalOutputs = seq[EvalOutput]
  #PEvalOutputs = ptr EvalOutputs


var
  code: CodeBlocks = @[]  # a code block is multi lines for if, proc, block, etc
  evalResults: EvalOutputs = @[]
  blockNr: int = 0        # index of next block to add, not current blockNr
  currIndent = 0          # starts at 0 for no indent at top scope level
  inputCmds = initTable[string, proc(w: seq[string])]()
  getOut = false          # flag to trigger exit of REPL
  #currDir = getAppDir()
  doEval = false          # force re-evaluation of the code buffer

# ---------------- forward declarations -----------
proc tnimClear(w: seq[string])
proc tnimDelete(w: seq[string])
proc tnimEval(w: seq[string])
proc tnimEdit(w: seq[string])
proc tnimEdConfig(w: seq[string])
proc tnimHelp(w: seq[string])
proc tnimList(w: seq[string])
proc tnimNrList(w: seq[string])
proc tnimQuit(w: seq[string])
proc tnimQuitClear(w: seq[string])
proc tnimRead(w: seq[string])
proc tnimSet(w: seq[string])
proc tnimWrite(w: seq[string])
proc tnimVersion(w: seq[string])

# ---------------- general stuff ------------------
proc doInit() =
  inputCmds.add(r"\?",            tnimHelp)
  inputCmds.add(r"\h",            tnimHelp)
  inputCmds.add(r"\help",         tnimHelp)
  inputCmds.add(r"\l",            tnimNrList)
  inputCmds.add(r"\list",         tnimNrList)
  inputCmds.add(r"\ln",           tnimList)
  inputCmds.add(r"\listnn",       tnimList)
  inputCmds.add(r"\c",            tnimClear)
  inputCmds.add(r"\clear",        tnimClear)
  inputCmds.add(r"\d",            tnimDelete)
  inputCmds.add(r"\delete",       tnimDelete)
  inputCmds.add(r"\e",            tnimEval)
  inputCmds.add(r"\eval",         tnimEval)
  inputCmds.add(r"\ed",           tnimEdit)
  inputCmds.add(r"\edit",         tnimEdit)
  inputCmds.add(r"\ec",           tnimEdConfig)
  inputCmds.add(r"\edconfig",     tnimEdConfig)
  inputCmds.add(r"\v",            tnimVersion)
  inputCmds.add(r"\version",      tnimVersion)
  inputCmds.add(r"\w",            tnimWrite)
  inputCmds.add(r"\write",        tnimWrite)
  inputCmds.add(r"\r",            tnimRead)
  inputCmds.add(r"\read",         tnimRead)
  inputCmds.add(r"\s",            tnimSet)
  inputCmds.add(r"\set",          tnimSet)
  inputCmds.add(r"\q",            tnimQuit)
  inputCmds.add(r"\quit",         tnimQuit)
  inputCmds.add(r"\qc",           tnimQuitClear)
  inputCmds.add(r"\quitclear",    tnimQuitClear)

proc errMsg(s:string) =
  writeLine(stderr, TnimStart & "Error: " & s)

#proc add(cb: var CodeBlocks, lines: seq[string]) =
#  var newCB: CodeBlock
#  newCB.lines = lines
#  newCB.compiles = false
#  cb.add(newCB)

proc add(cb: var CodeBlocks, line: string) =
  var newCB: CodeBlock
  newCB.lines = @[line]
  newCB.compiles = false
  cb.add(newCB)
  inc(blockNr)

proc getCmdLineOpts() =
  ## get any configuration and running options
  discard

proc words(s: string): seq[string] {.inline.} =
  ## strip leading/trailing space and split into words
  ## returning a seq of words (string)
  result = s.strip(leading=true, trailing=true).split()

proc isDigits(s: string): bool =
  ## return true if all chars are Digits
  result = (s.len > 0)
  for c in s:
    result = result and (c in Digits)

proc getIndent(s: string): int =
  ## number of indent spaces at start of line
  ## base on the setting of indentSize (default=2)
  ## so getIndent is 1 for two spaces when indentSize=2
  var spaceCnt = 0
  result = 0
  for i,c in pairs(s):
    if c == ' ': inc(spaceCnt)
    else: break
  let x = spaceCnt.`div`(indentSize)
  # allow for end of indent shown by change in indent
  if x < currIndent: currIndent = x
  # check event nr of spaces
  #if spaceCnt != (x * indentSize):
  #  if spaceCnt < (x * indentSize):
  #    dec(indentSize)
  #    result = x
  #  else:
  #    errMsg("indentation is incorrect")
  #    result = -1
  #else:
  result = x

proc getInt(s: string): int =
  var
    i = 0
  result = 0
  while i < s.len and s[i] notIn Digits:
    inc(i)
  while i < s.len and s[i] in Digits:
    result = 10 * result + ord(s[i]) - ord('0')
    inc(i)

proc getCodeLine(ln: int): string =
  # linenumber ln is a 1.. based index, not a seq[] index
  var
    actLineNr = 0
    cIndx = 0
  result = ""
  while cIndx < code.len:
    for j in 0..<code[cIndx].lines.len:
      if actLineNr == ln-1:
        result = code[cIndx].lines[j]
        return
      inc(actLineNr)
    code[cIndx].compiles = true
    inc(cIndx)

proc filterCompileLines[T](s: T): string =
  # return the error message of the fail
  result = ""
  var
    tStr = ""
    tStr2 = ""
    lineNr = 0
    posNr = 0
  for line in s.splitLines():
    if line.contains(") Error"):
      tStr = line[SavedFileName.len..<line.len]
      tStr2 = tStr[find(tStr,"Error")..<tStr.len]
      lineNr = tStr.getInt()
      posNr = tStr[($lineNr).len+2..<tStr.len].getInt()
      result = getCodeLine(lineNr) & "\n" & " ".repeat(posNr-1) & "^\n"
      result &= tStr2 & "\n"
    elif tStr != "":
      result &= line

proc filterRunLines[T](s: T): string =
  # return the results of running a successful compile
  result = ""
  var
    linkStr = ""
    foundStart = false
    foundLink = false
  for line in s.splitLines():
    if foundLink:
      linkStr &= linkStr
    if foundStart:
      result &= line
    if line.contains("[SuccessX]"):
      foundStart = true
    if line.contains("[Link]"):
      foundLink = true
  if result == "":
    if linkStr != "": result = linkStr
    else: result = s.strip()

proc deleteLastLine()          # fwd decl

proc runEval(): tuple[errCode: int, resStr: string] =
  # (silently) compile the code using Nim, and return any errors
  # for displaying to stdout
  # Remove the offending last line of source code.
  # NB: If pasting in a multi lines of code with an error in it,
  #     the last line will be deleted but may not be the offending
  #     line of code  :-)
  var
    resStr = ""
  tnimWrite(@[SavedFileName])
  let (outp, exitCode) = execCmdEx("nim c -r --verbosity:0 --hints:off " & SavedFileName)
  # OOPS - Compile or Run failed!!
  if exitCode != 0:
    resStr = filterCompileLines(outp)
    # remove offending code line (stdin history exists to see what last line was)
    deleteLastLine()
  if resStr == "":
    resStr = filterRunLines(outp)
  return (exitCode, resStr)

# ---------------- tnimXXXX command jump table procs --------------------
proc tnimHelp(w: seq[string]) =
  echo """Commands (only one command per line):
\?,  \h, \help             this information.
\l,  \list                 list the previous code history (w/ line nr's)
\ln, \listnn               list with No (line) Numbers (raw code listing).
\c,  \clear                clear the current history buffer.
\d,  \delete [f [t]]       delete lines(s) [f [optionally to t]].
                           delete last line if none specified.
\e,  \eval                 force the eval (compile/run) of the code buffer.
\ec, \edconfig <editor>    define the path/name to an external editor
                           (if not defined, uses notepad (win) or vi)
\ed, \edit                 edit code in the code buffer.
                           (then reloads the code buffer, lists the code,
                            and evals (compile/run) the code)
\r,  \read <filename>      read code from <filename> and run.
                           Saved history is read on startup.
                           data from file is auto evaluated after reading.
\s,  \set [<option=value>] set {maxBlocks,indent}
\v,  \version              display the name and version.
\w,  \write [<filename>]   write code history [to <filename>].
                           \w by itself overwrites saved history (tnim_dat.dat).
                           \c followed by \w clears saved history.
\q,  \quit                 quit, saving code history to tnim_dat.dat file.
\qc, \quitclear            quit, clearing code history in tnim_dat.dat file.
"""

proc deleteCodeLine(lineNrFrom: int, lineNrTo: int) =
  var
    i = 0
    lnTo = if lineNrTo == -1: lineNrFrom else: lineNrTo
    lnFrom = lineNrFrom
  for cBlock in mitems(code):
    for j in 0..<cBlock.lines.len:
      if i >= lnFrom and i <= lnTo:
        cBlock.lines[j] = ""
      inc(i)
  dec(i)

  if lineNrFrom == -1: lnFrom = i  # delete last line

  for cb in countDown(code.len-1, 0):
    for j in countDown(code[cb].lines.len-1, 0):
      if i >= lineNrFrom and i <= lnTo and code[cb].lines[j] == "":
        code[cb].lines.delete(j)
      dec(i)

proc lastLineNr(): int =
  var i = 0
  if code.len == 0: return -1
  for cBlock in items(code):
    for s in cBlock.lines:
      inc(i)
  return i - 1

proc deleteLastLine() =
  # if an error compiling, then this is called
  # to delete last line of code
  let lln = lastLineNr()
  deleteCodeLine(lln, lln)

proc listCode(f: File, withln = false) =
  var i = 0
  if code.len == 0: return
  for cBlock in items(code):
    for s in cBlock.lines:
      if i > 0: f.writeLine("")
      if withln:
        f.write(align($i,5) & ": " & s)
      else:
        f.write(s)
      inc(i)

# --------- tnimXXXXX() procedures -----------------

proc tnimList(w: seq[string]) =
  listCode(stdout)
  doEval = false
  echo ""

proc tnimNrList(w: seq[string]) =
  listCode(stdout, true)
  doEval = false
  echo ""

proc tnimClear(w: seq[string]) =
  blockNr = 0
  code.setLen(0)
  evalResults.setLen(0)
  doEval = false

proc tnimDelete(w: seq[string]) =
  var
    f, t = -1
  if w.len >= 3: t = w[2].parseInt
  if w.len >= 2: f = w[1].parseInt
  if t == -1 and f != -1: t = f
  deleteCodeLine(f, t)
  tnimNrList(w)
  doEval = false

proc tnimEval(w: seq[string]) =
  doEval = true

proc tnimWrite(w: seq[string]) =
  var
    fn = if w.len > 1: w[1] else: SavedFileName
    f: File = open(fn, mode=fmWrite)
  f.listCode()
  f.close()
  doEval = false

proc tnimRead(w: seq[string]) =
  var
    fn = if w.len > 1: w[1] else: SavedFileName
    f: File
    hasCode = false
  if fileExists(fn):
    f = open(fn)
    var lines = f.readAll().splitLines()
    f.close()
    for line in lines:
      if not hasCode:
        if line.len == 0:
          continue
        else: hasCode = true
      code.add(line)
    tnimEval(w)
  elif fn != SavedFileName:
    errMsg("Unable to find file: " & fn)

proc tnimSet(w: seq[string]) =
  proc showItems() =
    echo "maxBlocks: ",maxBlocks
    echo "indentSize: ",indentSize

  if w.len <= 1: showItems()
  else:
    var wrds = w[1..<w.len].join(" ").split('=')
    for i in 0..<wrds.len:
      wrds[i] = wrds[i].strip()
    if wrds.len == 1: showItems()
    elif wrds[1].isDigits():
      case wrds[0]
      of "maxBlocks": maxBlocks = wrds[1].parseInt
      of "indentSize": indentSize = wrds[1].parseInt
      else:
        errMsg("variable " & wrds[0] & " is unknown.")
  doEval = false

proc tnimQuit(w: seq[string]) =
  getOut = true
  doEval = false

proc tnimQuitClear(w: seq[string]) =
  tnimClear(w)
  tnimQuit(w)

proc tnimVersion(w: seq[string]) =
  writeLine(stdout, TnimName & " V" & $TnimVersion)

# -------------- EDIT ---------------------------
proc setEditorAsDefault(): bool =
  var
    cmd = ""
    startStr = ""
  # Before looking up the path, try the EDITOR environment variable.
  if existsEnv("EDITOR"):
    editorPath = getEnv("EDITOR")
    return true

  if defined(windows):
    cmd = "where notepad.exe"
    startStr = "c:\\"
  else:
    cmd = "which vi"
    startStr = "/"
  result = false
  let outp = execProcess(cmd)
  if outp.toLowerAscii.startsWith(startStr):
    editorPath = outp.splitLines()[0]
    result = editorPath.len > 0

proc checkOrSetEditor(): bool =
  ## Check for the existence of an editorPath, and if it doesn't exist, attempt
  ## to set from the default.
  if editorPath == "":
    result = setEditorAsDefault()
    if not result:
      echo "Please define an editor (\ec)"
  else:
    result = true

proc tnimEdConfig(w: seq[string]) =
  if w.len > 1:
    editorPath = w[1]
  else:
    discard checkOrSetEditor()
  echo "Editor: ",editorPath

proc tnimEdit(w: seq[string]) =
  ## If an editorPath defined, use that editor
  ## Else
  ## clear the screen, display the code buffer
  ## and change the code
  var
    res = 0
  if not checkOrSetEditor(): return
  if not editorPath.fileExists:
    echo "Error: " & editorPath & " not found"
    editorPath = ""
  else:
    res = execCmd(editorPath & " tnim_dat.dat")
    if res == 0:
      tnimClear(@[])
      tnimRead(@[SavedFileName])
      tnimNrList(@[])
      tnimEval(@[])
    else:
      echo "Editing failed: returned ",res

# -------------- EVAL ---------------------------
proc nimEval(inp: string): tuple[res: bool, resStr: string] =
  # true if something to print
  var
    res = false
    resStr = ""
    iput = inp.words()

  if iput.len == 0:
    if currIndent > 0:  currIndent = 0  # continue with eval
    else: return (res, resStr)
  else:
    if inputCmds.hasKey(iput[0]):
      # eval user commands
      var
        cmdToRun = inputCmds[iput[0]]    # get command to run
      cmdToRun(iput)                     # tnimEval can set the doEval flag
      if not doEval:
        return (res, resStr)
      else:
        doEval = false
        let (_, rs) = runEval()
        return (true, rs)

    if blockNr == maxBlocks:
      errMsg("History buffer is full.  Write(\\w) and/or Clear (\\c) the history")
      return (res, resStr)
    {.breakpoint: "x" .}
    # handle a line of code, checking if indent is required
    let ident = getIndent(inp)
    #if ident == currIndent:             # ident should match currIndent
    if ident >= 0 and code.len-1 == blockNr:
      code[blockNr].lines.add(inp)
    else:
      code.add(inp)
    let lastWrd = iput[iput.len-1]
    # if block identified by ':' then inc indent
    if lastWrd[lastWrd.len-1] == ':':
      inc(currIndent)
    # multi-line statement or proc() definition
    elif lastWrd[lastWrd.len-1] == ',':     # don't eval, more to come
      return (res, resStr)
    # proc() definition on one line  (comment on end of line not handled!)
    elif iput[0] in ["proc", "iterator", "method", "converter"] and
                lastWrd[lastWrd.len-1] == '=':
      inc(currIndent)
    # proc() definition on multi lines
    elif iput[0] in ["template", "macro"]:
      inc(currIndent)
    # proc() definition on multi lines
    elif ident > 0 and lastWrd[lastWrd.len-1] == '=':
      inc(currIndent)
    elif iput[0][0..4] == "block":
      inc(currIndent)
    #elif ident != -1:
    #  errMsg("indentation is incorrect")

  doEval = false      # reset the flag
  if currIndent > 0: return (res, resStr)
  #
  #  eval code
  #
  let (_, rStr) = runEval()
  return (true, rStr)

# -------------- PRINT ---------------------------
proc print(s: string) {.inline.} =
  writeLine(stdout, s)

proc startMsg(): string {.inline.} =
  ## when indented, print the "..." else the "nim> " text
  result = (if currIndent == 0: TnimStart else: TnimContinue)

# -------------- REPL ---------------------------
proc REPL() =
  ## main processing loop
  var
    inp = ""
  while not getOut:
    inp = readLineFromStdin(startMsg()) # R
    let (res, resStr) = nimEval(inp)    # E
    if res: print(resStr)               # P


proc main() =
  doInit()
  # get previous code
  tnimRead(@[SavedFileName])
  # get command line options
  getCmdLineOpts()
  # display version
  tnimVersion(@[])
  # display help commands
  tnimHelp(@[])
  print(startMsg())
  # show current code buffer
  tnimNrList(@[])
  # and away it runs
  REPL()
  tnimWrite(@[SavedFileName])

when isMainModule:
  main()
