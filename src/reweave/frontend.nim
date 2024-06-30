import std/[paths, streams, strformat, sequtils]
import ./[opbuilders, parsers, osglue, links, relinks, ops, fsappliers, osutils, vfs]

type
  GeneralFlag* = enum
    gfVerbose    ## Print extra output.
    gfQuiet      ## Minimize output to be printed.
    gfNoRollback ## Do not try to restore the applied changes back in case of failure.
    gfDryRun     ## Don't make any changes, just show what is going change.
    gfForce      ## Really apply changes. Either this flag or `gfDryRun` must be present.

  Options* = object
    roots*: seq[Path]
    excludes*: seq[Path]
    generalFlags*: set[GeneralFlag]
    resolveLinkFlags*: set[ResolveLinkFlag]
    calcRelinksFlags*: set[CalcRelinksFlag]
    moveFlags*: set[CopyPreserveAllFlag]

  RunFailedError* = object of CatchableError

  Logger* = object
    error*: proc(where, msg: string) {.raises: [].}
    status*: proc(msg: string) {.raises: [].}
    info*: proc(msg: string) {.raises: [].}
    dryRunInfo*: proc(msg: string) {.raises: [].}

proc makeCalcRelinksOpts(opts: Options): CalcRelinksOptions {.raises: [OSError].} =
  CalcRelinksOptions(
    roots: opts.roots.map(expandToNaivePath),
    excludes: opts.excludes.map(expandToNaivePath),
    resolveLinkFlags: opts.resolveLinkFlags,
    flags: opts.calcRelinksFlags,
  )

func makeFsAppliersOpts(opts: Options): FsApplierOptions {.raises: [].} =
  var moveFlags = opts.moveFlags
  if gfNoRollback in opts.generalFlags:
    moveFlags.incl(cfNoRollbackMove)
  else:
    moveFlags.excl(cfNoRollbackMove)
  FsApplierOptions(moveFlags: moveFlags)

proc doFail(log: Logger, where, msg: string): ref RunFailedError =
  log.error(where, msg)
  RunFailedError.newException(where)

proc execute*(opts: Options, curDir: Path, input: Stream, log: Logger)
  {.raises: [IOError, OSError, RunFailedError].} =
  if card(opts.generalFlags * {gfDryRun, gfForce}) != 1:
    raise log.doFail("check options", "either dryRun or force must be specified")
  if card(opts.generalFlags * {gfQuiet, gfVerbose}) > 1:
    raise log.doFail("check options", "both quiet and verbose cannot be present at the same time")
  if opts.roots.len == 0:
    raise log.doFail("check options", "at least one root is required")
  let curDir = curDir.expandToNaivePath

  template stage(which: string) =
    if gfVerbose in opts.generalFlags: log.status(which)

  proc applierLogger(dir: FsApplierDirection, op: string) =
    if gfQuiet in opts.generalFlags: return
    case dir
    of adApply: log.info(fmt"apply: {op}")
    of adUnapply: log.info(fmt"unapply: {op}")

  stage "reading input script"
  var opBuilder = initOpListBuilder(curDir, osVfs)
  try:
    parseOpListFromStream(input, opBuilder)
  except OpListParseError:
    raise log.doFail("parse", getCurrentExceptionMsg())
  let opList = opBuilder.build

  stage "calculating link updates"
  let relinks = try:
    calcRelinks(opts.makeCalcRelinksOpts, opList)
  except CalcRelinksValidateError, RealPathError, WillBreakLinkError, VfsError:
    raise log.doFail("calc links", getCurrentExceptionMsg())

  if gfDryRun in opts.generalFlags:
    log.dryRunInfo("Will apply the following operations:")
    for op in opList.ops: log.dryRunInfo("* " & op.desc)
    for op in relinks: log.dryRunInfo("* " & op.desc)
    stage "completed"
    return

  doAssert gfForce in opts.generalFlags

  stage "applying link updates"
  let applier = initFsApplier(opts.makeFsAppliersOpts, applierLogger)
  try:
    for op in opList.ops: applier.apply(op)
    for op in relinks: applier.apply(op)
  except FsApplierError:
    let exc = log.doFail("apply", getCurrentExceptionMsg())
    if gfNoRollback notin opts.generalFlags:
      stage "trying to roll back"
      try:
        applier.rollback
      except FsApplierError:
        log.error("rollback", getCurrentExceptionMsg())
        log.info("everything is probably broken, go fix your filesystem manually")
    raise exc

  stage "completed"
