import std/[options, strformat]
import ./extpaths

type
  InodeKind* = enum
    ikFile, ikDir, ikLink

  VfsError* = object of CatchableError

  Vfs* = object
    inodeKind*: proc(p: NaivePath): Option[InodeKind] {.raises: [VfsError].}
    readDir*: proc(p: NaivePath): seq[string] {.raises: [VfsError].}
    readLink*: proc(p: NaivePath): RawPath {.raises: [VfsError].}

proc assertIsDir*(vfs: Vfs, dir: NaivePath) {.raises: [].} =
  try:
    doAssert dir == "/" or vfs.inodeKind(dir) == ikDir.some
  except VfsError as exc:
    raiseAssert fmt"unexpected error when checking {dir.esc}: {exc.msg}"
