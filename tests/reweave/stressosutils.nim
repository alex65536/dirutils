import std/[algorithm, sugar, sequtils, options, strformat, os]
import reweave/extpaths
import ./stressutils

proc materializeOnDisk*[T: FsEntry | FsEntryExt](fs: seq[T], root: NaivePath) =
  var fs = fs
  fs.keepIf(e => e.now.isSome)
  # Sort by number of slashes in the path. This helps us to ensure that a directory is created
  # before all the files inside it.
  fs.sort((e1, e2) => cmp(count($e1.now.get, '/'), count($e2.now.get, '/')))
  for e in fs:
    let
      path = e.now.get.asRaw.reroot(root)
      inode = e.inode
    case inode.kind
    of ikFile: writeFile($path, fmt"file at {e.now.get.esc}{'\n'}")
    of ikDir: createDir($path)
    of ikLink: createSymlink($inode.target.reroot(root), $path)
