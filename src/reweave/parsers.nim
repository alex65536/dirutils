import std/[parseutils, strformat, streams, enumerate]
from std/strutils import Whitespace
import nestd/neparseutils
import ./[opbuilders, extpaths, ops, vfs]
import ../common/escapes

type
  OpListParseError* = object of CatchableError

proc parseOpListLine(line: string, target: var OpListBuilder) =
  var pos = 0

  func expectWhitespace() =
    if pos >= line.len or line[pos] notin Whitespace:
      raise ValueError.newException("expected whitespace")

  func readArg(): string =
    expectWhitespace()
    pos += line.skipWhitespace(pos)
    var delta = line.parseEscapedString(result, start = pos)
    if delta == 0:
      delta = line.parseUntil(result, Whitespace, pos)
    if delta == 0:
      raise ValueError.newException("expected string argument")
    pos += delta

  pos += line.skipWhitespace(pos)
  var command: string
  pos += line.parseIdent(command, pos)
  case command:
  of "mkdir":
    let dir = readArg()
    target.mkdir(dir.RawPath)
  of "rmdir":
    let dir = readArg()
    target.rmdir(dir.RawPath)
  of "cd":
    let dir = readArg()
    target.cd(dir.RawPath)
  of "move":
    let src = readArg()
    let dst = readArg()
    target.move(src.RawPath, dst.RawPath)
  else: raise ValueError.newException(fmt"unknown command {command.esc}")
  pos += line.skipWhitespace(pos)
  if pos < line.len: raise ValueError.newException("extra data in line")

proc parseOpListFromStream*(s: Stream, target: var OpListBuilder)
  {.raises: [IOError, OSError, OpListParseError].} =
  for (lineNo, line) in enumerate(1, s.lines):
    try:
      parseOpListLine(line, target)
    except OpListPushError, OpListBuilderError, VfsError, ValueError:
      let exc = getCurrentException()
      raise OpListParseError.newException(fmt"line {lineNo}: {exc.msg}", exc)
