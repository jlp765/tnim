# tnim
TinyNim - a REPL for Nim 

*Try* **Nim Playground** *(https://play.nim-lang.org/) for an online experience*

This is an interactive sandbox for testing Nim code

`nim secret` also provides an interactive NIM experience (note: `nim secret` uses the VM in Nim, so it only allows the import of a subset of modules)

*`tnim` is SLOW!!.  It is a quick and dirty interactive tool, not a sleek and shiny speed demon.*

`tnim` is assumed to not work with multitasking (async library, et. al.)

Instructions are in the **tnim.html** file or **\?** at the tnim command line

The code buffer is saved to the file **tnim_dat.dat** (in the "current" directory).  You can add code to this file if you want to do development using a REPL interface.

*Note from Nimble doco (ensuring tnim can run):* 

* Nimble stores everything that has been installed in ~/.nimble on Unix systems and in your $home/.nimble on Windows. Libraries are stored in $nimbleDir/pkgs, and binaries are stored in **$nimbleDir/bin**. 

* However, some Nimble packages can provide additional tools or commands. **If you don't add their location ($nimbleDir/bin) to your $PATH** they will not work properly and you won't be able to run them.

(alternately, you can copy/link the tnim executable to a suitable location)

## Changes
2.0.4
-----

Minor readability changes.

2.0.3
-----

Minor nimble config change.

2.0.2
-----

* If there is a compilation error, the last line of code is removed from the code buffer.  (https://github.com/jlp765/tnim/issues/6)

NB: This assumes the code was typed and the error is with the last line.  If multi lines of code has been pasted into stdin and the last line of code is not in error, 
then you will need to add the last line of code back, as well as fix whichever line has an error.

2.0.1
-----

* EDITOR environment variable if set defines the default editor (thanks **@subsetpark**)

2.0.0
-----

* uses rdstdin (linenoise) for friendlier input handling (thanks **@subsetpark**)
* **edit the code buffer** (\ed) using an external editor, which defaults to **notepad** on windows and **vi** on linux/macosx (untested on macosx)
* define an external editor (\ec /bin/user/vi)
* bug fix: no longer adds a extra line to the code buffer on exit
* displays version and help commands on startup (to help newbies) before listing the code buffer
