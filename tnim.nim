## **tnim** (TinyNim) is an interactive REPL
## 
## It is a stop-gap replacement for the 
## functionality that was in old versions of Nim.
##
## It compiles and runs code exactly (?) the same
## way you would by hand, and does this using a shell 
## command in the background ( 
## ``nim c -r --verbosity:0 --hints:off <file>`` )
##
##  *Warning: this is SLOW!!.  It is a quick and dirty
##  interactive tool, not a sleek and shiny speed demon.*
##
## Commands:
## ---------
## .. code-block:: Nim
##
##  \?, \h, \help              this information.
##  \l, \list                  list the previous code history.
##  \c, \clear                 clear the current history buffer.
##  \e, \eval                  force the evaluation of the code buffer.
##  \r, \read <filename>       read code from <filename> and run.
##                             Saved history is read on startup.
##  \s, \set [<option=value>]  set {maxBlocks,indent}
##  \w, \write [<filename>]    write code history [to <filename>]
##                             \w by itself overwrites saved history.
##                             \c followed by \w clears saved histoy.
##  \q, \quit                  quit, saving code history.
##
import strutils, tables, sequtils, os, osproc

const
  TnimStart    = "nim> "
  TnimContinue = ".... "   # add "..".repeat(n) before this
  SavedFileName = "tnim_dat.dat"

# run-time Configurable but effectively const Config variables  
var
  maxBlocks = 100_000
  indentSize = 2

type
  CodeBlock = object   ## blocks of code (a block is the outer scope level)
    lines: seq[string]
    compiles: bool
    firstOutput: string
    lastOutput: string
    
  CodeBlocks = seq[CodeBlock]
  PCodeBlocks = ptr CodeBlocks
  
  EvalOutput = object
    msg: seq[string]
    output: seq[string]
    
  EvalOutputs = seq[EvalOutput]
  PEvalOutputs = ptr EvalOutputs
  
  
var
  code: CodeBlocks = @[]
  evalResults: EvalOutputs = @[]
  blockNr: int = 0        # a code block is multi lines for if, proc, block, etc
  currIndent = 0          # starts at 0 for no indent at top scope level
  inputCmds = initTable[string, proc(w: seq[string])]()
  getOut = false          # flag to trigger exit of REPL
  currDir = getAppDir()
  doEval = false          # force re-evaluation of the code buffer
  
# ---------------- forward declarations -----------
proc tnimClear(w: seq[string])
proc tnimEval(w: seq[string])
proc tnimHelp(w: seq[string])
proc tnimList(w: seq[string])
proc tnimQuit(w: seq[string])
proc tnimRead(w: seq[string])
proc tnimSet(w: seq[string])
proc tnimWrite(w: seq[string])

# ---------------- general stuff ------------------
proc doInit() =
  inputCmds.add("\\?",     tnimHelp)
  inputCmds.add("\\h",     tnimHelp)
  inputCmds.add("\\help",  tnimHelp)
  inputCmds.add("\\l",     tnimList)
  inputCmds.add("\\list",  tnimList)
  inputCmds.add("\\c",     tnimClear)
  inputCmds.add("\\clear", tnimClear)
  inputCmds.add("\\e",     tnimEval)
  inputCmds.add("\\eval",  tnimEval)
  inputCmds.add("\\w",     tnimWrite)
  inputCmds.add("\\write", tnimWrite)
  inputCmds.add("\\r",     tnimRead)
  inputCmds.add("\\read",  tnimRead)
  inputCmds.add("\\s",     tnimSet)
  inputCmds.add("\\set",   tnimSet)
  inputCmds.add("\\q",     tnimQuit)
  inputCmds.add("\\quit",  tnimQuit)
  
proc errMsg(s:string) =
  writeLine(stderr, TnimStart & "Error: " & s)

proc add(cb: var CodeBlocks, lines: seq[string]) =
  var newCB: CodeBlock
  newCB.lines = lines
  newCB.compiles = false
  cb.add(newCB)
  
proc add(cb: var CodeBlocks, line: string) =
  var newCB: CodeBlock
  newCB.lines = @[line]
  newCB.compiles = false
  cb.add(newCB)
  
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

proc runEval(): tuple[errCode: int, resStr: string] =
  var
    resStr = ""
  tnimWrite(@[SavedFileName])
  let (outp, exitCode) = execCmdEx("nim c -r --verbosity:0 --hints:off " & SavedFileName)
  # OOPS - Compile or Run failed!!
  if exitCode != 0:
    resStr = filterCompileLines(outp)  
  if resStr == "":
    resStr = filterRunLines(outp)  
  return (exitCode, resStr)
 
# ---------------- tnimXXXX command jump table procs --------------------
proc tnimHelp(w: seq[string]) =
  echo """Commands (only one command per line):
\?, \h, \help              this information.
\l, \list                  list the previous code history.
\c, \clear                 clear the current history buffer.
\e, \eval                  force the evaluation of the code buffer.
\r, \read <filename>       read code from <filename> and run.
                           Saved history is read on startup.
\s, \set [<option=value>]  set {maxBlocks,indent}
\w, \write [<filename>]    write code history [to <filename>]
                           \w by itself overwrites saved history.
                           \c followed by \w clears saved histoy.
\q, \quit                  quit, saving code history.
"""

proc listCode(f: File) =
  for cBlock in items(code):
    for s in cBlock.lines:
      f.writeLine(s)

proc tnimList(w: seq[string]) =
  listCode(stdout)

proc tnimClear(w: seq[string]) =
  blockNr = 0
  code.setLen(0)
  evalResults.setLen(0)

proc tnimEval(w: seq[string]) =
  doEval = true
  
proc tnimWrite(w: seq[string]) =
  var 
    fn = if w.len > 1: w[1] else: SavedFileName
    f: File = open(fn, mode=fmWrite)
  f.listCode()  
  f.close()

proc tnimRead(w: seq[string]) =
  var 
    fn = if w.len > 1: w[1] else: SavedFileName
    f: File
  if fileExists(fn):
    f = open(fn)
    var lines = f.readAll().splitLines()
    f.close()
    for line in lines:
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

proc tnimQuit(w: seq[string]) =
  getOut = true
  
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
        let (ec, rs) = runEval()
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
      var newB: CodeBlock
      newB.lines = @[inp]
      newB.compiles = false
      code.add(newB)
    let lastWrd = iput[iput.len-1]
    # if block identified by ':' then inc indent
    if lastWrd[lastWrd.len-1] == ':':
      inc(currIndent)
    # multi-line statement or proc() definition
    elif lastWrd[lastWrd.len-1] == ',':     # don't eval, more to come
      return (res, resStr)
    # proc() definition on one line  (comment on end of line not handled!)
    elif iput[0] == "proc" and lastWrd[lastWrd.len-1] == '=':
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
  let (errC, rStr) = runEval()    
  return (true, rStr)
  
# -------------- PRINT ---------------------------  
proc print(s: string) {.inline.} =
  writeLine(stdout, s)

proc printStartMsg() =
  ## when indented, print the "..." else the "nim> " text
  if currIndent == 0:
    write(stdout, TnimStart)
  else:
    write(stdout, TnimContinue)

# -------------- REPL ---------------------------  
proc REPL() =
  ## main processing loop
  var
    inp = ""
  while not getOut:
    printStartMsg()
    inp = readLine(stdin)             # R
    let (res, resStr) = nimEval(inp)  # E
    if res: print(resStr)             # P

    
proc main() =
  doInit()
  # get previous code
  tnimRead(@[SavedFileName])
  # get command line options
  getCmdLineOpts()
  REPL()
  tnimWrite(@[SavedFileName])
  
when isMainModule:
  main()
