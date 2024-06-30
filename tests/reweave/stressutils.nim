import std/[random, tables, options, algorithm, sets, sequtils, times, monotimes, strformat]
import reweave/[ops, vfs, extpaths]

const
  StressTimeMsec {.intdefine.}: int = 1000
  StressTime = initDuration(milliseconds = StressTimeMsec)
  StressEchoIntervalMsec {.intdefine.}: int = 200
  StressEchoInterval = initDuration(milliseconds = StressEchoIntervalMsec)

proc stressMainLoop*(action: proc(rnd: var Rand)) =
  var mainRnd = initRand(42)
  var testNum = 0
  let start = getMonoTime()
  var echoes = 0
  while true:
    let sinceStart = getMonoTime() - start
    if sinceStart > StressTime: break
    inc testNum
    if sinceStart >= StressEchoInterval * echoes:
      let floatTime = sinceStart.inNanoseconds.float64 / 1e9
      echo fmt"Time: {floatTime:.3f}s, Test# = {testNum}"
      while sinceStart >= StressEchoInterval * echoes: inc echoes
    var curRnd = initRand(mainRnd.rand(int64))
    action(curRnd)

type
  Inode* = object
    case kind*: InodeKind
    of ikFile, ikDir:
      discard
    of ikLink:
      target*: RawPath

  FsEntry* = object
    was*: Option[NaivePath]
    now*: Option[NaivePath]
    inode*: Inode

  FsEntryExt* = object
    was*: Option[NaivePath]
    now*: Option[NaivePath]
    case kind*: InodeKind
    of ikFile, ikDir:
      discard
    of ikLink:
      rawTarget*: RawPath
      fullTarget*: NaivePath

func inode*(e: FsEntryExt): Inode =
  case e.kind
  of ikFile, ikDir: Inode(kind: e.kind)
  of ikLink: Inode(kind: ikLink, target: e.rawTarget)

iterator genFilenames*(rnd: var Rand): string =
  var maxName = 4
  var counter = 1
  while true:
    if counter > maxName*4: maxName *= 2
    yield $rnd.rand(0..<maxName)
    counter += 1

type InodeKindCoefs* = array[InodeKind, Natural]

func doGenInodeKind(rnd: var Rand, coefs: InodeKindCoefs): InodeKind =
  var sum = 0
  for coef in coefs: sum += coef
  doAssert sum > 0
  var val = rnd.rand(0..<sum)
  for c in InodeKind:
    val -= coefs[c]
    if val < 0: return c
  raiseAssert "unreachable"

const
  genFsCoefs: InodeKindCoefs = [ikFile: 1, ikDir: 1, ikLink: 1]
  genFsExtCoefs: InodeKindCoefs = [ikFile: 1, ikDir: 1, ikLink: 2]
  genFsExtLinkCoefs: InodeKindCoefs = [ikFile: 1, ikDir: 4, ikLink: 11]

func genFs*(rnd: var Rand, size: int, coefs = genFsCoefs): seq[FsEntry] =
  doAssert size >= 1
  var
    tab = initTable[NaivePath, Inode]()
    res = newSeq[FsEntry]()
  proc doAdd(p: NaivePath, i: Inode) =
    doAssert p notin tab
    tab[p] = i
    res &= FsEntry(was: p.some, now: p.some, inode: i)
  doAdd("/".NaivePath, Inode(kind: ikDir))
  var lastLink = 0
  while res.len < size:
    while true:
      let e = rnd.sample(res)
      if e.inode.kind != ikDir: continue
      let parent = e.now.get
      for filename in rnd.genFilenames:
        let fullname = parent.child(filename)
        if fullname in tab: continue
        let kind = rnd.doGenInodeKind(coefs)
        let inode = case kind:
        of ikFile, ikDir: Inode(kind: kind)
        of ikLink:
          inc lastLink
          Inode(kind: ikLink, target: RawPath("target:" & $(lastLink-1)))
        doAdd(fullname, inode)
        break
      break
  res

func genFsExt*(
  rnd: var Rand, size: int, maxLinkComplexity: int = 40, relLinksOnly: bool = false,
  coefs = genFsExtCoefs, linkCoefs = genFsExtLinkCoefs,
): seq[FsEntryExt] =
  doAssert maxLinkComplexity >= 1
  var
    byKind: array[InodeKind, seq[FsEntryExt]]
    kinds = initTable[NaivePath, InodeKind]()
    linkPaths = newSeq[NaivePath]()
    complexities = initTable[NaivePath, int]()

  proc doAdd(e: FsEntryExt) =
    doAssert e.now.get notin kinds
    kinds[e.now.get] = e.kind
    byKind[e.kind].add(e)

  for e in rnd.genFs(size, coefs):
    doAssert e.was == e.now and e.was.isSome
    case e.inode.kind:
    of ikFile, ikDir: doAdd(FsEntryExt(was: e.was, now: e.now, kind: e.inode.kind))
    of ikLink: linkPaths.add(e.now.get)
  rnd.shuffle(linkPaths)

  for path in linkPaths:
    doAssert path != "/"
    var
      complexity = 1
      rawTarget = "".RawPath
      fullTarget = NaivePath.none
      pointsToDir = bool.none
      needAbs = if relLinksOnly: false else: rnd.sample([false, true])
      curPath = path.parent
    while true:
      var coefs = linkCoefs
      for i in InodeKind: coefs[i] *= byKind[i].len
      let
        nextEntry = rnd.sample(byKind[rnd.doGenInodeKind(coefs)])
        nextPath = nextEntry.now.get
      let complexityAdd = if nextEntry.kind == ikLink: complexities[nextPath] else: 0
      if complexity + complexityAdd > maxLinkComplexity: continue
      complexity += complexityAdd
      if needAbs:
        needAbs = false
        rawTarget = nextPath.asRaw
      else:
        rawTarget.extend(nextPath.relativeTo(curPath))
      if nextEntry.kind != ikLink:
        fullTarget = nextPath.some
        pointsToDir = some(nextEntry.kind == ikDir)
        break
      curPath = nextEntry.fullTarget
      if kinds[curPath] != ikDir:
        fullTarget = curPath.some
        pointsToDir = false.some
        break
    if rawTarget.strLen == 0: rawTarget = ".".RawPath
    if pointsToDir.get and rnd.sample([true, false]): rawTarget.addTrailingSep
    doAssert kinds[fullTarget.get] in {ikFile, ikDir}
    complexities[path] = complexity
    doAdd(FsEntryExt(was: path.some, now: path.some, kind: ikLink,
                     rawTarget: rawTarget, fullTarget: fullTarget.get))

  result = @[]
  for sub in byKind: result &= sub
  rnd.shuffle(result)

proc toVfs*[T: FsEntry | FsEntryExt](fs: seq[T]): Vfs =
  let tab = newTable[NaivePath, Inode](fs.len)
  for e in fs:
    if e.now.isSome:
      doAssert e.now.get notin tab
      tab[e.now.get] = e.inode
  doAssert "/".NaivePath in tab and tab["/".NaivePath].kind == ikDir
  for k in tab.keys:
    let p = k.parent
    doAssert p in tab and tab[p].kind == ikDir

  proc doGet[K, V](tab: TableRef[K, V], key: K): V {.raises: [].} =
    try: tab[key] except KeyError as exc: raiseAssert fmt"key error: {exc.msg}"

  proc inodeKind(p: NaivePath): Option[InodeKind] =
    if p in tab: tab.doGet(p).kind.some else: InodeKind.none

  proc readDir(p: NaivePath): seq[string] =
    doAssert p.inodeKind == ikDir.some, "no such directory"
    result = @[]
    # NB: to list directory contents, we read the entire filesystem. This is definitely not
    # optimal, but is used only for testing, so such approach is good enough.
    for x in tab.keys:
      if x != p and x.parent == p:
        result.add(x.filename)
    result.sort

  proc readLink(p: NaivePath): RawPath =
    doAssert p.inodeKind == ikLink.some, "file doesn\'t exist or not a symlink"
    tab.doGet(p).target

  Vfs(
    inodeKind: inodeKind,
    readDir: readDir,
    readLink: readLink,
  )

func applyOp*[T: FsEntry | FsEntryExt](fs: var seq[T], op: Op) =
  for e in fs.mitems:
    if e.now.isNone: continue
    let res = op.apply(e.now.get)
    e.now = case res.verdict
    of avExists: res.path.some
    of avRemovedDir: NaivePath.none
    of avImpossible: raiseAssert "impossible op"
  if op.kind == okMkdir:
    when T is FsEntry:
      fs.add(FsEntry(now: op.mkdir.some, was: NaivePath.none, inode: Inode(kind: ikDir)))
    else:
      fs.add(FsEntryExt(now: op.mkdir.some, was: NaivePath.none, kind: ikDir))

func doGenTarget[T: FsEntry | FsEntryExt](
  rnd: var Rand, fs: seq[T], src: Option[NaivePath]
): NaivePath =
  while true:
    let e = rnd.sample(fs)
    if e.inode.kind != ikDir or e.now.isNone: continue
    let parent = e.now.get
    if src.isSome and parent.hasPrefix(src.get): continue
    var children = initHashSet[string]()
    for se in fs:
      if se.now.isSome and se.now.get != "/" and se.now.get.parent == parent:
        children.incl(se.now.get.filename)
    for filename in rnd.genFilenames:
      if filename in children: continue
      return parent.child(filename)

func genOp*[T: FsEntry | FsEntryExt](rnd: var Rand, fs: seq[T]): Op =
  while true:
    case rnd.sample([okMove, okMove, okMove, okMkdir, okRmdir])
    of okMove:
      for _ in 1..(8*fs.len):
        let e = rnd.sample(fs)
        if e.now.isNone or e.now.get == "/": continue
        let src = e.now.get
        return Op(kind: okMove, src: src, dst: rnd.doGenTarget(fs, src.some))
    of okMkdir:
      return Op(kind: okMkdir, mkdir: rnd.doGenTarget(fs, NaivePath.none))
    of okRmdir:
      var notEmpty: HashSet[NaivePath]
      for e in fs:
        if e.now.isSome and e.now.get != "/":
          notEmpty.incl(e.now.get.parent)
      for _ in 1..(8*fs.len):
        let e = rnd.sample(fs)
        if e.now.isNone or e.inode.kind != ikDir or e.now.get in notEmpty or e.now.get == "/":
          continue
        return Op(kind: okRmdir, rmdir: e.now.get)
