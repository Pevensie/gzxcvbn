# gzxcvbn

Password strength estimation for Gleam, inspired by [zxcvbn](https://github.com/dropbox/zxcvbn).

[![Package Version](https://img.shields.io/hexpm/v/gzxcvbn)](https://hex.pm/packages/gzxcvbn)
[![Hex Docs](https://img.shields.io/badge/hex-docs-ffaff3)](https://hexdocs.pm/gzxcvbn/)

**[Live Demo](https://gzxcvbn.pevensie.dev)**

## Installation

Add the packages you need to your project:

```sh
gleam add gzxcvbn gzxcvbn_common gzxcvbn_en
```

## Usage

```gleam
import gzxcvbn
import gzxcvbn/common
import gzxcvbn/en

pub fn main() {
  // Build options with dictionaries and keyboard graphs
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_dictionaries(common.dictionaries())
    |> gzxcvbn.with_dictionaries(en.dictionaries())
    |> gzxcvbn.with_graphs(common.graphs())
    |> gzxcvbn.build()

  // Check a password
  let result = gzxcvbn.check("correcthorsebatterystaple", opts)

  // result.score is one of:
  // - TooGuessable (0): < 10^3 guesses
  // - VeryGuessable (1): < 10^6 guesses
  // - SomewhatGuessable (2): < 10^8 guesses
  // - SafelyUnguessable (3): < 10^10 guesses
  // - VeryUnguessable (4): >= 10^10 guesses
}
```

## Features

- **Dictionary matching** - Detects common passwords, English words, names
- **Sequence detection** - Finds patterns like "abc", "321", "qwerty"
- **Repeat detection** - Identifies repeated characters and patterns
- **Bruteforce estimation** - Calculates entropy for random-looking strings
- **User inputs** - Treat usernames, company names, etc. as weak passwords
- **Feedback generation** - Provides improvement suggestions
- **Crack time estimates** - For various attack scenarios

## Packages

This library is split into three packages:

| Package          | Description                                                                           |
| ---------------- | ------------------------------------------------------------------------------------- |
| `gzxcvbn`        | Core library with matching and scoring algorithms                                     |
| `gzxcvbn_common` | 49k passwords, 6 keyboard graphs (qwerty, dvorak, azerty, qwertz, keypad, keypad_mac) |
| `gzxcvbn_en`     | 150k English entries (common words, first names, last names, Wikipedia)               |

## Selective Dictionaries

Each data package exposes individual dictionaries if you don't need them all:

```gleam
import gzxcvbn
import gzxcvbn/common
import gzxcvbn/en

let opts =
  gzxcvbn.options()
  // Use only specific dictionaries
  |> gzxcvbn.with_dictionaries([common.passwords()])
  |> gzxcvbn.with_dictionaries([en.common_words(), en.lastnames()])
  // Use specific keyboard layouts
  |> gzxcvbn.with_graphs([common.qwerty(), common.dvorak()])
  |> gzxcvbn.build()
```

## Adding User Inputs

Include user-specific data to prevent easily guessable passwords:

```gleam
let opts =
  gzxcvbn.options()
  |> gzxcvbn.with_user_inputs(["username", "company", "email@example.com"])
  |> gzxcvbn.build()
```

## Development

```sh
cd packages/gzxcvbn && gleam test
```

### Regenerating Dictionaries

Dictionary data is fetched from [zxcvbn-ts](https://github.com/zxcvbn-ts/zxcvbn) and converted to Gleam:

```sh
cd packages/codegen && gleam run
```
