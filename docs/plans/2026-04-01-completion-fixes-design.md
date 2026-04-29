# Completion Value & Tooltip Fixes — Design

## Overview

Three issues found during code review of the completion scripts:

1. **`--effort` missing `max`** — Both scripts hardcode `low, medium, high` but the CLI also accepts `max`
2. **`--permission-mode` missing `auto`** — Both scripts hardcode `acceptEdits, bypassPermissions, default, dontAsk, plan` but the CLI also accepts `auto`
3. **PowerShell flag tooltips are empty** — `CompletionResult` tooltip field just repeats the flag name instead of showing the help description

Issues 1 and 2 affect both `claude.bash` and `claude.ps1`. Issue 3 is PowerShell-only.

## Analysis

### Missing enum values (issues 1 & 2)

The completion scripts hardcode known values for `--effort` and `--permission-mode`. These lists were accurate at time of writing but the CLI has since added `max` (effort) and `auto` (permission mode). The fix is straightforward: add the missing values to both scripts, maintaining alphabetical order for `--permission-mode`.

### Flag tooltips (issue 3)

PowerShell's `CompletionResult` has a `ToolTip` field that displays extended help when the user hovers or selects a completion. Currently, flag completions pass the flag name itself as the tooltip (e.g., `--model` shows tooltip `--model`), which adds no information.

The help output already contains descriptions:

```
  --model <model>                Model for session
  -p, --print                    Print response and exit
```

We can parse these descriptions with a regex similar to the existing `_ClaudeParseFlags` pattern, but capturing the trailing description text. The descriptions get cached alongside flags (one file per scope: `_root_flag_descriptions`, `mcp_flag_descriptions`, etc.) and loaded at completion time to populate tooltips.

**Design decisions:**
- Cache format: `--flag<TAB>description` (tab-separated, one per line) — simple, consistent with existing cache format
- Parser: new `_ClaudeParseFlagDescriptions` function, same regex structure as `_ClaudeParseFlags` but capturing the description column
- Lookup: hash table built from cache file at completion time, keyed by flag name
- Fallback: if no description found, use the flag name (preserves current behavior)

## Scope

| Change | `claude.bash` | `claude.ps1` | Tests |
|--------|:---:|:---:|:---:|
| `--effort` add `max` | Yes | Yes | Both |
| `--permission-mode` add `auto` | Yes | Yes | Both |
| Flag description parser | — | Yes | PowerShell |
| Cache flag descriptions | — | Yes | PowerShell |
| Tooltip from descriptions | — | Yes | PowerShell |
