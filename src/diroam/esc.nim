import std/[sugar, paths]
import nestd/neunicode
import unicodeplus

func esc*(s: string): string =
  s.escapeUnicode(r => r.int != 0xfffd and not r.isPrintable, options = {eoEscapeDoubleQuote})

func esc*(s: Path): string = s.string.esc
