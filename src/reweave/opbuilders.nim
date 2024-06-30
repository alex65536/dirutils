import std/[options, strformat]
import ./[vfs, ops, extpaths]

type
  OpListBuilder* = object
    curDir: NaivePath
    opList: OpList

  OpListBuilderError* = object of CatchableError

template check(expr: bool, errMsg: string) =
  if not expr: raise OpListBuilderError.newException(errMsg)

proc initOpListBuilder*(curDir: NaivePath, vfs: Vfs): OpListBuilder {.raises: [].} =
  vfs.assertIsDir(curDir)
  OpListBuilder(curDir: curDir, opList: initOpList(vfs))

func build*(b: sink OpListBuilder): OpList = b.opList

proc backtrack(b: OpListBuilder, path: RawPath): NaivePath =
  var
    stack = if path.isAbsolute: "/".NaivePath else: b.curDir
    lastKind = ikDir.some
  for sub in path.decompose(withAbsPathMarker = false):
    check lastKind.isSome, fmt"no such file or directory: {stack.esc}"
    check lastKind.get != ikLink,
          fmt"symlinks inside operation paths, like {stack.esc}, are not supported by now"
    check lastKind.get == ikDir, fmt"cannot recurse: {stack.esc} isn't a directory"
    if sub == ".": continue
    if sub == "..":
      stack.pop
      continue
    stack.push(sub)
    lastKind = b.opList.inodeKind(stack)
  stack

proc move*(b: var OpListBuilder, src, dst: RawPath)
  {.raises: [OpListPushError, OpListBuilderError, VfsError].} =
  let src = b.backtrack(src)
  let dst = b.backtrack(dst)
  check not b.curDir.hasPrefix(src), fmt"cannot move {src.esc}, as work dir will move"
  check not b.curDir.hasPrefix(dst), fmt"destination {dst.esc} already exists"
  b.opList.push(Op(kind: okMove, src: src, dst: dst))

proc mkdir*(b: var OpListBuilder, dir: RawPath)
  {.raises: [OpListPushError, OpListBuilderError, VfsError].} =
  let dir = b.backtrack(dir)
  check not b.curDir.hasPrefix(dir), fmt"mkdir target {dir.esc} already exists"
  b.opList.push(Op(kind: okMkdir, mkdir: dir))

proc cd*(b: var OpListBuilder, dir: RawPath) {.raises: [OpListBuilderError, VfsError].} =
  let dir = b.backtrack(dir)
  check b.opList.inodeKind(dir) == ikDir.some, fmt"cd target {dir.esc} is not a dir"
  b.curDir = dir

proc rmdir*(b: var OpListBuilder, dir: RawPath)
  {.raises: [OpListPushError, OpListBuilderError, VfsError].} =
  let dir = b.backtrack(dir)
  check b.curDir != dir, fmt"cannot remove work dir {dir.esc}"
  check not b.curDir.hasPrefix(dir), fmt"rmdir target {dir.esc} is not empty"
  b.opList.push(Op(kind: okRmdir, rmdir: dir))
