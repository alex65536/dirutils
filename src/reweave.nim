when isMainModule:
  import std/[strformat, terminal, sequtils, options, paths, strutils]
  import argparse
  import reweave/[frontend, links, relinks, osutils]

  const
    NimblePkgVersion {.strdefine.} = "???"
    version = NimblePkgVersion

  let useStderrColor = stderr.isatty and not existsEnv("NO_COLOR")

  template wrapIOErrors(actions: untyped) =
    try:
      actions
    except IOError:
      raiseAssert fmt"bad i/o error: {getCurrentExceptionMsg()}"

  proc logError(where, msg: string) {.raises: [].} =
    wrapIOErrors:
      if useStderrColor:
        stderr.styledWrite fgRed, styleBright, fmt"Error:"
        stderr.writeLine fmt" {where}: {msg}"
      else:
        stderr.writeLine fmt"Error: {where}: {msg}"

  proc logStatus(msg: string) {.raises: [].} =
    wrapIOErrors:
      if useStderrColor:
        stderr.styledWrite fgYellow, styleBright, "Status:"
        stderr.styledWriteLine styleBright, fmt" {msg}"
      else:
        stderr.writeLine fmt"Status: {msg}"

  proc logInfo(msg: string) {.raises: [].} =
    wrapIOErrors:
      if useStderrColor:
        stderr.styledWrite fgBlue, "Info:"
        stderr.writeLine fmt" {msg}"
      else:
        stderr.writeLine fmt"Info: {msg}"

  proc logDryRunInfo(msg: string) {.raises: [].} =
    wrapIOErrors:
      echo msg

  proc curDir(): Path = paths.getCurrentDir()

  var ap = newParser "reweave":
    help slurp("../doc/reweave-help.md").strip(chars = {'\n', '\r'})
    flag "--version", "-v", shortcircuit = true

    # General options
    option "--input", "-i", help = "read input commands from file instead of stdin"
    option "--root", "-r", multiple = true, help = "paths to scan links for"
    option "--exclude", "-x", multiple = true, help = "paths to exclude while scanning links"

    # General flags
    flag "--verbose", "-V", help = "print extra output"
    flag "--quiet", "-q", help = "minimize output to be printed"
    flag "--no-rollback",
         help = "do not try to restore the applied changes back in case of failure"
    flag "--dry-run", "-n",
         help = "don't make any changes, just show what is going change. " &
                "Either this or -f must be set"
    flag "--force", "-f", help = "really apply changes. Either this or -n must be set"

    # Resolve link flags
    flag "--allow-middle-dot-dot", help = "allow .. in the middle of the resulting target"
    flag "--simplify", "-S",
         help = "do not try to preserve links inside the target, simplify it instead."
    flag "--keep-target-end", "-k", help = "preserve trailing slash in the end of the target"

    # Calculate new link target flags
    flag "--no-normalize", "-N",
         help = "don't change link if it differs only by normalization after rewrite"
    flag "--skip-broken", "-b", help = "skip broken symlinks instead of raising an error"

    # Move flags
    flag "--preserve-hardlinks", "-H", help = "move hardlinks as hardlinks between file systems"
    flag "--move-devices", help = "allow to move block and character devices between file systems"
    flag "--move-fifos-sockets",
         help = "allow to move named pipes and sockets between file systems"
    flag "--force-update-times",
         help = "fail with exception if we could not update times during move between file systems"
    flag "--force-update-perms",
         help = "fail with exception if we could not update perms during move between file systems"

    run:
      var fileInput: File = nil
      defer: fileInput.close
      if opts.input_opt.isSome:
        fileInput = open(opts.input_opt.get, fmRead)

      let logger = Logger(
        error: logError,
        status: logStatus,
        info: logInfo,
        dryRunInfo: logDryRunInfo,
      )

      var o: Options
      template inclFlag(section, flag, target: untyped) =
        if opts.flag: o.section.incl(target)

      o.roots = opts.root.mapIt(it.Path)
      o.excludes = opts.exclude.mapIt(it.Path)

      inclFlag(generalFlags, verbose, gfVerbose)
      inclFlag(generalFlags, quiet, gfQuiet)
      inclFlag(generalFlags, noRollback, gfNoRollback)
      inclFlag(generalFlags, dryRun, gfDryRun)
      inclFlag(generalFlags, force, gfForce)

      inclFlag(resolveLinkFlags, allowMiddleDotDot, rlAllowMiddleDotDot)
      inclFlag(resolveLinkFlags, simplify, rlSimplify)
      inclFlag(resolveLinkFlags, keepTargetEnd, rlKeepTargetEnd)

      inclFlag(calcRelinksFlags, noNormalize, crNoNormalize)
      inclFlag(calcRelinksFlags, skipBroken, crSkipBrokenLinks)

      inclFlag(moveFlags, preserveHardlinks, cfPreserveHardlinks)
      inclFlag(moveFlags, moveDevices, cfCopyDevices)
      inclFlag(moveFlags, moveFifosSockets, cfCopyFifosSockets)
      inclFlag(moveFlags, forceUpdateTimes, cfForceUpdateTimes)
      inclFlag(moveFlags, forceUpdatePerms, cfForceUpdatePerms)
      # cfNoRollbackMove is omitted intentionally!

      execute(o, curDir(), newFileStream(fileInput), logger)

  try:
    ap.run
  except ShortCircuit as exc:
    case exc.flag:
      of "version": echo fmt"reweave (dirutils {version})"
      else: raise
  except RunFailedError:
    quit 1
  except UsageError:
    stdout.write fmt"Error: {getCurrentExceptionMsg()}{""\n\n""}"
    stdout.write ap.help
    quit 2
