import unittest
import std/[random, options, tempfiles, paths, dirs, os]
import reweave/[links, vfs, extpaths, osglue]
import ./reweave/[stressutils, stressosutils]

proc stressRealPathOs(fs: seq[FsEntryExt]) =
  let vfs = fs.toVfs
  let tempDir = createTempDir("stressoslink_", "").Path
  defer: tempDir.removeDir
  let root = tempDir.expandToNaivePath
  fs.materializeOnDisk(root)
  for e in fs:
    doAssert e.now.isSome
    if e.kind != ikLink: continue
    let
      path = e.now.get.asRaw
      expected = vfs.realPath(path, "/".NaivePath).asRaw.reroot(root)
      got = expandFilename(path.reroot(root).string)
    doAssert $expected == got

test "reweave: stress realPath() against OS":
  stressMainLoop do(rnd: var Rand):
    let fs = rnd.genFsExt(rnd.rand(1..40), maxLinkComplexity = 40)
    stressRealPathOs(fs)
