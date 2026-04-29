# Bundled Flag Completions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Tab-complete flags that the running `claude --help` doesn't list — both intentionally hidden flags and flags announced in the upstream CHANGELOG that the user's installed version pre-dates.

**Architecture:** Inline bundled-flag data block in each completion script (bash + PowerShell), merged into the existing per-subcommand cache files at cache-build time. Append-only refresh policy. Cache schema version constant invalidates stale caches when the data block changes. Project-level authoring skill drives refreshes; CI parity test guards against drift between scripts.

**Tech Stack:** Bash + bashunit; PowerShell + Pester v5.

**Spec:** `docs/plans/2026-04-29-bundled-flag-completions-design.md`

**Precursor (out of plan scope):** fnrhombus's `fix/completion-values-and-tooltips` branch must land first as a squash commit on `main`, with `Fixes #8` in the body. That branch creates `${scope}_flag_descriptions` cache files on the PowerShell side and wires them to `CompletionResult` tooltips. This plan extends that machinery to the bash side and to bundled flags.

---

## Task 1: Cache schema version (bash)

Adds `_CLAUDE_CACHE_VERSION` constant and folds it into the cache directory key so that bumping the constant invalidates all per-version caches.

**Files:**
- Modify: `claude.bash` (add constant; change `_claude_cache_dir`)
- Test: `tests/bash/cache_test.bash`

- [ ] **Step 1: Write the failing tests**

Append to `tests/bash/cache_test.bash`:

```bash
function test_cache_dir_includes_schema_version_suffix() {
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    # Expected format: <base>/bash/<cli-version>-c<schema-version>
    local last_segment="${cache_dir##*/}"
    assert_matches '^[0-9.]+-c[0-9]+$' "$last_segment"
}

function test_cleanup_old_cache_removes_old_schema_version() {
    _claude_ensure_cache
    local base_dir="$XDG_CACHE_HOME/claude-code-completion/bash"
    # Same CLI version, different schema version
    mkdir -p "$base_dir/1.0.0-c0"
    _claude_cleanup_old_cache
    assert_directory_not_exists "$base_dir/1.0.0-c0"
}

function test_cleanup_old_cache_removes_pre_schema_directories() {
    _claude_ensure_cache
    local base_dir="$XDG_CACHE_HOME/claude-code-completion/bash"
    # Old format with no -cN suffix
    mkdir -p "$base_dir/1.0.0"
    _claude_cleanup_old_cache
    assert_directory_not_exists "$base_dir/1.0.0"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/bash/run-tests.sh tests/bash/cache_test.bash`
Expected: three new tests fail (cache dir doesn't have `-c<N>` suffix yet).

- [ ] **Step 3: Add the constant and fold it into the cache dir**

In `claude.bash`, add the constant immediately above `_claude_version` (around line 16):

```bash
# Cache schema version. Bump on any change to bundled-flag data, sidecar
# file format, or cache layout. Bumps invalidate existing caches for the
# same CLI version.
_CLAUDE_CACHE_VERSION=1
```

Change `_claude_cache_dir` from:

```bash
_claude_cache_dir() {
    local xdg_cache="${XDG_CACHE_HOME:-$HOME/.cache}"
    echo "$xdg_cache/claude-code-completion/bash/$(_claude_version)"
}
```

to:

```bash
_claude_cache_dir() {
    local xdg_cache="${XDG_CACHE_HOME:-$HOME/.cache}"
    echo "$xdg_cache/claude-code-completion/bash/$(_claude_version)-c${_CLAUDE_CACHE_VERSION}"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/bash/run-tests.sh tests/bash/cache_test.bash`
Expected: all `cache_test.bash` tests PASS.

- [ ] **Step 5: Commit**

```bash
git add claude.bash tests/bash/cache_test.bash
git commit -m "feat(bash): add cache schema version to invalidate stale caches"
```

---

## Task 2: Cache schema version (PowerShell)

Parallel of Task 1 for the PowerShell side.

**Files:**
- Modify: `claude.ps1` (add constant; change `_ClaudeCacheDir`)
- Test: `tests/powershell/Cache.Tests.ps1`

- [ ] **Step 1: Write the failing tests**

Append to the `Context '_ClaudeCacheDir'` block in `tests/powershell/Cache.Tests.ps1`:

```powershell
        It 'includes schema version suffix in dir name' {
            $dir = _ClaudeCacheDir
            (Split-Path $dir -Leaf) | Should -Match '^[0-9.]+-c[0-9]+$'
        }
```

Add a new context for cleanup of old schema versions:

```powershell
    Context '_ClaudeCleanupOldCache schema version' {
        It 'removes directories for old schema versions' {
            _ClaudeEnsureCache
            $baseDir = Join-Path (Join-Path $script:TestCacheDir 'claude-code-completion') 'powershell'
            New-Item -ItemType Directory -Path (Join-Path $baseDir '1.0.0-c0') -Force | Out-Null
            _ClaudeCleanupOldCache
            Test-Path (Join-Path $baseDir '1.0.0-c0') | Should -BeFalse
        }

        It 'removes pre-schema directory names' {
            _ClaudeEnsureCache
            $baseDir = Join-Path (Join-Path $script:TestCacheDir 'claude-code-completion') 'powershell'
            New-Item -ItemType Directory -Path (Join-Path $baseDir '1.0.0') -Force | Out-Null
            _ClaudeCleanupOldCache
            Test-Path (Join-Path $baseDir '1.0.0') | Should -BeFalse
        }
    }
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/powershell/Invoke-Tests.ps1 tests/powershell/Cache.Tests.ps1`
Expected: the three new tests fail.

- [ ] **Step 3: Add the constant and fold it into the cache dir**

In `claude.ps1`, add near the top after the leading comments (above `_ClaudeVersion`):

```powershell
# Cache schema version. Bump on any change to bundled-flag data, sidecar
# file format, or cache layout. Bumps invalidate existing caches for the
# same CLI version.
$script:ClaudeCacheVersion = 1
```

Change `_ClaudeCacheDir` from:

```powershell
function global:_ClaudeCacheDir {
    $version = _ClaudeVersion
    $base = _ClaudeCacheBase
    Join-Path (Join-Path (Join-Path $base 'claude-code-completion') 'powershell') $version
}
```

to:

```powershell
function global:_ClaudeCacheDir {
    $version = _ClaudeVersion
    $base = _ClaudeCacheBase
    $key = "$version-c$($script:ClaudeCacheVersion)"
    Join-Path (Join-Path (Join-Path $base 'claude-code-completion') 'powershell') $key
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/powershell/Invoke-Tests.ps1 tests/powershell/Cache.Tests.ps1`
Expected: all `Cache.Tests.ps1` tests PASS.

- [ ] **Step 5: Commit**

```bash
git add claude.ps1 tests/powershell/Cache.Tests.ps1
git commit -m "feat(ps): add cache schema version to invalidate stale caches"
```

---

## Task 3: Bundled flags scaffold (bash)

Adds the empty `_CLAUDE_EXTRA_FLAGS` array, marker comment, and a helper that splits one record into its five fields.

**Files:**
- Modify: `claude.bash`
- Create: `tests/bash/bundled_flags_test.bash`

- [ ] **Step 1: Write the failing tests**

Create `tests/bash/bundled_flags_test.bash`:

```bash
#!/usr/bin/env bash

function set_up_before_script() {
    MOCK_BIN="$(mktemp -d)"
    create_mock_claude "$MOCK_BIN"
    export PATH="$MOCK_BIN:$PATH"
    source_claude_bash
}

function set_up() {
    export XDG_CACHE_HOME="$(mktemp -d)"
}

function tear_down() {
    rm -rf "$XDG_CACHE_HOME"
}

function tear_down_after_script() {
    rm -rf "$MOCK_BIN"
}

function test_extra_flags_array_exists() {
    assert_array_contains "" "${_CLAUDE_EXTRA_FLAGS[@]:-__missing__}"
    # The array should be defined (possibly empty), not unset.
    declare -p _CLAUDE_EXTRA_FLAGS &>/dev/null
    assert_successful_code "$?"
}

function test_parse_extra_flag_record_splits_five_fields() {
    local rec=$'_root\t--foo\t1\tdir\tExample description'
    local scope name takes_arg arg_type desc
    _claude_parse_extra_flag "$rec" scope name takes_arg arg_type desc
    assert_equals "_root" "$scope"
    assert_equals "--foo" "$name"
    assert_equals "1" "$takes_arg"
    assert_equals "dir" "$arg_type"
    assert_equals "Example description" "$desc"
}

function test_parse_extra_flag_handles_choice_arg_type() {
    local rec=$'mcp\t--bar\t1\tchoice:a,b,c\tWith choices'
    local scope name takes_arg arg_type desc
    _claude_parse_extra_flag "$rec" scope name takes_arg arg_type desc
    assert_equals "choice:a,b,c" "$arg_type"
}

function test_parse_extra_flag_handles_takes_arg_zero() {
    local rec=$'_root\t--baz\t0\tnone\tBoolean flag'
    local scope name takes_arg arg_type desc
    _claude_parse_extra_flag "$rec" scope name takes_arg arg_type desc
    assert_equals "0" "$takes_arg"
    assert_equals "none" "$arg_type"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/bash/run-tests.sh tests/bash/bundled_flags_test.bash`
Expected: tests fail (`_CLAUDE_EXTRA_FLAGS` unset, `_claude_parse_extra_flag` not defined).

- [ ] **Step 3: Add the array, marker, and parser to `claude.bash`**

Insert immediately below the `_CLAUDE_CACHE_VERSION` constant:

```bash
# Bundled flags last extended through CHANGELOG version: 0.0.0
# (The skill at .claude/skills/refresh-bundled-flags/ updates this marker.)
#
# Format: scope<TAB>name<TAB>takes_arg<TAB>arg_type<TAB>description
#   scope     — "_root" or a subcommand name (mcp, plugin, agents, …)
#   name      — flag form (e.g. --foo). Short forms are separate entries.
#   takes_arg — 0 or 1
#   arg_type  — none | file | dir | choice:a,b,c | unknown
#   description — short text; no embedded tabs
_CLAUDE_EXTRA_FLAGS=()

# Split a tab-separated extra-flag record into its fields.
# Usage: _claude_parse_extra_flag "$record" scope name takes_arg arg_type desc
_claude_parse_extra_flag() {
    local record="$1"
    local -n _scope="$2" _name="$3" _ta="$4" _at="$5" _desc="$6"
    IFS=$'\t' read -r _scope _name _ta _at _desc <<< "$record"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/bash/run-tests.sh tests/bash/bundled_flags_test.bash`
Expected: all four tests PASS.

- [ ] **Step 5: Commit**

```bash
git add claude.bash tests/bash/bundled_flags_test.bash
git commit -m "feat(bash): scaffold bundled flag data structure and parser"
```

---

## Task 4: Bundled flags scaffold (PowerShell)

Parallel of Task 3.

**Files:**
- Modify: `claude.ps1`
- Create: `tests/powershell/BundledFlags.Tests.ps1`

- [ ] **Step 1: Write the failing tests**

Create `tests/powershell/BundledFlags.Tests.ps1`:

```powershell
BeforeAll {
    . $PSScriptRoot/TestHelper.ps1
    Initialize-ClaudeTests
    New-DefaultMockClaude
}

Describe 'Bundled flag data structure' {
    It 'defines the ClaudeExtraFlags array' {
        $script:ClaudeExtraFlags | Should -Not -BeNull
    }

    It 'has expected schema (Scope, Name, TakesArg, ArgType, Description)' {
        $sample = [pscustomobject]@{
            Scope='_root'; Name='--foo'; TakesArg=$true; ArgType='dir'; Description='X'
        }
        ($sample.PSObject.Properties.Name | Sort-Object) -join ',' |
            Should -Be 'ArgType,Description,Name,Scope,TakesArg'
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/powershell/Invoke-Tests.ps1 tests/powershell/BundledFlags.Tests.ps1`
Expected: first test fails (`$script:ClaudeExtraFlags` not defined).

- [ ] **Step 3: Add the array and marker to `claude.ps1`**

Insert immediately below the `$script:ClaudeCacheVersion` line:

```powershell
# Bundled flags last extended through CHANGELOG version: 0.0.0
# (The skill at .claude/skills/refresh-bundled-flags/ updates this marker.)
#
# Each entry has fields: Scope, Name, TakesArg, ArgType, Description
#   Scope       — '_root' or a subcommand name (mcp, plugin, agents, …)
#   Name        — flag form (e.g. --foo). Short forms are separate entries.
#   TakesArg    — $true or $false
#   ArgType     — 'none' | 'file' | 'dir' | 'choice:a,b,c' | 'unknown'
#   Description — short text
$script:ClaudeExtraFlags = @()
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/powershell/Invoke-Tests.ps1 tests/powershell/BundledFlags.Tests.ps1`
Expected: both tests PASS.

- [ ] **Step 5: Commit**

```bash
git add claude.ps1 tests/powershell/BundledFlags.Tests.ps1
git commit -m "feat(ps): scaffold bundled flag data structure"
```

---

## Task 5: Cache merge for flags, flags_with_args, descriptions (bash)

Modifies `_claude_build_cache` to iterate `_CLAUDE_EXTRA_FLAGS` and append entries to `${scope}_flags`, `${scope}_flags_with_args`, and `${scope}_flag_descriptions`. Skips entries already present in `--help`-derived rows. Also creates the `${scope}_flag_descriptions` file from `--help` output (the bash side counterpart of fnrhombus's PS parser).

**Files:**
- Modify: `claude.bash`
- Modify: `tests/bash/bundled_flags_test.bash`

- [ ] **Step 1: Write the failing tests**

Add to `tests/bash/bundled_flags_test.bash`:

```bash
function _setup_extra_flag() {
    # Inject one bundled flag entry for this test only.
    _CLAUDE_EXTRA_FLAGS=("$1")
}

function test_bundled_root_flag_appears_in_root_flags() {
    _setup_extra_flag $'_root\t--bundled-root\t0\tnone\tA bundled root flag'
    _claude_build_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_file_contains "$cache_dir/_root_flags" "--bundled-root"
}

function test_bundled_subcommand_flag_appears_in_subcommand_flags_only() {
    _setup_extra_flag $'mcp\t--bundled-mcp\t0\tnone\tA bundled mcp flag'
    _claude_build_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_file_contains "$cache_dir/mcp_flags" "--bundled-mcp"
    assert_file_not_contains "$cache_dir/_root_flags" "--bundled-mcp"
}

function test_bundled_flag_with_takes_arg_appears_in_flags_with_args() {
    _setup_extra_flag $'_root\t--bundled-arg\t1\tdir\tTakes a dir'
    _claude_build_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_file_contains "$cache_dir/_root_flags_with_args" "--bundled-arg"
}

function test_bundled_flag_without_arg_not_in_flags_with_args() {
    _setup_extra_flag $'_root\t--bundled-bool\t0\tnone\tBoolean'
    _claude_build_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_file_not_contains "$cache_dir/_root_flags_with_args" "--bundled-bool"
}

function test_bundled_flag_dedupes_against_help_derived_flag() {
    # --model is already in the mock --help output
    _setup_extra_flag $'_root\t--model\t1\tunknown\tStale bundled entry'
    _claude_build_cache
    local cache_dir count
    cache_dir="$(_claude_cache_dir)"
    count=$(grep -cFx -- "--model" "$cache_dir/_root_flags")
    assert_equals "1" "$count"
}

function test_bundled_description_appears_in_flag_descriptions() {
    _setup_extra_flag $'_root\t--bundled-desc\t0\tnone\tDescriptive text'
    _claude_build_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_file_contains "$cache_dir/_root_flag_descriptions" "--bundled-desc"
    assert_file_contains "$cache_dir/_root_flag_descriptions" "Descriptive text"
}

function test_help_derived_flag_descriptions_present() {
    _claude_build_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_file_contains "$cache_dir/_root_flag_descriptions" "--model"
    assert_file_contains "$cache_dir/_root_flag_descriptions" "Model for session"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/bash/run-tests.sh tests/bash/bundled_flags_test.bash`
Expected: the new tests fail (no description parser, no merge logic).

- [ ] **Step 3: Add a help-line description parser to `claude.bash`**

Insert after `_claude_parse_flags_with_args`:

```bash
_claude_parse_flag_descriptions() {
    # Parse "<flag><TAB><description>" lines from help output on stdin.
    # Two whitespace gap separates the flag block (with optional <value>
    # / [value] argument placeholder) from the description. Mirrors
    # fnrhombus's PowerShell parser at claude.ps1's _ClaudeParseFlagDescriptions.
    local line short long rest desc
    while IFS= read -r line; do
        if [[ "$line" =~ ^[[:space:]]+(-[a-zA-Z]),?[[:space:]]+(--[a-zA-Z][-a-zA-Z]*)(.*)$ ]]; then
            short="${BASH_REMATCH[1]}"
            long="${BASH_REMATCH[2]}"
            rest="${BASH_REMATCH[3]}"
            if [[ "$rest" =~ [[:space:]][[:space:]]+([^[:space:]].*)$ ]]; then
                desc="${BASH_REMATCH[1]}"
                printf '%s\t%s\n' "$short" "$desc"
                printf '%s\t%s\n' "$long" "$desc"
            fi
        elif [[ "$line" =~ ^[[:space:]]+(--[a-zA-Z][-a-zA-Z]*)(.*)$ ]]; then
            long="${BASH_REMATCH[1]}"
            rest="${BASH_REMATCH[2]}"
            if [[ "$rest" =~ [[:space:]][[:space:]]+([^[:space:]].*)$ ]]; then
                desc="${BASH_REMATCH[1]}"
                printf '%s\t%s\n' "$long" "$desc"
            fi
        fi
    done
}
```

- [ ] **Step 4: Modify `_claude_build_cache` to write `_flag_descriptions` and merge bundled entries**

Find the existing root-level write block in `_claude_build_cache`:

```bash
echo "$help_output" > "$cache_dir/_root_help"
echo "$help_output" | _claude_parse_flags > "$cache_dir/_root_flags"
echo "$help_output" | _claude_parse_flags_with_args > "$cache_dir/_root_flags_with_args"
echo "$help_output" | _claude_parse_subcommands > "$cache_dir/_root_subcommands"
```

Add a description-parser line and a merge-bundled call:

```bash
echo "$help_output" > "$cache_dir/_root_help"
echo "$help_output" | _claude_parse_flags > "$cache_dir/_root_flags"
echo "$help_output" | _claude_parse_flags_with_args > "$cache_dir/_root_flags_with_args"
echo "$help_output" | _claude_parse_flag_descriptions > "$cache_dir/_root_flag_descriptions"
echo "$help_output" | _claude_parse_subcommands > "$cache_dir/_root_subcommands"
```

In the per-subcommand loop, parallel addition:

```bash
echo "$sub_help" | _claude_parse_flags > "$cache_dir/${subcmd}_flags"
echo "$sub_help" | _claude_parse_flags_with_args > "$cache_dir/${subcmd}_flags_with_args"
echo "$sub_help" | _claude_parse_flag_descriptions > "$cache_dir/${subcmd}_flag_descriptions"
echo "$sub_help" | _claude_parse_subcommands > "$cache_dir/${subcmd}_subcommands"
```

Then, immediately before the `_claude_cleanup_old_cache` call at the end of `_claude_build_cache`, add:

```bash
# Merge bundled flags into the cache files (skip ones already present from --help).
local rec scope name takes_arg arg_type desc
for rec in "${_CLAUDE_EXTRA_FLAGS[@]}"; do
    [[ -z "$rec" ]] && continue
    _claude_parse_extra_flag "$rec" scope name takes_arg arg_type desc
    local flags_file="$cache_dir/${scope}_flags"
    [[ -f "$flags_file" ]] || continue
    if grep -qx -- "$name" "$flags_file"; then
        continue  # --help wins on overlap
    fi
    echo "$name" >> "$flags_file"
    if [[ "$takes_arg" == "1" ]]; then
        echo "$name" >> "$cache_dir/${scope}_flags_with_args"
    fi
    printf '%s\t%s\n' "$name" "$desc" >> "$cache_dir/${scope}_flag_descriptions"
done
```

- [ ] **Step 5: Run tests to verify they pass**

Run: `./tests/bash/run-tests.sh tests/bash/bundled_flags_test.bash tests/bash/cache_test.bash`
Expected: all tests PASS.

- [ ] **Step 6: Run the full bash suite to catch regressions**

Run: `./tests/bash/run-tests.sh`
Expected: all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add claude.bash tests/bash/bundled_flags_test.bash
git commit -m "feat(bash): merge bundled flags into per-scope cache files"
```

---

## Task 6: Cache merge (PowerShell)

Parallel of Task 5. The PowerShell side already has `_ClaudeParseFlagDescriptions` and `_flag_descriptions` files (from the precursor); this task adds bundled-flag merging into those files plus `_flags` and `_flags_with_args`.

**Files:**
- Modify: `claude.ps1`
- Modify: `tests/powershell/BundledFlags.Tests.ps1`

- [ ] **Step 1: Write the failing tests**

Append to `tests/powershell/BundledFlags.Tests.ps1`:

```powershell
Describe 'Bundled flag cache merging' {
    BeforeEach {
        $script:TestCacheDir = Join-Path $TestDrive "cache-$([guid]::NewGuid())"
        $env:XDG_CACHE_HOME = $script:TestCacheDir
        # Snapshot and clear the bundled list for each test
        $script:OriginalExtraFlags = $script:ClaudeExtraFlags
        $script:ClaudeExtraFlags = @()
    }

    AfterEach {
        $env:XDG_CACHE_HOME = $null
        $script:ClaudeExtraFlags = $script:OriginalExtraFlags
    }

    It 'adds a bundled root flag to _root_flags' {
        $script:ClaudeExtraFlags = @(
            [pscustomobject]@{ Scope='_root'; Name='--bundled-root'; TakesArg=$false; ArgType='none'; Description='A bundled root flag' }
        )
        _ClaudeBuildCache
        $cacheDir = _ClaudeCacheDir
        Get-Content (Join-Path $cacheDir '_root_flags') | Should -Contain '--bundled-root'
    }

    It 'scopes bundled subcommand flag to its subcommand only' {
        $script:ClaudeExtraFlags = @(
            [pscustomobject]@{ Scope='mcp'; Name='--bundled-mcp'; TakesArg=$false; ArgType='none'; Description='A bundled mcp flag' }
        )
        _ClaudeBuildCache
        $cacheDir = _ClaudeCacheDir
        Get-Content (Join-Path $cacheDir 'mcp_flags') | Should -Contain '--bundled-mcp'
        Get-Content (Join-Path $cacheDir '_root_flags') | Should -Not -Contain '--bundled-mcp'
    }

    It 'puts takes_arg=true bundled flag into _flags_with_args' {
        $script:ClaudeExtraFlags = @(
            [pscustomobject]@{ Scope='_root'; Name='--bundled-arg'; TakesArg=$true; ArgType='dir'; Description='Takes a dir' }
        )
        _ClaudeBuildCache
        $cacheDir = _ClaudeCacheDir
        Get-Content (Join-Path $cacheDir '_root_flags_with_args') | Should -Contain '--bundled-arg'
    }

    It 'dedupes bundled flag against --help-derived entry' {
        $script:ClaudeExtraFlags = @(
            [pscustomobject]@{ Scope='_root'; Name='--model'; TakesArg=$true; ArgType='unknown'; Description='Stale bundled entry' }
        )
        _ClaudeBuildCache
        $cacheDir = _ClaudeCacheDir
        $occurrences = (Get-Content (Join-Path $cacheDir '_root_flags') | Where-Object { $_ -eq '--model' }).Count
        $occurrences | Should -Be 1
    }

    It 'records bundled description in _flag_descriptions' {
        $script:ClaudeExtraFlags = @(
            [pscustomobject]@{ Scope='_root'; Name='--bundled-desc'; TakesArg=$false; ArgType='none'; Description='Descriptive text' }
        )
        _ClaudeBuildCache
        $cacheDir = _ClaudeCacheDir
        $content = Get-Content (Join-Path $cacheDir '_root_flag_descriptions') -Raw
        $content | Should -Match '--bundled-desc'
        $content | Should -Match 'Descriptive text'
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/powershell/Invoke-Tests.ps1 tests/powershell/BundledFlags.Tests.ps1`
Expected: the merge tests fail.

- [ ] **Step 3: Modify `_ClaudeBuildCache` to merge bundled entries**

Just before the trailing `_ClaudeCleanupOldCache` call at the end of `_ClaudeBuildCache`, insert:

```powershell
    # Merge bundled flags into the cache files (skip ones already present from --help).
    foreach ($entry in $script:ClaudeExtraFlags) {
        if (-not $entry) { continue }
        $flagsFile = Join-Path $cacheDir "$($entry.Scope)_flags"
        if (-not (Test-Path $flagsFile)) { continue }
        $existing = @(Get-Content $flagsFile)
        if ($existing -contains $entry.Name) { continue }
        Add-Content -Path $flagsFile -Value $entry.Name
        if ($entry.TakesArg) {
            Add-Content -Path (Join-Path $cacheDir "$($entry.Scope)_flags_with_args") -Value $entry.Name
        }
        Add-Content -Path (Join-Path $cacheDir "$($entry.Scope)_flag_descriptions") -Value "$($entry.Name)`t$($entry.Description)"
    }
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `./tests/powershell/Invoke-Tests.ps1 tests/powershell/BundledFlags.Tests.ps1`
Expected: all tests PASS.

- [ ] **Step 5: Run the full PowerShell suite to catch regressions**

Run: `./tests/powershell/Invoke-Tests.ps1`
Expected: all tests PASS.

- [ ] **Step 6: Commit**

```bash
git add claude.ps1 tests/powershell/BundledFlags.Tests.ps1
git commit -m "feat(ps): merge bundled flags into per-scope cache files"
```

---

## Task 7: Sidecar arg_types file and lookup (bash)

Writes a `${scope}_flag_arg_types` sidecar at cache build, and consults it in `_claude_complete_flag_arg`'s default case so bundled flags with known arg-types get the right value completion.

**Files:**
- Modify: `claude.bash`
- Modify: `tests/bash/bundled_flags_test.bash` and/or `tests/bash/flag_args_test.bash`

- [ ] **Step 1: Write the failing tests**

Append to `tests/bash/bundled_flags_test.bash`:

```bash
function test_bundled_arg_type_dir_completes_directories() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    mkdir "$tmpdir/subdir"
    touch "$tmpdir/file.txt"
    cd "$tmpdir" || return
    _setup_extra_flag $'_root\t--my-dir\t1\tdir\tDir flag'
    local result
    result="$(simulate_completion "claude --my-dir ")"
    cd / && rm -rf "$tmpdir"
    assert_contains "subdir" "$result"
    assert_not_contains "file.txt" "$result"
}

function test_bundled_arg_type_choice_completes_options() {
    _setup_extra_flag $'_root\t--my-choice\t1\tchoice:alpha,beta,gamma\tChoice flag'
    local result
    result="$(simulate_completion "claude --my-choice ")"
    assert_contains "alpha" "$result"
    assert_contains "beta" "$result"
    assert_contains "gamma" "$result"
}

function test_bundled_arg_type_none_yields_no_value_completion() {
    _setup_extra_flag $'_root\t--my-bool\t0\tnone\tBoolean flag'
    # When --my-bool isn't in flags_with_args, the completion should not invoke value completion.
    # Easiest assertion: the cache's flags_with_args file does not list it.
    _claude_build_cache
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    assert_file_not_contains "$cache_dir/_root_flags_with_args" "--my-bool"
}

function test_bundled_arg_type_unknown_falls_back_to_file_completion() {
    local tmpdir
    tmpdir="$(mktemp -d)"
    touch "$tmpdir/somefile"
    cd "$tmpdir" || return
    _setup_extra_flag $'_root\t--my-mystery\t1\tunknown\tMystery flag'
    local result
    result="$(simulate_completion "claude --my-mystery ")"
    cd / && rm -rf "$tmpdir"
    assert_contains "somefile" "$result"
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/bash/run-tests.sh tests/bash/bundled_flags_test.bash`
Expected: the dir/choice tests fail (no sidecar lookup yet); the `none` test passes once the takes_arg=0 entry is correctly skipped from `flags_with_args` (already implemented in Task 5); the `unknown` test passes because the existing default falls back to file completion.

- [ ] **Step 3: Write the sidecar at cache build**

In `_claude_build_cache`'s bundled-merge loop (added in Task 5), after the `printf` for description, append:

```bash
    printf '%s\t%s\n' "$name" "$arg_type" >> "$cache_dir/${scope}_flag_arg_types"
```

- [ ] **Step 4: Add an arg-type lookup helper**

Insert above `_claude_complete_flag_arg`:

```bash
_claude_lookup_arg_type() {
    # Look up the bundled arg_type for a flag in the given scope. Returns
    # empty string if no entry. Pure bash; no external commands.
    local flag="$1" scope="$2"
    local cache_dir
    cache_dir="$(_claude_cache_dir)"
    local file="$cache_dir/${scope}_flag_arg_types"
    [[ -f "$file" ]] || return
    local f t
    while IFS=$'\t' read -r f t; do
        if [[ "$f" == "$flag" ]]; then
            echo "$t"
            return
        fi
    done < "$file"
}
```

- [ ] **Step 5: Update `_claude_complete_flag_arg` signature and default case**

Change the function to accept a third `scope` argument and add bundled-arg-type handling in the default case:

```bash
_claude_complete_flag_arg() {
    local flag="$1"
    local cur="$2"
    local scope="${3:-_root}"

    case "$flag" in
        --model)
            # ... unchanged ...
            ;;
        # ... other existing arms unchanged ...
        *)
            # Consult bundled arg_type sidecar before falling back to file completion.
            local arg_type
            arg_type="$(_claude_lookup_arg_type "$flag" "$scope")"
            case "$arg_type" in
                dir)
                    COMPREPLY=( $(compgen -d -- "$cur") )
                    ;;
                choice:*)
                    local choices="${arg_type#choice:}"
                    COMPREPLY=( $(compgen -W "${choices//,/ }" -- "$cur") )
                    ;;
                none)
                    COMPREPLY=()
                    ;;
                file|unknown|"")
                    COMPREPLY=( $(compgen -f -- "$cur") )
                    ;;
            esac
            ;;
    esac
}
```

- [ ] **Step 6: Pass scope from `_claude` to `_claude_complete_flag_arg`**

In `_claude`, find the existing call:

```bash
if [[ -f "$flags_with_args_file" ]] && grep -qx -- "$prev" "$flags_with_args_file"; then
    _claude_complete_flag_arg "$prev" "$cur"
    return
fi
```

Change the call to pass scope:

```bash
local _scope="_root"
[[ -n "$subcmd" ]] && _scope="$subcmd"
if [[ -f "$flags_with_args_file" ]] && grep -qx -- "$prev" "$flags_with_args_file"; then
    _claude_complete_flag_arg "$prev" "$cur" "$_scope"
    return
fi
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `./tests/bash/run-tests.sh tests/bash/bundled_flags_test.bash tests/bash/flag_args_test.bash`
Expected: all PASS.

- [ ] **Step 8: Run the full bash suite**

Run: `./tests/bash/run-tests.sh`
Expected: all tests PASS.

- [ ] **Step 9: Commit**

```bash
git add claude.bash tests/bash/bundled_flags_test.bash
git commit -m "feat(bash): wire bundled flag arg-type sidecar to value completion"
```

---

## Task 8: Sidecar arg_types and lookup (PowerShell)

Parallel of Task 7.

**Files:**
- Modify: `claude.ps1`
- Modify: `tests/powershell/BundledFlags.Tests.ps1`

- [ ] **Step 1: Write the failing tests**

Append to `tests/powershell/BundledFlags.Tests.ps1`:

```powershell
Describe 'Bundled arg-type completion' {
    BeforeEach {
        $script:TestCacheDir = Join-Path $TestDrive "cache-$([guid]::NewGuid())"
        $env:XDG_CACHE_HOME = $script:TestCacheDir
        $script:OriginalExtraFlags = $script:ClaudeExtraFlags
        $script:ClaudeExtraFlags = @()
    }

    AfterEach {
        $env:XDG_CACHE_HOME = $null
        $script:ClaudeExtraFlags = $script:OriginalExtraFlags
    }

    It 'completes choices for arg_type=choice:a,b,c' {
        $script:ClaudeExtraFlags = @(
            [pscustomobject]@{ Scope='_root'; Name='--my-choice'; TakesArg=$true; ArgType='choice:alpha,beta,gamma'; Description='Choice flag' }
        )
        _ClaudeBuildCache
        $results = Get-CompletionText 'claude --my-choice '
        $results | Should -Contain 'alpha'
        $results | Should -Contain 'beta'
        $results | Should -Contain 'gamma'
    }

    It 'sidecar file written for bundled arg_type entries' {
        $script:ClaudeExtraFlags = @(
            [pscustomobject]@{ Scope='_root'; Name='--my-dir'; TakesArg=$true; ArgType='dir'; Description='Dir flag' }
        )
        _ClaudeBuildCache
        $cacheDir = _ClaudeCacheDir
        $content = Get-Content (Join-Path $cacheDir '_root_flag_arg_types') -Raw
        $content | Should -Match '--my-dir\tdir'
    }
}
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `./tests/powershell/Invoke-Tests.ps1 tests/powershell/BundledFlags.Tests.ps1`
Expected: new tests fail.

- [ ] **Step 3: Write the sidecar at cache build**

In `_ClaudeBuildCache`'s bundled-merge loop (Task 6), after the description `Add-Content`, append:

```powershell
        Add-Content -Path (Join-Path $cacheDir "$($entry.Scope)_flag_arg_types") -Value "$($entry.Name)`t$($entry.ArgType)"
```

- [ ] **Step 4: Add a lookup helper and call it from `_ClaudeCompleteFlagArg`**

Insert above `_ClaudeCompleteFlagArg`:

```powershell
function global:_ClaudeLookupArgType {
    param([string]$Flag, [string]$Scope)
    $cacheDir = _ClaudeCacheDir
    $file = Join-Path $cacheDir "${Scope}_flag_arg_types"
    if (-not (Test-Path $file)) { return $null }
    foreach ($line in Get-Content $file) {
        $parts = $line -split "`t", 2
        if ($parts.Count -eq 2 -and $parts[0] -eq $Flag) {
            return $parts[1]
        }
    }
    return $null
}
```

In `_ClaudeCompleteFlagArg`, add a `Scope` parameter and consult the lookup in the `default` arm. Find the function signature and change to:

```powershell
function global:_ClaudeCompleteFlagArg {
    param(
        [string]$Flag,
        [string]$WordToComplete,
        [string]$Scope = '_root'
    )
    switch ($Flag) {
        # ... existing arms unchanged ...
        default {
            $argType = _ClaudeLookupArgType -Flag $Flag -Scope $Scope
            switch -Wildcard ($argType) {
                'dir' {
                    Get-ChildItem -Directory -Filter "$WordToComplete*" -ErrorAction SilentlyContinue |
                        ForEach-Object {
                            [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ProviderItem', $_.FullName)
                        }
                }
                'choice:*' {
                    $choices = $argType.Substring('choice:'.Length) -split ','
                    $choices | Where-Object { $_ -like "$WordToComplete*" } | ForEach-Object {
                        [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
                    }
                }
                'none' { }
                default {
                    Get-ChildItem -Filter "$WordToComplete*" -ErrorAction SilentlyContinue |
                        ForEach-Object {
                            [System.Management.Automation.CompletionResult]::new($_.Name, $_.Name, 'ProviderItem', $_.FullName)
                        }
                }
            }
        }
    }
}
```

- [ ] **Step 5: Pass scope from `_ClaudeComplete` to `_ClaudeCompleteFlagArg`**

Find the call site in `_ClaudeComplete` (the function that dispatches when `$prev` is in `flags_with_args`) and change `_ClaudeCompleteFlagArg -Flag $prev -WordToComplete $WordToComplete` to:

```powershell
$scopeArg = if ($subcmd) { $subcmd } else { '_root' }
_ClaudeCompleteFlagArg -Flag $prev -WordToComplete $WordToComplete -Scope $scopeArg
```

- [ ] **Step 6: Run tests to verify they pass**

Run: `./tests/powershell/Invoke-Tests.ps1 tests/powershell/BundledFlags.Tests.ps1`
Expected: all PASS.

- [ ] **Step 7: Run the full PowerShell suite**

Run: `./tests/powershell/Invoke-Tests.ps1`
Expected: all tests PASS.

- [ ] **Step 8: Commit**

```bash
git add claude.ps1 tests/powershell/BundledFlags.Tests.ps1
git commit -m "feat(ps): wire bundled flag arg-type sidecar to value completion"
```

---

## Task 9: Bash flag description display

Wires `_claude_format_descriptions` into the bash flag-completion path so flag completions render as `--flag    # description`. Benefits both `--help`-derived and bundled descriptions. PowerShell already does this via fnrhombus's precursor (descriptions become `CompletionResult` tooltips).

**Files:**
- Modify: `claude.bash`
- Modify: `tests/bash/completion_test.bash`

- [ ] **Step 1: Write the failing test**

Append to `tests/bash/completion_test.bash`:

```bash
function test_flag_completion_renders_descriptions_when_multiple_match() {
    # When multiple flags match, descriptions render via the Cobra/kubectl
    # `--flag    # description` formatter. Single-match case strips the
    # description for clean insertion (covered by existing single-match tests).
    local result
    result="$(simulate_completion "claude --")"
    # Several long flags match "--" in the mock; --model has description
    # "Model for session". The formatter renders "--model    # Model for session".
    assert_contains "Model for session" "$result"
}
```

- [ ] **Step 2: Run test to verify it fails**

Run: `./tests/bash/run-tests.sh tests/bash/completion_test.bash`
Expected: new test fails.

- [ ] **Step 3: Add a helper that builds candidate entries for the formatter**

Insert above the `_claude` function:

```bash
_claude_flag_candidates_with_descriptions() {
    # Build a "flag<TAB>desc" array (printed to stdout, one per line) for the
    # flags in $1 that match prefix $2. Looks up descriptions in $3.
    local flags_file="$1"
    local prefix="$2"
    local desc_file="$3"

    declare -A descs
    if [[ -f "$desc_file" ]]; then
        local f d
        while IFS=$'\t' read -r f d; do
            descs["$f"]="$d"
        done < "$desc_file"
    fi

    local flag
    while IFS= read -r flag; do
        [[ -z "$flag" ]] && continue
        [[ "$flag" == "$prefix"* ]] || continue
        if [[ -n "${descs[$flag]:-}" ]]; then
            printf '%s\t%s\n' "$flag" "${descs[$flag]}"
        else
            echo "$flag"
        fi
    done < "$flags_file"
}
```

- [ ] **Step 4: Replace the flag completion paths in `_claude`**

Find the two flag-completion paths in `_claude`. Subcommand path:

```bash
if [[ -f "$cache_dir/${subcmd}_flags" ]]; then
    COMPREPLY=( $(compgen -W "$(cat "$cache_dir/${subcmd}_flags")" -- "$cur") )
fi
```

Replace with:

```bash
if [[ -f "$cache_dir/${subcmd}_flags" ]]; then
    local candidates=()
    while IFS= read -r line; do
        candidates+=("$line")
    done < <(_claude_flag_candidates_with_descriptions \
        "$cache_dir/${subcmd}_flags" "$cur" \
        "$cache_dir/${subcmd}_flag_descriptions")
    if (( ${#candidates[@]} == 1 )) || [[ ${COMP_TYPE:-9} == @(37|42) ]]; then
        # Single match or menu-complete: strip description so insertion is clean.
        COMPREPLY=()
        local c
        for c in "${candidates[@]}"; do
            COMPREPLY+=("${c%%$'\t'*}")
        done
    else
        _claude_format_descriptions candidates
    fi
fi
```

Root path uses `_root_flags`/`_root_flag_descriptions` — make the parallel change for that block.

- [ ] **Step 5: Run tests to verify they pass**

Run: `./tests/bash/run-tests.sh tests/bash/completion_test.bash`
Expected: PASS.

- [ ] **Step 6: Run the full bash suite**

Run: `./tests/bash/run-tests.sh`
Expected: all tests PASS.

- [ ] **Step 7: Commit**

```bash
git add claude.bash tests/bash/completion_test.bash
git commit -m "feat(bash): show flag descriptions in tab-completion output"
```

---

## Task 10: Cross-shell parity test

Adds a parity check that asserts `claude.bash` and `claude.ps1` carry the same bundled-flag set, the same marker version, and the same cache-version constant.

**Files:**
- Create: `tests/bash/parity_test.bash`

- [ ] **Step 1: Write the failing tests**

Create `tests/bash/parity_test.bash`:

```bash
#!/usr/bin/env bash
# Cross-shell parity: assert claude.bash and claude.ps1 carry the same
# bundled-flag set, marker version, and cache-version constant.

function set_up_before_script() {
    BASH_SCRIPT="$PROJECT_ROOT/claude.bash"
    PS_SCRIPT="$PROJECT_ROOT/claude.ps1"
}

# Source claude.bash in a subshell and dump the array — gives native
# access to the data without parsing.
extract_bash_extra_flags() {
    (
        source "$BASH_SCRIPT" >/dev/null 2>&1
        printf '%s\n' "${_CLAUDE_EXTRA_FLAGS[@]}"
    ) | sort
}

# Parse [pscustomobject]@{...} lines from the PowerShell script and emit
# normalized tab-separated records matching the bash array format
# (scope<TAB>name<TAB>takes_arg<TAB>arg_type<TAB>description).
extract_ps_extra_flags() {
    grep -E '^\s+\[pscustomobject\]@\{' "$PS_SCRIPT" | while IFS= read -r line; do
        local scope name ta arg_type desc
        scope=$(echo "$line" | sed -n "s/.*Scope='\([^']*\)'.*/\1/p")
        name=$(echo "$line"  | sed -n "s/.*Name='\([^']*\)'.*/\1/p")
        if [[ "$line" == *'TakesArg=$true'* ]]; then ta=1; else ta=0; fi
        arg_type=$(echo "$line" | sed -n "s/.*ArgType='\([^']*\)'.*/\1/p")
        desc=$(echo "$line"     | sed -n "s/.*Description='\([^']*\)'.*/\1/p")
        printf '%s\t%s\t%s\t%s\t%s\n' "$scope" "$name" "$ta" "$arg_type" "$desc"
    done | sort
}

function test_bundled_flag_sets_match() {
    local bash_out ps_out
    bash_out="$(extract_bash_extra_flags)"
    ps_out="$(extract_ps_extra_flags)"
    assert_equals "$bash_out" "$ps_out"
}

function test_marker_versions_match() {
    local bash_marker ps_marker
    bash_marker="$(grep -o 'last extended through CHANGELOG version: [0-9.][0-9.]*' "$BASH_SCRIPT" | head -1)"
    ps_marker="$(grep -o 'last extended through CHANGELOG version: [0-9.][0-9.]*' "$PS_SCRIPT" | head -1)"
    assert_equals "$bash_marker" "$ps_marker"
}

function test_cache_version_constants_match() {
    local bash_v ps_v
    bash_v="$(grep -E '^_CLAUDE_CACHE_VERSION=' "$BASH_SCRIPT" | head -1 | sed 's/.*=//')"
    ps_v="$(grep -E '^\$script:ClaudeCacheVersion = ' "$PS_SCRIPT" | head -1 | sed 's/.*= //')"
    assert_equals "$bash_v" "$ps_v"
}
```

- [ ] **Step 2: Run tests to verify they pass on the current state**

The two scripts should already be in parity (both with empty bundled lists, same marker `0.0.0`, same cache version `1`). If a test fails, the data structures introduced in Tasks 3/4 don't agree — fix the discrepancy in those scripts before adding more entries.

Run: `./tests/bash/run-tests.sh tests/bash/parity_test.bash`
Expected: all three tests PASS.

- [ ] **Step 3: Verify the test detects deliberate drift**

Temporarily add an entry to `_CLAUDE_EXTRA_FLAGS` in `claude.bash` (without adding to `claude.ps1`).

Run: `./tests/bash/run-tests.sh tests/bash/parity_test.bash`
Expected: `test_bundled_flag_sets_match` FAILS.

Revert the temporary edit.

Run: `./tests/bash/run-tests.sh tests/bash/parity_test.bash`
Expected: all tests PASS again.

- [ ] **Step 4: Commit**

```bash
git add tests/bash/parity_test.bash
git commit -m "test: add cross-shell parity check for bundled flags"
```

---

## Task 11: Refresh skill

Adds the project-level skill that drives bundled-flag refreshes from upstream CHANGELOG entries.

**Files:**
- Create: `.claude/skills/refresh-bundled-flags/SKILL.md`

- [ ] **Step 1: Write the skill**

Create `.claude/skills/refresh-bundled-flags/SKILL.md`:

````markdown
---
name: refresh-bundled-flags
description: Use when refreshing the inline bundled-flag list in claude.bash and claude.ps1 from upstream Claude Code CHANGELOG entries. Triggers: "refresh bundled flags", "scan the changelog for new flags", or after a Claude Code release. Updates both completion scripts in lockstep, bumps the cache schema version, and runs the parity test.
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
````

- [ ] **Step 2: Verify the skill file is well-formed**

Run: `head -3 .claude/skills/refresh-bundled-flags/SKILL.md`
Expected: shows the frontmatter `---` opener and `name:` field.

- [ ] **Step 3: Commit**

```bash
git add .claude/skills/refresh-bundled-flags/SKILL.md
git commit -m "feat: add refresh-bundled-flags authoring skill"
```

---

## Done criteria

- All eleven tasks committed in order.
- `./tests/bash/run-tests.sh` and `./tests/powershell/Invoke-Tests.ps1` both pass.
- Parity test passes — bundled lists, marker version, and cache version all match between scripts.
- The refresh skill is invocable when working in this repo (`.claude/skills/refresh-bundled-flags/SKILL.md` exists with valid frontmatter).
- The CHANGELOG itself has not yet been scanned to populate entries — that's a separate first invocation of the refresh skill, performed by the user when ready.
