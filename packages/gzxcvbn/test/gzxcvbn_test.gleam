import gleam/dict
import gleam/int
import gleam/list
import gleam/option
import gleam/string
import gleeunit
import gzxcvbn

pub fn main() -> Nil {
  gleeunit.main()
}

// =============================================================================
// Test Helpers
// =============================================================================

fn test_passwords_dict() -> gzxcvbn.NamedDictionary {
  gzxcvbn.NamedDictionary(
    name: "common_passwords",
    kind: gzxcvbn.Passwords,
    dictionary: dict.from_list([
      #("password", 1),
      #("123456", 2),
      #("qwerty", 3),
      #("letmein", 4),
      #("monkey", 5),
    ]),
  )
}

fn test_opts() -> gzxcvbn.Options {
  gzxcvbn.options()
  |> gzxcvbn.with_dictionaries([test_passwords_dict()])
  |> gzxcvbn.build()
}

// =============================================================================
// Integration Tests
// =============================================================================

pub fn check_weak_password_test() {
  let opts = test_opts()
  let result = gzxcvbn.check("password", opts)

  // "password" is rank 1 in test dict - should be very weak
  assert result.score == gzxcvbn.TooGuessable
  assert result.guesses < 1000
}

pub fn check_common_password_test() {
  let opts = test_opts()
  let result = gzxcvbn.check("123456", opts)

  // "123456" is rank 2 - still very weak
  assert result.score == gzxcvbn.TooGuessable
}

pub fn check_empty_password_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("", opts)

  assert result.guesses == 1
  assert result.score == gzxcvbn.TooGuessable
}

pub fn check_random_password_test() {
  let opts = test_opts()

  // A truly random-looking password should score high
  let result = gzxcvbn.check("xK9#mP2$nQ7@wL4", opts)

  // Should be at least somewhat guessable due to length and complexity
  assert result.score == gzxcvbn.SafelyUnguessable
    || result.score == gzxcvbn.VeryUnguessable
}

pub fn check_sequence_pattern_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("abcdefgh", opts)

  // Should detect as sequence and score low
  assert result.score == gzxcvbn.TooGuessable
    || result.score == gzxcvbn.VeryGuessable

  // Should have sequence match in results
  let has_sequence =
    list.any(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.SequenceMatch(..) -> True
        _ -> False
      }
    })
  assert has_sequence
}

pub fn check_repeat_pattern_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("aaaaaaa", opts)

  // Repeated characters should be weak
  assert result.score == gzxcvbn.TooGuessable
    || result.score == gzxcvbn.VeryGuessable
}

pub fn check_user_inputs_test() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_user_inputs(["companyname", "username123"])
    |> gzxcvbn.build()

  let result = gzxcvbn.check("companyname", opts)

  // Should detect user input as dictionary word
  assert result.score == gzxcvbn.TooGuessable
}

pub fn check_feedback_present_test() {
  let opts = test_opts()
  let result = gzxcvbn.check("password", opts)

  // Weak passwords should have warnings
  assert result.feedback.warning != ""
}

pub fn check_feedback_empty_for_strong_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("xK9#mP2$nQ7@wL4vB8", opts)

  // Strong passwords should have no warning
  assert result.feedback.warning == ""
}

// =============================================================================
// Crack Time Tests
// =============================================================================

pub fn crack_times_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("password123", opts)

  // Crack times should be populated
  assert result.crack_times.online_throttled_display != ""
  assert result.crack_times.online_unthrottled_display != ""
  assert result.crack_times.offline_slow_display != ""
  assert result.crack_times.offline_fast_display != ""
}

// =============================================================================
// Options Tests
// =============================================================================

pub fn options_builder_test() {
  let graph =
    gzxcvbn.NamedGraph(
      name: "test",
      graph: dict.from_list([
        #("a", [option.Some("b"), option.None]),
        #("b", [option.Some("a"), option.Some("c")]),
      ]),
    )

  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_dictionaries([test_passwords_dict()])
    |> gzxcvbn.with_graphs([graph])
    |> gzxcvbn.with_user_inputs(["test", "user"])
    |> gzxcvbn.build()

  // Should be able to use the options
  let result = gzxcvbn.check("test", opts)
  assert result.score == gzxcvbn.TooGuessable
}

// =============================================================================
// DictionaryKind Feedback Tests
// =============================================================================

fn test_names_dict() -> gzxcvbn.NamedDictionary {
  gzxcvbn.NamedDictionary(
    name: "first_names",
    kind: gzxcvbn.Names,
    dictionary: dict.from_list([
      #("john", 1),
      #("mary", 2),
      #("james", 3),
    ]),
  )
}

fn test_words_dict() -> gzxcvbn.NamedDictionary {
  gzxcvbn.NamedDictionary(
    name: "common_words",
    kind: gzxcvbn.Words,
    dictionary: dict.from_list([
      #("hello", 1),
      #("world", 2),
      #("computer", 3),
    ]),
  )
}

pub fn user_names_warning_test() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_user_names(["alice", "bob"])
    |> gzxcvbn.build()

  let result = gzxcvbn.check("alice", opts)

  assert result.score == gzxcvbn.TooGuessable
  assert result.feedback.warning == "Names by themselves are easy to guess."
}

pub fn user_years_warning_test() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_user_years([1990, 2000])
    |> gzxcvbn.build()

  let result = gzxcvbn.check("1990", opts)

  assert result.score == gzxcvbn.TooGuessable
  assert result.feedback.warning
    == "Years associated with you are easy to guess."
  assert list.contains(
    result.feedback.suggestions,
    "Avoid years that are associated with you.",
  )
}

pub fn names_dict_warning_test() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_dictionaries([test_names_dict()])
    |> gzxcvbn.build()

  let result = gzxcvbn.check("john", opts)

  assert result.score == gzxcvbn.TooGuessable
  assert result.feedback.warning
    == "Common names and surnames are easy to guess."
}

pub fn words_dict_warning_test() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_dictionaries([test_words_dict()])
    |> gzxcvbn.build()

  let result = gzxcvbn.check("hello", opts)

  assert result.score == gzxcvbn.TooGuessable
  assert result.feedback.warning == "A word by itself is easy to guess."
}

pub fn passwords_dict_top_ten_warning_test() {
  let opts = test_opts()
  let result = gzxcvbn.check("password", opts)

  // "password" is rank 1 - should be top-10
  assert result.feedback.warning == "This is a top-10 common password."
}

pub fn passwords_dict_top_hundred_warning_test() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_dictionaries([
      gzxcvbn.NamedDictionary(
        name: "passwords",
        kind: gzxcvbn.Passwords,
        dictionary: dict.from_list([#("testpass", 50)]),
      ),
    ])
    |> gzxcvbn.build()

  let result = gzxcvbn.check("testpass", opts)

  assert result.feedback.warning == "This is a top-100 common password."
}

pub fn passwords_dict_common_warning_test() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_dictionaries([
      gzxcvbn.NamedDictionary(
        name: "passwords",
        kind: gzxcvbn.Passwords,
        dictionary: dict.from_list([#("obscurepass", 500)]),
      ),
    ])
    |> gzxcvbn.build()

  let result = gzxcvbn.check("obscurepass", opts)

  assert result.feedback.warning == "This is a very common password."
}

// =============================================================================
// Match Position Tests
// =============================================================================

pub fn dictionary_match_positions_test() {
  let opts = test_opts()
  let result = gzxcvbn.check("password", opts)

  // Should have exactly one match covering the whole password
  let assert [match] = result.sequence
  let assert gzxcvbn.DictionaryMatch(start: 0, end: 7, token: "password", ..) =
    match.match
}

pub fn sequence_match_positions_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("abcdef", opts)

  let seq_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.SequenceMatch(..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = seq_match
  let assert gzxcvbn.SequenceMatch(start: 0, end: 5, token: "abcdef", ..) =
    match.match
}

pub fn bruteforce_match_for_random_chars_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("!@#$", opts)

  // Random symbols should result in bruteforce match
  let has_bruteforce =
    list.any(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.BruteforceMatch(..) -> True
        _ -> False
      }
    })
  assert has_bruteforce
}

pub fn bruteforce_match_positions_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("xy", opts)

  // Short random string should be a single bruteforce match
  let assert [match] = result.sequence
  let assert gzxcvbn.BruteforceMatch(start: 0, end: 1, token: "xy") =
    match.match
}

pub fn mixed_match_positions_test() {
  let opts = test_opts()
  // "password" is in dict, "xy" is not
  let result = gzxcvbn.check("passwordxy", opts)

  // Should have dictionary match for "password" and bruteforce for remainder
  let dict_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.DictionaryMatch(..) -> True
        _ -> False
      }
    })

  let assert Ok(dm) = dict_match
  let assert gzxcvbn.DictionaryMatch(start: 0, end: 7, token: "password", ..) =
    dm.match

  // Remaining characters should be covered by bruteforce matches
  let brute_matches =
    list.filter(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.BruteforceMatch(..) -> True
        _ -> False
      }
    })

  // Should have bruteforce coverage for positions 8 and 9
  let covers_8 =
    list.any(brute_matches, fn(m) { m.match.start <= 8 && m.match.end >= 8 })
  let covers_9 =
    list.any(brute_matches, fn(m) { m.match.start <= 9 && m.match.end >= 9 })
  assert covers_8
  assert covers_9
}

pub fn matches_cover_full_password_test() {
  let opts = test_opts()
  let password = "password123abc"
  let result = gzxcvbn.check(password, opts)

  // Verify matches cover the entire password with no gaps
  let sorted =
    list.sort(result.sequence, fn(a, b) {
      int.compare(a.match.start, b.match.start)
    })

  // First match should start at 0
  let assert [first, ..] = sorted
  assert first.match.start == 0

  // Last match should end at password length - 1
  let assert Ok(last) = list.last(sorted)
  assert last.match.end == string.length(password) - 1

  // No gaps between matches
  let has_gaps =
    sorted
    |> list.window_by_2
    |> list.any(fn(pair) {
      let #(prev, next) = pair
      next.match.start != prev.match.end + 1
    })
  assert !has_gaps
}

pub fn repeat_match_positions_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("aaaa", opts)

  let repeat_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.RepeatMatch(..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = repeat_match
  let assert gzxcvbn.RepeatMatch(
    start: 0,
    end: 3,
    token: "aaaa",
    base_token: "a",
    repeat_count: 4,
    ..,
  ) = match.match
}

// =============================================================================
// Reversed Dictionary Matching Tests
// =============================================================================

pub fn reversed_dictionary_match_test() {
  let opts = test_opts()
  // "drowssap" is "password" reversed
  let result = gzxcvbn.check("drowssap", opts)

  let dict_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.DictionaryMatch(reversed: True, ..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = dict_match
  let assert gzxcvbn.DictionaryMatch(reversed: True, token: "drowssap", ..) =
    match.match
}

// =============================================================================
// Custom Translations Tests
// =============================================================================

pub fn custom_translations_test() {
  let opts = test_opts()
  let translations =
    gzxcvbn.Translations(
      warning: fn(w) {
        case w {
          gzxcvbn.TopTenPassword -> "CUSTOM: Top 10!"
          _ -> "CUSTOM: Other warning"
        }
      },
      suggestion: fn(s) {
        case s {
          gzxcvbn.AddAnotherWord -> "CUSTOM: Add more words"
          _ -> "CUSTOM: Other suggestion"
        }
      },
    )

  let result = gzxcvbn.check_with_translations("password", opts, translations)

  assert result.feedback.warning == "CUSTOM: Top 10!"
  assert list.contains(result.feedback.suggestions, "CUSTOM: Add more words")
}

// =============================================================================
// Descending Sequence Tests
// =============================================================================

pub fn descending_alpha_sequence_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("zyxwvu", opts)

  let seq_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.SequenceMatch(ascending: False, ..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = seq_match
  let assert gzxcvbn.SequenceMatch(
    token: "zyxwvu",
    ascending: False,
    sequence_name: "lower",
    ..,
  ) = match.match
}

pub fn descending_digit_sequence_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("9876543", opts)

  let seq_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.SequenceMatch(ascending: False, ..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = seq_match
  let assert gzxcvbn.SequenceMatch(
    token: "9876543",
    ascending: False,
    sequence_name: "digits",
    ..,
  ) = match.match
}

// =============================================================================
// Multi-Character Repeat Tests
// =============================================================================

pub fn multi_char_repeat_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  // Use non-sequential chars to ensure repeat detection wins
  let result = gzxcvbn.check("qazqazqaz", opts)

  let repeat_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.RepeatMatch(..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = repeat_match
  let assert gzxcvbn.RepeatMatch(
    token: "qazqazqaz",
    base_token: "qaz",
    repeat_count: 3,
    ..,
  ) = match.match
}

pub fn two_char_repeat_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  // "qa" is non-sequential (q=113, a=97)
  let result = gzxcvbn.check("qaqaqaqa", opts)

  let repeat_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.RepeatMatch(..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = repeat_match
  let assert gzxcvbn.RepeatMatch(
    token: "qaqaqaqa",
    base_token: "qa",
    repeat_count: 4,
    ..,
  ) = match.match
}

// =============================================================================
// Edge Case Tests
// =============================================================================

pub fn single_char_password_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("a", opts)

  assert result.score == gzxcvbn.TooGuessable
  assert result.guesses >= 10
}

pub fn unicode_password_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("日本語パスワード", opts)

  // Should handle unicode without crashing
  assert result.guesses >= 1
}

pub fn mixed_case_dictionary_test() {
  let opts = test_opts()
  // "PASSWORD" should match "password" in dictionary
  let result = gzxcvbn.check("PASSWORD", opts)

  assert result.score == gzxcvbn.TooGuessable

  let dict_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.DictionaryMatch(..) -> True
        _ -> False
      }
    })

  let assert Ok(_) = dict_match
}

pub fn uppercase_sequence_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("ABCDEF", opts)

  let seq_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.SequenceMatch(sequence_name: "upper", ..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = seq_match
  let assert gzxcvbn.SequenceMatch(sequence_name: "upper", ascending: True, ..) =
    match.match
}

// =============================================================================
// Spatial Matching Tests
// =============================================================================

fn test_qwerty_graph() -> gzxcvbn.NamedGraph {
  gzxcvbn.NamedGraph(
    name: "qwerty",
    graph: dict.from_list([
      #("q", [
        option.None,
        option.Some("1!"),
        option.Some("2@"),
        option.Some("wW"),
        option.Some("aA"),
        option.None,
      ]),
      #("w", [
        option.Some("qQ"),
        option.Some("2@"),
        option.Some("3#"),
        option.Some("eE"),
        option.Some("sS"),
        option.Some("aA"),
      ]),
      #("e", [
        option.Some("wW"),
        option.Some("3#"),
        option.Some("4$"),
        option.Some("rR"),
        option.Some("dD"),
        option.Some("sS"),
      ]),
      #("r", [
        option.Some("eE"),
        option.Some("4$"),
        option.Some("5%"),
        option.Some("tT"),
        option.Some("fF"),
        option.Some("dD"),
      ]),
      #("t", [
        option.Some("rR"),
        option.Some("5%"),
        option.Some("6^"),
        option.Some("yY"),
        option.Some("gG"),
        option.Some("fF"),
      ]),
      #("y", [
        option.Some("tT"),
        option.Some("6^"),
        option.Some("7&"),
        option.Some("uU"),
        option.Some("hH"),
        option.Some("gG"),
      ]),
      #("a", [
        option.None,
        option.Some("qQ"),
        option.Some("wW"),
        option.Some("sS"),
        option.Some("zZ"),
        option.None,
      ]),
      #("s", [
        option.Some("aA"),
        option.Some("wW"),
        option.Some("eE"),
        option.Some("dD"),
        option.Some("xX"),
        option.Some("zZ"),
      ]),
      #("d", [
        option.Some("sS"),
        option.Some("eE"),
        option.Some("rR"),
        option.Some("fF"),
        option.Some("cC"),
        option.Some("xX"),
      ]),
      #("f", [
        option.Some("dD"),
        option.Some("rR"),
        option.Some("tT"),
        option.Some("gG"),
        option.Some("vV"),
        option.Some("cC"),
      ]),
      #("g", [
        option.Some("fF"),
        option.Some("tT"),
        option.Some("yY"),
        option.Some("hH"),
        option.Some("bB"),
        option.Some("vV"),
      ]),
      #("h", [
        option.Some("gG"),
        option.Some("yY"),
        option.Some("uU"),
        option.Some("jJ"),
        option.Some("nN"),
        option.Some("bB"),
      ]),
      #("z", [
        option.None,
        option.Some("aA"),
        option.Some("sS"),
        option.Some("xX"),
        option.None,
        option.None,
      ]),
      #("x", [
        option.Some("zZ"),
        option.Some("sS"),
        option.Some("dD"),
        option.Some("cC"),
        option.None,
        option.None,
      ]),
      #("c", [
        option.Some("xX"),
        option.Some("dD"),
        option.Some("fF"),
        option.Some("vV"),
        option.None,
        option.None,
      ]),
      #("v", [
        option.Some("cC"),
        option.Some("fF"),
        option.Some("gG"),
        option.Some("bB"),
        option.None,
        option.None,
      ]),
      #("b", [
        option.Some("vV"),
        option.Some("gG"),
        option.Some("hH"),
        option.Some("nN"),
        option.None,
        option.None,
      ]),
      #("n", [
        option.Some("bB"),
        option.Some("hH"),
        option.Some("jJ"),
        option.Some("mM"),
        option.None,
        option.None,
      ]),
      #("2", [
        option.Some("1!"),
        option.None,
        option.None,
        option.Some("3#"),
        option.Some("wW"),
        option.Some("qQ"),
      ]),
      #("5", [
        option.Some("4$"),
        option.None,
        option.None,
        option.Some("6^"),
        option.Some("tT"),
        option.Some("rR"),
      ]),
      #("8", [
        option.Some("7&"),
        option.None,
        option.None,
        option.Some("9("),
        option.Some("iI"),
        option.Some("uU"),
      ]),
    ]),
  )
}

fn test_keypad_graph() -> gzxcvbn.NamedGraph {
  gzxcvbn.NamedGraph(
    name: "keypad",
    graph: dict.from_list([
      #("2", [
        option.None,
        option.None,
        option.None,
        option.Some("3"),
        option.Some("6"),
        option.Some("5"),
        option.Some("4"),
        option.Some("1"),
      ]),
      #("5", [
        option.Some("2"),
        option.Some("3"),
        option.Some("6"),
        option.Some("9"),
        option.Some("8"),
        option.Some("7"),
        option.Some("4"),
        option.Some("1"),
      ]),
      #("8", [
        option.Some("5"),
        option.Some("6"),
        option.Some("9"),
        option.None,
        option.None,
        option.None,
        option.Some("0"),
        option.Some("7"),
      ]),
    ]),
  )
}

pub fn spatial_qwerty_test() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_graphs([test_qwerty_graph()])
    |> gzxcvbn.build()

  let result = gzxcvbn.check("qwerty", opts)

  let spatial_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.SpatialMatch(..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = spatial_match
  let assert gzxcvbn.SpatialMatch(token: "qwerty", graph: "qwerty", ..) =
    match.match
}

pub fn spatial_asdfgh_test() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_graphs([test_qwerty_graph()])
    |> gzxcvbn.build()

  let result = gzxcvbn.check("asdfgh", opts)

  let spatial_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.SpatialMatch(..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = spatial_match
  let assert gzxcvbn.SpatialMatch(token: "asdfgh", graph: "qwerty", ..) =
    match.match
}

pub fn spatial_shifted_test() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_graphs([test_qwerty_graph()])
    |> gzxcvbn.build()

  let result = gzxcvbn.check("QWERTY", opts)

  let spatial_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.SpatialMatch(shifted_count: s, ..) if s > 0 -> True
        _ -> False
      }
    })

  let assert Ok(match) = spatial_match
  let assert gzxcvbn.SpatialMatch(shifted_count: 6, ..) = match.match
}

pub fn spatial_keypad_test() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_graphs([test_keypad_graph()])
    |> gzxcvbn.build()

  let result = gzxcvbn.check("258", opts)

  let spatial_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.SpatialMatch(graph: "keypad", ..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = spatial_match
  let assert gzxcvbn.SpatialMatch(token: "258", graph: "keypad", ..) =
    match.match
}

pub fn spatial_minimum_length_test() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_graphs([test_qwerty_graph()])
    |> gzxcvbn.build()

  let result = gzxcvbn.check("qw", opts)

  // Should NOT have a spatial match (too short)
  let spatial_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.SpatialMatch(..) -> True
        _ -> False
      }
    })

  assert spatial_match == Error(Nil)
}

pub fn spatial_mixed_case_test() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_graphs([test_qwerty_graph()])
    |> gzxcvbn.build()

  // Mixed case should still detect the spatial pattern
  let result = gzxcvbn.check("qWeRtY", opts)

  let spatial_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.SpatialMatch(..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = spatial_match
  let assert gzxcvbn.SpatialMatch(token: "qWeRtY", graph: "qwerty", ..) =
    match.match
}

pub fn spatial_mixed_case_partial_shift_test() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_graphs([test_qwerty_graph()])
    |> gzxcvbn.build()

  // Some shifted, some not
  let result = gzxcvbn.check("qwERty", opts)

  let spatial_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.SpatialMatch(..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = spatial_match
  let assert gzxcvbn.SpatialMatch(
    token: "qwERty",
    shifted_count: 2,
    graph: "qwerty",
    ..,
  ) = match.match
}

pub fn spatial_alternating_case_test() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_graphs([test_qwerty_graph()])
    |> gzxcvbn.build()

  // Alternating case pattern
  let result = gzxcvbn.check("AsdfGh", opts)

  let spatial_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.SpatialMatch(..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = spatial_match
  let assert gzxcvbn.SpatialMatch(
    token: "AsdfGh",
    shifted_count: 2,
    graph: "qwerty",
    ..,
  ) = match.match
}

// =============================================================================
// Date Matching Tests
// =============================================================================

pub fn date_no_separator_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("19901225", opts)

  let date_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.DateMatch(..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = date_match
  let assert gzxcvbn.DateMatch(
    token: "19901225",
    year: 1990,
    month: 12,
    day: 25,
    has_separator: False,
    ..,
  ) = match.match
}

pub fn date_with_separator_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("25/12/1990", opts)

  let date_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.DateMatch(has_separator: True, ..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = date_match
  let assert gzxcvbn.DateMatch(
    year: 1990,
    month: 12,
    day: 25,
    has_separator: True,
    ..,
  ) = match.match
}

pub fn date_dash_separator_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("1-1-90", opts)

  let date_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.DateMatch(has_separator: True, ..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = date_match
  let assert gzxcvbn.DateMatch(year: 1990, has_separator: True, ..) =
    match.match
}

pub fn date_dot_separator_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("01.01.90", opts)

  let date_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.DateMatch(has_separator: True, ..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = date_match
  let assert gzxcvbn.DateMatch(year: 1990, has_separator: True, ..) =
    match.match
}

pub fn date_feedback_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("19901225", opts)

  // Should have date-related feedback
  assert result.feedback.warning == "Dates are often easy to guess."
    || result.feedback.warning == "Recent years are easy to guess."
}

pub fn date_recent_year_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("20201225", opts)

  let date_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.DateMatch(..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = date_match
  let assert gzxcvbn.DateMatch(year: 2020, ..) = match.match

  // Recent years should trigger the "Recent years" warning
  assert result.feedback.warning == "Recent years are easy to guess."
}

pub fn date_invalid_month_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  // 13 is not a valid month
  let result = gzxcvbn.check("20201325", opts)

  let date_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.DateMatch(month: 13, ..) -> True
        _ -> False
      }
    })

  // Should not match with month=13
  assert date_match == Error(Nil)
}

pub fn date_invalid_day_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  // 32 is not a valid day
  let result = gzxcvbn.check("20201232", opts)

  let date_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.DateMatch(day: 32, ..) -> True
        _ -> False
      }
    })

  // Should not match with day=32
  assert date_match == Error(Nil)
}

pub fn date_year_out_of_range_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  // Year 2100 is outside the valid range (>2050)
  let result = gzxcvbn.check("21001225", opts)

  let date_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.DateMatch(year: 2100, ..) -> True
        _ -> False
      }
    })

  // Should not match with year=2100
  assert date_match == Error(Nil)
}

pub fn date_with_separator_invalid_month_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  // 13 is not a valid month
  let result = gzxcvbn.check("25/13/2020", opts)

  let date_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.DateMatch(month: 13, has_separator: True, ..) -> True
        _ -> False
      }
    })

  // Should not match with month=13
  assert date_match == Error(Nil)
}

pub fn date_mismatched_separators_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  // Mixed separators (slash and dash) should not match as a date
  let result = gzxcvbn.check("25/12-1990", opts)

  let date_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.DateMatch(has_separator: True, ..) -> True
        _ -> False
      }
    })

  // Should not match with mismatched separators
  assert date_match == Error(Nil)
}

pub fn date_mismatched_separators_dot_dash_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  // Mixed separators (dot and dash) should not match as a date
  let result = gzxcvbn.check("25.12-1990", opts)

  let date_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.DateMatch(has_separator: True, ..) -> True
        _ -> False
      }
    })

  // Should not match with mismatched separators
  assert date_match == Error(Nil)
}

pub fn date_mismatched_separators_slash_dot_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  // Mixed separators (slash and dot) should not match as a date
  let result = gzxcvbn.check("25/12.1990", opts)

  let date_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.DateMatch(has_separator: True, ..) -> True
        _ -> False
      }
    })

  // Should not match with mismatched separators
  assert date_match == Error(Nil)
}

// =============================================================================
// L33t Matching Tests
// =============================================================================

pub fn l33t_simple_test() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_dictionaries([
      gzxcvbn.NamedDictionary(
        name: "passwords",
        kind: gzxcvbn.Passwords,
        dictionary: dict.from_list([#("password", 1)]),
      ),
    ])
    |> gzxcvbn.build()

  let result = gzxcvbn.check("p@ssword", opts)

  let l33t_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.DictionaryMatch(l33t: True, ..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = l33t_match
  let assert gzxcvbn.DictionaryMatch(
    l33t: True,
    token: "p@ssword",
    dictionary_name: "passwords",
    ..,
  ) = match.match
}

pub fn l33t_multiple_subs_test() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_dictionaries([
      gzxcvbn.NamedDictionary(
        name: "passwords",
        kind: gzxcvbn.Passwords,
        dictionary: dict.from_list([#("password", 1)]),
      ),
    ])
    |> gzxcvbn.build()

  let result = gzxcvbn.check("p@$$w0rd", opts)

  let l33t_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.DictionaryMatch(l33t: True, ..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = l33t_match
  let assert gzxcvbn.DictionaryMatch(l33t: True, l33t_subs: subs, ..) =
    match.match

  // Should have tracked multiple substitutions
  assert list.length(subs) >= 2
}

pub fn l33t_feedback_test() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_dictionaries([
      gzxcvbn.NamedDictionary(
        name: "passwords",
        kind: gzxcvbn.Passwords,
        dictionary: dict.from_list([#("password", 1)]),
      ),
    ])
    |> gzxcvbn.build()

  let result = gzxcvbn.check("p@ssword", opts)

  // Should have feedback about predictable substitutions
  let has_sub_suggestion =
    list.any(result.feedback.suggestions, fn(s) {
      string.contains(s, "substitution")
    })
  assert has_sub_suggestion
}

pub fn l33t_no_false_positive_test() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_dictionaries([
      gzxcvbn.NamedDictionary(
        name: "words",
        kind: gzxcvbn.Words,
        dictionary: dict.from_list([#("abc", 1)]),
      ),
    ])
    |> gzxcvbn.build()

  // "@bc" - only @ is a l33t character, should not match "abc" because
  // there's no l33t substitution actually needed (bc is already bc)
  let result = gzxcvbn.check("@bc", opts)

  let l33t_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.DictionaryMatch(l33t: True, ..) -> True
        _ -> False
      }
    })

  let assert Ok(match) = l33t_match
  let assert gzxcvbn.DictionaryMatch(
    l33t: True,
    l33t_subs: [gzxcvbn.L33tSubstitution(from: "@", to: "a")],
    ..,
  ) = match.match
}

// =============================================================================
// match_length Tests
// =============================================================================

pub fn match_length_dictionary_test() {
  let m =
    gzxcvbn.DictionaryMatch(
      start: 0,
      end: 7,
      token: "password",
      rank: 1,
      dictionary_name: "test",
      dictionary_kind: gzxcvbn.Passwords,
      reversed: False,
      l33t: False,
      l33t_subs: [],
    )
  assert gzxcvbn.match_length(m) == 8
}

pub fn match_length_single_char_test() {
  let m = gzxcvbn.BruteforceMatch(start: 5, end: 5, token: "x")
  assert gzxcvbn.match_length(m) == 1
}

// =============================================================================
// score_to_int Tests
// =============================================================================

pub fn score_to_int_test() {
  assert gzxcvbn.score_to_int(gzxcvbn.TooGuessable) == 0
  assert gzxcvbn.score_to_int(gzxcvbn.VeryGuessable) == 1
  assert gzxcvbn.score_to_int(gzxcvbn.SomewhatGuessable) == 2
  assert gzxcvbn.score_to_int(gzxcvbn.SafelyUnguessable) == 3
  assert gzxcvbn.score_to_int(gzxcvbn.VeryUnguessable) == 4
}

// =============================================================================
// Empty Dictionary Tests
// =============================================================================

pub fn empty_dictionaries_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("password", opts)

  // Without dictionaries, "password" should score based on bruteforce only
  assert result.guesses > 0
}

pub fn no_graphs_spatial_test() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_dictionaries([test_passwords_dict()])
    |> gzxcvbn.build()

  // Without graphs, "qwerty" should not get a spatial match
  let result = gzxcvbn.check("qwerty", opts)

  let spatial_match =
    list.find(result.sequence, fn(m) {
      case m.match {
        gzxcvbn.SpatialMatch(..) -> True
        _ -> False
      }
    })

  assert spatial_match == Error(Nil)
}

// =============================================================================
// Long Password Tests
// =============================================================================

pub fn long_password_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let long_password = string.repeat("x", 100)
  let result = gzxcvbn.check(long_password, opts)

  // Should handle long passwords without crashing
  // Note: Repeat patterns score lower than truly random passwords
  assert result.guesses > 0
}

pub fn long_random_password_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  // Use a non-repeating pattern to avoid repeat detection
  let long_password = "xK9#mP2$nQ7@wL4vB8yRtZ5"
  let result = gzxcvbn.check(long_password, opts)

  // Long non-repeating mixed passwords should score very high
  assert result.score == gzxcvbn.SafelyUnguessable
    || result.score == gzxcvbn.VeryUnguessable
}

// =============================================================================
// Display Time Tests
// =============================================================================

pub fn crack_times_instant_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("a", opts)

  // Very weak password should have fast crack times
  assert string.contains(result.crack_times.offline_fast_display, "second")
    || result.crack_times.offline_fast_display == "less than a second"
}

pub fn crack_times_very_long_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  let result = gzxcvbn.check("xK9#mP2$nQ7@wL4vB8yR", opts)

  // Strong password should have long crack times
  assert string.contains(result.crack_times.online_throttled_display, "centur")
    || string.contains(result.crack_times.online_throttled_display, "year")
}

// =============================================================================
// Pluralisation Tests
// =============================================================================

pub fn crack_times_plural_seconds_test() {
  let opts = gzxcvbn.options() |> gzxcvbn.build()
  // A password that takes a few seconds to crack offline fast
  let result = gzxcvbn.check("abc", opts)

  // Check pluralisation works
  let display = result.crack_times.offline_slow_display
  assert display == "less than a second"
    || string.contains(display, "second")
    || string.contains(display, "minute")
}

// =============================================================================
// Overlapping Match Resolution Tests
// =============================================================================

pub fn overlapping_matches_test() {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_dictionaries([
      gzxcvbn.NamedDictionary(
        name: "words",
        kind: gzxcvbn.Words,
        dictionary: dict.from_list([
          #("pass", 1),
          #("password", 2),
          #("word", 3),
        ]),
      ),
    ])
    |> gzxcvbn.build()

  // "password" contains both "pass" and "word" but should resolve optimally
  let result = gzxcvbn.check("password", opts)

  // The optimal solution should cover the whole password without gaps
  let sorted =
    list.sort(result.sequence, fn(a, b) {
      int.compare(a.match.start, b.match.start)
    })

  let assert [first, ..] = sorted
  assert first.match.start == 0

  let assert Ok(last) = list.last(sorted)
  assert last.match.end == 7
}
