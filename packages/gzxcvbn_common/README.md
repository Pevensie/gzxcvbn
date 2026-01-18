# gzxcvbn_common

[![Package Version](https://img.shields.io/hexpm/v/gzxcvbn_common)](https://hex.pm/packages/gzxcvbn_common)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gzxcvbn_common/)

Common passwords and keyboard graphs for [gzxcvbn](https://hex.pm/packages/gzxcvbn).

This package provides:
- **Passwords dictionary** - 49,233 common passwords ranked by frequency
- **Keyboard graphs** - adjacency graphs for 6 keyboard layouts (QWERTY, AZERTY, DVORAK, QWERTZ, keypad, Mac keypad)

## Installation

```sh
gleam add gzxcvbn_common
```

## Usage

```gleam
import gzxcvbn
import gzxcvbn/common

pub fn main() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_dictionaries(common.dictionaries())
    |> gzxcvbn.with_graphs(common.graphs())
    |> gzxcvbn.build()

  // ...
}
```

You can also add individual dictionaries or graphs:

```gleam
let opts =
  gzxcvbn.options()
  |> gzxcvbn.with_dictionaries([common.passwords()])
  |> gzxcvbn.with_graphs([common.qwerty()])
  |> gzxcvbn.build()
```

Further documentation can be found at <https://hexdocs.pm/gzxcvbn_common>.
