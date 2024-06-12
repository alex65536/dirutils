# Package

version       = "1.1.0"
author        = "Alexander Kernozhitsky"
description   = "Various utilities to work with directory trees"
license       = "MIT"
srcDir        = "src"
binDir        = "bin"
bin           = @["diroam"]

# Dependencies

requires "nim >= 2.0.0"
requires "https://github.com/alex65536/nim-nestd#v0.1.1"
requires "argparse ~= 4.0.1"
requires "unicodeplus ~= 0.13.0"
requires "nimcrypto ~= 0.6.0"

# Tasks

task pretty, "Prettify the sources":
  proc walk(dir: string) =
    for f in dir.listFiles:
      if f.endsWith ".nim":
        exec "nimpretty --maxLineLen:100 " & f
    for f in dir.listDirs:
      walk f
  walk "src"
