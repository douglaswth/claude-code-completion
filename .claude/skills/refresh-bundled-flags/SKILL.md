---
name: refresh-bundled-flags
description: Use when refreshing the inline bundled-flag list in claude.bash and claude.ps1 from upstream Claude Code CHANGELOG entries. Triggers, "refresh bundled flags", "scan the changelog for new flags", or after a Claude Code release. Updates both completion scripts in lockstep, bumps the cache schema version when a bundled list changes, and runs the parity test.
---

# Refresh Bundled Flags

Use this skill to maintain the inline bundled lists in `claude.bash` and `claude.ps1` — things the completion offers in addition to whatever it parses live from `claude --help` at completion time. There are two:

- **`_CLAUDE_EXTRA_FLAGS` / `$script:ClaudeExtraFlags`** — flags.
- **`_CLAUDE_EXTRA_SUBCOMMANDS` / `$script:ClaudeExtraSubcommands`** — subcommands the CLI implements but omits from the `Commands:` section of `claude --help`. See **Hidden subcommands** below; a hidden subcommand's flags cannot be bundled without its name, because the merge skips any scope that was never probed.

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

6. **Probe the siblings of every hidden flag you find.** The CHANGELOG is not a reliable index of what is hidden: it announces flags, not their visibility, and it says nothing at all about flags that were never announced or that predate the baseline. When a candidate turns out to be functional-but-hidden, immediately check the rest of its family — the same stem with and without `-file`, singular and `subagent` forms, and any inline/file pairing:

   ```
   for f in --system-prompt-file --append-system-prompt-file \
            --append-subagent-system-prompt --append-subagent-system-prompt-file; do
       claude --help | grep -- "$f"            # visible?
       claude "$f" /nonexistent -p hi          # functional? ("not found" = yes,
   done                                        #   "unknown option" = no)
   ```

   In the 2.1.276 refresh this found three flags the changelog sweep could not: `--append-subagent-system-prompt` (never announced), `--append-system-prompt-file` (2.1.69) and `--system-prompt-file` (1.0.55) — all hidden, all functional, none bundled. Their *inline* counterparts `--system-prompt` and `--append-system-prompt` are in `--help`, which is exactly what makes the gap easy to miss.

   Use a value that will fail fast. A probe like `--append-subagent-system-prompt foo -p hi` consumes its argument and then runs a real session, which costs an API call.

7. **Classify each new candidate.** Determine the five fields:
   - `scope` — `_root` or subcommand name
   - `name` — `--foo` (one entry per form; short forms are separate entries with the same metadata)
   - `takes_arg` — `none`, `required`, or `optional`. Determine from the placeholder syntax in the CHANGELOG / secondary `--help`:
     - `--foo <value>` → `required`
     - `--foo [value]` → `optional` (the argument may be omitted, so completion still offers other flags after it)
     - `--foo` (no placeholder) → `none`
     - Beware false positives: a flag with no placeholder whose **description** merely starts with `[` (e.g. `--mcp-debug   [DEPRECATED…]`) is `none`, not `optional`. The placeholder always follows the flag after a single space; a 2+ space gap is the description column.
   - `arg_type` — `none`, `file`, `dir`, `choice:a,b,c`, or `unknown`
   - `description` — short string trimmed from the CHANGELOG entry; no embedded tabs

8. **Show diff to user.** Group additions by scope. Allow user edits before applying.

9. **Apply.** In lockstep:
   - Edit `claude.bash`: insert each new entry into `_CLAUDE_EXTRA_FLAGS` as a `$'scope\tname\ttakes_arg\targ_type\tdescription'` line, or into `_CLAUDE_EXTRA_SUBCOMMANDS` as a `$'name\tdescription'` line.
   - Edit `claude.ps1`: insert each new entry into `$script:ClaudeExtraFlags` or `$script:ClaudeExtraSubcommands` as a `[pscustomobject]@{...}` line.
   - Update both marker comments to the highest CHANGELOG version processed.
   - Bump both `_CLAUDE_CACHE_VERSION` (bash) and `$script:ClaudeCacheVersion` (PS) by 1 — **only when a bundled list's contents change.** The bump exists to discard caches built from the old list; the marker is a comment the cache never reads. So a sweep that finds nothing to add advances the marker alone and leaves the cache version where it is, as the marker-only advances in `faad225`, `dce4492` (#15) and `674e78f` (#23) did.
   - Run the parity test: `./tests/bash/run-tests.sh tests/bash/parity_test.bash`.
   - Run both shell suites: `./tests/bash/run-tests.sh` and `./tests/powershell/Invoke-Tests.ps1`.

## Hidden subcommands

`claude self-hosted-runner` is real, fully functional and has 39 flags of its own, but it does not appear in the `Commands:` section of `claude --help`. The cache builder learns command names only from that section, so a hidden subcommand is never probed, none of its flags are cached, and nothing about it completes.

**Bundling its flags does not help.** The merge in `_claude_build_cache` skips any scope whose node was never probed:

```bash
flags_file="$build_dir/${scope}_flags"
[[ -f "$flags_file" ]] || continue
```

So the *name* has to be bundled. `_CLAUDE_EXTRA_SUBCOMMANDS` is seeded into `_root_subcommands` before the walk collects its children, after which the node is probed like any other and its flags are parsed and cached by the ordinary machinery — the parsers cope with unusual help layouts (`self-hosted-runner` uses `Connection:` / `Runtime:` / `Debug:` headings rather than `Options:`).

To find candidates, probe a name directly: `claude <name> --help` succeeds for a hidden subcommand and fails for one that does not exist. Note `claude help` is **not** a help command — it runs `help` as a prompt and starts a real session.

Names are added optimistically, as flags are: if one disappears upstream its probe returns nothing, no cache files are written, and only the bare name is offered.

## Removal Policy (separate opt-in pass)

The default workflow above is **append-only**. Removal is rare and easy to get wrong: a bundled flag is a safety net for older fielded installs, so the bar for removing one is "it no longer exists in any version still plausibly in the field," **not** "the latest `claude --help` now documents it." A flag that merely graduated from hidden to documented must stay — that's the whole point of the list (see Why this list exists). To check for genuine upstream removals:

1. Run the tertiary `strings` source on the running `claude` binary.
2. For each entry in `_CLAUDE_EXTRA_FLAGS`, check whether its `name` appears in the binary strings. Absence from the *latest* binary is necessary but **not** sufficient — confirm a CHANGELOG entry actually removed the flag, and that no still-fielded install (distro, port, pinned image) is recent enough to lack it yet old enough to have once exposed it.
3. Show flagged candidates to the user **with that reasoning**; the user decides whether to remove. Manual removals also require a `_CLAUDE_CACHE_VERSION` bump.

## Editing Conventions

- Bash entries are tab-separated; descriptions cannot contain literal tabs. Use spaces for any necessary whitespace inside descriptions.
- PowerShell entries use `[pscustomobject]@{ ... }` with the property names `Scope`, `Name`, `TakesArg`, `ArgType`, `Description`. `TakesArg` is a string (`'none'`/`'required'`/`'optional'`), matching the bash `takes_arg` column — not a boolean.
- Keep entries grouped by scope; within a scope, sort alphabetically by name for predictable diffs.
- `_CLAUDE_EXTRA_SUBCOMMANDS` entries are `name<TAB>description`; the PowerShell mirror uses `[pscustomobject]@{ Name=...; Description=... }`. `tests/bash/parity_test.bash` compares both lists across the two shells, and its extraction is scoped per array — the script holds more than one `[pscustomobject]` array, so an unscoped grep mixes them.
- Do **not** edit `_CLAUDE_KNOWN_MODELS` from this skill — it's a separate list maintained alongside Claude Code model releases.
