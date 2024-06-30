import std/[options, sets, strformat]
import ./[vfs, ops, links, extpaths]

type
  CalcRelinksFlag* = enum
    crNoNormalize     ## Don't change link if it differs only by normalization after rewrite.
    crSkipBrokenLinks ## Skip broken symlinks instead of raising an error.

  CalcRelinksOptions* = object
    roots*: seq[NaivePath]
    excludes*: seq[NaivePath]
    resolveLinkFlags*: set[ResolveLinkFlag]
    flags*: set[CalcRelinksFlag]

  Relink* = object
    path*: NaivePath
    oldTarget*, newTarget*: RawPath

  CalcRelinksValidateError* = object of CatchableError

func desc*(r: Relink): string =
  fmt"relink {r.path.esc} from {r.oldTarget.esc} to {r.newTarget.esc}"

template check(expr: bool, errMsg: string) =
  if not expr: raise CalcRelinksValidateError.newException(errMsg)

func validate*(o: CalcRelinksOptions) {.raises: [CalcRelinksValidateError].} =
  check not o.roots.hasNestedPaths, "some roots nest into each other"

func validate*(o: CalcRelinksOptions, opList: OpList) {.raises: [CalcRelinksValidateError].} =
  o.validate
  let
    rootPrefixSet = o.roots.toPathPrefixSet
    rootSet = o.roots.toHashSet
  for op in opList.ops:
    case op.kind
    of okMove:
      check op.src in rootPrefixSet, fmt"cannot move {op.src.esc} from outside of given roots"
      check op.src notin rootSet, fmt"cannot move root {op.src.esc}"
      check op.dst in rootPrefixSet, fmt"cannot move {op.dst.esc} to outside of given roots"
      check op.dst notin rootSet, fmt"cannot remove root {op.dst.esc}"
    of okMkdir:
      check op.mkdir in rootPrefixSet, fmt"cannot mkdir {op.mkdir.esc} outside of given roots"
      check op.mkdir notin rootSet, fmt"cannot create root {op.mkdir.esc}"
    of okRmdir:
      check op.rmdir in rootPrefixSet, fmt"cannot rmdir {op.rmdir.esc} outside of given roots"
      check op.rmdir notin rootSet, fmt"cannot remove root {op.rmdir.esc}"

proc scanLinks(vfs: Vfs, path: NaivePath, excludes: PathPrefixSet, res: var seq[NaivePath]) =
  if path in excludes: return
  let kind = vfs.inodeKind(path)
  if kind.isNone: return
  case kind.get
  of ikFile: discard
  of ikLink: res.add(path)
  of ikDir:
    for sub in vfs.readDir(path):
      vfs.scanLinks(path.child(sub), excludes, res)

func doNormalized(path: RawPath): RawPath =
  result = "".RawPath
  for sub in path.decompose(withAbsPathMarker = true):
    if sub == ".": continue
    result.push(sub)
  if result.strLen == 0: result = ".".RawPath

proc calcRelinks*(opts: CalcRelinksOptions, opList: OpList): seq[Relink]
  {.raises: [CalcRelinksValidateError, RealPathError, WillBreakLinkError, VfsError].} =
  opts.validate(opList)
  let vfs = opList.innerVfs
  let excludes = opts.excludes.toPathPrefixSet
  var links = newSeq[NaivePath]()
  for root in opts.roots:
    vfs.scanLinks(root, excludes, links)
  result = @[]
  for link in links:
    let (newLink, newTarget) = try:
      opList.resolveLink(link, flags = opts.resolveLinkFlags)
    except RealPathError as exc:
      if crSkipBrokenLinks in opts.flags: continue else: raise exc
    let oldTarget = vfs.readLink(link)
    let linksDiffer = if crNoNormalize in opts.flags:
      $oldTarget.doNormalized != $newTarget
    else:
      $oldTarget != $newTarget
    if linksDiffer:
      result.add(Relink(path: newLink, oldTarget: oldTarget, newTarget: newTarget))
