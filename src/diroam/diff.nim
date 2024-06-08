import std/[strformat, paths, sets]
import ./entry

type
  DiffEntryKind* = enum
    deAdd, deDel, deMod

  DiffEntry* = object
    case kind*: DiffEntryKind
      of deAdd:
        add*: Entry
      of deDel:
        del*: Entry
      of deMod:
        pre*, cur*: Entry

  DiffObserver* = proc(e: DiffEntry)

  DiffOptions* = object
    scan*: ScanOptions
    foldDirs*: HashSet[Path]

  DiffCtx = object
    opts: DiffOptions
    observ: DiffObserver

proc treesEqual(c: DiffCtx, a, b: RootedEntry): bool =
  if a.e.inode != b.e.inode:
    return false
  let
    sa = a.scan(c.opts.scan)
    sb = b.scan(c.opts.scan)
  if sa.len != sb.len:
    return false
  for i in sa.low..sa.high:
    if sa[i][0] != sb[i][0] or not c.treesEqual(sa[i][1], sb[i][1]):
      return false
  true

proc reportTree(c: DiffCtx, e: RootedEntry, k: DiffEntryKind) =
  case k:
    of deDel: c.observ(DiffEntry(kind: deDel, del: e.e))
    of deAdd: c.observ(DiffEntry(kind: deAdd, add: e.e))
    else: raiseAssert fmt"unexpected diff kind {k}"
  if e.e.path in c.opts.foldDirs:
    return
  for (_, se) in e.scan(c.opts.scan):
    c.reportTree(se, k)

proc diff(c: DiffCtx, a, b: RootedEntry) =
  doAssert a.e.path == b.e.path
  if a.e.path in c.opts.foldDirs:
    if not c.treesEqual(a, b):
      c.observ(DiffEntry(kind: deMod, pre: a.e, cur: b.e))
    return
  if a.e.inode != b.e.inode:
    c.observ(DiffEntry(kind: deMod, pre: a.e, cur: b.e))
  let
    sa = a.scan(c.opts.scan)
    sb = b.scan(c.opts.scan)
  var
    ia = 0
    ib = 0
  while ia < sa.len or ib < sb.len:
    let cmp: int =
      if ia == sa.len: 1
      elif ib == sb.len: -1
      else: sa[ia][0].cmp(sb[ib][0])
    case cmp:
      of int.low..(-1):
        c.reportTree(sa[ia][1], deDel)
        inc ia
      of 1..int.high:
        c.reportTree(sb[ib][1], deAdd)
        inc ib
      of 0:
        c.diff(sa[ia][1], sb[ib][1])
        inc ia
        inc ib

proc diff*(rootA, rootB: Path, opts: DiffOptions, observ: DiffObserver) =
  DiffCtx(opts: opts, observ: observ).diff(
    curDirEntry().withRoot(rootA),
    curDirEntry().withRoot(rootB),
  )
