import unittest
import std/[random, options]
import reweave/[ops, vfs, extpaths, links]
import ./reweave/stressutils

proc stressRealPath(rnd: var Rand, fs: seq[FsEntryExt]) =
  let vfs = fs.toVfs
  for e in fs:
    let target = if e.kind == ikLink: e.fullTarget else: e.now.get
    doAssert vfs.realPath(e.now.get.asRaw, "/".NaivePath) == target
  for _ in 1..3:
    while true:
      let dirEntry = rnd.sample(fs)
      if dirEntry.kind != ikDir: continue
      let dir = dirEntry.now.get
      for e in fs:
        let target = if e.kind == ikLink: e.fullTarget else: e.now.get
        doAssert vfs.realPath(e.now.get.relativeTo(dir), dir) == target
      break

proc stressResolveLink(
  rnd: var Rand, fs: seq[FsEntryExt], steps: int, flags: set[ResolveLinkFlag],
) =
  var opList = initOpList(fs.toVfs)
  var fs = fs
  for _ in 1..steps:
    let op = rnd.genOp(fs)
    opList.push(op)
    fs.applyOp(op)
  var
    newFs = newSeqOfCap[FsEntry](fs.len)
    newFsTests = newSeq[tuple[link: NaivePath, target: NaivePath]]()
  for e in fs:
    if e.kind != ikLink:
      newFs.add(FsEntry(was: e.was, now: e.now, inode: Inode(kind: e.kind)))
      continue
    doAssert e.was.isSome and e.now.isSome
    try:
      let (newLink, newTarget) = opList.resolveLink(e.was.get, flags = flags)
      doAssert newLink == e.now.get
      doAssert newTarget.isAbsolute == e.rawTarget.isAbsolute
      if rlKeepTargetEnd in flags:
        doAssert newTarget.hasTrailingSep == e.rawTarget.hasTrailingSep or $newTarget == "/"
      newFs.add(FsEntry(was: e.was, now: e.now, inode: Inode(kind: ikLink, target: newTarget)))
      newFsTests.add((link: e.now.get, target: opList.resolve(e.fullTarget).getPath))
    except WillBreakLinkError:
      doAssert opList.resolve(e.fullTarget).getPossible.isNone
  let newVfs = newFs.toVfs
  for (link, target) in newFsTests:
    doAssert newVfs.realPath(link.asRaw, "/".NaivePath) == target

proc stressResolveLinkAll(rnd: var Rand, fs: seq[FsEntryExt], steps: int) =
  for flags in [
    {},
    {rlAllowMiddleDotDot},
    {rlSimplify},
    {rlKeepTargetEnd},
    {rlKeepTargetEnd, rlSimplify},
  ]:
    stressResolveLink(rnd, fs, steps, flags)

test "reweave: stress realPath()":
  stressMainLoop do(rnd: var Rand):
    let fs = rnd.genFsExt(rnd.rand(1..40), maxLinkComplexity = 40)
    stressRealPath(rnd, fs)

test "reweave: stress resolveLinkAll()":
  stressMainLoop do(rnd: var Rand):
    let fs = rnd.genFsExt(rnd.rand(1..40), maxLinkComplexity = 40)
    stressResolveLinkAll(rnd, fs, rnd.rand(1..40))
