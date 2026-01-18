# gzxcvbn_en

[![Package Version](https://img.shields.io/hexpm/v/gzxcvbn_en)](https://hex.pm/packages/gzxcvbn_en)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gzxcvbn_en/)

English language dictionaries for [gzxcvbn](https://hex.pm/packages/gzxcvbn).

This package provides:
- **Common words** - 26,758 entries from TV/film subtitles
- **First names** - 4,945 entries
- **Last names** - 88,799 entries
- **Wikipedia words** - 29,782 entries

## Installation

```sh
gleam add gzxcvbn_en
```

## Usage

```gleam
import gzxcvbn
import gzxcvbn/en

pub fn main() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_dictionaries(en.dictionaries())
    |> gzxcvbn.build()

  // ...
}
```

You can also add individual dictionaries:

```gleam
let opts =
  gzxcvbn.options()
  |> gzxcvbn.with_dictionaries([en.common_words(), en.firstnames()])
  |> gzxcvbn.build()
```

Further documentation can be found at <https://hexdocs.pm/gzxcvbn_en>.
