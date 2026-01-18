//// Codegen script to fetch dictionary data from zxcvbn-ts and generate Gleam source files.
////
//// Run with: gleam run

import gleam/dict
import gleam/dynamic/decode
import gleam/http/request
import gleam/httpc
import gleam/int
import gleam/io
import gleam/json
import gleam/list
import gleam/option
import gleam/result
import gleam/string
import shellout
import simplifile

const base_url = "https://raw.githubusercontent.com/zxcvbn-ts/zxcvbn/master/packages/languages"

const common_package_root = "../gzxcvbn_common"

const en_package_root = "../gzxcvbn_en"

// =============================================================================
// Main
// =============================================================================

pub fn main() -> Nil {
  io.println("Fetching dictionary data from zxcvbn-ts...")

  // Fetch common data
  let assert Ok(passwords) = fetch_string_list("/common/src/passwords.json")
  io.println(
    "  passwords: " <> int.to_string(list.length(passwords)) <> " entries",
  )

  let assert Ok(graphs) =
    fetch_adjacency_graphs("/common/src/adjacencyGraphs.json")
  io.println("  graphs: " <> int.to_string(dict.size(graphs)) <> " keyboards")

  // Fetch English data
  let assert Ok(common_words) = fetch_string_list("/en/src/commonWords.json")
  io.println(
    "  common_words: " <> int.to_string(list.length(common_words)) <> " entries",
  )

  let assert Ok(firstnames) = fetch_string_list("/en/src/firstnames.json")
  io.println(
    "  firstnames: " <> int.to_string(list.length(firstnames)) <> " entries",
  )

  let assert Ok(lastnames) = fetch_string_list("/en/src/lastnames.json")
  io.println(
    "  lastnames: " <> int.to_string(list.length(lastnames)) <> " entries",
  )

  let assert Ok(wikipedia) = fetch_string_list("/en/src/wikipedia.json")
  io.println(
    "  wikipedia: " <> int.to_string(list.length(wikipedia)) <> " entries",
  )

  // Generate common.gleam
  io.println("\nGenerating gzxcvbn_common...")
  let common_content = generate_common(passwords, graphs)
  let common_path = common_package_root <> "/src/gzxcvbn/common.gleam"
  let assert Ok(_) = simplifile.write(common_path, common_content)
  io.println("  Written " <> common_path)

  // Generate en.gleam
  io.println("Generating gzxcvbn_en...")
  let en_content = generate_en(common_words, firstnames, lastnames, wikipedia)
  let en_path = en_package_root <> "/src/gzxcvbn/en.gleam"
  let assert Ok(_) = simplifile.write(en_path, en_content)
  io.println("  Written " <> en_path)

  // Format generated files
  io.println("\nFormatting generated files...")
  io.print("  Formatting common.gleam... ")
  let assert Ok(_) =
    shellout.command("gleam", ["format"], common_package_root, [])
  io.println("done")
  io.print("  Formatting en.gleam... ")
  let assert Ok(_) = shellout.command("gleam", ["format"], en_package_root, [])
  io.println("done")

  io.println("\nDone! Run 'gleam check' in each package to verify.")
}

// =============================================================================
// HTTP Fetching
// =============================================================================

fn fetch_string_list(path: String) -> Result(List(String), String) {
  let url = base_url <> path
  use req <- result.try(
    request.to(url) |> result.replace_error("Invalid URL: " <> url),
  )
  use resp <- result.try(
    httpc.send(req) |> result.replace_error("HTTP request failed for: " <> url),
  )
  json.parse(resp.body, decode.list(decode.string))
  |> result.replace_error("JSON parse failed for: " <> url)
}

fn fetch_adjacency_graphs(
  path: String,
) -> Result(dict.Dict(String, dict.Dict(String, List(String))), String) {
  let url = base_url <> path
  use req <- result.try(
    request.to(url) |> result.replace_error("Invalid URL: " <> url),
  )
  use resp <- result.try(
    httpc.send(req) |> result.replace_error("HTTP request failed for: " <> url),
  )

  // Decode as Dict(String, Dict(String, List(String | Null)))
  let graph_decoder =
    decode.dict(
      decode.string,
      decode.dict(decode.string, decode.list(decode.optional(decode.string))),
    )

  use raw_graphs <- result.try(
    json.parse(resp.body, graph_decoder)
    |> result.replace_error("JSON parse failed for: " <> url),
  )

  // Convert Option(String) to String (using empty string for None, we'll handle in codegen)
  let graphs =
    dict.map_values(raw_graphs, fn(_, graph) {
      dict.map_values(graph, fn(_, adjacents) {
        list.map(adjacents, fn(adj) {
          case adj {
            option.Some(s) -> s
            option.None -> ""
          }
        })
      })
    })

  Ok(graphs)
}

// =============================================================================
// Code Generation - Common
// =============================================================================

fn generate_common(
  passwords: List(String),
  graphs: dict.Dict(String, dict.Dict(String, List(String))),
) -> String {
  let passwords_count = int.to_string(list.length(passwords))
  let graphs_count = int.to_string(dict.size(graphs))

  let graph_names =
    dict.keys(graphs)
    |> list.sort(string.compare)

  let graph_list =
    graph_names
    |> list.map(to_snake_case)
    |> list.map(fn(name) { name <> "()" })
    |> string.join(", ")

  let graph_pub_fns =
    graph_names
    |> list.map(fn(name) {
      let snake = to_snake_case(name)
      "/// " <> name <> " keyboard adjacency graph.
pub fn " <> snake <> "() -> gzxcvbn.NamedGraph {
  gzxcvbn.NamedGraph(name: \"" <> name <> "\", graph: " <> snake <> "_data())
}"
    })
    |> string.join("\n\n")

  let graph_data_fns =
    graph_names
    |> list.map(fn(name) {
      let assert Ok(graph) = dict.get(graphs, name)
      generate_adjacency_graph_data(to_snake_case(name), graph)
    })
    |> string.join("\n\n")

  "//// Common passwords dictionary and keyboard adjacency graphs.
////
//// This module provides:
//// - Common passwords (" <> passwords_count <> " entries)
//// - Keyboard adjacency graphs (" <> graphs_count <> " layouts)

import gleam/dict
import gleam/option
import gzxcvbn

/// Get all common dictionaries.
pub fn dictionaries() -> List(gzxcvbn.NamedDictionary) {
  [passwords()]
}

/// Common passwords dictionary (" <> passwords_count <> " entries).
pub fn passwords() -> gzxcvbn.NamedDictionary {
  gzxcvbn.NamedDictionary(name: \"passwords\", dictionary: passwords_data())
}

/// Get all keyboard adjacency graphs.
pub fn graphs() -> List(gzxcvbn.NamedGraph) {
  [" <> graph_list <> "]
}

" <> graph_pub_fns <> "

// =============================================================================
// Data
// =============================================================================

" <> generate_ranked_dict_data("passwords", passwords) <> "

" <> graph_data_fns
}

fn generate_adjacency_graph_data(
  name: String,
  graph: dict.Dict(String, List(String)),
) -> String {
  let entries =
    dict.to_list(graph)
    |> list.sort(fn(a, b) { string.compare(a.0, b.0) })
    |> list.map(fn(entry) {
      let #(key, adjacents) = entry
      let escaped_key = escape_string(key)
      let adj_values =
        list.map(adjacents, fn(adj) {
          case adj {
            "" -> "option.None"
            s -> "option.Some(\"" <> escape_string(s) <> "\")"
          }
        })
        |> string.join(", ")
      "    #(\"" <> escaped_key <> "\", [" <> adj_values <> "]),"
    })
    |> string.join("\n")

  "fn " <> name <> "_data() -> dict.Dict(String, List(option.Option(String))) {
  dict.from_list([
" <> entries <> "
  ])
}"
}

// =============================================================================
// Code Generation - English
// =============================================================================

fn generate_en(
  common_words: List(String),
  firstnames: List(String),
  lastnames: List(String),
  wikipedia: List(String),
) -> String {
  let common_words_count = int.to_string(list.length(common_words))
  let firstnames_count = int.to_string(list.length(firstnames))
  let lastnames_count = int.to_string(list.length(lastnames))
  let wikipedia_count = int.to_string(list.length(wikipedia))

  "//// English language dictionaries for gzxcvbn.
////
//// This module provides:
//// - Common English words (" <> common_words_count <> " entries from TV/film subtitles)
//// - First names (" <> firstnames_count <> " entries)
//// - Last names (" <> lastnames_count <> " entries)
//// - Wikipedia words (" <> wikipedia_count <> " entries)

import gleam/dict
import gzxcvbn

/// Get all English dictionaries.
pub fn dictionaries() -> List(gzxcvbn.NamedDictionary) {
  [common_words(), firstnames(), lastnames(), wikipedia()]
}

/// Common English words from TV/film subtitles (" <> common_words_count <> " entries).
pub fn common_words() -> gzxcvbn.NamedDictionary {
  gzxcvbn.NamedDictionary(name: \"commonWords\", dictionary: common_words_data())
}

/// Common first names (" <> firstnames_count <> " entries).
pub fn firstnames() -> gzxcvbn.NamedDictionary {
  gzxcvbn.NamedDictionary(name: \"firstnames\", dictionary: firstnames_data())
}

/// Common last names (" <> lastnames_count <> " entries).
pub fn lastnames() -> gzxcvbn.NamedDictionary {
  gzxcvbn.NamedDictionary(name: \"lastnames\", dictionary: lastnames_data())
}

/// Common Wikipedia words (" <> wikipedia_count <> " entries).
pub fn wikipedia() -> gzxcvbn.NamedDictionary {
  gzxcvbn.NamedDictionary(name: \"wikipedia\", dictionary: wikipedia_data())
}

// =============================================================================
// Data
// =============================================================================

" <> generate_ranked_dict_data("common_words", common_words) <> "

" <> generate_ranked_dict_data("firstnames", firstnames) <> "

" <> generate_ranked_dict_data("lastnames", lastnames) <> "

" <> generate_ranked_dict_data("wikipedia", wikipedia)
}

// =============================================================================
// Helpers
// =============================================================================

fn generate_ranked_dict_data(name: String, words: List(String)) -> String {
  let entries =
    words
    |> list.index_map(fn(word, index) {
      let rank = index + 1
      "    #(\"" <> escape_string(word) <> "\", " <> int.to_string(rank) <> "),"
    })
    |> string.join("\n")

  "fn " <> name <> "_data() -> dict.Dict(String, Int) {
  dict.from_list([
" <> entries <> "
  ])
}"
}

fn escape_string(s: String) -> String {
  s
  |> string.replace("\\", "\\\\")
  |> string.replace("\"", "\\\"")
}

fn to_snake_case(s: String) -> String {
  s
  |> string.to_graphemes
  |> list.map(fn(c) {
    case is_uppercase(c) {
      True -> "_" <> string.lowercase(c)
      False -> c
    }
  })
  |> string.concat
  |> string.trim_start
  |> fn(str) {
    case string.starts_with(str, "_") {
      True -> string.drop_start(str, 1)
      False -> str
    }
  }
}

fn is_uppercase(c: String) -> Bool {
  let upper = string.uppercase(c)
  let lower = string.lowercase(c)
  c == upper && c != lower
}
