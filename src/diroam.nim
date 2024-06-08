when isMainModule:
  import std/[strformat, paths, sets, sugar, terminal]
  import argparse
  import diroam/[entry, diff]

  let useColor = stdout.isatty and not existsEnv("NO_COLOR")

  proc printDiffLine(dir: char, s: string) =
    let color = case dir:
      of '+': fgGreen
      of '-': fgRed
      else: raiseAssert fmt"unexpected dir {dir}"
    if useColor:
      styledEcho color, dir & " " & s
    else:
      echo dir & " " & s

  proc observer(e: DiffEntry) =
    case e.kind:
      of deAdd: printDiffLine '+', e.add.desc
      of deDel: printDiffLine '-', e.del.desc
      of deMod:
        printDiffLine '-', e.pre.desc
        printDiffLine '+', e.cur.desc

  proc list(e: RootedEntry, opts: ScanOptions) =
    echo e.e.desc
    for (_, se) in e.scan(opts):
      list(se, opts)

  func parseFileReadLimit(s: string): uint64 =
    if s == "oo":
      return uint64.high
    s.parseBiggestUInt.uint64

  var scan = none(ScanOptions)
  var ap = newParser "diroam":
    help "recursively walks around directory trees"
    option "--file-read-limit", "-l", default = "4096".some,
           help = "max file size that can be read fully, use \"oo\" for unlimited"
    flag "--no-scan-git", "-G", help = "treat git repos as regular dirs, not as git repos"
    option "--exclude", "-x", multiple = true, help = "ignore given path while traversing"
    run:
      scan = ScanOptions(
        fileReadLimit: opts.fileReadLimit.parseFileReadLimit,
        scanGitRepos: not opts.noScanGit,
        excludes: toHashSet[Path](opts.exclude.map(s => s.Path.dup(normalizePath))),
      ).some
      if opts.argparse_command == "":
        raise UsageError.newException("No command supplied")
      if ".".Path in scan.get.excludes:
        raise UsageError.newException("Cannot exclude the entire directory tree")
    command "list":
      help "lists directory contents recursively"
      arg "dir", help = "directory to list"
      run:
        list(curDirEntry().withRoot(opts.dir.Path.dup(normalizePath)), scan.get)
    command "diff":
      help "computes recursively the difference between two directories"
      arg "dir1", help = "first directory to compare"
      arg "dir2", help = "second directory to compare"
      option "--fold-dir", "-d", multiple = true, help = "do not show detailed diff of FOLD_DIR, only indicate whether it is changed"
      run:
        let o = DiffOptions(
          scan: scan.get,
          foldDirs: toHashSet[Path](opts.foldDir.map(s => s.Path.dup(normalizePath))),
        )
        diff(opts.dir1.Path.dup(normalizePath), opts.dir2.Path.dup(normalizePath), o, observer)

  try:
    ap.run
  except UsageError:
    stderr.writeLine(getCurrentExceptionMsg())
    quit 1
