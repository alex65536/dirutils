import std/[os, posix, paths, tables, strformat]
import nestd/neposix
import ../common/escapes

type
  CopyPreserveAllFlag* = enum
    ## Flags for `copyPreserveAll`_ and `movePreserveAll`_.
    cfPreserveHardlinks ## Copy hardlinks as hardlinks.
    cfCopyDevices       ## Allow to copy block and character devices.
    cfCopyFifosSockets  ## Allow to copy named pipes and sockets.
    cfForceUpdateTimes  ## Fail with exception if we could not update times.
    cfForceUpdatePerms  ## Fail with exception if we could not update permissions.
    cfNoRollbackMove    ## Do not remove partially copied directory on failure (only for move).

  UnsupportedFileError* = object of CatchableError

proc exists(path: Path): bool =
  var st: Stat
  lstat(path.string.cstring, st) == 0

proc copyPreserveAll*(src, dst: Path, flags: set[CopyPreserveAllFlag] = {})
  {.raises: [OSError, IOError, UnsupportedFileError].} =
  ## Copies `src` to `dst` while trying to preserve as much metadata as possible.
  ##
  ## Things that are NOT preserved:
  ## - ownership
  ## - xattrs
  ##
  ## Things that are preserved only with a corresponding flag on:
  ## - hardlinks
  ##
  ## Also, copying "weird" files requires extra flags, otherwise it will result in error.

  var hardlinks = initTable[uint64, string]()

  # This implementation (and some hard cases it needs to consider!) is partially inspired by
  # https://github.com/moby/moby/blob/11179de6/daemon/graphdriver/copy/copy.go#L124.
  proc doCopy(src, dst: string) =
    var st: Stat
    if lstat(src, st) < 0: raiseOSError(osLastError(), src)
    let ftype = st.st_mode.cint and S_IFMT

    var hardlinked = false
    if cfPreserveHardlinks in flags and ftype != S_IFDIR:
      let inode = st.st_ino.uint64
      if inode in hardlinks:
        try:
          createHardlink(hardlinks[inode], dst)
          hardlinked = true
        except OSError:
          # If we failed to create a hardlink, maybe just copy the file?
          discard
      else:
        hardlinks[inode] = dst
    if hardlinked: return

    if ftype == S_IFREG:
      copyFile(src, dst, {cfSymlinkAsIs})
    elif ftype == S_IFDIR:
      createDir(dst)
      for (_, sub) in walkDir(src, relative = true, checkDir = true, skipSpecial = false):
        doCopy(src / sub, dst / sub)
    elif ftype == S_IFLNK:
      createSymlink(expandSymlink(src), dst)
    elif ftype == S_IFCHR or ftype == S_IFBLK:
      if cfCopyDevices notin flags:
        raise UnsupportedFileError.newException(fmt"found device {src.esc}, cannot copy it")
      if mknod(dst.cstring, st.st_mode, st.st_rdev) < 0: raiseOSError(osLastError(), dst)
    elif ftype == S_IFIFO or ftype == S_IFSOCK:
      if cfCopyFifosSockets notin flags:
        let typeStr = if ftype == S_IFIFO: "named pipe" else: "socket"
        raise UnsupportedFileError.newException(fmt"found {typeStr} {src.esc}, cannot copy it")
      if mknod(dst.cstring, st.st_mode, 0) < 0: raiseOSError(osLastError(), dst)
    else:
      raise UnsupportedFileError.newException(
        fmt"found file {src.esc} of unknown type, cannot copy it")

    let times = [st.st_atim, st.st_mtim]
    if utimensat(AT_FDCWD, dst.cstring, addr times, AT_SYMLINK_NOFOLLOW) < 0:
      if cfForceUpdateTimes in flags:
        raiseOSError(osLastError(), dst)

    if ftype != S_IFLNK:
      if chmod(dst.cstring, st.st_mode and 0o7777) < 0:
        if cfForceUpdatePerms in flags:
          raiseOSError(osLastError(), dst)

  if dst.exists:
    raise IOError.newException(fmt"destination {dst.esc} already exists")
  try:
    doCopy(src.string, dst.string)
  except KeyError:
    raiseAssert "internal error: " & getCurrentExceptionMsg()

proc removeFileOrDir(path: string) =
  if dirExists(path):
    removeDir(path, checkDir = true)
  else:
    removeFile(path)

proc movePreserveAll*(src, dst: Path, flags: set[CopyPreserveAllFlag] = {})
  {.raises: [OSError, IOError, UnsupportedFileError].} =
  ## Same as `copyPreserveAll`_, but moves `src` to `dst` instead of copying.
  if rename(src.string.cstring, dst.string.cstring) == 0:
    return
  let err = osLastError()
  if err != EXDEV.OSErrorCode: raiseOSError(err, $(src, dst))

  if dst.exists:
    raise IOError.newException(fmt"destination {dst.esc} already exists")

  var copied = false
  defer:
    if cfNoRollbackMove notin flags and not copied:
      try:
        removeFileOrDir(dst.string)
      except CatchableError:
        discard
  copyPreserveAll(src, dst, flags)
  copied = true
  removeFileOrDir(src.string)
