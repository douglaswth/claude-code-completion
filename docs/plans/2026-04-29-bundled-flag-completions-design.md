# Bundled Flag Completions — Design

## Goal

Tab-complete flags that the running `claude --help` doesn't list — both intentionally hidden flags and flags that the upstream CHANGELOG has announced but `--help` hasn't caught up to (or that the user's installed version pre-dates the documentation, e.g. lagging FreeBSD ports).

Today the bash and PowerShell completion scripts derive their entire flag set by parsing `claude --help` (and `claude <subcmd> --help`) at cache-build time. There is no mechanism to surface anything that `--help` doesn't already say.

## Precursor: land fnrhombus's branch

This design assumes [fnrhombus's `fix/completion-values-and-tooltips` branch][branch] has landed. That branch contributes three changes:

- `--effort` value list adds `max`.
- `--permission-mode` value list adds `auto`.
- PowerShell flag completion tooltips populated from `--help` descriptions, via new `${scope}_flag_descriptions` cache files and a `_ClaudeParseFlagDescriptions` parser.

[branch]: https://github.com/fnrhombus/claude-code-completion/tree/fix/completion-values-and-tooltips

The branch will be squashed onto `main` as a single commit authored by `fnrhombus <2511516+fnrhombus@users.noreply.github.com>`, with `Fixes #8` in the body to auto-close the tracking issue. The bundled-flags work in this design extends fnrhombus's PowerShell description plumbing to the bash side and to the bundled list.

## Approach overview

A small inline data block in each completion script (`claude.bash`, `claude.ps1`) lists "extra known flags" with metadata. At cache-build time, these entries are merged into the existing per-subcommand cache files. Existing completion code reads the merged cache and is largely unchanged. A project-level authoring skill drives refreshes; a CI parity test guards against drift between the two scripts.

## Data shape

Five fields per flag entry:

- `scope` — `_root` (matches existing cache file naming) or a subcommand name (`mcp`, `plugin`, `agents`, …).
- `name` — `--foo`. Short forms (`-x`) are separate entries with the same metadata.
- `takes_arg` — `0` or `1`.
- `arg_type` — one of `none`, `file`, `dir`, `choice:a,b,c`, `unknown`. Default → file completion via the existing `_claude_complete_flag_arg` fallback.
- `description` — short string.

### Bash representation

An indexed array of tab-separated records:

```bash
# bundled flags last extended through CHANGELOG version: X.Y.Z
_CLAUDE_EXTRA_FLAGS=(
    $'_root\t--example-flag\t1\tdir\tExample undocumented flag'
    $'mcp\t--example-mcp-flag\t0\tnone\tExample mcp-only flag'
)
```

### PowerShell representation

An array of `[pscustomobject]` records mirroring the same fields:

```powershell
# bundled flags last extended through CHANGELOG version: X.Y.Z
$script:ClaudeExtraFlags = @(
    [pscustomobject]@{ Scope='_root'; Name='--example-flag';     TakesArg=$true;  ArgType='dir';  Description='Example undocumented flag' }
    [pscustomobject]@{ Scope='mcp';   Name='--example-mcp-flag'; TakesArg=$false; ArgType='none'; Description='Example mcp-only flag' }
)
```

## Cache integration

At cache-build time, for each entry with scope `S`:

- Append `name` to `${S}_flags`.
- If `takes_arg=1`, also to `${S}_flags_with_args`.
- Description appended to `${S}_flag_descriptions` (the same file fnrhombus's branch creates; bundled rows live alongside `--help`-derived rows).
- Arg-type appended to a new sidecar `${S}_flag_arg_types` (`--name<TAB>arg_type` lines).

Sidecar files are kept separate from the existing cache files so existing parsers stay untouched. Tab-separated records are used throughout; descriptions must not contain literal tabs.

### Dedup

If a bundled flag's name already appears in `${S}_flags` from `--help` parsing, the bundled rows are skipped for that user's cache (`--help` wins). The inline source list is not edited — the bundled entry simply doesn't make it into the cache for users whose `claude` already documents the flag.

### Arg-type lookup

`_claude_complete_flag_arg` (bash) and `_ClaudeCompleteFlagArg` (PowerShell) consult `${S}_flag_arg_types` *after* their hardcoded cases (`--model`, `--permission-mode`, `--resume`, …). Existing custom logic continues to win for the flags it knows; new bundled entries with known arg-types get the appropriate completion behavior; unknown ones fall back to file completion (the existing default).

### Description display

- **Bash:** `_claude` builds a `name<TAB>desc` array from `${S}_flag_descriptions` for the current scope and passes it to the existing `_claude_format_descriptions` helper at `claude.bash:174-212`. The Cobra/kubectl `# desc` rendering already handles formatting, truncation, and `compopt -o nosort`.
- **PowerShell:** already wired by fnrhombus's branch — descriptions used as `CompletionResult` tooltip.

## Cache invalidation

Cache directory key extends from `${CLI_VERSION}` to `${CLI_VERSION}-c${CACHE_VERSION}`, where `_CLAUDE_CACHE_VERSION` (bash) and `$script:ClaudeCacheVersion` (PowerShell) are integer constants in the scripts. The cleanup logic that already prunes non-current cache directories picks up stale schema-version directories for free.

The cache version is bumped on any change that affects what the cache holds — new bundled flag entries, edits to existing entries, new sidecar files, column changes. The refresh skill bumps it automatically; manual edits require humans to bump it. Failure mode if a bump is forgotten: users with a pre-existing cache for the same `claude` version don't see new bundled entries until their `claude` upgrades. Soft failure that self-heals.

The parity test asserts both scripts hold the same integer for their respective cache-version constants.

## Refresh policy

The bundled flag list is **append-only**. Refreshes add entries; they never remove ones that have graduated into upstream `--help`. A flag documented upstream may still be undocumented on a lagging install (FreeBSD ports, etc.); keeping the bundled entry costs nothing for the upstream user (deduped at cache build) and preserves completion for the lagging user.

There is no per-entry version-introduced field and no version filtering. Both directions of filtering were rejected:

- Forward filtering (hide flags newer than running CLI) is unwanted — same logic that lets `claude-opus-4-7` work on the FreeBSD port for models works for flags. The user accepts that some suggested flags may not work on their installed version.
- Backward filtering would compete with append-only.

A single comment in each script — `# bundled flags last extended through CHANGELOG version: X.Y.Z` — tracks the resume point for the refresh skill. Not load-bearing at runtime.

Removal is allowed only in extraordinary cases (upstream removes a flag entirely from the binary). The refresh skill exposes this as a separate opt-in pass — driven by the tertiary `strings` source — that flags bundled entries no longer present in the binary and asks for human confirmation. The default refresh workflow (the seven steps below) only adds entries.

The hardcoded models list (`_CLAUDE_KNOWN_MODELS`) follows the same append-only, unfiltered policy it has today — no change needed.

## Authoring skill

A project-level skill at `.claude/skills/refresh-bundled-flags/SKILL.md` encodes the refresh workflow. It is auto-discovered when working in this repo.

### Sources

- **Primary:** upstream `anthropics/claude-code/CHANGELOG.md` (latest `main`).
- **Secondary cross-reference:** current `claude --help` and `claude <subcmd> --help` of the running install — used to fill in `takes_arg` / `arg_type` for flags that became documented after introduction (their `--foo <value>` syntax in `--help` reveals it). Not used for filtering.
- **Tertiary, opt-in:** `strings <claude binary> | grep -E '^--[a-z]'` for flags that work but were never mentioned in the CHANGELOG. Noisy; used only when the user explicitly asks for binary-derived candidates.

### Workflow

1. **Determine baseline.** Read the marker comment. If absent (first run), treat baseline as "everything before the earliest CHANGELOG entry."
2. **Pull sources** (primary + secondary; tertiary on explicit request).
3. **Extract candidate flags.** For CHANGELOG sections between baseline and HEAD, regex `--[a-z][-a-z]*`. Capture the surrounding sentence as a description seed and the `## X.Y.Z` heading for traceability.
4. **Skip already-bundled flags.** Append-only — entries already in the data block are left alone, even if upstream `--help` now lists them.
5. **Classify each candidate.** Determine the five fields from CHANGELOG context and secondary cross-reference.
6. **Show diff to user.** Proposed additions per script, grouped by scope. User can edit metadata before applying.
7. **Apply.** In lockstep:
   - Edit `claude.bash` and `claude.ps1` to insert new entries.
   - Update both marker comments to the new latest CHANGELOG version.
   - Bump both cache-version constants.
   - Run the parity test.
   - Run both shells' test suites.

## Tests

- **Parity test** (CI): extracts the bundled flag set + metadata + cache version + marker version from both scripts and asserts they match.
- **Per-shell tests:**
  - Bundled flag appears in completion when not in mock `--help`.
  - Bundled flag is deduped when present in mock `--help`.
  - Bundled flag scoped to a subcommand only appears for that subcommand.
  - Bundled flag's `arg_type` drives `_claude_complete_flag_arg` / `_ClaudeCompleteFlagArg` behavior.
  - Description display renders for bundled and `--help`-derived flags alike.
  - Cache version bump invalidates a previously-built cache directory.

## Scope

In scope:

- Inline bundled flag data block in each completion script.
- Cache integration via new sidecar files (`${S}_flag_arg_types`) and existing `${S}_flag_descriptions`.
- Bash flag description display through `_claude_format_descriptions`.
- Cache schema version constant and key extension.
- Project-level refresh skill.
- Parity test in CI.

Out of scope:

- Per-entry version-introduced fields and version filtering.
- Automatic removal of bundled flags.
- Network fetch of CHANGELOG at runtime — refreshes happen at completion-script-release time, driven by the skill.
- Generator script that auto-builds the embedded data block from a separate source file — manual edits via the skill, with the parity test as the safety net.
