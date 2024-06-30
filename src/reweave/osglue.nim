import std/[os, posix, options, dirs, sugar, paths, symlinks]
import ./[vfs, extpaths]

proc inodeKind(p: NaivePath): Option[InodeKind] =
  var res: Stat
  if lstat(($p).cstring, res) < 0: InodeKind.none
  elif S_ISDIR(res.st_mode): ikDir.some
  elif S_ISLNK(res.st_mode): ikLink.some
  else: ikFile.some

proc readDir(p: NaivePath): seq[string] =
  try:
    collect:
      for (_, sp) in ($p).Path.walkDir(relative = true, checkDir = true, skipSpecial = false):
        sp.string
  except OSError as exc:
    raise VfsError.newException(exc.msg, exc)

proc readLink(p: NaivePath): RawPath =
  try:
    ($p).Path.expandSymlink.string.RawPath
  except OSError as exc:
    raise VfsError.newException(exc.msg, exc)

const osVfs* = Vfs(
  inodeKind: inodeKind,
  readDir: readDir,
  readLink: readLink,
)

proc expandToNaivePath*(path: Path): NaivePath {.raises: [OSError].} =
  result = expandFilename(path.string).NaivePath
  result.assertValid

func asOsPath*(p: NaivePath): Path = p.string.Path
func asOsPath*(p: RawPath): Path = p.string.Path
