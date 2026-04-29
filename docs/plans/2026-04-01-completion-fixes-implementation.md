# Completion Value & Tooltip Fixes — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Add missing `--effort max` and `--permission-mode auto` completion values to both scripts, and show help descriptions as flag completion tooltips in PowerShell.

**Architecture:** Modify existing `claude.bash`, `claude.ps1`, and their test suites. Add a new `_ClaudeParseFlagDescriptions` function and corresponding cache files for PowerShell tooltip support.

**Tech Stack:** Bash, PowerShell 5.1+/7+, bashunit, Pester 5

**Reference:** [Design doc](2026-04-01-completion-fixes-design.md)

---

### Task 1: Add `max` to `--effort` completion values

**Files:**
- Modify: `claude.ps1`
- Modify: `claude.bash`
- Modify: `tests/powershell/FlagArgs.Tests.ps1`
- Modify: `tests/bash/flag_args_test.bash`

**TDD:**

1. Add `$results | Should -Contain 'max'` to the `'completes effort levels'` test in `FlagArgs.Tests.ps1`
2. Add `assert_contains "max" "$result"` to `test_effort_completes_levels` in `flag_args_test.bash`
3. Verify both tests fail
4. In `claude.ps1` `_ClaudeCompleteFlagArg`, change `@('low', 'medium', 'high')` to `@('low', 'medium', 'high', 'max')`
5. In `claude.bash` `_claude_complete_flag_arg`, change `"low medium high"` to `"low medium high max"`
6. Verify both tests pass

```bash
git add claude.ps1 claude.bash tests/powershell/FlagArgs.Tests.ps1 tests/bash/flag_args_test.bash
git commit -m "feat: add 'max' to --effort completion values"
```

---

### Task 2: Add `auto` to `--permission-mode` completion values

**Files:**
- Modify: `claude.ps1`
- Modify: `claude.bash`
- Modify: `tests/powershell/FlagArgs.Tests.ps1`
- Modify: `tests/bash/flag_args_test.bash`

**TDD:**

1. Add `$results | Should -Contain 'auto'` to `'completes permission mode choices'` in `FlagArgs.Tests.ps1`
2. Add `assert_contains "auto" "$result"` to `test_permission_mode_completes_choices` in `flag_args_test.bash`
3. Update mock help text in `flag_args_test.bash` `set_up_before_script` to include `"auto"` in permission-mode choices
4. Verify both tests fail
5. In `claude.ps1` `_ClaudeCompleteFlagArg`, change `@('acceptEdits', 'bypassPermissions', 'default', 'dontAsk', 'plan')` to `@('acceptEdits', 'auto', 'bypassPermissions', 'default', 'dontAsk', 'plan')`
6. In `claude.bash` `_claude_complete_flag_arg`, change `"acceptEdits bypassPermissions default dontAsk plan"` to `"acceptEdits auto bypassPermissions default dontAsk plan"`
7. Verify both tests pass

```bash
git add claude.ps1 claude.bash tests/powershell/FlagArgs.Tests.ps1 tests/bash/flag_args_test.bash
git commit -m "feat: add 'auto' to --permission-mode completion values"
```

---

### Task 3: Add flag description parser for tooltips

**Files:**
- Modify: `claude.ps1`
- Modify: `tests/powershell/HelpParsing.Tests.ps1`

**TDD:**

1. Add a `_ClaudeParseFlagDescriptions` context to `HelpParsing.Tests.ps1` that verifies:
   - Short+long flag lines produce two entries (one per flag form) with the description
   - Long-only flag lines produce one entry with the description
   - Non-flag lines are skipped
2. Verify tests fail
3. Add `_ClaudeParseFlagDescriptions` function to `claude.ps1` — parses help lines and outputs `flag<TAB>description` pairs
4. Verify tests pass

```bash
git add claude.ps1 tests/powershell/HelpParsing.Tests.ps1
git commit -m "feat(ps): add flag description parser for tooltips"
```

---

### Task 4: Cache flag descriptions for tooltip lookup

**Files:**
- Modify: `claude.ps1`
- Modify: `tests/powershell/Cache.Tests.ps1`

**TDD:**

1. Add tests to the `_ClaudeBuildCache` context in `Cache.Tests.ps1`:
   - `_root_flag_descriptions` file is created
   - File contains description for `--model`
   - Subcommand description files are created (e.g., `auth_flag_descriptions`)
2. Verify tests fail
3. In `_ClaudeBuildCache`, add `Set-Content` calls for `_root_flag_descriptions` and `${subcmd}_flag_descriptions`
4. Verify tests pass

```bash
git add claude.ps1 tests/powershell/Cache.Tests.ps1
git commit -m "feat(ps): cache flag descriptions for tooltip lookup"
```

---

### Task 5: Show help descriptions as flag completion tooltips

**Files:**
- Modify: `claude.ps1`
- Modify: `tests/powershell/Completion.Tests.ps1`

**TDD:**

1. Add tests to `Completion.Tests.ps1`:
   - Flag completions have tooltips that differ from the flag name
   - Tooltip contains the help description text
2. Verify tests fail
3. In `_ClaudeComplete`, update both top-level and subcommand flag completion blocks to load descriptions from cache and use as tooltips
4. Verify tests pass

```bash
git add claude.ps1 tests/powershell/Completion.Tests.ps1
git commit -m "feat(ps): show help descriptions as flag completion tooltips"
```

---

### Task 6: Update existing design doc

**Files:**
- Modify: `docs/plans/2026-03-04-powershell-completion-design.md`

Update the completion scenarios table:
- `--effort` row: `low, medium, high` → `low, medium, high, max`
- `--permission-mode` row: add note about `auto`

```bash
git add docs/plans/2026-03-04-powershell-completion-design.md
git commit -m "docs: update design doc with current CLI completion values"
```
