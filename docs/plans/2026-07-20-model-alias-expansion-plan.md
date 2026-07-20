# `--model` Alias-Expansion Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `--model` completion offer the `fable` alias and let any alias stem (opus/sonnet/haiku/fable, or a prefix of one) also complete to that family's `claude-<family>-*` versioned models.

**Architecture:** Treat the leading `claude-` as optional when matching: offer a model `C` when `C` starts with the typed word `cur` **or** with `"claude-" + cur`. A small per-shell helper builds the candidate set (hardcoded known models + `claude-*` IDs scraped from cached `--help`, deduped) and applies the rule; the `--model` dispatch calls it.

**Tech Stack:** POSIX-ish bash 4+ (`claude.bash`), PowerShell 5.1+/7 (`claude.ps1`), bashunit, Pester v5.

## Global Constraints

- Both scripts change **in lockstep** to preserve cross-shell parity.
- **Match rule (verbatim):** offer `C` iff `C` starts with `cur` OR `C` starts with `"claude-" + cur`.
- **No `_CLAUDE_CACHE_VERSION` / `$script:ClaudeCacheVersion` bump** — the model list is a script constant and the help-cache schema is unchanged.
- **No substring/fuzzy matching** — only the `claude-` prefix is optional.
- Commits must be **GPG-signed**: run `unlock-gpg -c && git commit …` as one sandbox-disabled command. If `unlock-gpg -c` fails, stop and ask the user to unlock; never commit unsigned.
- Design reference: `docs/plans/2026-07-20-model-alias-expansion-design.md`.

---

### Task 1: Add the bare `fable` alias to both known-model lists

Adds the missing `fable` alias so it is offered like `opus`/`sonnet`/`haiku`. Pure prefix matching still applies at this point (expansion arrives in Tasks 2–3).

**Files:**
- Modify: `claude.bash:461-472` (`_CLAUDE_KNOWN_MODELS`)
- Modify: `claude.ps1:291-303` (`$script:_ClaudeKnownModels`)
- Test: `tests/bash/flag_args_test.bash`
- Test: `tests/powershell/FlagArgs.Tests.ps1`

**Interfaces:**
- Consumes: nothing.
- Produces: bare string `fable` present in both known-model lists.

- [ ] **Step 1: Write the failing bash test**

Append to `tests/bash/flag_args_test.bash`:

```bash
function test_model_completes_bare_fable_alias() {
    # Bare `fable` alias (like opus/sonnet/haiku) — the stem "fabl" matches the
    # bare alias but not claude-fable-5 under plain prefix matching.
    local result
    result="$(simulate_completion "claude --model fabl")"
    assert_contains "fable" "$result"
}
```

- [ ] **Step 2: Run it to verify it fails**

Run: `./tests/bash/run-tests.sh`
Expected: FAIL on `test_model_completes_bare_fable_alias` — `fabl` matches nothing (no bare `fable` yet), so the result is empty.

- [ ] **Step 3: Add `fable` to the bash known-model list**

In `claude.bash`, change the first line of `_CLAUDE_KNOWN_MODELS`:

```bash
_CLAUDE_KNOWN_MODELS=(
    sonnet opus haiku fable
    claude-fable-5
```

- [ ] **Step 4: Run it to verify it passes**

Run: `./tests/bash/run-tests.sh`
Expected: PASS, full suite green.

- [ ] **Step 5: Write the failing PowerShell test**

Add inside the model `Describe` block in `tests/powershell/FlagArgs.Tests.ps1`:

```powershell
It 'completes the bare fable alias' {
    $results = @(Get-CompletionText 'claude --model fabl')
    $results | Should -Contain 'fable'
}
```

- [ ] **Step 6: Run it to verify it fails**

Run: `./tests/powershell/Invoke-Tests.ps1`
Expected: FAIL on `completes the bare fable alias` — no `fable` element yet.

- [ ] **Step 7: Add `fable` to the PowerShell known-model list**

In `claude.ps1`, change the first line of `$script:_ClaudeKnownModels`:

```powershell
$script:_ClaudeKnownModels = @(
    'sonnet', 'opus', 'haiku', 'fable',
    'claude-fable-5',
```

- [ ] **Step 8: Run it to verify it passes**

Run: `./tests/powershell/Invoke-Tests.ps1`
Expected: PASS, all green.

- [ ] **Step 9: Confirm parity still holds**

Run: `./tests/bash/run-tests.sh tests/bash/parity_test.bash`
Expected: PASS (parity checks flag sets/markers/cache version — unaffected).

- [ ] **Step 10: Commit**

```bash
unlock-gpg -c && git add claude.bash claude.ps1 tests/bash/flag_args_test.bash tests/powershell/FlagArgs.Tests.ps1 && git commit -m "Add fable to known --model aliases"
```

---

### Task 2: bash alias-expansion helper

Introduces `_claude_model_candidates` and rewires the bash `--model` case to it.

**Files:**
- Modify: `claude.bash` — add helper immediately above `_claude_complete_flag_arg` (currently line 491); replace the `--model)` case body (currently lines 499-513).
- Test: `tests/bash/flag_args_test.bash`

**Interfaces:**
- Consumes: `_CLAUDE_KNOWN_MODELS`, `_claude_cache_dir`.
- Produces: `_claude_model_candidates <cur>` — prints matching model strings, one per line, deduped, applying the two-prong rule.

- [ ] **Step 1: Write the failing tests**

Append to `tests/bash/flag_args_test.bash`:

```bash
function test_model_alias_expands_to_versioned_family() {
    local out
    out="$(_claude_model_candidates "opus")"
    assert_equals "opus" "$(grep -x 'opus' <<< "$out")"
    assert_contains "claude-opus-4-8" "$out"
    assert_not_contains "claude-sonnet" "$out"
    assert_not_contains "claude-haiku" "$out"
}

function test_model_alias_partial_stem_expands() {
    local out
    out="$(_claude_model_candidates "h")"
    assert_equals "haiku" "$(grep -x 'haiku' <<< "$out")"
    assert_contains "claude-haiku-4-5-20251001" "$out"
}

function test_model_sonnet_alias_expands_including_bare_numbered() {
    # sonnet family has both claude-sonnet-5 and claude-sonnet-4-5-...
    local out
    out="$(_claude_model_candidates "sonnet")"
    assert_equals "sonnet" "$(grep -x 'sonnet' <<< "$out")"
    assert_contains "claude-sonnet-5" "$out"
    assert_contains "claude-sonnet-4-5-20250929" "$out"
}

function test_model_claude_prefix_offers_no_bare_alias() {
    local out
    out="$(_claude_model_candidates "claude-op")"
    assert_contains "claude-opus-4-8" "$out"
    assert_equals "" "$(grep -x 'opus' <<< "$out")"
}

function test_model_post_claude_fragment_matches() {
    local out
    out="$(_claude_model_candidates "opus-4-8")"
    assert_equals "claude-opus-4-8" "$(grep -x 'claude-opus-4-8' <<< "$out")"
}

function test_model_empty_stem_returns_full_set() {
    local out
    out="$(_claude_model_candidates "")"
    assert_equals "opus" "$(grep -x 'opus' <<< "$out")"
    assert_contains "claude-opus-4-8" "$out"
    assert_equals "sonnet" "$(grep -x 'sonnet' <<< "$out")"
}

function test_model_expansion_reaches_help_scraped_id() {
    # Populate the help cache, then reach the scraped id via its post-claude- stem.
    simulate_completion "claude --model " >/dev/null
    local out
    out="$(_claude_model_candidates "test")"
    assert_contains "claude-test-9-99" "$out"
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `./tests/bash/run-tests.sh`
Expected: FAIL — `_claude_model_candidates: command not found` (helper undefined).

- [ ] **Step 3: Add the helper**

Insert into `claude.bash` immediately above `_claude_complete_flag_arg()`:

```bash
_claude_model_candidates() {
    # Print --model completions, one per line, deduplicated. A model matches
    # when it starts with $cur OR with "claude-$cur", so an alias stem
    # (opus/sonnet/haiku/fable) also reaches its claude-<family>-* versions.
    local cur="$1"
    local models=("${_CLAUDE_KNOWN_MODELS[@]}")
    local cache_dir line
    cache_dir="$(_claude_cache_dir)"
    if [[ -f "$cache_dir/_root_help" ]]; then
        while IFS= read -r line; do
            if [[ "$line" =~ claude-[a-z]+-[0-9][a-z0-9-]* ]]; then
                models+=("${BASH_REMATCH[0]}")
            fi
        done < "$cache_dir/_root_help"
    fi
    local m
    local -A seen=()
    for m in "${models[@]}"; do
        if [[ "$m" == "$cur"* || "$m" == "claude-$cur"* ]]; then
            if [[ -z "${seen[$m]:-}" ]]; then
                seen[$m]=1
                printf '%s\n' "$m"
            fi
        fi
    done
}
```

- [ ] **Step 4: Rewire the `--model` case**

In `claude.bash`, replace the `--model)` arm body (the merge/compgen block) with:

```bash
        --model)
            COMPREPLY=()
            local _model
            while IFS= read -r _model; do
                COMPREPLY+=("$_model")
            done < <(_claude_model_candidates "$cur")
            ;;
```

- [ ] **Step 5: Run to verify all pass**

Run: `./tests/bash/run-tests.sh`
Expected: PASS — new tests green; existing `test_model_completes_aliases`, `test_model_partial_input_filters`, and `test_model_extracts_ids_from_help_without_trailing_punctuation` still green (empty/`so`/scraped-id behavior preserved).

- [ ] **Step 6: Commit**

```bash
unlock-gpg -c && git add claude.bash tests/bash/flag_args_test.bash && git commit -m "Expand --model alias stems to versioned models (bash)"
```

---

### Task 3: PowerShell alias-expansion helper

Mirror of Task 2 in `claude.ps1`.

**Files:**
- Modify: `claude.ps1` — add helper near the other `function global:_Claude*` helpers; replace the `'--model'` switch arm (currently lines 322-336).
- Test: `tests/powershell/FlagArgs.Tests.ps1`

**Interfaces:**
- Consumes: `$script:_ClaudeKnownModels`, `_ClaudeCacheDir`.
- Produces: `_ClaudeModelCandidates -WordToComplete <cur>` — emits matching model strings applying the two-prong rule (dedup via `Select-Object -Unique`).

- [ ] **Step 1: Write the failing tests**

Add inside the model `Describe` block in `tests/powershell/FlagArgs.Tests.ps1`:

```powershell
It 'expands opus alias to its versioned models' {
    $r = @(_ClaudeModelCandidates -WordToComplete 'opus')
    $r | Should -Contain 'opus'
    $r | Should -Contain 'claude-opus-4-8'
    $r | Should -Not -Contain 'claude-sonnet-5'
}

It 'expands a partial stem h to the haiku family' {
    $r = @(_ClaudeModelCandidates -WordToComplete 'h')
    $r | Should -Contain 'haiku'
    $r | Should -Contain 'claude-haiku-4-5-20251001'
}

It 'expands sonnet including the bare-numbered claude-sonnet-5' {
    $r = @(_ClaudeModelCandidates -WordToComplete 'sonnet')
    $r | Should -Contain 'sonnet'
    $r | Should -Contain 'claude-sonnet-5'
    $r | Should -Contain 'claude-sonnet-4-5-20250929'
}

It 'claude- prefix offers no bare alias' {
    $r = @(_ClaudeModelCandidates -WordToComplete 'claude-op')
    $r | Should -Contain 'claude-opus-4-8'
    $r | Should -Not -Contain 'opus'
}

It 'matches a post-claude fragment' {
    $r = @(_ClaudeModelCandidates -WordToComplete 'opus-4-8')
    $r | Should -Contain 'claude-opus-4-8'
}

It 'expansion reaches a help-scraped id via its stem' {
    Get-CompletionText 'claude --model ' | Out-Null
    $r = @(_ClaudeModelCandidates -WordToComplete 'test')
    $r | Should -Contain 'claude-test-9-99'
}
```

- [ ] **Step 2: Run to verify they fail**

Run: `./tests/powershell/Invoke-Tests.ps1`
Expected: FAIL — `_ClaudeModelCandidates` is not recognized.

- [ ] **Step 3: Add the helper**

Insert into `claude.ps1` next to the other `function global:_Claude*` helpers:

```powershell
function global:_ClaudeModelCandidates {
    param([string]$WordToComplete)
    $models = @($script:_ClaudeKnownModels)
    $cacheDir = _ClaudeCacheDir
    $helpFile = Join-Path $cacheDir '_root_help'
    if (Test-Path $helpFile) {
        foreach ($line in Get-Content $helpFile) {
            if ($line -match '(claude-[a-z]+-[0-9][a-z0-9-]*)') {
                $models += $Matches[1]
            }
        }
    }
    $models | Select-Object -Unique | Where-Object {
        $_ -like "$WordToComplete*" -or $_ -like "claude-$WordToComplete*"
    }
}
```

- [ ] **Step 4: Rewire the `'--model'` switch arm**

In `claude.ps1`, replace the `'--model'` arm body with:

```powershell
        '--model' {
            _ClaudeModelCandidates -WordToComplete $WordToComplete | ForEach-Object {
                [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
            }
        }
```

- [ ] **Step 5: Run to verify all pass**

Run: `./tests/powershell/Invoke-Tests.ps1`
Expected: PASS — new tests green; existing `completes model aliases`, `filters model completions by partial input`, and `extracts model IDs from help text without trailing punctuation` still green.

- [ ] **Step 6: Full cross-shell green + parity**

Run: `./tests/bash/run-tests.sh` then `./tests/powershell/Invoke-Tests.ps1`
Expected: both suites PASS. Parity test (in the bash suite) green.

- [ ] **Step 7: Commit**

```bash
unlock-gpg -c && git add claude.ps1 tests/powershell/FlagArgs.Tests.ps1 && git commit -m "Expand --model alias stems to versioned models (PowerShell)"
```

---

## Notes for the implementer

- Do **not** re-filter the helper output through `compgen -- "$cur"` (bash) or a second `-like "$WordToComplete*"` (PowerShell) — that would strip the expanded `claude-<family>-*` entries. The helper is the sole matcher.
- `README.md`/`CLAUDE.md` describe `--model` completion only as "stable aliases + help-parsed + hardcoded list" — no wording change is required, but if you add a usage example, update both files in sync (per repo docs rule).
