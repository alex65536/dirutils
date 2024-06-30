import std/[paths, strformat, dirs, symlinks, files]
import nestd/neposix_utils
import ./[osutils, osglue, extpaths, ops, relinks]
import ../common/escapes

type
  FsApplierError* = object of CatchableError

  FsApplierDirection* = enum
    adApply, adUnapply

  FsApplierLogger* = proc(dir: FsApplierDirection, op: string) {.raises: [].}

  FsApplierOptions* = object
    moveFlags*: set[CopyPreserveAllFlag]

  UnapplyProc = proc() {.raises: [FsApplierError].}

  FsApplier* = ref object
    opts: FsApplierOptions
    logger: FsApplierLogger
    unapplyProcs: seq[UnapplyProc]

func initFsApplier*(opts: FsApplierOptions, logger: FsApplierLogger): FsApplier =
  FsApplier(opts: opts, logger: logger, unapplyProcs: @[])

func raiseFsApplierOpError(parent: ref Exception, dir: FsApplierDirection, op: string) =
  let dirText = if dir == adApply: "apply" else: "unapply"
  raise FsApplierError.newException(fmt"{dirText} {op}: {parent.msg}", parent)

template wrapOpExceptions(dir: FsApplierDirection, op: string, actions: untyped) =
  try:
    actions
  except OSError, IOError, UnsupportedFileError, FsApplierError:
    raiseFsApplierOpError(getCurrentException(), dir, op)

template applyImpl(srcA: FsApplier, srcMsg: string, apply: untyped, unapply: untyped) =
  let msg = srcMsg
  let a = srcA
  a.logger(adApply, msg)
  wrapOpExceptions(adApply, msg, apply)
  a.unapplyProcs.add do():
    a.logger(adUnapply, msg)
    wrapOpExceptions(adUnapply, msg, unapply)
  # Work around https://github.com/nim-lang/Nim/issues/23748.
  discard a

proc rollback*(a: FsApplier) {.raises: [FsApplierError].} =
  while a.unapplyProcs.len > 0:
    let p = a.unapplyProcs.pop
    p()

proc doRelink(path: NaivePath, oldTarget, newTarget: RawPath) =
  let path = path.asOsPath
  if not path.symlinkExists:
    raise FsApplierError.newException(fmt"not a link: {path.esc}")
  let realTarget = path.expandSymlink.string
  if realTarget != $oldTarget:
    raise FsApplierError.newException(
      fmt"{path.esc} target must be {oldTarget.esc}, not {realTarget.esc}")
  path.removeFile
  createSymlink(newTarget.asOsPath, path)

proc apply*(a: FsApplier, op: Op) {.raises: [FsApplierError].} =
  a.applyImpl(op.desc) do:
    case op.kind
    of okMove: movePreserveAll(op.src.asOsPath, op.dst.asOsPath, a.opts.moveFlags)
    of okMkdir: op.mkdir.asOsPath.createDir
    of okRmdir: op.rmdir.asOsPath.removeEmptyDir
  do:
    case op.kind
    of okMove: movePreserveAll(op.dst.asOsPath, op.src.asOsPath, a.opts.moveFlags)
    of okMkdir: op.mkdir.asOsPath.removeEmptyDir
    of okRmdir: op.rmdir.asOsPath.createDir

proc apply*(a: FsApplier, r: Relink) {.raises: [FsApplierError].} =
  a.applyImpl(r.desc) do:
    doRelink(r.path, r.oldTarget, r.newTarget)
  do:
    doRelink(r.path, r.newTarget, r.oldTarget)
