# Optional-argument flag completion

**Date:** 2026-06-05
**Branch:** `optional-arg-flags`
**Status:** Implemented (bash 108 tests, PowerShell 112 tests, all passing;
newly-added code fully covered in both shells; pre-existing coverage gaps left
out of scope)

## Problem

After an optional-argument flag such as `--remote-control [name]`, no other
completions work:

```
claude --remote-control --<TAB>   → (nothing)
claude --remote-control <TAB>     → (nothing useful)
```

The completer treats the flag's *following word* as the flag's argument and
returns early, never offering other flags or subcommands.

### Root cause

Both scripts conflate two argument styles that `claude --help` distinguishes:

- `--flag <value>` — argument **required**
- `--flag [value]` — argument **optional**

The flag-with-args detectors match either bracket style:

- `claude.bash:116,119` — regex `...[<\[]`
- `claude.ps1:144,147` — regex `...[<\[]`

Any flag landing in the `_flags_with_args` sidecar triggers the dispatch
branch (`claude.bash:540-552`, `claude.ps1:465-477`) that completes the
flag's argument and `return`s. For a *required*-arg flag this is correct; for
an *optional*-arg flag it is wrong, because the next token may legitimately be
another flag.

### Affected flags

Optional-arg (`[value]`) flags observed in `claude --help`:

| Flag                         | Source on FreeBSD 2.1.110 | Source on local 2.1.165 |
| ---------------------------- | ------------------------- | ----------------------- |
| `-d, --debug [filter]`       | dynamic (`--help`)        | dynamic                 |
| `--from-pr [value]`          | dynamic                   | dynamic                 |
| `-r, --resume [value]`       | dynamic                   | dynamic                 |
| `-w, --worktree [name]`      | dynamic                   | dynamic                 |
| `--prompt-suggestions [value]` | absent (flag not present) | dynamic               |
| `--remote-control [name]`    | **hidden → bundled only** | dynamic                 |

`--resume` already has special-case argument completion (session list,
`claude.bash:416`); for it the change only adds the "dash → flags"
fall-through.

### Two independent sources, so two fixes

`--remote-control` is **hidden** from `--help` on FreeBSD 2.1.110 — only
`--remote-control-session-name-prefix <prefix>` is documented. There it is
reachable solely through the bundled `_CLAUDE_EXTRA_FLAGS` table. Therefore:

1. The **dynamic `--help` parser** must distinguish `[value]` from `<value>`
   (fixes debug/from-pr/resume/worktree/prompt-suggestions, and
   `--remote-control` on versions that document it).
2. The **bundled table** must also carry optionality (fixes `--remote-control`
   on versions that hide it, and any *future* hidden optional-arg flag — the
   bundled table exists precisely to cover hidden flags, so this can't be a
   one-flag special case).

### Latent parser bug surfaced

`--mcp-debug` takes **no** argument, but its description starts with
`[DEPRECATED. Use --debug instead]`. The existing detector matches
`flag` + `[[:space:]]+` + bracket, so it already misclassifies `--mcp-debug`
as taking an argument on both versions. Commander.js separates an argument
*placeholder* from the flag by a **single** space (`--flag <value>` /
`--flag [value]`) and separates the *description* by a 2+ space gap. Tightening
both detectors to require a single space before the bracket fixes the
`--mcp-debug` false positive and prevents the new optional detector from
inheriting it.

## Desired behavior

Decision (confirmed with user): **"dash → flags, else arg."** After an
*optional*-arg flag, branch on the current word:

| Current word (`cur`)              | Behavior                                  |
| --------------------------------- | ----------------------------------------- |
| empty                             | complete the flag's argument (arg type)   |
| exactly `-`                       | offer flags / subcommands (fall through)  |
| starts with `-` (e.g. `--`, `-r`) | offer flags / subcommands (fall through)  |
| anything else (e.g. `foo`)        | complete the flag's argument              |

Precise rule: **fall through to flags iff `cur` is non-empty and starts with
`-`** (covers both a bare `-` and `--…`); otherwise complete the argument. A
bare `-` is the user starting to type a flag, not a literal argument value.

*Required*-arg flags are unchanged: always complete the argument.

```
claude --remote-control --<TAB>   → --flags / subcommands
claude --remote-control -<TAB>    → flags (short -x and long --xx)
claude --remote-control fo<TAB>   → files matching fo* (arg type = unknown → file fallback)
claude --remote-control <TAB>     → files (arg type)
```

## Design

### New sidecar + additive optionality lookup

Mirror the existing "one parser per sidecar file" pattern. Add a narrower
detector that emits only *optional*-arg flags into a new per-scope sidecar
`{scope}_flags_with_optional_args`. The existing `{scope}_flags_with_args`
keeps listing **all** arg-taking flags, so the "does this flag take an arg"
check is unchanged; optionality is a second, additive lookup.

Dispatch becomes:

```
if prev is in flags_with_args:
    if prev is in flags_with_optional_args AND cur is non-empty AND cur starts with '-':
        fall through to normal flag/subcommand completion
    else:
        complete the flag's argument and return
```

### Single-space placeholder rule

Both detectors require the placeholder bracket to follow the flag by exactly
one space:

- required detector: `flag` + single space + `<`
- optional detector: `flag` + single space + `[`

This excludes descriptions that merely begin with `[` (`--mcp-debug`).

### Tri-state `takes_arg` in the bundled table

Optionality is **semantically part of** "does this flag take an argument?" — so
`takes_arg` becomes tri-state rather than gaining a sibling field. Values:

- `none` — flag takes no argument
- `required` — argument required (`<value>`)
- `optional` — argument optional (`[value]`)

PowerShell's `TakesArg` moves from `$true`/`$false` to the same three string
literals, so the two bundled tables stay byte-identical in the compared fields
and the parity extractor can drop its `TakesArg=$true → 1` mapping and read the
string directly. `--remote-control`'s bundled row becomes `optional`; all other
existing rows map `1 → required`, `0 → none`.

Merge logic:

- `takes_arg != none` → append to `{scope}_flags_with_args`
- `takes_arg == optional` → also append to `{scope}_flags_with_optional_args`

### refresh-bundled-flags skill

In-scope for this branch: the skill that regenerates the bundled tables must
emit `optional` for `[value]` placeholders and `required` for `<value>`, so the
new field stays correct the next time a hidden flag is added. Without this the
field goes stale and the generality is lost.

### Cache version bump

The cache layout gains a new sidecar file. Old caches lack it; the dispatch
reads it under an existence guard, so a stale cache degrades gracefully to the
old (buggy) behavior rather than erroring. Bump the cache-version constant
(`_CLAUDE_CACHE_VERSION`, `$script:ClaudeCacheVersion`, both `3 → 4`) so caches
rebuild and the fix takes effect immediately. The parity test asserts these two
constants match.

## Implementation steps

### `claude.bash`

1. Bump `_CLAUDE_CACHE_VERSION` `3` → `4` (line 19).
2. Tighten `_claude_parse_flags_with_args()` to a single-space placeholder
   (`[[:space:]][<\[]`) so `--mcp-debug` is no longer misclassified.
3. Add `_claude_parse_flags_with_optional_args()` — single space + `\[` only.
4. In `_claude_build_cache`, write the new sidecar for root (after line 184)
   and per subcommand (after line 195).
5. Convert `_CLAUDE_EXTRA_FLAGS` `takes_arg` column to `none/required/optional`;
   set `--remote-control` to `optional`. Update the format comment (lines
   24-29).
6. Update the bundled-merge loop (lines 211-213): `!= none` → flags_with_args,
   `== optional` → optional sidecar.
7. Dispatch (lines 540-552): add the optional + non-empty + dash-prefix
   fall-through.

### `claude.ps1`

8. Bump `$script:ClaudeCacheVersion` `3` → `4` (line 7).
9. Tighten `_ClaudeParseFlagsWithArgs` to single-space; add
   `_ClaudeParseFlagsWithOptionalArgs` (single space + `\[`).
10. In `_ClaudeBuildCache`, write the new sidecar for root (after line 94) and
    per subcommand (after line 106).
11. Convert `$script:ClaudeExtraFlags` `TakesArg` to the three string literals;
    set `--remote-control` to `'optional'`. Update the field comment (lines
    12-16).
12. Update the bundled-merge loop (lines 119-121): `-ne 'none'` →
    flags_with_args, `-eq 'optional'` → optional sidecar.
13. Dispatch (lines 465-477): add the optional + non-empty + dash-prefix
    fall-through.

### Tests

14. `parity_test.bash:27`: read `takes_arg` string from both tables directly
    (drop boolean mapping). Cache constants bumped in lockstep.
15. `bundled_flags_test.bash` / `BundledFlags.Tests.ps1`: update expected
    `takes_arg`/`TakesArg` values to the strings; assert `--remote-control` is
    `optional`.
16. bash (`tests/bash/`): in `flag_args_test.bash` / `help_parsing_test.bash` —
    optional detector emits `[value]` flags (and the short forms) to the new
    sidecar; `<value>` flags do not; `--mcp-debug` is in neither; dispatch
    falls through on `--remote-control --…` and bare `--remote-control -…`,
    completes the arg on `--remote-control foo…`, and completes the arg on
    empty `--remote-control `.
17. PowerShell (`tests/powershell/`): mirror in `FlagArgs.Tests.ps1` /
    `HelpParsing.Tests.ps1`.

### Docs / skill

18. `refresh-bundled-flags` skill: emit `optional`/`required`/`none`; bump its
    own references to the cache-schema version if it tracks one.
19. Update `CLAUDE.md` / `README.md` only if they document flag-argument
    completion behavior (likely no change needed).

### Verification

20. Run both suites; walk the coverage review for both shells per `CLAUDE.md`.
