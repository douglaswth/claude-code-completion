# Version Memoization and Atomic Cache — Design

## Goal

Two related fixes to the completion scripts (`claude.bash`, `claude.ps1`):

1. **Performance.** Every tab press resolved the CLI version by spawning `claude --version`, a Node cold start of ~1.2–2.0s. Tab completion should be effectively instant after the first press in a shell session.
2. **Cache robustness.** Cache builds wrote files directly into the live cache directory and gated completion on the directory merely existing. An interrupted or concurrent build left a half-populated directory that subsequent completions treated as ready, producing missing or partial completions until the next CLI upgrade.

The bash side landed first; this design also covers mirroring both fixes into PowerShell so the two scripts stay in lockstep.

## Approach overview

- **Memoize the version** per shell session, keyed on the resolved executable's path + mtime, so repeated tab presses reuse the cached value but a CLI upgrade still invalidates it.
- **Build the cache into a staging directory** named with the process id, then atomically rename it into place, so a partial build is never visible.
- **Gate completion on a sentinel file** (`_root_help`) inside the cache directory rather than on the directory's existence, so a directory that exists but isn't fully populated is treated as not-ready and rebuilt.

## Version memoization

`claude --version` is a Node process cold start. Calling it on every tab press dominated completion latency. The fix caches the parsed version for the lifetime of the shell session and only re-runs `claude --version` when the underlying executable changes.

### Key: executable path + mtime

The memo key is the resolved executable path plus its modification time:

- **Bash:** `${claude_path}:$(_claude_mtime)`, where `claude_path` is `command -v claude` and `_claude_mtime` reads the file mtime portably (BSD/macOS `stat -f %m`, falling back to GNU/Linux `stat -c %Y`).
- **PowerShell:** `"${src}:${mtime}"`, where `src` is `(Get-Command claude).Source` and `mtime` is `(Get-Item $src).LastWriteTimeUtc.Ticks`.

An upgrade changes the key two ways — a new install path, or the same path rewritten in place (new mtime) — and either forces a refresh. Within a session, the key is stable, so the cached value is returned without respawning Node.

### The function-wrapper case is deliberately unsupported

In PowerShell, if `claude` resolves to a *function* (someone wrapping the real executable), `Get-Command claude` reports an empty `Source`, so the key degrades to `:0` — stable and harmless, but it won't notice a version change inside the wrapper.

This is an accepted limitation. Keying on a function's body was considered and rejected: a wrapper function commonly does *not* change when the wrapped CLI is upgraded, so a body-based key would go stale exactly when it mattered. Rather than build something subtly wrong, the wrapper case is left out. If a real user hits it, they can file an issue.

### Graceful degradation when `claude` is absent

If `claude` cannot be resolved, `_ClaudeVersion` returns nothing rather than throwing. This required an explicit early return:

```powershell
$cmd = Get-Command claude -ErrorAction SilentlyContinue
if (-not $cmd) { return }
```

A subtlety drove this: when `claude` is absent, calling `claude --version` raises `CommandNotFoundException`, and `2>$null` does **not** suppress it (stream redirection is not error suppression in PowerShell). The early return avoids the call entirely. The bash side already degrades cleanly because `command -v claude` short-circuits.

## Atomic cache publish

The cache build previously wrote each file directly into the final cache directory. If the build was interrupted (Ctrl-C, shell exit, a killed `claude --help`) or two shells built concurrently, the directory could be left partially written.

The fix builds into a per-process staging directory and renames it into place once complete:

- **Bash:** `build_dir="${cache_dir}.tmp.$$"` (`$$` is the shell's PID), all build writes target `build_dir`, then `mv "$build_dir" "$cache_dir"`.
- **PowerShell:** `$buildDir = "$cacheDir.tmp.$PID"` (`$PID` is the PowerShell process id, the analogue of bash `$$`), all build writes target `$buildDir`, then `Move-Item -Path $buildDir -Destination $cacheDir`.

A stale staging directory from a previous interrupted run (same PID reused) is removed before building. After a successful publish, the existing old-cache cleanup runs as before.

Using the PID in the staging name keeps two shells building concurrently from colliding: each builds in its own directory, and the rename is atomic on the same filesystem.

## Readiness gating

Completion previously proceeded if the cache directory existed. With direct-to-final builds gone that check is also strengthened: completion now gates on the presence of the `_root_help` sentinel file inside the cache directory, not on the directory itself.

- **Bash:** `[[ ! -f "$cache_dir/_root_help" ]]` triggers a rebuild.
- **PowerShell:** `if (-not (Test-Path (Join-Path $cacheDir '_root_help')))` triggers a rebuild.

`_root_help` is written during the build, so its presence means a build completed. Combined with atomic publish, the directory either doesn't exist or is fully populated — but gating on the sentinel is defensive against any future path that creates the directory early.

## Benchmark results

Measured against the pre-memoization scripts installed from the user's profile (`~/.local/share/bash-completion/completions/claude`, `~/.config/powershell/completions/claude.ps1`) as the baseline:

| | Before (per tab) | After (steady state) |
|---|---|---|
| Bash | 1.974 s | 5.5 ms |
| PowerShell | 1.206 s | 7.9 ms |

A warm `claude --version` is ~1.2–1.5s (cold ~4.9s). After the change, only the first tab press in a shell session pays that cost; every subsequent press is served from the memo. That is roughly a 250–350× speedup on steady-state tab latency.

## Tests

- **Version memoization (both shells):**
  - Returns the parsed version.
  - Invokes `claude --version` only once across repeated calls (proven by a counter the mock executable increments).
  - Re-invokes after the executable's mtime changes (simulating an upgrade by rewriting the on-disk binary / bumping its `LastWriteTime`).
  - Returns nothing and does not throw when no `claude` is resolvable (PowerShell — covers the `CommandNotFoundException` path).
- **Cache readiness gating (both shells):** an empty cache directory and an incomplete (sentinel-missing) cache directory both trigger a rebuild that yields working completions.
- **Atomic publish (both shells):** after a build, no `*.tmp.*` staging directories remain under the cache base.

PowerShell tests use a real on-disk mock executable (a shell script that counts `--version` invocations) rather than a function mock, so the path+mtime key is exercised realistically. The mock is dropped via `Remove-Item function:claude` and PATH is restricted to the mock's directory; note `Remove-Item function:global:claude` silently fails (the `global:` qualifier is not honored on a Function provider path), so the unqualified form is required.

## Scope

In scope:

- Per-session version memoization keyed on executable path + mtime, in both scripts.
- Portable mtime helper for bash (`_claude_mtime`).
- Atomic cache publish via a PID-named staging directory + rename, in both scripts.
- Readiness gating on the `_root_help` sentinel, in both scripts.
- The `CommandNotFoundException` early-return fix in PowerShell.
- Tests for memoization, readiness gating, and atomic publish in both shells.

Out of scope:

- Function-wrapper version detection (deliberately unsupported; see above).
- Cross-session persistence of the version memo — it is intentionally per-session, since the cache directory key already carries the version across sessions.
- Locking to serialize concurrent builds — concurrent builds are made safe by per-PID staging + atomic rename, not by a lock.
