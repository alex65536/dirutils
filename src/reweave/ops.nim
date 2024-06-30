import std/[algorithm, options, strformat, sugar, sets, sequtils]
import ./[vfs, extpaths]

type
  OpKind* = enum
    okMove, okMkdir, okRmdir

  Op* = object
    case kind*: OpKind
    of okMove:
      src*, dst*: NaivePath
    of okMkdir:
      mkdir*: NaivePath
    of okRmdir:
      rmdir*: NaivePath

  ApplyVerdict* = enum
    avImpossible, avRemovedDir, avExists

  ApplyResult* = object
    case verdict*: ApplyVerdict
    of avImpossible, avRemovedDir:
      discard
    of avExists:
      path*: NaivePath

func inv*(o: Op): Op =
  case o.kind
  of okMove: Op(kind: okMove, src: o.dst, dst: o.src)
  of okMkdir: Op(kind: okRmdir, rmdir: o.mkdir)
  of okRmdir: Op(kind: okMkdir, mkdir: o.rmdir)

func doMove(p, src, dst: NaivePath): NaivePath =
  let
    lBound = if dst == "/": 0 else: dst.strLen
    rBound = if src == "/": 0 else: src.strLen
    res = ($dst)[0..<lBound] & ($p)[rBound..^1]
  NaivePath(if res != "": res else: "/")

func apply*(o: Op, p: NaivePath): ApplyResult =
  case o.kind
  of okMove:
    if p.hasPrefix(o.src): ApplyResult(verdict: avExists, path: p.doMove(o.src, o.dst))
    elif p.hasPrefix(o.dst): ApplyResult(verdict: avImpossible)
    else: ApplyResult(verdict: avExists, path: p)
  of okMkdir:
    if p.hasPrefix(o.mkdir): ApplyResult(verdict: avImpossible)
    else: ApplyResult(verdict: avExists, path: p)
  of okRmdir:
    if p == o.rmdir: ApplyResult(verdict: avRemovedDir)
    elif p.hasPrefix(o.rmdir): ApplyResult(verdict: avImpossible)
    else: ApplyResult(verdict: avExists, path: p)

func desc*(o: Op): string =
  case o.kind
  of okMove: fmt"move {o.src.esc} to {o.dst.esc}"
  of okMkdir: fmt"mkdir {o.mkdir.esc}"
  of okRmdir: fmt"rmdir {o.rmdir.esc}"

func getPossible*(a: ApplyResult): Option[NaivePath] =
  case a.verdict
  of avExists: a.path.some
  of avRemovedDir: NaivePath.none
  of avImpossible: raiseAssert fmt"bad verdict {a.verdict}"

func getPath*(a: ApplyResult): NaivePath =
  doAssert a.verdict == avExists, fmt"bad verdict {a.verdict}"
  a.path

type
  OpList* = object
    list: seq[Op]
    vfs: Vfs

  OpListPushError* = object of CatchableError

func initOpList*(vfs: Vfs): OpList =
  OpList(list: @[], vfs: vfs)

iterator ops*(l: OpList): Op =
  for op in l.list:
    yield op

iterator unops*(l: OpList): Op =
  for i in countdown(l.list.high, l.list.low):
    yield l.list[i].inv

func resolve*(l: OpList, p: NaivePath): ApplyResult {.raises: [].} =
  # NB: this works in O(n) now and might be optimized in the future.
  result = ApplyResult(verdict: avExists, path: p)
  for op in l.ops:
    if result.verdict != avExists: break
    result = op.apply(result.path)

func unresolve*(l: OpList, p: NaivePath): ApplyResult {.raises: [].} =
  # NB: this works in O(n) now and might be optimized in the future.
  result = ApplyResult(verdict: avExists, path: p)
  for op in l.unops:
    if result.verdict != avExists: break
    result = op.apply(result.path)

proc readDir*(l: OpList, p: NaivePath): seq[string] {.raises: [VfsError].} =
  # NB: this works in O(n) now and might be optimized in the future.
  proc unwind(start: int, p: NaivePath, items: seq[string]): seq[string] =
    var p = p
    var entries = items.toHashSet
    proc doIncl(f: string) =
      doAssert f notin entries
      entries.incl(f)
    proc doExcl(f: string) =
      doAssert f in entries
      entries.excl(f)
    for i in start..l.list.high:
      let op = l.list[i]
      case op.kind
      of okMove:
        doAssert op.dst != p
        if p.hasPrefix(op.src):
          p = p.doMove(op.src, op.dst)
        else:
          if op.src.parent == p: doExcl(op.src.filename)
          if op.dst.parent == p: doIncl(op.dst.filename)
      of okMkdir:
        doAssert op.mkdir != p
        if op.mkdir.parent == p: doIncl(op.mkdir.filename)
      of okRmdir:
        doAssert op.rmdir != p
        if op.rmdir.parent == p: doExcl(op.rmdir.filename)
    entries.toSeq.sorted
  var p = p
  for i in countdown(l.list.high, l.list.low):
    let res = l.list[i].inv.apply(p)
    case res.verdict
    of avExists: p = res.path
    of avRemovedDir: return unwind(i+1, p, @[])
    of avImpossible: raiseAssert "directory doesn\'t exist"
  doAssert l.vfs.inodeKind(p) == ikDir.some
  unwind(0, p, l.vfs.readDir(p))

proc inodeKind*(l: OpList, p: NaivePath): Option[InodeKind] {.raises: [VfsError].} =
  let res = l.unresolve(p)
  case res.verdict
  of avExists: l.vfs.inodeKind(res.path)
  of avRemovedDir: ikDir.some
  of avImpossible: InodeKind.none

proc readLink*(l: OpList, p: NaivePath): RawPath {.raises: [VfsError].} =
  l.vfs.readLink(l.unresolve(p).getPath)

func innerVfs*(l: OpList): Vfs = l.vfs

func asVfs*(l: OpList): Vfs =
  Vfs(
    inodeKind: (p: NaivePath) => l.inodeKind(p),
    readDir: (p: NaivePath) => l.readDir(p),
    readLink: (p: NaivePath) => l.readLink(p),
  )

proc push*(l: var OpList, o: Op) {.raises: [OpListPushError, VfsError].} =
  template check(expr: bool, errMsg: string) =
    if not expr: raise OpListPushError.newException(errMsg)
  proc exists(l: OpList, p: NaivePath): bool = l.inodeKind(p).isSome
  case o.kind
  of okMove:
    if o.src == o.dst: return
    check not o.src.hasPrefix(o.dst), fmt"cannot rename {o.dst.esc} to its parent"
    check not o.dst.hasPrefix(o.src), fmt"cannot move {o.src.esc} inside itself"
    check l.exists(o.src), fmt"source {o.src.esc} doesn't exist"
    check not l.exists(o.dst), fmt"destination {o.dst.esc} already exists"
    check l.exists(o.dst.parent), fmt"destination parent {o.dst.parent.esc} doesn't exist"
  of okMkdir:
    check not l.exists(o.mkdir), fmt"mkdir target {o.mkdir.esc} already exists"
    check l.exists(o.mkdir.parent), fmt"mkdir target parent {o.mkdir.parent.esc} doesn't exist"
  of okRmdir:
    check l.exists(o.rmdir), fmt"rmdir target {o.rmdir.esc} doesn't exist"
    check l.inodeKind(o.rmdir) == ikDir.some, fmt"rmdir target {o.rmdir.esc} is not a directory"
    check l.readDir(o.rmdir).len == 0, fmt"rmdir target {o.rmdir.esc} is not empty"
  l.list.add(o)
