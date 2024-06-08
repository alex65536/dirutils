import std/[dirs, paths, times, strformat, algorithm, sugar, posix, symlinks, strutils, sets]
import nestd/[nechecksums, neposix, nesystem, nepaths]
import ./[git, esc]
import nimcrypto/[hash, sha2]

type
  InodeKind* = enum
    ikFile, ikDir, ikLink, ikBlockDev, ikCharDev, ikFifo, ikSocket, ikUnknown, ikGit

  Inode* = object
    case kind*: InodeKind
    of ikFile:
      size*: uint64
      fileMtime*: DateTime
      hash*: string
    of ikDir: discard
    of ikLink:
      target*: Path
    of ikBlockDev, ikCharDev:
      dev*: uint64
    of ikFifo, ikSocket: discard
    of ikUnknown:
      unknownMtime*: DateTime
    of ikGit:
      head*: string
      gitMtime*: DateTime

  Entry* = object
    rawPath*: Path
    inode*: Inode

  RootedEntry* = object
    e*: Entry
    root*: Path

  ScanOptions* = object
    fileReadLimit*: uint64
    scanGitRepos*: bool
    excludes*: HashSet[Path]

addEqForObject(Inode)

func doFmt(t: DateTime): string = t.format("yyyy-MM-dd HH:mm:ss")

func desc*(i: Inode): string =
  case i.kind:
    of ikFile:
      if i.hash != "":
        fmt"{i.size} {i.fileMtime.doFmt} {i.hash}"
      else:
        fmt"{i.size} {i.fileMtime.doFmt}"
    of ikDir: "dir"
    of ikLink: fmt"-> {i.target.esc}"
    of ikBlockDev: fmt"dev blk 0x{i.dev:x}"
    of ikCharDev: fmt"dev char 0x{i.dev:x}"
    of ikFifo: "ipc fifo"
    of ikSocket: "ipc socket"
    of ikUnknown: fmt"??? {i.unknownMtime.doFmt}"
    of ikGit: fmt"git {i.gitMtime.doFmt} {i.head}"

func expandRawPath(p: Path): Path =
  if p == "".Path: ".".Path else: p

func path*(e: Entry): Path = e.rawPath.expandRawPath
func desc*(e: Entry): string = fmt"{e.path.esc} {e.inode.desc}"
func withRoot*(e: sink Entry, root: Path): RootedEntry = RootedEntry(e: e, root: root)

func curDirEntry*(): Entry = Entry(rawPath: "".Path, inode: Inode(kind: ikDir))

proc scan*(e: RootedEntry, opts: ScanOptions): seq[(string, RootedEntry)] =
  if e.e.inode.kind != ikDir:
    return @[]
  let fullPath = e.root / e.e.rawPath
  var entries = collect:
    for _, entry in fullPath.walkDir(relative = true, checkDir = true, skipSpecial = false):
      entry
  entries.sort((l, r) => cmp($l, $r))
  result = @[]
  for sub in entries:
    let rawPath = e.e.rawPath / sub
    if rawPath.expandRawPath in opts.excludes:
      continue
    let subFullPath = fullPath / sub
    proc getInode(): Inode =
      let stat = try:
        subFullPath.lstat
      except OSError as exc:
        if exc.errorCode == ENOENT:
          return Inode(kind: ikUnknown, unknownMtime: 0.fromUnix.utc)
        raise
      let size = stat.st_size.uint64
      let mtime = stat.st_mtim.toTime.utc
      let ftype = stat.st_mode.cint and S_IFMT
      if ftype == S_IFREG:
        let hash = if size != 0 and size <= opts.fileReadLimit:
          toLowerAscii($subFullPath.checksumFile(sha256))
        else:
          ""
        Inode(kind: ikFile, size: size, fileMtime: mtime, hash: hash)
      elif ftype == S_IFDIR:
        if opts.scanGitRepos:
          try:
            var g = newGit(subFullPath)
            return Inode(
              kind: ikGit,
              head: g.parseHeadCommit,
              gitMtime: g.parseMtimeFromLog,
            )
          except CatchableError:
            discard
        Inode(kind: ikDir)
      elif ftype == S_IFLNK:
        Inode(kind: ikLink, target: subFullPath.expandSymlink)
      elif ftype == S_IFCHR:
        Inode(kind: ikCharDev, dev: stat.st_rdev.Dev)
      elif ftype == S_IFBLK:
        Inode(kind: ikBlockDev, dev: stat.st_rdev.Dev)
      elif ftype == S_IFIFO:
        Inode(kind: ikFifo)
      elif ftype == S_IFSOCK:
        Inode(kind: ikSocket)
      else:
        Inode(kind: ikUnknown, unknownMtime: mtime)
    result.add(($sub, RootedEntry(e: Entry(rawPath: rawPath, inode: getInode()), root: e.root)))
