# `--model` Alias-Expansion Completion — Design

## Problem

Two gaps in `--model` completion:

1. **Missing `fable` alias.** The CLI documents `fable` as a model alias
   (`claude --help`: *"Provide an alias for the latest model (e.g. 'fable',
   'opus', or 'sonnet')…"*), but the completion's known-models list carries the
   bare aliases `sonnet opus haiku` and the full name `claude-fable-5` — not the
   bare `fable`. So `--model fable` is accepted by the CLI yet never offered by
   completion the way `opus`/`sonnet`/`haiku` are.

2. **Aliases don't reach their versioned models.** Both shells match `--model`
   candidates by strict prefix (`compgen -W … -- "$cur"` in bash;
   `-like "$WordToComplete*"` in PowerShell). Typing `opus` matches only
   candidates starting with `opus` — i.e. just the bare `opus` alias. The
   pinned models `claude-opus-4-8`, `claude-opus-4-7`, … start with `claude-`,
   so they are unreachable from the `opus` stem.

## Decision

Treat the leading `claude-` as **optional when matching**, and add the missing
`fable` alias.

### Match rule

Given the typed word `cur` and the candidate set `M` (aliases + hardcoded
versioned models + `claude-*` IDs scraped from cached `--help`, deduped), offer
a candidate `C` when **either**:

- `C` starts with `cur` (existing prefix behavior), **or**
- `C` starts with `"claude-" + cur` (the `claude-` prefix treated as optional).

No alias set and no per-family expansion loop are needed: because every family
token (`opus`, `sonnet`, `haiku`, `fable`) sits immediately after `claude-` in
the versioned names, the second prong reaches a family's versioned models
directly from its stem.

Empty `cur` still yields all of `M` (both prongs match everything → deduped to
the full set), so the no-argument case is unchanged.

### Behavior table

| `cur` | via `startswith cur` | via `startswith "claude-$cur"` | Offered |
|-------|----------------------|--------------------------------|---------|
| *(empty)* | all of `M` | all `claude-*` | all of `M` (unchanged) |
| `opus` | `opus` | `claude-opus-4-5-20251101`, `-4-6`, `-4-7`, `-4-8` | bare `opus` + all versioned opus |
| `op` | `opus` | `claude-opus-*` | same as `opus` |
| `s` | `sonnet` | `claude-sonnet-4-5-20250929`, `-4-6`, `claude-sonnet-5` | bare `sonnet` + versioned sonnet |
| `haiku` | `haiku` | `claude-haiku-4-5-20251001` | bare `haiku` + the single versioned haiku |
| `h` | `haiku` | `claude-haiku-*` | same as `haiku` |
| `fable` | `fable` | `claude-fable-5` | bare `fable` + `claude-fable-5` |
| `claude-op` | `claude-opus-*` | *(none — `claude-claude-op…`)* | versioned opus only, no bare alias |
| `opus-4-8` | *(none)* | `claude-opus-4-8` | `claude-opus-4-8` (type the post-`claude-` part) |
| `5` | *(none)* | *(none — no `claude-5…`)* | empty (no cross-family surprise) |

The rule augments rather than replaces: the bare alias remains a valid pick
(it resolves to the latest model in that family), shown alongside the pinned
versions.

## Components

A small, unit-testable helper in each shell owns the candidate assembly and
match rule; the `--model` dispatch case just calls it.

- **bash:** `_claude_model_candidates <cur>` — builds `M` from
  `_CLAUDE_KNOWN_MODELS` plus `claude-*` IDs scraped from the cached `_root_help`
  file, deduplicates, applies the two-prong rule, and prints one candidate per
  line. The `--model)` case feeds its output to `COMPREPLY`.
- **PowerShell:** `_ClaudeModelCandidates -WordToComplete <cur>` — same
  contract, returns the matched model strings; the `'--model'` switch arm wraps
  each in a `CompletionResult`.

Keeping the logic in a named helper (rather than inline in the dispatch switch)
makes the match rule directly testable without simulating a full completion,
and keeps the two shells structurally parallel.

### Alias list change

Add `fable` to the bare-alias portion of the known-models lists — the only
alias-list edit this design requires:

- `claude.bash`: `sonnet opus haiku` → `sonnet opus haiku fable`
- `claude.ps1`: add `'fable',` alongside `'sonnet', 'opus', 'haiku',`

The versioned models stay where they are; `M` is still the concatenation of the
known-models list and the help-scraped IDs. No separate alias constant is
introduced (the match rule does not need one).

## Testing

New cases in both suites (bashunit + Pester), covering **all four families**:

- `opus` → offers bare `opus` **and** `claude-opus-4-8` (multi-version family);
  asserts no `sonnet`/`haiku`/`fable` models leak in.
- `sonnet` → bare `sonnet` + `claude-sonnet-5` + `claude-sonnet-4-5-…`
  (multi-version, including the bare-numbered `claude-sonnet-5`).
- `haiku` → bare `haiku` + `claude-haiku-4-5-20251001` (single-version family —
  the minimal expansion).
- `fable` → bare `fable` + `claude-fable-5`. Doubles as the Q1 regression that
  the bare `fable` alias is offered at all.
- `op` and `h` → expand their families from a partial stem.
- `claude-op` → versioned opus only, **no** bare `opus` (plain-prefix unchanged).
- `opus-4-8` → `claude-opus-4-8` (post-`claude-` fragment matching).
- Empty `cur` → the full known-models set (regression).
- Help-scraped model: with a mock `_root_help` containing a new versioned model
  (e.g. `claude-opus-4-9`), `opus` surfaces it — expansion runs against the
  help-merged set, not just the hardcoded list.

## Non-goals / notes

- **No cache-version bump.** The model list is a script constant and the
  help-cache schema is unchanged; only match logic and one alias entry change.
- **No substring/fuzzy matching.** A bare token like `5` deliberately does not
  match across families (`claude-sonnet-5`, `claude-fable-5`); only the
  `claude-` prefix is treated as optional.
- **Ordering is not significant.** The helper deduplicates but imposes no sort;
  each shell (and readline) may reorder candidates for display. Tests assert
  membership, not order.
- **Case behavior is unchanged.** Each shell keeps its existing convention —
  bash prefix matching is case-sensitive, PowerShell `-like` is
  case-insensitive. This design does not alter that pre-existing difference.
- Both scripts change in lockstep to preserve cross-shell parity.
