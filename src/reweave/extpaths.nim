import std/[sequtils, hashes, strutils, strformat, algorithm]
import ../common/escapes

type
  NaivePath* = distinct string
    ## `NaivePath` is a path that satisfies the following criteria:
    ## - it is absolute
    ## - it doesn't have trailing slashes
    ## - it doesn't have double slashes
    ## - it doesn't have `"."` and `".."` components
    ## - only the last path component is allowed to be a symink

  RawPath* = distinct string
    ## Raw unix path. The difference with `std.paths.Path` is that it doesn't try to normalize
    ## on each operation.
    ##
    ## Normalization is a bad idea, because in the weird world of symbolic links `a/../b` and `a`
    ## may be different paths actually.

template `$`*(p: NaivePath): string = p.string
func `==`*(a: NaivePath, b: string): bool = $a == b
func `==`*(a: string, b: NaivePath): bool = a == $b
func `==`*(a, b: NaivePath): bool = $a == $b
func strLen*(p: NaivePath): Natural = ($p).len
func esc*(p: NaivePath): string = esc($p)
func hash*(p: NaivePath): Hash = ($p).hash

template `$`*(p: RawPath): string = p.string
func strLen*(p: RawPath): Natural = ($p).len
func esc*(p: RawPath): string = esc($p)

func isValid*(p: NaivePath): bool =
  ## Checks all the invariants about `NaivePath` (except for symlink part)
  let s = $p
  if s == "/": return true
  if not s.startsWith('/'): return false
  if s.endsWith('/'): return false
  if "//" in s: return false
  if s.endsWith("/.") or s.endsWith("/..") or "/./" in s or "/../" in s: return false
  true

func assertValid*(p: NaivePath) =
  ## Asserts all the invariants about `NaivePath` (except for symlink part)
  doAssert p.isValid, fmt"{p.esc} is not a valid NaivePath"

func hasPrefix*(p: NaivePath, pref: NaivePath): bool =
  if pref == "/": return true
  startsWith($p, $pref) and (p.strLen <= pref.strLen or ($p)[pref.strLen] == '/')

func push*(p: var NaivePath, filename: string) =
  doAssert filename != "" and filename != "." and filename != ".." and filename.find('/') == -1
  if p != "/": $p &= '/'
  $p &= filename

func pop*(p: var NaivePath) =
  let slash = ($p).rfind('/')
  doAssert slash >= 0
  ($p).setLen(if slash == 0: 1 else: slash)

func parent*(p: NaivePath): NaivePath =
  result = p
  result.pop

func filename*(p: NaivePath): string =
  let slash = ($p).rfind('/')
  doAssert slash >= 0
  ($p)[(slash+1)..^1]

func child*(p: NaivePath, filename: string): NaivePath =
  result = p
  result.push(filename)

func asRaw*(p: NaivePath): RawPath = RawPath($p)

func multiDotDot(times: int): RawPath =
  $result = ""
  for i in 1..times:
    $result &= (if i == 1: ".." else: "/..")

func relativeTo*(path, base: NaivePath, dotIfEqual = false): RawPath =
  # First, find common path prefix between `path` and `base`.
  var lcp = 0
  while lcp < ($path).len and lcp < ($base).len and ($path)[lcp] == ($base)[lcp]:
    inc lcp
  if lcp == ($path).len and lcp == ($base).len:
    # Paths are equal. Return either `"."` or `""`, depending on options.
    return if dotIfEqual: ".".RawPath else: "".RawPath
  # If one of the paths is `"/"`, then this case needs a special treatment.
  if base == "/": return RawPath(($path)[1..^1])
  if path == "/": return multiDotDot(($base).count('/'))
  # Then, compute `start`: position where the paths begin to diverge as paths (not as strings).
  # We may need to roll back, as "/a/b/c" and "a/bc" have common prefix `"/a/b"`, but common part
  # is only `"/a"`. For each of the paths, `start` points to either end of string (if one of the
  # paths is a prefix to another), or to `"/"` character after which the two paths diverge.
  var start = lcp
  let startOk = (start == ($path).len or ($path)[start] == '/') and
                (start == ($base).len or ($base)[start] == '/')
  if not startOk:
    dec start
    while start >= 0 and ($path)[start] != '/':
      dec start
  doAssert start >= 0
  # Build the result. Note that for each path `p`, the substring `($p)[start..^1]` is either empty
  # or has the form `/a/b/c/.../d`, so easy to work with.
  var dotDotCount = 0
  for i in start..high($base):
    if ($base)[i] == '/': inc dotDotCount
  result = multiDotDot(dotDotCount)
  if start < ($path).len:
    let pos = if result.strLen == 0: start+1 else: start
    $result &= ($path)[pos..^1]
  doAssert result.strLen != 0

iterator decompose*(p: RawPath, withAbsPathMarker = true): string =
  var pos = 0
  if withAbsPathMarker and pos < ($p).len and ($p)[pos] == '/':
    # This path is absolute and we ask for initial slash.
    yield "/"
    inc pos
  while pos < ($p).len and ($p)[pos] == '/': inc pos
  while pos < ($p).len:
    let left = pos
    while pos < ($p).len and ($p)[pos] != '/': inc pos
    yield ($p)[left..<pos]
    while pos < ($p).len and ($p)[pos] == '/': inc pos

func isAbsolute*(p: RawPath): bool = p.strLen != 0 and ($p)[0] == '/'

func extend*(a: var RawPath, b: RawPath) =
  if $b == "": return
  if $a == "":
    a = b
    return
  doAssert not b.isAbsolute
  if ($a)[^1] != '/': $a &= '/'
  $a &= $b

func push*(a: var RawPath, filename: string) =
  doAssert filename != "" and filename.find('/') == -1
  a.extend(filename.RawPath)

func join*(a, b: RawPath): RawPath =
  result = a
  result.extend(b)

func hasTrailingSep*(path: RawPath): bool =
  if ($path).allIt(it == '/'): return false
  doAssert path.strLen != 0
  ($path)[^1] == '/'

func addTrailingSep*(path: var RawPath) =
  if path.strLen != 0 and ($path)[^1] != '/': $path &= '/'

func reroot*(path: RawPath, root: NaivePath): RawPath =
  if not path.isAbsolute: return path
  let relTarget = strip($path, leading = true, trailing = false, chars = {'/'}).RawPath
  root.asRaw.join(relTarget)

func toSlashed(p: NaivePath): string =
  if p == "/": $p else: $p & "/"

func hasNestedPaths*(paths: openArray[NaivePath]): bool =
  ## Returns `true` if there exist such distinct `i` and `j` that `paths[i].hasPrefix(paths[j])`.
  if paths.len < 2: return false
  var slashed = paths.map(toSlashed)
  slashed.sort
  for i in 1..<slashed.len:
    if slashed[i].startsWith(slashed[i-1]): return true
  false

type
  PathPrefixSet* = object
    slashed: seq[string]

func toPathPrefixSet*(paths: openArray[NaivePath]): PathPrefixSet =
  var srcSlashed = paths.map(toSlashed)
  srcSlashed.sort
  var slashed = newSeqOfCap[string](srcSlashed.len)
  for s in srcSlashed:
    if slashed.len == 0 or not s.startsWith(slashed[^1]): slashed.add(s)
  PathPrefixSet(slashed: slashed)

func contains*(s: PathPrefixSet, path: NaivePath): bool =
  ## Returns `true` if `path` is a child of any of the directories kept in this `PathPrefixSet` or
  ## is equal to one of them.
  let key = path.toSlashed
  let pos = s.slashed.upperBound(key)
  pos != 0 and key.startsWith(s.slashed[pos-1])
