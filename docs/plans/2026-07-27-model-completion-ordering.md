# `--model` Completion — Canonical Ordering and the Documented Alias Set

## Problem

The known-model lists (`_CLAUDE_KNOWN_MODELS` in `claude.bash`,
`$script:_ClaudeKnownModels` in `claude.ps1`) grew by appending: bare aliases,
then families in the order they happened to be added, with each family's
versions ascending (`claude-opus-4-5-20251101`, `-4-6`, `-4-7`, `-4-8`,
`claude-opus-5`).

Two consequences:

1. **Oldest version first.** The version a user most likely wants — the newest
   in a family — sat at the *bottom* of its group. Adding `claude-opus-5`
   (2026-07) pushed the newest model further down still.
2. **The order was only half-honored.** PowerShell renders completions in the
   order they are returned, so the list order *was* the display order there.
   Bash handed the candidates to `COMPREPLY` without `compopt -o nosort`, so
   readline re-sorted them alphabetically before display. The two shells
   therefore showed `--model` candidates in genuinely different orders — bash
   put the bare aliases last (they sort after `claude-*`), PowerShell first.
   Reordering the array alone would have been a no-op in bash and would have
   widened that divergence rather than fixed it.

The ordering had never been stated as an invariant, in either script or in
`2026-07-20-model-alias-expansion-design.md`, so neither behavior was a
deliberate decision.

3. **The alias set was incomplete.** Checking
   [Model configuration](https://code.claude.com/docs/en/model-config) against
   the list turned up four documented aliases we never offered: `best`,
   `opusplan`, `opus[1m]`, and `sonnet[1m]` (plus `opusplan[1m]`, documented in
   prose). `--model` takes all of them — *"At startup: launch with
   `claude --model <alias|name>`"*.

## Decision

Order both lists by **Anthropic's canonical catalog order**, and make both
shells actually display that order.

### Alias set

Take the alias table in `model-config` as the source of truth — `best`,
`fable`, `opus`, `opus[1m]`, `sonnet`, `sonnet[1m]`, `haiku`, `opusplan`,
`opusplan[1m]` — plus `fable[1m]`, which the docs table omits but the CLI
accepts. The binary's alias array is exactly
`["sonnet","opus","haiku","fable","best","sonnet[1m]","opus[1m]","fable[1m]","opusplan"]`,
and redundancy is not a reason to leave `fable[1m]` out: `sonnet[1m]` is
documented while carrying the same caveat ("No effect when `sonnet` already
resolves to Sonnet 5 with its native 1M window"). There is deliberately no
`haiku[1m]` — Haiku 4.5 is a 200K model, and the binary's array agrees.

Deliberately excluded:

- **`default`** — listed in the same table but flagged there as *"Not itself a
  model alias"*; it clears an override rather than selecting a model.
- **`<full-name>[1m]`** — the docs allow `claude-opus-4-8[1m]`, but enumerating
  a suffixed twin for every pinned ID doubles the list to buy an exact-match
  case the user can type in two keystrokes.

### Ordering rule

1. Aliases first, in the order above, with each `[1m]` variant immediately
   after its base alias so the pair reads as one entry.
2. Then full model IDs, capability tier descending — fable, opus, sonnet,
   haiku — matching the Current Models table in Anthropic's model docs and the
   order `claude --help` names the aliases ("an alias for the latest model
   (e.g. 'fable', 'opus', or 'sonnet')").
3. Within a tier, versions **newest first**.

Aliases stay grouped at the top rather than interleaved with their tier: they
are the common pick, and a user who wants "just the latest opus" should not
have to read past five pinned IDs to find `opus`.

Note the two sources disagree on tier order: `model-config`'s alias table lists
sonnet before opus, while the API Current Models table and `claude --help` put
opus first. We follow opus-first, on the grounds that it is the capability
order and matches the CLI's own help text — but it is a coin-flip worth
revisiting if the docs converge.

The bare-numbered IDs (`claude-opus-5`, `claude-sonnet-5`) sort ahead of the
dotted ones in their tier, since Opus 5 supersedes Opus 4.8. Alphabetical
sorting gets this right by accident (`4-8` < `5`) but only within a tier, and
only for as long as the numbering stays single-digit.

### Parity

`compopt -o nosort` on the bash `--model` branch is what makes the rule real
rather than advisory. Without it the rule holds in PowerShell only, and the
scripts diverge on something a user sees directly.

This has a second, intended effect in bash: candidates are no longer
alphabetized at all, so the bare aliases move from the bottom of the list to
the top — matching what PowerShell has always shown.

### Bracket metacharacters

`[` and `]` are metacharacters in both shells, in different places, so the
`[1m]` aliases need handling on both the matching and the insertion side:

- **bash, insertion** — an unescaped `opus[1m]` on the command line is a glob.
  With a file named `opus1` in the cwd it pathname-expands to `opus1`, and
  under `failglob` an unmatched pattern aborts the command. Candidates are run
  through `printf -v … '%q'` when filling `COMPREPLY`, which yields
  `opus\[1m\]` and leaves plain IDs untouched.
- **bash, matching** — readline hands back the word as typed, so a
  half-typed bracket arrives escaped (`opus\[1`). `_claude_model_candidates`
  strips backslashes from `cur` before matching, so the escaped and unescaped
  forms behave the same.
- **PowerShell, matching** — `-like` reads `[` as the start of a character
  class, and `'opus[1m]' -like 'opus[1*'` does not merely fail to match: it
  **throws** `WildcardPatternException`. Typing `opus[1` would have taken the
  completer down. Matching now uses ordinal `StartsWith`, which is what the
  rule always meant and is wildcard-free by construction.
- **PowerShell, insertion** — nothing needed. PowerShell does not glob native
  command arguments, and `opus[1m]` parses as an ordinary bareword.

### Cost

One `compopt` call per `--model` completion, guarded to bash 4.4+ (`nosort`
does not exist earlier) and already `2>/dev/null || true` for the
not-in-a-completion case. On bash < 4.4 the list still displays alphabetized;
that is a graceful degradation, not a correctness problem.

`printf -v` writes into a variable rather than a command substitution, so the
escaping adds no subshell per candidate.

## Implementation

- **`claude.bash` / `claude.ps1`** — reorder both arrays per the rule above,
  with a comment on each stating the rule and pointing at its counterpart.
- **`claude.bash`** — extract the existing bash-4.4 `nosort` guard from
  `_claude_format_descriptions` into `_claude_preserve_order`, and call it from
  both there and the `--model)` branch of `_claude_complete_flag_arg`.
- **`claude.bash`** — strip backslashes from `cur` in
  `_claude_model_candidates`; escape each candidate with `printf -v … '%q'`
  when filling `COMPREPLY`.
- **`claude.ps1`** — swap the `-like` filter in `_ClaudeModelCandidates` for
  ordinal `StartsWith`. No ordering code needed; PowerShell preserves return
  order natively, and the comment on the array records that asymmetry so the
  next reader does not go looking for a missing `nosort` equivalent.

Help-scraped IDs (`claude-*` matched out of the cached `_root_help`) are still
appended after the hardcoded set, so an unknown-to-us model surfaces last
rather than in an arbitrary position mid-list.

## Testing

- **Both shells** — assert `_claude_model_candidates ""` /
  `_ClaudeModelCandidates -WordToComplete ''` returns a representative subset
  in exactly the canonical order. Probing a subset rather than asserting the
  whole list keeps the test stable when a help-scraped ID is present from an
  earlier case in the same file.
- **Both shells** — assert a single tier comes back newest-first
  (`opus`, `claude-opus-5`, `claude-opus-4-8`, …), which is the assertion that
  actually fails if someone appends a new model to the end of the array.
- **`parity_test.bash`** — compare the two known-model lists **unsorted**.
  The existing parity cases sort before comparing (membership is what matters
  for flags); for models the order *is* the contract, so this one must not.
- **bash** — assert an escaped stem (`opus\[1`) still matches `opus[1m]`, and
  that a full `--model opus[1` completion emits the escaped `opus\[1m\]` rather
  than the bare form.
- **PowerShell** — assert `opus[1` matches `opus[1m]`. This is a regression
  test for the `-like` throw, not just for the match.

## Maintenance

When a new model ships, insert it in canonical position — at the head of its
tier, not at the end of the array. The parity and ordering tests fail if it is
appended. This list is deliberately outside the scope of the
`refresh-bundled-flags` skill (see its `SKILL.md`); it tracks model releases,
not CHANGELOG flags.

The alias set is worth re-checking against `model-config` at the same time —
aliases are added there without a CHANGELOG flag entry, which is how `best`,
`opusplan`, and the `[1m]` variants went missing for as long as they did. The
binary's own alias array (`strings` the installed `claude`, look for the list
containing `opusplan`) is the better cross-check, since it is what the CLI
actually accepts — it carried `fable[1m]` before the docs table did.
