---
name: refresh-bundled-flags
description: Use when refreshing the inline bundled-flag list in claude.bash and claude.ps1 from upstream Claude Code CHANGELOG entries. Triggers, "refresh bundled flags", "scan the changelog for new flags", or after a Claude Code release. Updates both completion scripts in lockstep, bumps the cache schema version, and runs the parity test.
---

# Refresh Bundled Flags

Use this skill to add bundled-flag entries for flags that appear in upstream Claude Code CHANGELOG entries but not in the running `claude --help`. This keeps tab-completion useful for hidden flags and for users on lagging installs (e.g. FreeBSD ports).

## Sources

1. **Primary:** [`anthropics/claude-code/CHANGELOG.md`](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md). Fetch the latest `main` content.
2. **Secondary cross-reference:** the running `claude --help` and `claude <subcmd> --help`. Use to fill in `takes_arg`/`arg_type` for flags now documented in the running install.
3. **Tertiary, opt-in:** `strings $(readlink -f "$(command -v claude)") | grep -E '^--[a-z]'`. Only run when the user explicitly asks for binary-derived candidates — output is noisy.

## Workflow

1. **Determine baseline.** Read the marker comment from `claude.bash`:
   ```
   # Bundled flags last extended through CHANGELOG version: X.Y.Z
   ```
   If absent (first run), treat baseline as "everything before the earliest CHANGELOG entry."

2. **Pull sources.** Fetch primary; gather secondary from the running install. Skip tertiary unless explicitly requested.

3. **Extract candidates.** For each CHANGELOG section between baseline and HEAD:
   - Note the heading version (`## X.Y.Z`).
   - Regex: `--[a-z][-a-z]*` over the entry body. Capture the surrounding sentence as a description seed.
   - Identify scope from context (e.g. "added `--foo` to the `mcp` command" → scope `mcp`).

4. **Skip already-bundled flags.** Read both `_CLAUDE_EXTRA_FLAGS` (bash) and `$script:ClaudeExtraFlags` (PS); ignore any candidate whose `name`+`scope` already appears.

5. **Classify each new candidate.** Determine the five fields:
   - `scope` — `_root` or subcommand name
   - `name` — `--foo` (one entry per form; short forms are separate entries with the same metadata)
   - `takes_arg` — `0` or `1`. From CHANGELOG syntax (`--foo <value>`) or from secondary `--help`
   - `arg_type` — `none`, `file`, `dir`, `choice:a,b,c`, or `unknown`
   - `description` — short string trimmed from the CHANGELOG entry; no embedded tabs

6. **Show diff to user.** Group additions by scope. Allow user edits before applying.

7. **Apply.** In lockstep:
   - Edit `claude.bash`: insert each new entry into `_CLAUDE_EXTRA_FLAGS` as a `$'scope\tname\ttakes_arg\targ_type\tdescription'` line.
   - Edit `claude.ps1`: insert each new entry into `$script:ClaudeExtraFlags` as a `[pscustomobject]@{...}` line.
   - Update both marker comments to the highest CHANGELOG version processed.
   - Bump both `_CLAUDE_CACHE_VERSION` (bash) and `$script:ClaudeCacheVersion` (PS) by 1.
   - Run the parity test: `./tests/bash/run-tests.sh tests/bash/parity_test.bash`.
   - Run both shell suites: `./tests/bash/run-tests.sh` and `./tests/powershell/Invoke-Tests.ps1`.

## Removal Policy (separate opt-in pass)

The default workflow above is **append-only**. To check for upstream removals (rare):

1. Run the tertiary `strings` source on the running `claude` binary.
2. For each entry in `_CLAUDE_EXTRA_FLAGS`, check whether its `name` appears in the binary strings.
3. Show flagged candidates to the user; the user decides whether to remove. Manual removals also require a `_CLAUDE_CACHE_VERSION` bump.

## Editing Conventions

- Bash entries are tab-separated; descriptions cannot contain literal tabs. Use spaces for any necessary whitespace inside descriptions.
- PowerShell entries use `[pscustomobject]@{ ... }` with the property names `Scope`, `Name`, `TakesArg`, `ArgType`, `Description`.
- Keep entries grouped by scope; within a scope, sort alphabetically by name for predictable diffs.
- Do **not** edit `_CLAUDE_KNOWN_MODELS` from this skill — it's a separate list maintained alongside Claude Code model releases.
