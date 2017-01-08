# tnim
TinyNim - a REPL for Nim 

This is an interactive sandbox for testing Nim code

Instructions are in the **tnim.html** file 

or \? form within tnim

# Changes

2.0
---

* uses rdstdin (linenoise) for friendlier input handling (thanks @subsetpark)
* edit code buffer (\ed) which defaults to notepad on windows and vi on linux/macosx (untested)
* define an editor (\ec)
* bug fix: no longer adds a extra line to the code buffer on exit
* displays version and help commands on startup (to help newbies) before listing the code buffer
