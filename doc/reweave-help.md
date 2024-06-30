Moves, creates and removes directories, keeping symbolic links from and into the moved directories
consistent. It updates links after move to make sure that they are not broken and still point to
the correct target (even if the target was moved).

The input of this tool is a sequence of commands. The commands are separated by newline. By
default, the commands are read from stdin and are run only after end-of-stream is reached (i.e.
after pressing Ctrl-D). Alternatively, you may chooose to read the input from a file, via -i
option.

Each command consists of its name and one or more arguments, space-separated. To allow special
characters, spaces and newlines in arguments, the arguments may be quoted, i.e. enclosed in quotes
with escape sequences applied. Argument may be quoted only fully and not partially (unlike shell).
The command name can not be quoted. The following commands are supported:

* `cd DIR`: change current directory to DIR
* `move SRC DST`: rename a file or directory called SRC to DST
* `mkdir DIR`: create a directory DIR
* `rmdir DIR`: remove an empty directory DIR

For example, `cd /1/2/3` and `mkdir "../../path/with/line\nbreaks/and spaces"` are valid commands.

_Roots_ are paths in which the program scans for symbolic links to replace. Your commands must not
touch anything outside of the roots, otherwise an error is raised, and no command is performed.
This also means that you must always specify at least one root. Use -r option to do this. Also, you
may not specify two roots which are nested into each other.

You may also specify paths to exclude, via -x option. Excluded paths are not scanned for symbolic
links, but still can be affected by the commands. Use this option with caution: you must manually
ensure that all the links in the excluded paths will not become broken after applying the commands.

While replacing symbolic links, the tool tries to preserve them as much as possible. This means
that absolute links remain absolute, relative links remain relative, and if the symbolic link
target itself contains a link inside the path, the rewritten link will most likely also contain
this inner link inside its target path. Some customization to this process may be applied, though,
see flags for more details.
