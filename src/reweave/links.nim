import std/[options, strformat, strutils]
import ./[vfs, ops, extpaths]

type
  RealPathError* = object of CatchableError
  TooManyLinksError* = object of RealPathError
  BrokenLinkError* = object of RealPathError
  WillBreakLinkError* = object of CatchableError

proc doRealPath(v: Vfs, path: RawPath, maxFollow: Natural): NaivePath =
  doAssert path.isAbsolute
  var
    path = path
    stack = "/".NaivePath
  for _ in 0..maxFollow:
    var
      newPath = "".RawPath
      passThrough = false
      isDir = true
    for item in path.decompose(withAbsPathMarker = false):
      if passThrough:
        newPath.push(item)
        continue
      if not isDir:
        raise BrokenLinkError.newException(fmt"cannot recurse: {stack.esc} isn't a directory")
      if item == ".": continue
      if item == "..":
        stack.pop
        continue
      stack.push(item)
      let kind = v.inodeKind(stack)
      if kind.isNone:
        raise BrokenLinkError.newException(fmt"no such file or directory {stack.esc}")
      if kind != ikLink.some:
        isDir = kind.get == ikDir
        continue
      newPath = v.readLink(stack)
      if newPath.isAbsolute:
        stack = "/".NaivePath
      else:
        stack.pop
      passThrough = true
    if passThrough:
      path = newPath
      continue
    if v.inodeKind(stack).isNone:
      raise BrokenLinkError.newException(fmt"no such file or directory {stack.esc}")
    return stack
  raise TooManyLinksError.newException(fmt"more than {maxFollow} link follows in realPath()")

proc realPath*(v: Vfs, path: RawPath, cwd: NaivePath, maxFollow: Natural = 40): NaivePath
  {.raises: [RealPathError, VfsError].} =
  v.assertIsDir(cwd)
  if path.isAbsolute:
    v.doRealPath(path, maxFollow)
  else:
    v.doRealPath(cwd.asRaw.join(path), maxFollow)

type
  ResolveLinkFlag* = enum
    rlAllowMiddleDotDot ## Allow `".."` in the middle of the resulting target.
    rlSimplify          ## Do not try to preserve links inside the target, simplify it instead.
    rlKeepTargetEnd     ## Preserve trailing slash in the end of the target.

func hasPrefixDotDot(path: RawPath): bool = $path == ".." or ($path).startsWith("../")

template getOr[T](srcOpt: Option[T], action: untyped): T =
  let opt = srcOpt
  if opt.isNone: action else: opt.get

proc resolveLink*(
  l: OpList, oldLink: NaivePath, maxFollow: Natural = 40, flags: set[ResolveLinkFlag] = {},
): tuple[newLink: NaivePath, newTarget: RawPath]
  {.raises: [RealPathError, WillBreakLinkError, VfsError].} =
  let oldVfs = l.innerVfs
  doAssert oldVfs.inodeKind(oldLink) == ikLink.some
  let oldTarget = oldVfs.readLink(oldLink)
  doAssert oldTarget.strLen != 0
  let newLink = l.resolve(oldLink).getPath
  let isAbs = oldTarget.isAbsolute

  func moldResult(newTarget: sink RawPath): tuple[newLink: NaivePath, newTarget: RawPath] =
    if newTarget.strLen == 0: newTarget = ".".RawPath
    if rlKeepTargetEnd in flags and oldTarget.hasTrailingSep:
      newTarget.addTrailingSep
    (newLink: newLink, newTarget: newTarget)

  if rlSimplify in flags:
    let oldRealPath = oldVfs.realPath(oldTarget, oldLink.parent, maxFollow)
    let newRealPath = l.resolve(oldRealPath).getPossible.getOr:
      raise WillBreakLinkError.newException(
        fmt"{oldLink.esc} will break, as {oldRealPath.esc} will be removed")
    let newTarget = if isAbs: newRealPath.asRaw else: newRealPath.relativeTo(newLink.parent)
    return moldResult(newTarget)

  var
    newTarget = "".RawPath
    newBasePath = if isAbs: "/".NaivePath else: newLink.parent
    segmentCnt = 0

  proc doAddSegment(newLinkPath, newRealPath: NaivePath) =
    if isAbs and segmentCnt == 0:
      newTarget = newLinkPath.asRaw
    else:
      let newRelativePath = newLinkPath.relativeTo(newBasePath)
      if segmentCnt == 0 or rlAllowMiddleDotDot in flags or not newRelativePath.hasPrefixDotDot:
        newTarget.extend(newRelativePath)
      else:
        newTarget = if isAbs: newLinkPath.asRaw else: newLinkPath.relativeTo(newLink.parent)
    newBasePath = newRealPath
    inc segmentCnt

  var
    oldCurPath = if isAbs: "/".NaivePath else: oldLink.parent
    justResolved = false
  for item in oldTarget.decompose(withAbsPathMarker = false):
    justResolved = false
    if item == ".": continue
    if item == "..":
      oldCurPath.pop
      continue
    oldCurPath.push(item)
    let kind = oldVfs.inodeKind(oldCurPath)
    if kind.isNone:
      raise BrokenLinkError.newException(fmt"no such file or directory {oldCurPath.esc}")
    if kind != ikLink.some: continue
    let
      oldLinkPath = oldCurPath
      oldRealPath = oldVfs.doRealPath(oldCurPath.asRaw, maxFollow)
    oldCurPath = oldRealPath
    let
      newLinkPath = l.resolve(oldLinkPath).getPath
      newRealPath = l.resolve(oldRealPath).getPossible.getOr: continue
    doAddSegment(newLinkPath, newRealPath)
    justResolved = true
  if not justResolved:
    let newCurPath = l.resolve(oldCurPath).getPossible.getOr:
      raise WillBreakLinkError.newException(
        fmt"{oldLink.esc} will break, as {oldCurPath.esc} will be removed")
    doAddSegment(newCurPath, newCurPath)
  moldResult(newTarget)
