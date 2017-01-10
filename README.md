# tnim
TinyNim - a REPL for Nim 

This is an interactive sandbox for testing Nim code

Instructions are in the **tnim.html** file or **\?** at the tnim command line

The code buffer is saved to the file **tnim_dat.dat** (in the "current" directory).  You can add code to this file if you want to do development using a REPL interface.

## Changes

2.1
---

* EDITOR environment variable if set defines the default editor (thanks **@subsetpark**)

2.0
---

* uses rdstdin (linenoise) for friendlier input handling (thanks **@subsetpark**)
* **edit the code buffer** (\ed) using an external editor, which defaults to **notepad** on windows and **vi** on linux/macosx (untested on macosx)
* define an external editor (\ec /bin/user/vi)
* bug fix: no longer adds a extra line to the code buffer on exit
* displays version and help commands on startup (to help newbies) before listing the code buffer
