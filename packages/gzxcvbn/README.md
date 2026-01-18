# gzxcvbn

[![Package Version](https://img.shields.io/hexpm/v/gzxcvbn)](https://hex.pm/packages/gzxcvbn)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gzxcvbn/)

Password strength estimation for Gleam, inspired by
[zxcvbn](https://github.com/dropbox/zxcvbn).

Unlike naive strength meters that just count character types, gzxcvbn recognises
common patterns attackers exploit: dictionary words, keyboard patterns,
repeated characters, sequences, and dates. This gives realistic estimates of
how long a password would take to crack.

## Installation

```sh
gleam add gzxcvbn gzxcvbn_common gzxcvbn_en
```

## Usage

```gleam
import gzxcvbn
import gzxcvbn/common
import gzxcvbn/en

pub fn main() {
  // Build options with dictionaries and keyboard graphs.
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_dictionaries(common.dictionaries())
    |> gzxcvbn.with_dictionaries(en.dictionaries())
    |> gzxcvbn.with_graphs(common.graphs())
    |> gzxcvbn.build()

  // Check a password's strength.
  let result = gzxcvbn.check("correcthorsebatterystaple", opts)

  // result.score == gzxcvbn.VeryUnguessable
  // result.crack_times.offline_slow_display == "centuries"
}
```

### User Inputs

You can add user-specific inputs (names, email, etc.) to catch passwords
containing personal information:

```gleam
let opts =
  gzxcvbn.options()
  |> gzxcvbn.with_dictionaries(common.dictionaries())
  |> gzxcvbn.with_user_inputs(["john", "john@example.com", "acme"])
  |> gzxcvbn.build()
```

### Custom Translations

Feedback messages can be translated by providing custom translation functions:

```gleam
let translations =
  gzxcvbn.Translations(
    warning: fn(key) {
      case key {
        gzxcvbn.TopTenPassword -> "Dies ist ein Top-10 Passwort."
        _ -> gzxcvbn.default_translations().warning(key)
      }
    },
    suggestion: gzxcvbn.default_translations().suggestion,
  )

let result = gzxcvbn.check_with_translations("password", opts, translations)
```

Further documentation can be found at <https://hexdocs.pm/gzxcvbn>.

## Development

```sh
gleam test  # Run the tests
```
