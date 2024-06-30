import unittest
import std/sequtils
import reweave/extpaths

test "reweave: hasPrefix for NaivePath":
  check NaivePath("/").hasPrefix(NaivePath("/"))
  check not NaivePath("/").hasPrefix(NaivePath("/a"))
  check not NaivePath("/").hasPrefix(NaivePath("/a/b"))
  check not NaivePath("/").hasPrefix(NaivePath("/a/b/c"))
  check NaivePath("/a").hasPrefix(NaivePath("/"))
  check NaivePath("/a/b").hasPrefix(NaivePath("/"))
  check NaivePath("/a/b/c").hasPrefix(NaivePath("/"))
  check NaivePath("/a/bcd").hasPrefix(NaivePath("/a/bcd"))
  check NaivePath("/a/bcd/ef").hasPrefix(NaivePath("/a/bcd"))
  check not NaivePath("/a/bcd").hasPrefix(NaivePath("/a/bcd/ef"))
  check not NaivePath("/a/bcdef").hasPrefix(NaivePath("/a/bcd"))
  check not NaivePath("/a/bcd").hasPrefix(NaivePath("/a/bcdef"))
  check not NaivePath("/a/b/c").hasPrefix(NaivePath("/a/b/d"))

test "reweave: parent for NaivePath":
  check NaivePath("/").parent == NaivePath("/")
  check NaivePath("/a").parent == NaivePath("/")
  check NaivePath("/abc/de").parent == NaivePath("/abc")

test "reweave: filename for NaivePath":
  check NaivePath("/").filename == ""
  check NaivePath("/a").filename == "a"
  check NaivePath("/abc/de").filename == "de"

test "reweave: child for NaivePath":
  check NaivePath("/").child("abc") == NaivePath("/abc")
  check NaivePath("/abc").child("de") == NaivePath("/abc/de")

test "reweave: relativeTo for NaivePath":
  check $NaivePath("/ab/cde").relativeTo(NaivePath("/ab/cde"), dotIfEqual = true) == "."
  check $NaivePath("/ab/cde").relativeTo(NaivePath("/ab/cde"), dotIfEqual = false) == ""
  check $NaivePath("/").relativeTo(NaivePath("/"), dotIfEqual = true) == "."
  check $NaivePath("/").relativeTo(NaivePath("/"), dotIfEqual = false) == ""

  check $NaivePath("/a/bb/c").relativeTo(NaivePath("/a/bb")) == "c"
  check $NaivePath("/a/bb/c1/c2/c3").relativeTo(NaivePath("/a/bb")) == "c1/c2/c3"
  check $NaivePath("/a/bb").relativeTo(NaivePath("/a/bb/c")) == ".."
  check $NaivePath("/a/bb").relativeTo(NaivePath("/a/bb/c1/c2/c3")) == "../../.."

  check $NaivePath("/a/bbb/cccc").relativeTo(NaivePath("/a/bbb/dd/ee")) == "../../cccc"
  check $NaivePath("/a/bbb/dd/ee").relativeTo(NaivePath("/a/bbb/c")) == "../dd/ee"

  check $NaivePath("/a/bbb/ca").relativeTo(NaivePath("/a/bbb/c")) == "../ca"
  check $NaivePath("/a/bbb/c").relativeTo(NaivePath("/a/bbb/ca")) == "../c"
  check $NaivePath("/a/bbb/ca").relativeTo(NaivePath("/a/bbb/cb")) == "../ca"

  check $NaivePath("/aa/bbb/cccc").relativeTo(NaivePath("/")) == "aa/bbb/cccc"
  check $NaivePath("/aa").relativeTo(NaivePath("/")) == "aa"
  check $NaivePath("/").relativeTo(NaivePath("/aa/bbb/cccc")) == "../../.."
  check $NaivePath("/").relativeTo(NaivePath("/aa")) == ".."

test "reweave: decompose for RawPath":
  check RawPath("/ab/ccc/../dd").decompose(withAbsPathMarker = true).toSeq ==
        @["/", "ab", "ccc", "..", "dd"]
  check RawPath("/ab/ccc/../dd").decompose(withAbsPathMarker = false).toSeq ==
        @["ab", "ccc", "..", "dd"]

  check RawPath("//ab/ccc/..///dd//").decompose(withAbsPathMarker = true).toSeq ==
        @["/", "ab", "ccc", "..", "dd"]
  check RawPath("//ab/ccc/..///dd//").decompose(withAbsPathMarker = false).toSeq ==
        @["ab", "ccc", "..", "dd"]

  check RawPath("ab/ccc/../dd").decompose(withAbsPathMarker = true).toSeq ==
        @["ab", "ccc", "..", "dd"]
  check RawPath("ab/ccc/../dd").decompose(withAbsPathMarker = false).toSeq ==
        @["ab", "ccc", "..", "dd"]

  check RawPath("ab/ccc/..///dd//").decompose(withAbsPathMarker = true).toSeq ==
        @["ab", "ccc", "..", "dd"]
  check RawPath("ab/ccc/..///dd//").decompose(withAbsPathMarker = false).toSeq ==
        @["ab", "ccc", "..", "dd"]

  check RawPath("/").decompose(withAbsPathMarker = true).toSeq == @["/"]
  check RawPath("/").decompose(withAbsPathMarker = false).toSeq == newSeq[string]()

test "reweave: join for RawPath":
  check $RawPath("/a/b/c/d").join(RawPath("")) == "/a/b/c/d"
  check $RawPath("").join(RawPath("/a/b/c/d")) == "/a/b/c/d"
  check $RawPath("").join(RawPath("")) == ""
  check $RawPath("/").join(RawPath("a")) == "/a"
  check $RawPath("/").join(RawPath("a/b/c/")) == "/a/b/c/"
  check $RawPath("a/b").join(RawPath("cc/dd")) == "a/b/cc/dd"
  check $RawPath("a/b/").join(RawPath("cc/dd")) == "a/b/cc/dd"
  check $RawPath("a/b//").join(RawPath("cc/dd")) == "a/b//cc/dd"

test "reweave: reroot for RawPath":
  check $RawPath("a/b/c").reroot(NaivePath("/root")) == "a/b/c"
  check $RawPath("/a/b/c").reroot(NaivePath("/root")) == "/root/a/b/c"
  check $RawPath("").reroot(NaivePath("/root")) == ""
  check $RawPath("/").reroot(NaivePath("/root")) == "/root"
  check $RawPath("//aaa/bbbb/").reroot(NaivePath("/root")) == "/root/aaa/bbbb/"

test "reweave: hasNestedPaths for NaivePath":
  check not hasNestedPaths([NaivePath("/")])
  check hasNestedPaths([NaivePath("/"), NaivePath("/a")])
  check hasNestedPaths([NaivePath("/a/b"), NaivePath("/a/b/cc/dd")])
  check hasNestedPaths([NaivePath("/a/b"), NaivePath("/a/c"), NaivePath("/a/b/d")])
  check not hasNestedPaths([NaivePath("/a/b"), NaivePath("/a/b!")])
  check not hasNestedPaths([NaivePath("/a/b"), NaivePath("/a/bb")])

test "reweave: PathPrefixSet":
  let s = toPathPrefixSet([NaivePath("/b"), NaivePath("/b/c"), NaivePath("/c"), NaivePath("/a/b"),
                           NaivePath("/a/c")])
  check not s.contains(NaivePath("/"))
  check s.contains(NaivePath("/b"))
  check s.contains(NaivePath("/b/c"))
  check s.contains(NaivePath("/b/a"))
  check s.contains(NaivePath("/b/a/bb/cc/ddd"))
  check s.contains(NaivePath("/c"))
  check s.contains(NaivePath("/c/dd"))
  check s.contains(NaivePath("/c/dd/ccc"))
  check not s.contains(NaivePath("/a"))
  check not s.contains(NaivePath("/a/b!"))
  check not s.contains(NaivePath("/a/bd"))
  check not s.contains(NaivePath("/a/c!"))
  check not s.contains(NaivePath("/a/cd"))
  check s.contains(NaivePath("/a/b"))
  check s.contains(NaivePath("/a/c"))
  check s.contains(NaivePath("/a/b/ccc"))
  check s.contains(NaivePath("/a/b/ccc/ddd"))
  check s.contains(NaivePath("/a/c/t/g"))
