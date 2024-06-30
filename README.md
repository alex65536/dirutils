# dirutils

This repository is intended to be a collection of various utilities for working with directory
trees. The utilities are written on [Nim](https://nim-lang.org/) programming language.

## What utilities can I find here?

The set of utilities currently includes:
- `diroam` (**roam**s around **dir**ectories). Contains multiple subcommands:
  - `diroam list`: Lists directory contents recursively, printing file names and some of their
    metadata.
  - `diroam diff`: Searches for differences between two directories recurively. Unlike `diff -r`,
    it mostly uses only metadata for the search and prints a convenient summary of which files are
    added, deleted or modified.
- `reweave`: Moves, creates and removes directories, keeping symbolic links from and into the moved
  directories consistent. It updates links after move to make sure that they are not broken and
  still point to the correct target (even if the target was moved).

## Which operating systems are supported?

Only UNIX-like operating systems are supported. Only Linux is tested, but every other OS supported
by Nim compiler should work fine as well. Windows is not supported and will never be.

## Building

1. Install Nim. See [here](https://nim-lang.org/install.html) for details.
2. Run `nimble build`.

The built binaries are placed into `bin/` subdirectory.

## License

This project is licensed under MIT License. see [LICENSE](LICENSE) for more details.

## Why is the main branch named `m`?

The main branch is the most used one, so it's a good idea to give it the shortest possible name.
Also, `m` is a quite neutral name and is not connected to any controversies.
