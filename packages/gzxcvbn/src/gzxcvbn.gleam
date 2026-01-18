//// gzxcvbn - Password strength estimation for Gleam.
////
//// A Gleam port of zxcvbn, the password strength estimator developed by Dropbox.
////
//// ## Example
////
//// ```gleam
//// import gzxcvbn
//// import gzxcvbn/common
//// import gzxcvbn/en
////
//// let opts =
////   gzxcvbn.options()
////   |> gzxcvbn.with_dictionaries(common.dictionaries())
////   |> gzxcvbn.with_dictionaries(en.dictionaries())
////   |> gzxcvbn.with_graphs(common.graphs())
////   |> gzxcvbn.build()
////
//// let result = gzxcvbn.check("correcthorsebatterystaple", opts)
//// // result.score == VeryUnguessable
//// ```

import gleam/dict
import gleam/float
import gleam/int
import gleam/list
import gleam/option
import gleam/order
import gleam/result
import gleam/string

// =============================================================================
// Public Types - Score & Result
// =============================================================================

/// Password strength score on a 0-4 scale.
pub type Score {
  /// Too guessable: risky password (guesses < 10^3)
  TooGuessable
  /// Very guessable: protection from throttled online attacks (guesses < 10^6)
  VeryGuessable
  /// Somewhat guessable: protection from unthrottled online attacks (guesses < 10^8)
  SomewhatGuessable
  /// Safely unguessable: moderate protection from offline slow-hash scenarios (guesses < 10^10)
  SafelyUnguessable
  /// Very unguessable: strong protection from offline slow-hash scenarios (guesses >= 10^10)
  VeryUnguessable
}

/// Convert a score to its numeric value (0-4).
pub fn score_to_int(score: Score) -> Int {
  case score {
    TooGuessable -> 0
    VeryGuessable -> 1
    SomewhatGuessable -> 2
    SafelyUnguessable -> 3
    VeryUnguessable -> 4
  }
}

/// Result of password strength estimation.
pub type CheckResult {
  CheckResult(
    /// The analysed password
    password: String,
    /// Overall strength score (0-4)
    score: Score,
    /// Estimated number of guesses needed
    guesses: Int,
    /// Log base 10 of guesses
    guesses_log10: Float,
    /// User-facing feedback for improvement
    feedback: Feedback,
    /// Crack time estimates for different attack scenarios
    crack_times: CrackTimes,
    /// The optimal match sequence found
    sequence: List(MatchWithGuesses),
  )
}

// =============================================================================
// Public Types - Match
// =============================================================================

/// A leetspeak character substitution.
pub type L33tSubstitution {
  L33tSubstitution(
    /// The original character in the password (e.g. "@")
    from: String,
    /// The letter it represents (e.g. "a")
    to: String,
  )
}

/// A pattern match found in the password.
///
/// All variants have `start` and `end` fields representing 0-indexed,
/// inclusive positions in the password string.
pub type Match {
  /// Word from a ranked dictionary
  DictionaryMatch(
    start: Int,
    end: Int,
    token: String,
    rank: Int,
    dictionary_name: String,
    dictionary_kind: DictionaryKind,
    reversed: Bool,
    l33t: Bool,
    l33t_subs: List(L33tSubstitution),
  )
  /// Keyboard pattern (qwerty, etc.)
  SpatialMatch(
    start: Int,
    end: Int,
    token: String,
    graph: String,
    turns: Int,
    shifted_count: Int,
  )
  /// Sequential characters (abc, 123, zyx)
  SequenceMatch(
    start: Int,
    end: Int,
    token: String,
    sequence_name: String,
    ascending: Bool,
  )
  /// Repeated characters or patterns (aaa, abcabc)
  RepeatMatch(
    start: Int,
    end: Int,
    token: String,
    base_token: String,
    repeat_count: Int,
    base_guesses: Int,
  )
  /// Date pattern
  DateMatch(
    start: Int,
    end: Int,
    token: String,
    year: Int,
    month: Int,
    day: Int,
    has_separator: Bool,
  )
  /// Fallback for unmatched characters
  BruteforceMatch(start: Int, end: Int, token: String)
}

/// Get the length of a match.
pub fn match_length(m: Match) -> Int {
  m.end - m.start + 1
}

/// A match with its estimated guesses.
pub type MatchWithGuesses {
  MatchWithGuesses(match: Match, guesses: Int, guesses_log10: Float)
}

// =============================================================================
// Public Types - Options
// =============================================================================

/// What kind of data a dictionary contains.
pub type DictionaryKind {
  /// Common passwords (triggers password-specific warnings)
  Passwords
  /// Personal names (first or last)
  Names
  /// Common words (generic dictionary)
  Words
  /// User-provided inputs with category
  UserInput(UserInputKind)
}

/// Category of user-provided input.
pub type UserInputKind {
  /// User-related names (triggers name warnings)
  UserNames
  /// User-related years like birth year (triggers year warnings)
  UserYears
  /// Other user inputs (generic warning)
  UserOther
}

/// Named dictionary with its name and ranked words.
/// The dictionary maps words to their frequency rank (1 = most common).
pub type NamedDictionary {
  NamedDictionary(
    name: String,
    kind: DictionaryKind,
    dictionary: dict.Dict(String, Int),
  )
}

/// Named adjacency graph with its name and graph data.
pub type NamedGraph {
  NamedGraph(
    name: String,
    graph: dict.Dict(String, List(option.Option(String))),
  )
}

/// Configuration options for the password checker.
pub opaque type Options {
  Options(
    dictionaries: List(NamedDictionary),
    graphs: List(NamedGraph),
    l33t_table: dict.Dict(String, List(String)),
  )
}

/// Builder for constructing Options.
pub opaque type OptionsBuilder {
  OptionsBuilder(
    dictionaries: List(NamedDictionary),
    graphs: List(NamedGraph),
    user_names: List(String),
    user_years: List(Int),
    user_other: List(String),
    l33t_table: dict.Dict(String, List(String)),
  )
}

/// Create a new options builder with default settings.
pub fn options() -> OptionsBuilder {
  OptionsBuilder(
    dictionaries: [],
    graphs: [],
    user_names: [],
    user_years: [],
    user_other: [],
    l33t_table: default_l33t_table(),
  )
}

/// Add dictionaries to the options.
pub fn with_dictionaries(
  builder: OptionsBuilder,
  dictionaries: List(NamedDictionary),
) -> OptionsBuilder {
  OptionsBuilder(
    ..builder,
    dictionaries: list.append(builder.dictionaries, dictionaries),
  )
}

/// Add keyboard graphs for spatial matching.
pub fn with_graphs(
  builder: OptionsBuilder,
  graphs: List(NamedGraph),
) -> OptionsBuilder {
  OptionsBuilder(..builder, graphs: list.append(builder.graphs, graphs))
}

/// Add user-provided names (usernames, family names, etc.).
/// Triggers name-specific warnings when matched.
pub fn with_user_names(
  builder: OptionsBuilder,
  names: List(String),
) -> OptionsBuilder {
  OptionsBuilder(..builder, user_names: list.append(builder.user_names, names))
}

/// Add user-related years (birth year, anniversary, etc.).
/// Triggers year-specific warnings when matched.
pub fn with_user_years(
  builder: OptionsBuilder,
  years: List(Int),
) -> OptionsBuilder {
  OptionsBuilder(..builder, user_years: list.append(builder.user_years, years))
}

/// Add other user inputs to treat as dictionary words.
pub fn with_user_inputs(
  builder: OptionsBuilder,
  inputs: List(String),
) -> OptionsBuilder {
  OptionsBuilder(..builder, user_other: list.append(builder.user_other, inputs))
}

/// Build the final Options from the builder.
pub fn build(builder: OptionsBuilder) -> Options {
  let user_dicts =
    [
      build_user_dictionary(builder.user_names, UserInput(UserNames)),
      build_user_dictionary(
        list.map(builder.user_years, int.to_string),
        UserInput(UserYears),
      ),
      build_user_dictionary(builder.user_other, UserInput(UserOther)),
    ]
    |> result.values
  Options(
    dictionaries: list.append(builder.dictionaries, user_dicts),
    graphs: builder.graphs,
    l33t_table: builder.l33t_table,
  )
}

// =============================================================================
// Public Types - Feedback
// =============================================================================

/// Feedback to help users create stronger passwords.
pub type Feedback {
  Feedback(warning: String, suggestions: List(String))
}

/// Translation functions for internationalising feedback messages.
pub type Translations {
  Translations(
    warning: fn(Warning) -> String,
    suggestion: fn(Suggestion) -> String,
  )
}

/// Warning message keys for translation.
pub type Warning {
  NoWarning
  StraightRowOfKeys
  ShortKeyboardPatterns
  RepeatedCharacters
  RepeatedCharacterPatterns
  SequenceAbcEtc
  RecentYears
  Dates
  TopTenPassword
  TopHundredPassword
  CommonPassword
  SimilarToCommonPassword
  WordByItself
  /// Names from a dictionary (e.g. first_names, last_names)
  CommonNamesByThemselves
  /// User-provided names via `with_user_names`
  NamesByThemselves
  /// User-provided years that are associated with the user
  AssociatedYears
}

/// Suggestion message keys for translation.
pub type Suggestion {
  UseMoreWords
  NoNeedForSymbolsOrDigits
  AddAnotherWord
  CapitalisationDoesntHelp
  AllUppercaseDoesntHelp
  ReversedDoesntHelp
  PredictableSubstitutions
  UseKeyboardPatternLonger
  AvoidRepeatedWords
  AvoidSequences
  AvoidRecentYears
  AvoidDates
  /// For user-provided years
  AvoidAssociatedYears
}

/// Default English translations.
pub fn default_translations() -> Translations {
  Translations(warning: default_warning, suggestion: default_suggestion)
}

// =============================================================================
// Public Types - Crack Times
// =============================================================================

/// Crack time estimates for different attack scenarios.
pub type CrackTimes {
  CrackTimes(
    /// Seconds to crack with online throttled attack (100/hour).
    online_throttled_seconds: Float,
    /// Seconds to crack with online unthrottled attack (10/second).
    online_unthrottled_seconds: Float,
    /// Seconds to crack with offline slow attack (10k/second).
    offline_slow_seconds: Float,
    /// Seconds to crack with offline fast attack (10B/second).
    offline_fast_seconds: Float,
    /// Human-readable time for online throttled attack.
    online_throttled_display: String,
    /// Human-readable time for online unthrottled attack.
    online_unthrottled_display: String,
    /// Human-readable time for offline slow attack.
    offline_slow_display: String,
    /// Human-readable time for offline fast attack.
    offline_fast_display: String,
  )
}

// =============================================================================
// Main API
// =============================================================================

/// Check a password's strength.
pub fn check(password: String, opts: Options) -> CheckResult {
  check_with_translations(password, opts, default_translations())
}

/// Check a password's strength with custom translations.
pub fn check_with_translations(
  password: String,
  opts: Options,
  translations: Translations,
) -> CheckResult {
  let matches = omnimatch(password, opts)
  let #(sequence, guesses) =
    most_guessable_match_sequence(password, matches, opts.graphs)
  let guesses_log10 = log10(guesses)
  let score_int = guesses_to_score(guesses)
  let score = int_to_score(score_int)
  let crack_times = estimate_crack_times(guesses)
  let feedback_result = generate_feedback(sequence, score_int, translations)

  CheckResult(
    password:,
    score:,
    guesses:,
    guesses_log10:,
    feedback: feedback_result,
    crack_times:,
    sequence:,
  )
}

// =============================================================================
// Internal - Constants
// =============================================================================

const min_guesses = 1

const min_guesses_single_char = 10

const lowercase_count = 26

const uppercase_count = 26

const digit_count = 10

const symbol_count = 33

const bruteforce_cardinality = 10

const reference_year = 2026

const online_throttled_per_second = 0.027778

const online_unthrottled_per_second = 10.0

const offline_slow_per_second = 10_000.0

const offline_fast_per_second = 10_000_000_000.0

// =============================================================================
// Internal - Matching
// =============================================================================

fn omnimatch(password: String, opts: Options) -> List(Match) {
  [
    dictionary_match(password, opts),
    l33t_match(password, opts),
    sequence_match(password),
    repeat_match(password, opts),
    spatial_match(password, opts),
    date_match(password),
  ]
  |> list.flatten
  |> sort_matches
}

fn dictionary_match(password: String, opts: Options) -> List(Match) {
  let password_lower = string.lowercase(password)
  let password_len = string.length(password)

  let forward_matches =
    list.range(0, password_len - 1)
    |> list.flat_map(fn(start) {
      list.range(start, password_len - 1)
      |> list.flat_map(fn(end) {
        let token = string.slice(password_lower, start, end - start + 1)
        let orig_token = string.slice(password, start, end - start + 1)
        check_dictionaries(
          token,
          start,
          end,
          orig_token,
          opts.dictionaries,
          False,
        )
      })
    })

  let reversed_matches = dictionary_match_reversed(password, opts)
  list.flatten([forward_matches, reversed_matches])
}

fn dictionary_match_reversed(password: String, opts: Options) -> List(Match) {
  let reversed = string.reverse(password)
  let reversed_lower = string.lowercase(reversed)
  let password_len = string.length(password)

  list.range(0, password_len - 1)
  |> list.flat_map(fn(start) {
    list.range(start, password_len - 1)
    |> list.flat_map(fn(end) {
      let token = string.slice(reversed_lower, start, end - start + 1)
      let orig_start = password_len - 1 - end
      let orig_end = password_len - 1 - start
      let orig_token =
        string.slice(password, orig_start, orig_end - orig_start + 1)
      check_dictionaries(
        token,
        orig_start,
        orig_end,
        orig_token,
        opts.dictionaries,
        True,
      )
    })
  })
}

fn check_dictionaries(
  token: String,
  start: Int,
  end: Int,
  original_token: String,
  dictionaries: List(NamedDictionary),
  reversed: Bool,
) -> List(Match) {
  dictionaries
  |> list.filter_map(fn(named_dict) {
    case dict.get(named_dict.dictionary, token) {
      Ok(rank) ->
        Ok(
          DictionaryMatch(
            start:,
            end:,
            token: original_token,
            rank:,
            dictionary_name: named_dict.name,
            dictionary_kind: named_dict.kind,
            reversed:,
            l33t: False,
            l33t_subs: [],
          ),
        )
      Error(_) -> Error(Nil)
    }
  })
}

fn sequence_match(password: String) -> List(Match) {
  let chars = string.to_graphemes(password)
  case chars {
    [] | [_] -> []
    _ -> find_sequences(chars, 0, [])
  }
}

fn find_sequences(
  chars: List(String),
  start_idx: Int,
  acc: List(Match),
) -> List(Match) {
  case chars {
    [] | [_] -> acc
    [first, second, ..rest] -> {
      let delta = char_delta(first, second)
      case delta == 1 || delta == -1 {
        False -> find_sequences([second, ..rest], start_idx + 1, acc)
        True -> {
          // Store in reverse for O(1) prepend, reverse when done
          let #(seq_chars_rev, remaining) =
            extend_sequence([second, first], rest, delta)
          let seq_chars = list.reverse(seq_chars_rev)
          let seq_len = list.length(seq_chars)
          case seq_len >= 3 {
            True -> {
              let token = string.concat(seq_chars)
              let sequence_name = get_sequence_name(first)
              let new_match =
                SequenceMatch(
                  start: start_idx,
                  end: start_idx + seq_len - 1,
                  token:,
                  sequence_name:,
                  ascending: delta > 0,
                )
              find_sequences(remaining, start_idx + seq_len, [new_match, ..acc])
            }
            False -> find_sequences([second, ..rest], start_idx + 1, acc)
          }
        }
      }
    }
  }
}

/// Extends a sequence by prepending matching chars. Returns (chars_reversed, remaining).
fn extend_sequence(
  current_rev: List(String),
  remaining: List(String),
  delta: Int,
) -> #(List(String), List(String)) {
  case remaining, current_rev {
    [], _ -> #(current_rev, [])
    [next, ..rest], [last, ..] -> {
      case char_delta(last, next) == delta {
        True -> extend_sequence([next, ..current_rev], rest, delta)
        False -> #(current_rev, remaining)
      }
    }
    _, [] -> #(current_rev, remaining)
  }
}

fn char_delta(a: String, b: String) -> Int {
  char_code(b) - char_code(a)
}

fn char_code(char: String) -> Int {
  case string.to_utf_codepoints(char) {
    [cp] -> string.utf_codepoint_to_int(cp)
    _ -> 0
  }
}

fn get_sequence_name(first_char: String) -> String {
  let lower = string.lowercase(first_char)
  case string.contains("abcdefghijklmnopqrstuvwxyz", lower) {
    True ->
      case first_char == lower {
        True -> "lower"
        False -> "upper"
      }
    False ->
      case string.contains("0123456789", first_char) {
        True -> "digits"
        False -> "unicode"
      }
  }
}

fn repeat_match(password: String, opts: Options) -> List(Match) {
  let len = string.length(password)
  case len < 2 {
    True -> []
    False -> find_repeats(password, 0, opts, [])
  }
}

fn find_repeats(
  password: String,
  idx: Int,
  opts: Options,
  acc: List(Match),
) -> List(Match) {
  let len = string.length(password)
  case idx >= len {
    True -> acc
    False -> {
      case find_repeat_at(password, idx) {
        option.Some(#(base_token, repeat_count, end_idx)) -> {
          let token = string.slice(password, idx, end_idx - idx + 1)
          let base_guesses = estimate_base_guesses(base_token, opts)
          let new_match =
            RepeatMatch(
              start: idx,
              end: end_idx,
              token:,
              base_token:,
              repeat_count:,
              base_guesses:,
            )
          find_repeats(password, end_idx + 1, opts, [new_match, ..acc])
        }
        option.None -> find_repeats(password, idx + 1, opts, acc)
      }
    }
  }
}

fn find_repeat_at(
  password: String,
  idx: Int,
) -> option.Option(#(String, Int, Int)) {
  let remaining = string.slice(password, idx, string.length(password) - idx)
  let len = string.length(remaining)
  let max_base_len = int.max(1, len / 2)

  list.range(1, max_base_len)
  |> list.fold(option.None, fn(best, base_len) {
    let base = string.slice(remaining, 0, base_len)
    let repeat_count = count_repeats(remaining, base)
    case repeat_count >= 2 {
      True -> {
        let total_len = base_len * repeat_count
        let end_idx = idx + total_len - 1
        case best {
          option.None -> option.Some(#(base, repeat_count, end_idx))
          option.Some(#(_, _, best_end)) ->
            case end_idx > best_end {
              True -> option.Some(#(base, repeat_count, end_idx))
              False -> best
            }
        }
      }
      False -> best
    }
  })
}

fn count_repeats(s: String, base: String) -> Int {
  let base_len = string.length(base)
  count_repeats_helper(s, base, base_len, 0)
}

fn count_repeats_helper(
  s: String,
  base: String,
  base_len: Int,
  count: Int,
) -> Int {
  case string.length(s) >= base_len {
    False -> count
    True -> {
      let prefix = string.slice(s, 0, base_len)
      case prefix == base {
        True -> {
          let rest = string.slice(s, base_len, string.length(s) - base_len)
          count_repeats_helper(rest, base, base_len, count + 1)
        }
        False -> count
      }
    }
  }
}

// =============================================================================
// Internal - Spatial Matching
// =============================================================================

fn spatial_match(password: String, opts: Options) -> List(Match) {
  let chars = string.to_graphemes(password)
  let len = list.length(chars)
  case len < 3 {
    True -> []
    False ->
      opts.graphs
      |> list.flat_map(fn(named_graph) {
        find_spatial_patterns(chars, named_graph.name, named_graph.graph)
      })
  }
}

fn find_spatial_patterns(
  chars: List(String),
  graph_name: String,
  graph: dict.Dict(String, List(option.Option(String))),
) -> List(Match) {
  let len = list.length(chars)
  find_spatial_from(chars, 0, len, graph_name, graph, [])
}

fn find_spatial_from(
  chars: List(String),
  idx: Int,
  len: Int,
  graph_name: String,
  graph: dict.Dict(String, List(option.Option(String))),
  acc: List(Match),
) -> List(Match) {
  case idx >= len - 2 {
    True -> acc
    False -> {
      case walk_spatial(chars, idx, graph) {
        option.Some(#(end_idx, turns, shifted)) -> {
          let token = slice_chars(chars, idx, end_idx - idx + 1)
          let new_match =
            SpatialMatch(
              start: idx,
              end: end_idx,
              token:,
              graph: graph_name,
              turns:,
              shifted_count: shifted,
            )
          find_spatial_from(chars, end_idx + 1, len, graph_name, graph, [
            new_match,
            ..acc
          ])
        }
        option.None ->
          find_spatial_from(chars, idx + 1, len, graph_name, graph, acc)
      }
    }
  }
}

fn walk_spatial(
  chars: List(String),
  start: Int,
  graph: dict.Dict(String, List(option.Option(String))),
) -> option.Option(#(Int, Int, Int)) {
  let chars_from_start = list.drop(chars, start)
  case chars_from_start {
    [] | [_] -> option.None
    [first, ..rest] ->
      case graph_get(graph, first) {
        Ok(_) -> {
          let initial_shifted = case is_shifted_char(first) {
            True -> 1
            False -> 0
          }
          walk_spatial_step(
            rest,
            first,
            start,
            start + 1,
            graph,
            -1,
            0,
            initial_shifted,
          )
        }
        Error(_) -> option.None
      }
  }
}

fn walk_spatial_step(
  remaining: List(String),
  prev_char: String,
  start_idx: Int,
  current_idx: Int,
  graph: dict.Dict(String, List(option.Option(String))),
  last_direction: Int,
  turns: Int,
  shifted: Int,
) -> option.Option(#(Int, Int, Int)) {
  case remaining {
    [] -> {
      // Walk length is current_idx - start_idx (we've processed up to current_idx - 1)
      let walk_len = current_idx - start_idx
      case walk_len >= 3 {
        True -> option.Some(#(current_idx - 1, turns, shifted))
        False -> option.None
      }
    }
    [current, ..rest] -> {
      case find_adjacent(graph, prev_char, current) {
        option.None -> {
          // Walk ends at previous character
          let end_idx = current_idx - 1
          let walk_len = end_idx - start_idx + 1
          case walk_len >= 3 {
            True -> option.Some(#(end_idx, turns, shifted))
            False -> option.None
          }
        }
        option.Some(#(direction, is_shifted)) -> {
          let new_shifted = case is_shifted {
            True -> shifted + 1
            False -> shifted
          }
          let new_turns = case
            last_direction >= 0 && direction != last_direction
          {
            True -> turns + 1
            False -> turns
          }
          walk_spatial_step(
            rest,
            current,
            start_idx,
            current_idx + 1,
            graph,
            direction,
            new_turns,
            new_shifted,
          )
        }
      }
    }
  }
}

/// Look up a key in the graph, falling back to lowercase if not found.
fn graph_get(
  graph: dict.Dict(String, List(option.Option(String))),
  key: String,
) -> Result(List(option.Option(String)), Nil) {
  case dict.get(graph, key) {
    Ok(v) -> Ok(v)
    Error(_) -> dict.get(graph, string.lowercase(key))
  }
}

fn find_adjacent(
  graph: dict.Dict(String, List(option.Option(String))),
  from_char: String,
  to_char: String,
) -> option.Option(#(Int, Bool)) {
  case graph_get(graph, from_char) {
    Error(_) -> option.None
    Ok(adj) -> find_in_adjacents(adj, to_char, 0)
  }
}

fn find_in_adjacents(
  adjacents: List(option.Option(String)),
  target: String,
  direction: Int,
) -> option.Option(#(Int, Bool)) {
  case adjacents {
    [] -> option.None
    [option.None, ..rest] -> find_in_adjacents(rest, target, direction + 1)
    [option.Some(adj_chars), ..rest] -> {
      case char_in_adjacent(adj_chars, target) {
        option.Some(is_shifted) -> option.Some(#(direction, is_shifted))
        option.None -> find_in_adjacents(rest, target, direction + 1)
      }
    }
  }
}

fn char_in_adjacent(adj_chars: String, target: String) -> option.Option(Bool) {
  let chars = string.to_graphemes(adj_chars)
  case chars {
    [] -> option.None
    [first] ->
      case first == target {
        True -> option.Some(False)
        False -> option.None
      }
    [first, second, ..] ->
      case first == target {
        True -> option.Some(False)
        False ->
          case second == target {
            True -> option.Some(True)
            False -> option.None
          }
      }
  }
}

fn is_shifted_char(c: String) -> Bool {
  let upper = string.uppercase(c)
  let lower = string.lowercase(c)
  upper == c && lower != c
}

fn slice_chars(chars: List(String), start: Int, length: Int) -> String {
  chars
  |> list.drop(start)
  |> list.take(length)
  |> string.concat
}

// =============================================================================
// Internal - Date Matching
// =============================================================================

fn date_match(password: String) -> List(Match) {
  let no_sep = date_match_no_separator(password)
  let with_sep = date_match_with_separator(password)
  list.append(no_sep, with_sep)
}

fn date_match_no_separator(password: String) -> List(Match) {
  let chars = string.to_graphemes(password)
  let len = list.length(chars)
  case len < 4 {
    True -> []
    False -> find_date_no_sep(password, 0, len, [])
  }
}

fn find_date_no_sep(
  password: String,
  idx: Int,
  len: Int,
  acc: List(Match),
) -> List(Match) {
  case idx > len - 4 {
    True -> acc
    False -> {
      let new_matches =
        [4, 5, 6, 7, 8]
        |> list.filter(fn(date_len) { idx + date_len <= len })
        |> list.filter_map(fn(date_len) {
          let token = string.slice(password, idx, date_len)
          case all_digits(token) {
            False -> Error(Nil)
            True ->
              parse_date_no_sep(token, date_len)
              |> result.map(fn(date) {
                let #(year, month, day) = date
                DateMatch(
                  start: idx,
                  end: idx + date_len - 1,
                  token:,
                  year:,
                  month:,
                  day:,
                  has_separator: False,
                )
              })
          }
        })
      find_date_no_sep(password, idx + 1, len, list.append(new_matches, acc))
    }
  }
}

fn parse_date_no_sep(token: String, len: Int) -> Result(#(Int, Int, Int), Nil) {
  let splits = case len {
    4 -> [[1, 2], [2, 3]]
    5 -> [[1, 3], [2, 3], [2, 4], [1, 4], [3, 4]]
    6 -> [[1, 3], [2, 4], [4, 5], [1, 5], [2, 5], [3, 5]]
    7 -> [[1, 4], [2, 4], [2, 5], [3, 5], [4, 5], [4, 6]]
    8 -> [[2, 4], [4, 6]]
    _ -> []
  }
  try_date_splits(token, splits)
}

fn try_date_splits(
  token: String,
  splits: List(List(Int)),
) -> Result(#(Int, Int, Int), Nil) {
  case splits {
    [] -> Error(Nil)
    [[i, j], ..rest] -> {
      let a = string.slice(token, 0, i)
      let b = string.slice(token, i, j - i)
      let c = string.slice(token, j, string.length(token) - j)
      case int.parse(a), int.parse(b), int.parse(c) {
        Ok(a_int), Ok(b_int), Ok(c_int) ->
          case validate_date(a_int, b_int, c_int) {
            Ok(result) -> Ok(result)
            Error(_) -> try_date_splits(token, rest)
          }
        _, _, _ -> try_date_splits(token, rest)
      }
    }
    _ -> Error(Nil)
  }
}

fn date_match_with_separator(password: String) -> List(Match) {
  let len = string.length(password)
  case len < 6 {
    True -> []
    False -> find_date_with_sep(password, 0, len, [])
  }
}

fn find_date_with_sep(
  password: String,
  idx: Int,
  len: Int,
  acc: List(Match),
) -> List(Match) {
  case idx > len - 6 {
    True -> acc
    False -> {
      let new_matches =
        list.range(6, int.min(10, len - idx))
        |> list.filter_map(fn(date_len) {
          let token = string.slice(password, idx, date_len)
          parse_date_with_sep(token)
          |> result.map(fn(date) {
            let #(year, month, day) = date
            DateMatch(
              start: idx,
              end: idx + date_len - 1,
              token:,
              year:,
              month:,
              day:,
              has_separator: True,
            )
          })
        })
      find_date_with_sep(password, idx + 1, len, list.append(new_matches, acc))
    }
  }
}

fn parse_date_with_sep(token: String) -> Result(#(Int, Int, Int), Nil) {
  let chars = string.to_graphemes(token)
  let is_sep = fn(char) { char == "/" || char == "-" || char == "." }

  // Find positions of separators
  let sep_positions =
    chars
    |> list.index_map(fn(char, index) { #(char, index) })
    |> list.filter_map(fn(pair) {
      case is_sep(pair.0) {
        True -> Ok(pair.1)
        False -> Error(Nil)
      }
    })

  case sep_positions {
    [sep1, sep2] -> {
      let part1 = string.slice(token, 0, sep1)
      let part2 = string.slice(token, sep1 + 1, sep2 - sep1 - 1)
      let part3 = string.slice(token, sep2 + 1, string.length(token) - sep2 - 1)

      // Check separators are the same
      let s1 = string.slice(token, sep1, 1)
      let s2 = string.slice(token, sep2, 1)
      case s1 == s2 {
        False -> Error(Nil)
        True ->
          case int.parse(part1), int.parse(part2), int.parse(part3) {
            Ok(a), Ok(b), Ok(c) -> validate_date(a, b, c)
            _, _, _ -> Error(Nil)
          }
      }
    }
    _ -> Error(Nil)
  }
}

fn validate_date(a: Int, b: Int, c: Int) -> Result(#(Int, Int, Int), Nil) {
  // Try different interpretations: YMD, MDY, DMY
  try_ymd(a, b, c)
  |> result.lazy_or(fn() { try_mdy(a, b, c) })
  |> result.lazy_or(fn() { try_dmy(a, b, c) })
}

fn try_ymd(a: Int, b: Int, c: Int) -> Result(#(Int, Int, Int), Nil) {
  use year <- result.try(normalise_year(a))
  case is_valid_month(b) && is_valid_day(c) {
    True -> Ok(#(year, b, c))
    False -> Error(Nil)
  }
}

fn try_mdy(a: Int, b: Int, c: Int) -> Result(#(Int, Int, Int), Nil) {
  use year <- result.try(normalise_year(c))
  case is_valid_month(a) && is_valid_day(b) {
    True -> Ok(#(year, a, b))
    False -> Error(Nil)
  }
}

fn try_dmy(a: Int, b: Int, c: Int) -> Result(#(Int, Int, Int), Nil) {
  use year <- result.try(normalise_year(c))
  case is_valid_month(b) && is_valid_day(a) {
    True -> Ok(#(year, b, a))
    False -> Error(Nil)
  }
}

fn normalise_year(y: Int) -> Result(Int, Nil) {
  case y {
    _ if y >= 0 && y <= 50 -> Ok(y + 2000)
    _ if y >= 51 && y <= 99 -> Ok(y + 1900)
    _ if y >= 1000 && y <= 2050 -> Ok(y)
    _ -> Error(Nil)
  }
}

fn is_valid_month(m: Int) -> Bool {
  m >= 1 && m <= 12
}

fn is_valid_day(d: Int) -> Bool {
  d >= 1 && d <= 31
}

fn all_digits(s: String) -> Bool {
  string.to_graphemes(s)
  |> list.all(is_digit)
}

// =============================================================================
// Internal - L33t Matching
// =============================================================================

fn l33t_match(password: String, opts: Options) -> List(Match) {
  let relevant_table = relevant_l33t_subtable(password, opts.l33t_table)
  case dict.is_empty(relevant_table) {
    True -> []
    False -> {
      let inverted = invert_l33t_table(relevant_table)
      let subs = enumerate_l33t_subs(inverted)
      subs
      |> list.flat_map(fn(sub) { l33t_match_with_sub(password, sub, opts) })
    }
  }
}

fn relevant_l33t_subtable(
  password: String,
  l33t_table: dict.Dict(String, List(String)),
) -> dict.Dict(String, List(String)) {
  let password_chars = string.to_graphemes(password)

  l33t_table
  |> dict.fold(dict.new(), fn(acc, letter, subs) {
    let relevant_subs =
      list.filter(subs, fn(sub) { list.contains(password_chars, sub) })
    case relevant_subs {
      [] -> acc
      _ -> dict.insert(acc, letter, relevant_subs)
    }
  })
}

fn invert_l33t_table(
  table: dict.Dict(String, List(String)),
) -> dict.Dict(String, List(String)) {
  table
  |> dict.fold(dict.new(), fn(acc, letter, subs) {
    list.fold(subs, acc, fn(inner_acc, sub) {
      let existing = dict.get(inner_acc, sub) |> result.unwrap([])
      dict.insert(inner_acc, sub, [letter, ..existing])
    })
  })
}

fn enumerate_l33t_subs(
  inverted: dict.Dict(String, List(String)),
) -> List(dict.Dict(String, String)) {
  let entries = dict.to_list(inverted)
  case entries {
    [] -> [dict.new()]
    _ -> build_substitution_combinations(entries, [dict.new()], 0)
  }
}

/// Builds all combinations of l33t substitution mappings (Cartesian product).
/// E.g. [#("@", ["a"]), #("1", ["i", "l"])] produces:
/// [{"@": "a", "1": "i"}, {"@": "a", "1": "l"}]
fn build_substitution_combinations(
  entries: List(#(String, List(String))),
  acc: List(dict.Dict(String, String)),
  depth: Int,
) -> List(dict.Dict(String, String)) {
  // Cap at 100 combinations to avoid exponential blowup
  case depth > 10 || list.length(acc) > 100 {
    True -> list.take(acc, 100)
    False ->
      case entries {
        [] -> acc
        [#(sub_char, letters), ..rest] -> {
          let new_acc =
            acc
            |> list.flat_map(fn(existing_sub) {
              letters
              |> list.map(fn(letter) {
                dict.insert(existing_sub, sub_char, letter)
              })
            })
          build_substitution_combinations(rest, new_acc, depth + 1)
        }
      }
  }
}

fn l33t_match_with_sub(
  password: String,
  sub: dict.Dict(String, String),
  opts: Options,
) -> List(Match) {
  let #(subbed_password, actual_subs) = apply_l33t_subs(password, sub)

  case actual_subs {
    [] -> []
    _ -> {
      let subbed_lower = string.lowercase(subbed_password)
      let password_len = string.length(password)

      list.range(0, password_len - 1)
      |> list.flat_map(fn(start) {
        list.range(start, password_len - 1)
        |> list.filter_map(fn(end) {
          let token = string.slice(subbed_lower, start, end - start + 1)
          let orig_token = string.slice(password, start, end - start + 1)

          // Get subs that apply to this token
          let token_subs =
            actual_subs
            |> list.filter(fn(sub) { string.contains(orig_token, sub.from) })

          case token_subs {
            [] -> Error(Nil)
            _ ->
              opts.dictionaries
              |> list.find_map(fn(named_dict) {
                case dict.get(named_dict.dictionary, token) {
                  Ok(rank) ->
                    Ok(DictionaryMatch(
                      start:,
                      end:,
                      token: orig_token,
                      rank:,
                      dictionary_name: named_dict.name,
                      dictionary_kind: named_dict.kind,
                      reversed: False,
                      l33t: True,
                      l33t_subs: token_subs,
                    ))
                  Error(_) -> Error(Nil)
                }
              })
          }
        })
      })
    }
  }
}

fn apply_l33t_subs(
  password: String,
  sub: dict.Dict(String, String),
) -> #(String, List(L33tSubstitution)) {
  let chars = string.to_graphemes(password)
  let #(new_chars, subs_made) =
    list.fold(chars, #([], []), fn(acc, c) {
      let #(chars_acc, subs_acc) = acc
      case dict.get(sub, c) {
        Ok(replacement) -> {
          let sub_entry = L33tSubstitution(from: c, to: replacement)
          let already_recorded =
            list.any(subs_acc, fn(s: L33tSubstitution) {
              s.from == c && s.to == replacement
            })
          let new_subs = case already_recorded {
            True -> subs_acc
            False -> [sub_entry, ..subs_acc]
          }
          #([replacement, ..chars_acc], new_subs)
        }
        Error(_) -> #([c, ..chars_acc], subs_acc)
      }
    })
  #(string.concat(list.reverse(new_chars)), list.reverse(subs_made))
}

fn estimate_base_guesses(base_token: String, opts: Options) -> Int {
  let base_lower = string.lowercase(base_token)
  let dict_rank =
    opts.dictionaries
    |> list.find_map(fn(named_dict) {
      dict.get(named_dict.dictionary, base_lower)
    })

  case dict_rank {
    Ok(rank) -> rank
    Error(_) -> {
      let cardinality = calculate_cardinality(base_token)
      let len = string.length(base_token)
      power(cardinality, len)
    }
  }
}

fn sort_matches(matches: List(Match)) -> List(Match) {
  list.sort(matches, fn(a, b) {
    case int.compare(a.start, b.start) {
      order.Eq -> int.compare(a.end, b.end)
      other -> other
    }
  })
}

// =============================================================================
// Internal - Scoring
// =============================================================================

fn most_guessable_match_sequence(
  password: String,
  matches: List(Match),
  graphs: List(NamedGraph),
) -> #(List(MatchWithGuesses), Int) {
  let n = string.length(password)
  case n {
    0 -> #([], 1)
    _ -> {
      let matches_by_j = group_matches_by_end(matches)
      let initial_state = dict.new()
      let result =
        list.range(0, n - 1)
        |> list.fold(initial_state, fn(optimal, k) {
          update_optimal(optimal, k, password, matches_by_j, graphs)
        })

      case dict.get(result, n - 1) {
        Ok(#(guesses, sequence)) -> #(list.reverse(sequence), guesses)
        Error(_) -> #([], estimate_bruteforce_guesses(password))
      }
    }
  }
}

fn group_matches_by_end(matches: List(Match)) -> dict.Dict(Int, List(Match)) {
  list.fold(matches, dict.new(), fn(acc, m) {
    let existing = dict.get(acc, m.end) |> result.unwrap([])
    dict.insert(acc, m.end, [m, ..existing])
  })
}

fn update_optimal(
  optimal: dict.Dict(Int, #(Int, List(MatchWithGuesses))),
  k: Int,
  password: String,
  matches_by_j: dict.Dict(Int, List(Match)),
  graphs: List(NamedGraph),
) -> dict.Dict(Int, #(Int, List(MatchWithGuesses))) {
  let bruteforce_guesses =
    estimate_bruteforce_guesses(string.slice(password, 0, k + 1))
  let bruteforce_match =
    BruteforceMatch(start: 0, end: k, token: string.slice(password, 0, k + 1))
  let bruteforce_estimated =
    MatchWithGuesses(
      match: bruteforce_match,
      guesses: bruteforce_guesses,
      guesses_log10: log10(bruteforce_guesses),
    )
  let initial_best = #(bruteforce_guesses, [bruteforce_estimated])

  let matches_at_k = dict.get(matches_by_j, k) |> result.unwrap([])
  let best_with_matches =
    list.fold(matches_at_k, initial_best, fn(best, m) {
      let guesses = estimate_guesses(m, graphs)
      let estimated =
        MatchWithGuesses(match: m, guesses:, guesses_log10: log10(guesses))

      let #(prefix_guesses, prefix_sequence) = case m.start {
        0 -> #(1, [])
        _ ->
          dict.get(optimal, m.start - 1)
          |> result.unwrap(
            #(
              estimate_bruteforce_guesses(string.slice(password, 0, m.start)),
              [],
            ),
          )
      }

      let total_guesses = prefix_guesses * guesses
      case total_guesses < best.0 {
        True -> #(total_guesses, [estimated, ..prefix_sequence])
        False -> best
      }
    })

  let best = case k > 0 {
    True -> {
      case dict.get(optimal, k - 1) {
        Ok(#(prev_guesses, prev_sequence)) -> {
          let char = string.slice(password, k, 1)
          let char_guesses = estimate_bruteforce_guesses(char)
          let total = prev_guesses * char_guesses

          let bruteforce_char = BruteforceMatch(start: k, end: k, token: char)
          let char_estimated =
            MatchWithGuesses(
              match: bruteforce_char,
              guesses: char_guesses,
              guesses_log10: log10(char_guesses),
            )

          case total < best_with_matches.0 {
            True -> #(total, [char_estimated, ..prev_sequence])
            False -> best_with_matches
          }
        }
        Error(_) -> best_with_matches
      }
    }
    False -> best_with_matches
  }

  dict.insert(optimal, k, best)
}

fn estimate_guesses(m: Match, graphs: List(NamedGraph)) -> Int {
  let base_guesses = case m {
    DictionaryMatch(rank:, reversed:, l33t:, l33t_subs:, token:, ..) ->
      estimate_dictionary_guesses(rank, token, reversed, l33t, l33t_subs)
    SpatialMatch(token:, graph:, turns:, shifted_count:, ..) ->
      estimate_spatial_guesses(token, graph, turns, shifted_count, graphs)
    SequenceMatch(token:, ascending:, ..) ->
      estimate_sequence_guesses(token, ascending)
    RepeatMatch(base_guesses:, repeat_count:, ..) -> base_guesses * repeat_count
    DateMatch(year:, has_separator:, ..) ->
      estimate_date_guesses(year, has_separator)
    BruteforceMatch(token:, ..) -> estimate_bruteforce_guesses(token)
  }

  let len = match_length(m)
  let min = case len {
    1 -> min_guesses_single_char
    _ -> min_guesses
  }
  int.max(base_guesses, min)
}

fn estimate_dictionary_guesses(
  rank: Int,
  token: String,
  reversed: Bool,
  l33t: Bool,
  l33t_subs: List(L33tSubstitution),
) -> Int {
  let uppercase_factor = uppercase_variations(token)
  let reversed_factor = case reversed {
    True -> 2
    False -> 1
  }
  let l33t_factor = case l33t {
    True -> l33t_variations(l33t_subs)
    False -> 1
  }
  rank * uppercase_factor * reversed_factor * l33t_factor
}

fn uppercase_variations(token: String) -> Int {
  let chars = string.to_graphemes(token)
  let lower_count =
    list.count(chars, fn(char) {
      string.lowercase(char) == char && string.uppercase(char) != char
    })
  let upper_count =
    list.count(chars, fn(char) {
      string.uppercase(char) == char && string.lowercase(char) != char
    })

  case lower_count, upper_count {
    _, 0 -> 1
    0, _ -> 1
    lower, 1 if lower > 0 -> 2
    lower, upper -> {
      let total = lower + upper
      list.range(1, int.min(upper, lower))
      |> list.fold(0, fn(acc, i) { acc + n_choose_k(total, i) })
    }
  }
}

fn l33t_variations(subs: List(L33tSubstitution)) -> Int {
  case subs {
    [] -> 1
    _ -> list.fold(subs, 1, fn(acc, _sub) { acc * 2 })
  }
}

fn estimate_spatial_guesses(
  token: String,
  graph_name: String,
  turns: Int,
  shifted_count: Int,
  graphs: List(NamedGraph),
) -> Int {
  let len = string.length(token)

  let graph_info =
    list.find(graphs, fn(named_graph) { named_graph.name == graph_name })
    |> result.map(fn(named_graph) {
      let starting_positions = dict.size(named_graph.graph)
      let avg_degree = calculate_avg_degree(named_graph.graph)
      #(starting_positions, avg_degree)
    })
    |> result.unwrap(#(47, 4.6))

  let #(starting_positions, avg_degree) = graph_info

  let base_sum =
    list.range(2, len)
    |> list.fold(0, fn(acc, l) {
      let turn_possibilities =
        list.range(1, int.min(turns, l - 1))
        |> list.fold(0, fn(t_acc, t) {
          t_acc
          + n_choose_k(l - 1, t - 1)
          * starting_positions
          * power(float.truncate(avg_degree), l - 1)
        })
      acc + turn_possibilities
    })

  let base = case base_sum {
    0 -> starting_positions * power(float.truncate(avg_degree), len - 1)
    _ -> base_sum
  }

  let shift_factor = case shifted_count {
    0 -> 1
    s if s == len -> 2
    _ -> {
      let unshifted = len - shifted_count
      list.range(1, int.min(shifted_count, unshifted))
      |> list.fold(0, fn(acc, i) { acc + n_choose_k(len, i) })
      |> int.max(1)
    }
  }

  base * shift_factor
}

fn calculate_avg_degree(
  graph: dict.Dict(String, List(option.Option(String))),
) -> Float {
  let values = dict.values(graph)
  let total =
    list.fold(values, 0, fn(acc, adjacents) {
      acc + list.count(adjacents, option.is_some)
    })
  int.to_float(total) /. int.to_float(list.length(values))
}

fn estimate_sequence_guesses(token: String, ascending: Bool) -> Int {
  let first = string.slice(token, 0, 1)
  let len = string.length(token)

  let base = case first {
    "a" | "A" | "z" | "Z" | "0" | "1" | "9" -> 2
    _ ->
      case is_digit(first) {
        True -> 5
        False -> 13
      }
  }

  let direction = case ascending {
    True -> 1
    False -> 2
  }

  base * direction * len
}

fn estimate_date_guesses(year: Int, has_separator: Bool) -> Int {
  let year_distance = int.absolute_value(year - reference_year)
  let base = 365 * int.max(year_distance, 1)
  let separator_factor = case has_separator {
    True -> 4
    False -> 1
  }
  base * separator_factor
}

fn estimate_bruteforce_guesses(token: String) -> Int {
  let cardinality = calculate_cardinality(token)
  let len = string.length(token)
  power(cardinality, len)
}

fn calculate_cardinality(token: String) -> Int {
  let #(has_lower, has_upper, has_digit, has_symbol) =
    string.to_graphemes(token)
    |> list.fold(#(False, False, False, False), fn(acc, char) {
      let #(lower, upper, digit, symbol) = acc
      let is_alpha_char = is_alpha(char)
      let is_digit_char = is_digit(char)
      #(
        lower || { string.lowercase(char) == char && is_alpha_char },
        upper || { string.uppercase(char) == char && is_alpha_char },
        digit || is_digit_char,
        symbol || { !is_alpha_char && !is_digit_char },
      )
    })

  let cardinality =
    case has_lower {
      True -> lowercase_count
      False -> 0
    }
    + case has_upper {
      True -> uppercase_count
      False -> 0
    }
    + case has_digit {
      True -> digit_count
      False -> 0
    }
    + case has_symbol {
      True -> symbol_count
      False -> 0
    }

  int.max(cardinality, bruteforce_cardinality)
}

fn is_alpha(c: String) -> Bool {
  case string.to_utf_codepoints(c) {
    [cp] -> {
      let n = string.utf_codepoint_to_int(cp)
      { n >= 65 && n <= 90 } || { n >= 97 && n <= 122 }
    }
    _ -> False
  }
}

fn is_digit(c: String) -> Bool {
  case string.to_utf_codepoints(c) {
    [cp] -> {
      let n = string.utf_codepoint_to_int(cp)
      n >= 48 && n <= 57
    }
    _ -> False
  }
}

fn n_choose_k(n: Int, k: Int) -> Int {
  case k > n || k < 0 {
    True -> 0
    False -> {
      case k == 0 || k == n {
        True -> 1
        False -> {
          let k = case k > n - k {
            True -> n - k
            False -> k
          }
          list.range(0, k - 1)
          |> list.fold(1, fn(acc, i) { acc * { n - i } / { i + 1 } })
        }
      }
    }
  }
}

fn power(base: Int, exp: Int) -> Int {
  int.power(base, of: int.to_float(exp))
  |> result.unwrap(0.0)
  |> float.truncate
}

fn log10(n: Int) -> Float {
  case n <= 0 {
    True -> 0.0
    False -> do_log10(int.to_float(n))
  }
}

@external(erlang, "math", "log10")
@external(javascript, "./gzxcvbn_ffi.mjs", "log10")
fn do_log10(x: Float) -> Float

fn guesses_to_score(guesses: Int) -> Int {
  case guesses {
    g if g < 1000 -> 0
    g if g < 1_000_000 -> 1
    g if g < 100_000_000 -> 2
    g if g < 10_000_000_000 -> 3
    _ -> 4
  }
}

fn int_to_score(n: Int) -> Score {
  case n {
    4 -> VeryUnguessable
    3 -> SafelyUnguessable
    2 -> SomewhatGuessable
    1 -> VeryGuessable
    _ -> TooGuessable
  }
}

// =============================================================================
// Internal - Crack Times
// =============================================================================

fn estimate_crack_times(guesses: Int) -> CrackTimes {
  let g = int.to_float(guesses)

  let online_throttled_seconds = g /. online_throttled_per_second
  let online_unthrottled_seconds = g /. online_unthrottled_per_second
  let offline_slow_seconds = g /. offline_slow_per_second
  let offline_fast_seconds = g /. offline_fast_per_second

  CrackTimes(
    online_throttled_seconds:,
    online_unthrottled_seconds:,
    offline_slow_seconds:,
    offline_fast_seconds:,
    online_throttled_display: display_time(online_throttled_seconds),
    online_unthrottled_display: display_time(online_unthrottled_seconds),
    offline_slow_display: display_time(offline_slow_seconds),
    offline_fast_display: display_time(offline_fast_seconds),
  )
}

fn display_time(seconds: Float) -> String {
  let minute = 60.0
  let hour = minute *. 60.0
  let day = hour *. 24.0
  let month = day *. 31.0
  let year = day *. 365.0
  let century = year *. 100.0

  case seconds {
    s if s <. 1.0 -> "less than a second"
    s if s <. minute -> pluralise(float.truncate(s), "second")
    s if s <. hour -> pluralise(float.truncate(s /. minute), "minute")
    s if s <. day -> pluralise(float.truncate(s /. hour), "hour")
    s if s <. month -> pluralise(float.truncate(s /. day), "day")
    s if s <. year -> pluralise(float.truncate(s /. month), "month")
    s if s <. century -> pluralise(float.truncate(s /. year), "year")
    _ -> "centuries"
  }
}

fn pluralise(n: Int, unit: String) -> String {
  case n {
    1 -> "1 " <> unit
    _ -> int.to_string(n) <> " " <> unit <> "s"
  }
}

// =============================================================================
// Internal - Feedback
// =============================================================================

fn generate_feedback(
  sequence: List(MatchWithGuesses),
  score: Int,
  translations: Translations,
) -> Feedback {
  case score >= 3 {
    True -> Feedback(warning: "", suggestions: [])
    False -> {
      let longest_match = find_longest_match(sequence)
      let #(warning_key, suggestion_keys) = case longest_match {
        Ok(m) -> get_match_feedback(m.match)
        Error(_) -> #(NoWarning, [UseMoreWords, NoNeedForSymbolsOrDigits])
      }

      let warning = translations.warning(warning_key)
      let suggestions = list.map(suggestion_keys, translations.suggestion)

      let suggestions = case score < 2 {
        True -> [translations.suggestion(AddAnotherWord), ..suggestions]
        False -> suggestions
      }

      Feedback(warning:, suggestions: list.unique(suggestions))
    }
  }
}

fn find_longest_match(
  sequence: List(MatchWithGuesses),
) -> Result(MatchWithGuesses, Nil) {
  list.reduce(sequence, fn(current, m) {
    case match_length(m.match) > match_length(current.match) {
      True -> m
      False -> current
    }
  })
}

fn get_match_feedback(m: Match) -> #(Warning, List(Suggestion)) {
  case m {
    DictionaryMatch(rank:, dictionary_kind:, l33t:, reversed:, token:, ..) -> {
      let warning =
        get_dictionary_warning(rank, dictionary_kind, l33t, reversed)
      let suggestions = case dictionary_kind {
        UserInput(UserYears) -> [AvoidAssociatedYears]
        _ -> get_dictionary_suggestions(token, l33t, reversed)
      }
      #(warning, suggestions)
    }
    SpatialMatch(turns:, ..) -> {
      let warning = case turns == 1 {
        True -> StraightRowOfKeys
        False -> ShortKeyboardPatterns
      }
      #(warning, [UseKeyboardPatternLonger])
    }
    SequenceMatch(..) -> #(SequenceAbcEtc, [AvoidSequences])
    RepeatMatch(base_token:, ..) -> {
      let warning = case string.length(base_token) == 1 {
        True -> RepeatedCharacters
        False -> RepeatedCharacterPatterns
      }
      #(warning, [AvoidRepeatedWords])
    }
    DateMatch(year:, ..) -> {
      let warning = case year >= 2000 {
        True -> RecentYears
        False -> Dates
      }
      let suggestion = case year >= 2000 {
        True -> AvoidRecentYears
        False -> AvoidDates
      }
      #(warning, [suggestion])
    }
    BruteforceMatch(..) -> #(NoWarning, [UseMoreWords, NoNeedForSymbolsOrDigits])
  }
}

fn get_dictionary_warning(
  rank: Int,
  kind: DictionaryKind,
  l33t: Bool,
  reversed: Bool,
) -> Warning {
  case kind {
    Passwords ->
      case l33t || reversed {
        True -> SimilarToCommonPassword
        False ->
          case rank {
            r if r <= 10 -> TopTenPassword
            r if r <= 100 -> TopHundredPassword
            _ -> CommonPassword
          }
      }
    Names -> CommonNamesByThemselves
    UserInput(UserNames) -> NamesByThemselves
    UserInput(UserYears) -> AssociatedYears
    UserInput(UserOther) -> WordByItself
    Words -> WordByItself
  }
}

fn get_dictionary_suggestions(
  token: String,
  l33t: Bool,
  reversed: Bool,
) -> List(Suggestion) {
  let suggestions = []
  let suggestions = case is_capitalised(token) || is_all_uppercase(token) {
    True ->
      case is_all_uppercase(token) {
        True -> [AllUppercaseDoesntHelp, ..suggestions]
        False -> [CapitalisationDoesntHelp, ..suggestions]
      }
    False -> suggestions
  }
  let suggestions = case l33t {
    True -> [PredictableSubstitutions, ..suggestions]
    False -> suggestions
  }
  case reversed {
    True -> [ReversedDoesntHelp, ..suggestions]
    False -> suggestions
  }
}

fn is_capitalised(s: String) -> Bool {
  case string.pop_grapheme(s) {
    Ok(#(first, rest)) ->
      string.uppercase(first) == first && string.lowercase(rest) == rest
    Error(_) -> False
  }
}

fn is_all_uppercase(s: String) -> Bool {
  string.uppercase(s) == s && string.lowercase(s) != s
}

fn default_warning(key: Warning) -> String {
  case key {
    NoWarning -> ""
    StraightRowOfKeys -> "Straight rows of keys are easy to guess."
    ShortKeyboardPatterns -> "Short keyboard patterns are easy to guess."
    RepeatedCharacters -> "Repeats like \"aaa\" are easy to guess."
    RepeatedCharacterPatterns ->
      "Repeats like \"abcabcabc\" are only slightly harder to guess than \"abc\"."
    SequenceAbcEtc -> "Sequences like \"abc\" or \"6543\" are easy to guess."
    RecentYears -> "Recent years are easy to guess."
    Dates -> "Dates are often easy to guess."
    TopTenPassword -> "This is a top-10 common password."
    TopHundredPassword -> "This is a top-100 common password."
    CommonPassword -> "This is a very common password."
    SimilarToCommonPassword -> "This is similar to a commonly used password."
    WordByItself -> "A word by itself is easy to guess."
    CommonNamesByThemselves -> "Common names and surnames are easy to guess."
    NamesByThemselves -> "Names by themselves are easy to guess."
    AssociatedYears -> "Years associated with you are easy to guess."
  }
}

fn default_suggestion(key: Suggestion) -> String {
  case key {
    UseMoreWords -> "Use a few words, avoid common phrases."
    NoNeedForSymbolsOrDigits ->
      "No need for symbols, digits, or uppercase letters."
    AddAnotherWord -> "Add another word or two. Uncommon words are better."
    CapitalisationDoesntHelp -> "Capitalisation doesn't help very much."
    AllUppercaseDoesntHelp ->
      "All-uppercase is almost as easy to guess as all-lowercase."
    ReversedDoesntHelp -> "Reversed words aren't much harder to guess."
    PredictableSubstitutions ->
      "Predictable substitutions like '@' instead of 'a' don't help very much."
    UseKeyboardPatternLonger -> "Use a longer keyboard pattern with more turns."
    AvoidRepeatedWords -> "Avoid repeated words and characters."
    AvoidSequences -> "Avoid sequences."
    AvoidRecentYears -> "Avoid recent years."
    AvoidDates -> "Avoid dates and years that are associated with you."
    AvoidAssociatedYears -> "Avoid years that are associated with you."
  }
}

// =============================================================================
// Internal - Options Helpers
// =============================================================================

fn build_user_dictionary(
  inputs: List(String),
  kind: DictionaryKind,
) -> Result(NamedDictionary, Nil) {
  case inputs {
    [] -> Error(Nil)
    _ -> {
      let name = case kind {
        UserInput(UserNames) -> "user_names"
        UserInput(UserYears) -> "user_years"
        UserInput(UserOther) -> "user_other"
        _ -> "user_inputs"
      }
      let dictionary =
        inputs
        |> list.map(string.lowercase)
        |> list.index_map(fn(word, idx) { #(word, idx + 1) })
        |> dict.from_list
      Ok(NamedDictionary(name:, kind:, dictionary:))
    }
  }
}

fn default_l33t_table() -> dict.Dict(String, List(String)) {
  dict.from_list([
    #("a", ["4", "@"]),
    #("b", ["8"]),
    #("c", ["(", "{", "[", "<"]),
    #("d", ["6", "|)"]),
    #("e", ["3"]),
    #("f", ["#"]),
    #("g", ["6", "9", "&"]),
    #("h", ["#", "|-|"]),
    #("i", ["1", "!", "|"]),
    #("k", ["<", "|<"]),
    #("l", ["!", "1", "|", "7"]),
    #("m", ["^^", "nn", "2n", "/\\\\/\\\\"]),
    #("n", ["//"]),
    #("o", ["0", "()"]),
    #("q", ["9"]),
    #("s", ["$", "5"]),
    #("t", ["+", "7"]),
    #("u", ["|_|"]),
    #("v", ["<", ">", "/"]),
    #("w", ["^/", "uu", "vv", "2u", "2v", "\\\\/\\\\/"]),
    #("x", ["%", "><"]),
    #("z", ["2"]),
  ])
}
