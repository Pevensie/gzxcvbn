import gleam/float
import gleam/int
import gleam/list
import gleam/string
import gzxcvbn
import gzxcvbn/common
import gzxcvbn/en
import lustre
import lustre/attribute
import lustre/effect
import lustre/element
import lustre/element/html
import lustre/event

// MAIN ------------------------------------------------------------------------

pub fn main() {
  let app = lustre.application(init, update, view)
  let assert Ok(_) = lustre.start(app, "#app", Nil)
  Nil
}

// MODEL -----------------------------------------------------------------------

type Model {
  Model(password: String, result: gzxcvbn.CheckResult, options: gzxcvbn.Options)
}

fn init(_flags: Nil) -> #(Model, effect.Effect(Msg)) {
  let opts =
    gzxcvbn.options()
    |> gzxcvbn.with_dictionaries(common.dictionaries())
    |> gzxcvbn.with_dictionaries(en.dictionaries())
    |> gzxcvbn.with_graphs(common.graphs())
    |> gzxcvbn.build()

  let initial_password = ""
  let initial_result = gzxcvbn.check(initial_password, opts)

  #(
    Model(password: initial_password, result: initial_result, options: opts),
    effect.none(),
  )
}

// UPDATE ----------------------------------------------------------------------

type Msg {
  UserUpdatedPassword(String)
}

fn update(model: Model, msg: Msg) -> #(Model, effect.Effect(Msg)) {
  case msg {
    UserUpdatedPassword(password) -> {
      let result = gzxcvbn.check(password, model.options)
      #(Model(..model, password: password, result: result), effect.none())
    }
  }
}

// VIEW ------------------------------------------------------------------------

fn view(model: Model) -> element.Element(Msg) {
  html.main(
    [
      attribute.class(
        "min-h-screen bg-gradient-to-br from-slate-900 via-slate-800 to-slate-900 py-12 px-4",
      ),
    ],
    [
      html.div([attribute.class("max-w-2xl mx-auto")], [
        header(),
        password_input(model.password),
        strength_meter(model.result),
        crack_times(model.result),
        feedback(model.result),
        matches(model.result),
        footer(),
      ]),
    ],
  )
}

fn header() -> element.Element(Msg) {
  html.section([attribute.class("text-center mb-10")], [
    html.h1(
      [
        attribute.class("text-4xl font-bold text-white mb-2 tracking-tight"),
      ],
      [html.text("gzxcvbn")],
    ),
    html.p([attribute.class("text-slate-400 text-lg")], [
      html.text("Password strength estimation for Gleam"),
    ]),
  ])
}

fn password_input(password: String) -> element.Element(Msg) {
  html.div([attribute.class("mb-8")], [
    html.label(
      [attribute.class("block text-sm font-medium text-slate-300 mb-2")],
      [html.text("Enter a password to analyse")],
    ),
    html.input([
      attribute.type_("text"),
      attribute.placeholder(
        "Try 'password', 'correcthorsebatterystaple', or your own...",
      ),
      attribute.value(password),
      attribute.maxlength(128),
      attribute.autofocus(True),
      event.on_input(UserUpdatedPassword),
      attribute.class(
        "w-full px-4 py-3 rounded-lg bg-slate-700/50 border border-slate-600 text-white placeholder-slate-500 focus:outline-none focus:ring-2 focus:ring-emerald-500 focus:border-transparent font-mono text-lg",
      ),
    ]),
  ])
}

fn strength_meter(result: gzxcvbn.CheckResult) -> element.Element(Msg) {
  let score_info = score_to_info(result.score)
  let bar_width = case result.password {
    "" -> "0%"
    _ -> int.to_string({ score_info.level + 1 } * 20) <> "%"
  }

  html.div(
    [
      attribute.class(
        "bg-slate-800/50 rounded-xl p-6 mb-6 border border-slate-700",
      ),
    ],
    [
      html.div([attribute.class("flex justify-between items-center mb-3")], [
        html.span([attribute.class("text-slate-300 font-medium")], [
          html.text("Strength"),
        ]),
        html.span([attribute.class("font-semibold " <> score_info.colour)], [
          html.text(score_info.label),
        ]),
      ]),
      html.div(
        [attribute.class("h-3 bg-slate-700 rounded-full overflow-hidden")],
        [
          html.div(
            [
              attribute.class(
                "h-full transition-all duration-300 " <> score_info.bar_colour,
              ),
              attribute.style("width", bar_width),
            ],
            [],
          ),
        ],
      ),
      html.div([attribute.class("mt-4 grid grid-cols-2 gap-4 text-sm")], [
        html.div([], [
          html.span([attribute.class("text-slate-500")], [
            html.text("Guesses needed: "),
          ]),
          html.span([attribute.class("text-white font-mono")], [
            html.text(format_number(result.guesses)),
          ]),
        ]),
        html.div([], [
          html.span([attribute.class("text-slate-500")], [
            html.text("Log\u{2081}\u{2080}(guesses): "),
          ]),
          html.span([attribute.class("text-white font-mono")], [
            html.text(
              float.to_string(float.to_precision(result.guesses_log10, 2)),
            ),
          ]),
        ]),
      ]),
    ],
  )
}

fn crack_times(result: gzxcvbn.CheckResult) -> element.Element(Msg) {
  let times = result.crack_times

  html.div(
    [
      attribute.class(
        "bg-slate-800/50 rounded-xl p-6 mb-6 border border-slate-700",
      ),
    ],
    [
      html.h3([attribute.class("text-white font-semibold mb-4")], [
        html.text("Time to crack"),
      ]),
      html.div([attribute.class("grid grid-cols-2 gap-4")], [
        crack_time_item(
          "Online (throttled)",
          times.online_throttled_display,
          "100 attempts/hour",
        ),
        crack_time_item(
          "Online (unthrottled)",
          times.online_unthrottled_display,
          "10 attempts/second",
        ),
        crack_time_item(
          "Offline (slow hash)",
          times.offline_slow_display,
          "10k attempts/second",
        ),
        crack_time_item(
          "Offline (fast hash)",
          times.offline_fast_display,
          "10B attempts/second",
        ),
      ]),
    ],
  )
}

fn crack_time_item(
  label: String,
  time: String,
  subtitle: String,
) -> element.Element(Msg) {
  html.div([attribute.class("bg-slate-700/30 rounded-lg p-3")], [
    html.div([attribute.class("text-slate-400 text-xs mb-1")], [
      html.text(label),
    ]),
    html.div([attribute.class("text-white font-semibold")], [html.text(time)]),
    html.div([attribute.class("text-slate-500 text-xs mt-1")], [
      html.text(subtitle),
    ]),
  ])
}

fn feedback(result: gzxcvbn.CheckResult) -> element.Element(Msg) {
  let has_warning = result.feedback.warning != ""
  let has_suggestions = result.feedback.suggestions != []

  case has_warning || has_suggestions {
    False -> element.none()
    True ->
      html.div(
        [
          attribute.class(
            "bg-slate-800/50 rounded-xl p-6 mb-6 border border-slate-700",
          ),
        ],
        [
          html.h3([attribute.class("text-white font-semibold mb-4")], [
            html.text("Feedback"),
          ]),
          case has_warning {
            False -> element.none()
            True ->
              html.div(
                [
                  attribute.class(
                    "bg-amber-500/10 border border-amber-500/20 rounded-lg p-3 mb-4",
                  ),
                ],
                [
                  html.div([attribute.class("flex items-start gap-2")], [
                    html.span([attribute.class("text-amber-500")], [
                      html.text("\u{26A0}"),
                    ]),
                    html.span([attribute.class("text-amber-200")], [
                      html.text(result.feedback.warning),
                    ]),
                  ]),
                ],
              )
          },
          case has_suggestions {
            False -> element.none()
            True ->
              html.ul(
                [attribute.class("space-y-2")],
                list.map(result.feedback.suggestions, fn(s) {
                  html.li(
                    [attribute.class("flex items-start gap-2 text-slate-300")],
                    [
                      html.span([attribute.class("text-emerald-500")], [
                        html.text("\u{2192}"),
                      ]),
                      html.text(s),
                    ],
                  )
                }),
              )
          },
        ],
      )
  }
}

fn matches(result: gzxcvbn.CheckResult) -> element.Element(Msg) {
  case result.sequence {
    [] -> element.none()
    _ ->
      html.div(
        [
          attribute.class(
            "bg-slate-800/50 rounded-xl p-6 mb-6 border border-slate-700",
          ),
        ],
        [
          html.h3([attribute.class("text-white font-semibold mb-4")], [
            html.text("Pattern analysis"),
          ]),
          html.div(
            [attribute.class("space-y-3")],
            list.map(result.sequence, match_item),
          ),
        ],
      )
  }
}

fn match_item(estimated: gzxcvbn.MatchWithGuesses) -> element.Element(Msg) {
  let match_info = match_to_info(estimated.match)

  html.div([attribute.class("bg-slate-700/30 rounded-lg p-3")], [
    html.div([attribute.class("flex justify-between items-start mb-2")], [
      html.div([], [
        html.span(
          [
            attribute.class(
              "font-mono text-emerald-400 bg-emerald-400/10 px-2 py-0.5 rounded",
            ),
          ],
          [html.text(match_info.token)],
        ),
      ]),
      html.span(
        [
          attribute.class(
            "text-xs px-2 py-1 rounded " <> match_info.badge_class,
          ),
        ],
        [html.text(match_info.type_label)],
      ),
    ]),
    html.div([attribute.class("text-slate-400 text-sm")], [
      html.text(match_info.description),
    ]),
    html.div([attribute.class("text-slate-500 text-xs mt-2")], [
      html.text("Guesses: " <> format_number(estimated.guesses)),
    ]),
  ])
}

fn footer() -> element.Element(Msg) {
  html.footer([attribute.class("mt-10 text-center text-slate-500 text-sm")], [
    html.p([], [
      html.text("Built with "),
      html.a(
        [
          attribute.href("https://gleam.run"),
          attribute.target("_blank"),
          attribute.class("text-pink-400 hover:text-pink-300 transition-colors"),
        ],
        [html.text("Gleam")],
      ),
      html.text(" and "),
      html.a(
        [
          attribute.href("https://hexdocs.pm/lustre"),
          attribute.target("_blank"),
          attribute.class("text-pink-400 hover:text-pink-300 transition-colors"),
        ],
        [html.text("Lustre")],
      ),
    ]),
    html.p([attribute.class("mt-1")], [
      html.text("Inspired by "),
      html.a(
        [
          attribute.href("https://github.com/dropbox/zxcvbn"),
          attribute.target("_blank"),
          attribute.class("text-pink-400 hover:text-pink-300 transition-colors"),
        ],
        [html.text("zxcvbn")],
      ),
    ]),
  ])
}

// HELPERS ---------------------------------------------------------------------

type ScoreInfo {
  ScoreInfo(level: Int, label: String, colour: String, bar_colour: String)
}

fn score_to_info(score: gzxcvbn.Score) -> ScoreInfo {
  case score {
    gzxcvbn.TooGuessable ->
      ScoreInfo(
        level: 0,
        label: "Too guessable",
        colour: "text-red-400",
        bar_colour: "bg-red-500",
      )
    gzxcvbn.VeryGuessable ->
      ScoreInfo(
        level: 1,
        label: "Very guessable",
        colour: "text-orange-400",
        bar_colour: "bg-orange-500",
      )
    gzxcvbn.SomewhatGuessable ->
      ScoreInfo(
        level: 2,
        label: "Somewhat guessable",
        colour: "text-yellow-400",
        bar_colour: "bg-yellow-500",
      )
    gzxcvbn.SafelyUnguessable ->
      ScoreInfo(
        level: 3,
        label: "Safely unguessable",
        colour: "text-lime-400",
        bar_colour: "bg-lime-500",
      )
    gzxcvbn.VeryUnguessable ->
      ScoreInfo(
        level: 4,
        label: "Very unguessable",
        colour: "text-emerald-400",
        bar_colour: "bg-emerald-500",
      )
  }
}

type MatchInfo {
  MatchInfo(
    token: String,
    type_label: String,
    badge_class: String,
    description: String,
  )
}

fn match_to_info(m: gzxcvbn.Match) -> MatchInfo {
  case m {
    gzxcvbn.DictionaryMatch(
      token: token,
      dictionary_name: name,
      rank: rank,
      reversed: rev,
      l33t: l33t,
      ..,
    ) -> {
      let extras = case rev, l33t {
        True, True -> ["reversed", "l33t"]
        True, False -> ["reversed"]
        False, True -> ["l33t"]
        False, False -> []
      }
      let extra_text = case extras {
        [] -> ""
        _ -> " (" <> string.join(extras, ", ") <> ")"
      }
      MatchInfo(
        token: token,
        type_label: "Dictionary",
        badge_class: "bg-blue-500/20 text-blue-400",
        description: "Found in '"
          <> name
          <> "' dictionary at rank "
          <> int.to_string(rank)
          <> extra_text,
      )
    }

    gzxcvbn.SpatialMatch(token: token, graph: graph, turns: turns, ..) ->
      MatchInfo(
        token: token,
        type_label: "Keyboard",
        badge_class: "bg-purple-500/20 text-purple-400",
        description: "Keyboard pattern on "
          <> graph
          <> " layout with "
          <> int.to_string(turns)
          <> " turn(s)",
      )

    gzxcvbn.SequenceMatch(token: token, sequence_name: name, ascending: asc, ..) -> {
      let direction = case asc {
        True -> "ascending"
        False -> "descending"
      }
      MatchInfo(
        token: token,
        type_label: "Sequence",
        badge_class: "bg-cyan-500/20 text-cyan-400",
        description: string.capitalise(name) <> " sequence, " <> direction,
      )
    }

    gzxcvbn.RepeatMatch(token: token, base_token: base, repeat_count: count, ..) ->
      MatchInfo(
        token: token,
        type_label: "Repeat",
        badge_class: "bg-amber-500/20 text-amber-400",
        description: "'"
          <> base
          <> "' repeated "
          <> int.to_string(count)
          <> " times",
      )

    gzxcvbn.DateMatch(token: token, year: year, month: month, day: day, ..) ->
      MatchInfo(
        token: token,
        type_label: "Date",
        badge_class: "bg-rose-500/20 text-rose-400",
        description: "Date pattern: "
          <> int.to_string(year)
          <> "-"
          <> pad_number(month)
          <> "-"
          <> pad_number(day),
      )

    gzxcvbn.BruteforceMatch(token: token, ..) ->
      MatchInfo(
        token: token,
        type_label: "Bruteforce",
        badge_class: "bg-slate-500/20 text-slate-400",
        description: "No pattern found, would require brute force",
      )
  }
}

fn format_number(n: Int) -> String {
  case n {
    x if x >= 1_000_000_000_000 ->
      float.to_string(float.to_precision(
        int.to_float(x) /. 1_000_000_000_000.0,
        1,
      ))
      <> "T"
    x if x >= 1_000_000_000 ->
      float.to_string(float.to_precision(int.to_float(x) /. 1_000_000_000.0, 1))
      <> "B"
    x if x >= 1_000_000 ->
      float.to_string(float.to_precision(int.to_float(x) /. 1_000_000.0, 1))
      <> "M"
    x if x >= 1000 ->
      float.to_string(float.to_precision(int.to_float(x) /. 1000.0, 1)) <> "K"
    x -> int.to_string(x)
  }
}

fn pad_number(n: Int) -> String {
  int.to_string(n) |> string.pad_start(2, "0")
}
