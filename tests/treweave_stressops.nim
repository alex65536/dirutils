import unittest
import std/[random, tables, algorithm, options, sets]
import reweave/[ops, vfs, extpaths]
import ./reweave/stressutils

proc stressOps(rnd: var Rand, fs: seq[FsEntry], steps: int) =
  var opList = initOpList(fs.toVfs)
  var fs = fs
  for _ in 1..steps:
    let op = rnd.genOp(fs)
    opList.push(op)
    fs.applyOp(op)
    for e in fs:
      if e.now.isSome:
        doAssert opList.inodeKind(e.now.get) == e.inode.kind.some
        if e.inode.kind == ikLink:
          doAssert $opList.readLink(e.now.get) == $e.inode.target
        doAssert opList.unresolve(e.now.get).getPossible == e.was
      if e.was.isSome:
        doAssert opList.resolve(e.was.get).getPossible == e.now
    var readDirRes: Table[NaivePath, seq[string]]
    for e in fs:
      if e.now.isSome and e.now.get != "/":
        readDirRes.mgetOrPut(e.now.get.parent, @[]).add(e.now.get.filename)
    for (path, items) in readDirRes.mpairs:
      items.sort
      doAssert opList.readDir(path) == items
    var allFiles: HashSet[NaivePath]
    for e in fs:
      if e.now.isSome: allFiles.incl(e.now.get)
    for e in fs:
      if e.now.isNone: continue
      let parent = e.now.get
      let len = max(4, readDirRes.getOrDefault(parent, @[]).len + 1)
      for i in 1..len:
        let file = parent.child($i)
        doAssert opList.inodeKind(file).isSome == (file in allFiles)

test "reweave: stress ops":
  stressMainLoop do(rnd: var Rand):
    let fs = rnd.genFs(rnd.rand(1..30))
    stressOps(rnd, fs, 15)
