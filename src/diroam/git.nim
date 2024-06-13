import std/[dirs, paths, tables, options, strutils, times, strformat, strmisc]
import ./esc

type
  Git* = object
    path: Path
    packedRefs: Option[Table[string, string]]

  GitError* = object of CatchableError

func split2(src, pat: string): (string, string) =
  let (l, mid, r) = src.partition(pat)
  if mid == "":
    raise GitError.newException(fmt"expected {pat.esc}")
  return (l, r)

proc parseDateFromReflog(line: string): Time =
  # Yes, real actual git parses reflog lines approximately the same way...
  var line = line
  line = line.split2(">")[1]
  if not line.startsWith(' '):
    raise GitError.newException("expected \" \"")
  line = line[1..^1]
  line = line.split2("\t")[0]
  let (rawTs, rawTz) = line.split2(" ")
  let tz = rawTz.parse("ZZZ").timezone
  let ts = fromUnix(rawTs.parseBiggestInt.int64)
  ts.inZone(tz).toTime

proc newGit*(path: Path): Git =
  let gitPath = path / ".git".Path
  if not gitPath.dirExists:
    raise GitError.newException(fmt"{path.esc} is not a git repo")
  Git(path: gitPath, packedRefs: none(Table[string, string]))

using g: var Git

proc loadPackedRefs(g) =
  if g.packedRefs.isSome:
    return
  let f = open(string(g.path / "packed-refs".Path))
  defer: f.close
  var
    refs: Table[string, string]
    ln: string
  while f.readLine(ln):
    ln.stripLineEnd
    if ln.startsWith('#') or ln.startsWith('^'):
      continue
    let (hash, reference) = ln.split2(" ")
    refs[reference] = hash
  g.packedRefs = some(refs)

proc readRef(g; name: string): string =
  if g.packedRefs.isSome and name in g.packedRefs.get:
    return g.packedRefs.get[name]
  var f: File
  let fname = g.path / name.Path
  if not open(f, fname.string):
    g.loadPackedRefs
    if name in g.packedRefs.get:
      return g.packedRefs.get[name]
    raise GitError.newException(fmt"unable to open ref file {fname.esc}")
  defer: f.close
  result = f.readAll
  result.stripLineEnd

proc resolveRef(g; name: string): string =
  var name = name
  for _ in 0..<16:
    if (name != "HEAD" and not name.startsWith("refs/")) or "/." in name:
      raise GitError.newException(fmt"unsafe ref {name.esc}")
    name = g.readRef(name)
    const prefix = "ref: "
    if not name.startsWith(prefix):
      return name
    name = name.substr(prefix.len)
  raise GitError.newException("refs nest too deep")

proc parseMtimeFromLog*(g): Time =
  let f = open(string(g.path / "logs".Path / "HEAD".Path))
  defer: f.close
  var
    ln = ""
    refline = none(string)
  while f.readLine(ln):
    refline = some(ln)
  if refline.isNone:
    raise GitError.newException("no lines in reflog")
  parseDateFromReflog(refline.get)

proc parseHeadCommit*(g): string = g.resolveRef("HEAD")
