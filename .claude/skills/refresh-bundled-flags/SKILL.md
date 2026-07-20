---
name: refresh-bundled-flags
description: Use when refreshing the inline bundled-flag list in claude.bash and claude.ps1 from upstream Claude Code CHANGELOG entries. Triggers, "refresh bundled flags", "scan the changelog for new flags", or after a Claude Code release. Updates both completion scripts in lockstep, bumps the cache schema version, and runs the parity test.
---

# Refresh Bundled Flags

Use this skill to maintain the inline bundled-flag list in `claude.bash` and `claude.ps1` — flags the completion offers in addition to whatever it parses live from `claude --help` at completion time.

## Why this list exists (read first)

The completion serves a **range of Claude Code versions in the field at once**, not just the version installed on the machine you're editing from. Distro packages, the FreeBSD `misc/claude-code` port, pinned CI images, and Docker bases routinely run releases behind upstream `main` — the FreeBSD port, for instance, regularly trails the latest by a release or two. Each of those installs parses *its own* `claude --help`, which may not list a flag that newer versions document.

So the bundled list is a safety net for the **field**, and the local `claude --help` is a single, usually-newest sample of it. That has four consequences that drive every decision below:

- **`claude --help` is for arg metadata, not inclusion.** Use it to fill in `takes_arg`/`arg_type`/`scope`, never as the test for whether a flag belongs in the list.
- **"It's in my local `--help`" is not grounds to skip bundling.** A flag that newer versions surface in `--help` but older fielded versions hide — e.g. `--bg`/`--background`, which only appeared in `--help` in 2.1.187 — still needs a bundled entry for those older installs.
- **A CHANGELOG "Added `--flag`" is not by itself grounds to bundle.** Bundling only earns its keep when some still-fielded version has the flag *functionally* but omits it from `--help` — the hidden window (`--bg` again). If a flag is visible in `--help` from the version it first appears in, live parsing already surfaces it on every version that has it, and a bundled entry merely offers a nonexistent flag on older versions. Confirm the hidden window before including — don't infer it from changelog phrasing (see Workflow step 5).
- **"It's in my local `--help`" is never grounds to remove.** A flag leaves the list only when it's gone from upstream *entirely* and old enough that no still-fielded version exposes it (see Removal Policy).

The list can't carry every flag that ever existed. The practical horizon is "flags real in versions still plausibly in the field." Where that line falls is a human judgment call, not a mechanical rule — surface it to the user rather than guessing.

## Sources

1. **Primary:** [`anthropics/claude-code/CHANGELOG.md`](https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md). Fetch the latest `main` content.
2. **Secondary cross-reference:** the running `claude --help` and `claude <subcmd> --help`. Use to fill in `takes_arg`/`arg_type`/`scope` — **not** to decide inclusion (see Why this list exists). It's one sample of the field, biased toward the newest release.
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

4. **Skip only genuine duplicates.** Read both `_CLAUDE_EXTRA_FLAGS` (bash) and `$script:ClaudeExtraFlags` (PS); ignore a candidate only when its exact `name`+`scope` already appears. Do **not** skip a candidate just because the local `claude --help` documents it — older fielded versions may not (see Why this list exists). When a CHANGELOG entry reveals a flag was hidden from `--help` until version X, bundle it (and its aliases) so installs older than X still complete it.

5. **Verify the hidden window before including (inclusion gate).** A candidate belongs in the list only if some still-fielded version has it *functionally* but omits it from `--help`. Establish that against the authoritative source — the real `--help` of the introducing version — not the changelog wording:
   ```
   npx --yes @anthropic-ai/claude-code@<introducing-version> --help | grep -- '--the-flag'
   npx --yes @anthropic-ai/claude-code@<version-before>     --help | grep -- '--the-flag'
   ```
   - **Visible in `--help` at (or before) its introducing version** → no hidden window; live parsing already covers it on every version that has it. **Do not bundle.** (Common for user-facing flags announced as "Added `--flag`".)
   - **Functional but absent from `--help`** in some fielded version (the `--bg` pattern — the flag works but isn't listed) → bundle it and its aliases so those installs still complete it.
   - Existing bundled entries are almost all flags hidden from the current `--help` (`--spawn`, `--channels`, `--session-mirror`, …). A candidate that *does* show up in the current `--help` is a strong signal it does **not** need bundling — check before adding.

6. **Classify each new candidate.** Determine the five fields:
   - `scope` — `_root` or subcommand name
   - `name` — `--foo` (one entry per form; short forms are separate entries with the same metadata)
   - `takes_arg` — `none`, `required`, or `optional`. Determine from the placeholder syntax in the CHANGELOG / secondary `--help`:
     - `--foo <value>` → `required`
     - `--foo [value]` → `optional` (the argument may be omitted, so completion still offers other flags after it)
     - `--foo` (no placeholder) → `none`
     - Beware false positives: a flag with no placeholder whose **description** merely starts with `[` (e.g. `--mcp-debug   [DEPRECATED…]`) is `none`, not `optional`. The placeholder always follows the flag after a single space; a 2+ space gap is the description column.
   - `arg_type` — `none`, `file`, `dir`, `choice:a,b,c`, or `unknown`
   - `description` — short string trimmed from the CHANGELOG entry; no embedded tabs

7. **Show diff to user.** Group additions by scope. Allow user edits before applying.

8. **Apply.** In lockstep:
   - Edit `claude.bash`: insert each new entry into `_CLAUDE_EXTRA_FLAGS` as a `$'scope\tname\ttakes_arg\targ_type\tdescription'` line.
   - Edit `claude.ps1`: insert each new entry into `$script:ClaudeExtraFlags` as a `[pscustomobject]@{...}` line.
   - Update both marker comments to the highest CHANGELOG version processed.
   - Bump both `_CLAUDE_CACHE_VERSION` (bash) and `$script:ClaudeCacheVersion` (PS) by 1.
   - Run the parity test: `./tests/bash/run-tests.sh tests/bash/parity_test.bash`.
   - Run both shell suites: `./tests/bash/run-tests.sh` and `./tests/powershell/Invoke-Tests.ps1`.

## Removal Policy (separate opt-in pass)

The default workflow above is **append-only**. Removal is rare and easy to get wrong: a bundled flag is a safety net for older fielded installs, so the bar for removing one is "it no longer exists in any version still plausibly in the field," **not** "the latest `claude --help` now documents it." A flag that merely graduated from hidden to documented must stay — that's the whole point of the list (see Why this list exists). To check for genuine upstream removals:

1. Run the tertiary `strings` source on the running `claude` binary.
2. For each entry in `_CLAUDE_EXTRA_FLAGS`, check whether its `name` appears in the binary strings. Absence from the *latest* binary is necessary but **not** sufficient — confirm a CHANGELOG entry actually removed the flag, and that no still-fielded install (distro, port, pinned image) is recent enough to lack it yet old enough to have once exposed it.
3. Show flagged candidates to the user **with that reasoning**; the user decides whether to remove. Manual removals also require a `_CLAUDE_CACHE_VERSION` bump.

## Editing Conventions

- Bash entries are tab-separated; descriptions cannot contain literal tabs. Use spaces for any necessary whitespace inside descriptions.
- PowerShell entries use `[pscustomobject]@{ ... }` with the property names `Scope`, `Name`, `TakesArg`, `ArgType`, `Description`. `TakesArg` is a string (`'none'`/`'required'`/`'optional'`), matching the bash `takes_arg` column — not a boolean.
- Keep entries grouped by scope; within a scope, sort alphabetically by name for predictable diffs.
- Do **not** edit `_CLAUDE_KNOWN_MODELS` from this skill — it's a separate list maintained alongside Claude Code model releases.
