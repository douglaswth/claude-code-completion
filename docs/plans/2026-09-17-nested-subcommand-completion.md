# Nested Subcommand Completion — Arbitrary Depth

## Problem

Both completion scripts model the `claude` CLI as exactly two levels deep.

`_claude_build_cache` (`claude.bash`) iterated `_root_subcommands` and ran
`claude <subcmd> --help` for each. It never recursed, so
`claude plugin marketplace --help` was never parsed and no cache file listed
its commands. The resolver in `_claude` then matched at most two path
components into `subcmd` and `sub_subcmd`; with both filled
(`plugin` + `marketplace`) it routed to `_claude_complete_subcmd_arg`, whose
`case` had no `plugin/marketplace` arm, leaving `COMPREPLY` empty.

`claude.ps1` had the identical two-level structure
(`_ClaudeCompleteSubcmdArg`, and the `$subcmd`/`$subSubcmd` pair in
`_ClaudeComplete`), so this was a parity bug rather than a bash-only one.

Observed against CLI 2.1.275:

```
claude plugin <TAB>              -> details disable enable eval … marketplace …
claude plugin mark<TAB>          -> marketplace
claude plugin marketplace <TAB>  -> (empty)
```

A scan of the whole CLI found exactly two third-level command groups today:

| Path                 | Commands that could not be completed |
| -------------------- | ------------------------------------ |
| `plugin marketplace` | `add`, `help`, `list`, `remove`, `update` |
| `plugin eval`        | `init`                               |

## Decision

Walk the command tree to **arbitrary depth** rather than adding a third
hardcoded tier. The depth of the CLI is then a property of its `--help`
output, not of this code, so future nesting needs no change here.

### Cache build

A worklist processed one depth at a time:

1. Fan out `claude <path> --help` for every node at the current depth,
   **in parallel**, capturing raw help text only.
2. Wait for the level to finish.
3. Parse the captured text **serially in the parent**.
4. Collect the next depth from each `Commands:` section; repeat until a
   level contributes no nodes.

Parsing stays serial deliberately. PowerShell's `ForEach-Object -Parallel`
runs each iteration in a fresh runspace that does *not* inherit the script's
functions, so `_ClaudeParseSubcommands` does not exist inside the parallel
block. Restricting the parallel section to process invocation sidesteps that
entirely, and costs nothing: the `claude … --help` call is ~0.26s while the
parsing is pure string work.

Cache keys are the command path joined by `_` — `plugin_marketplace_flags`,
`plugin_marketplace_subcommands`. This is filename-safe because `claude`
command names use `-` as their word separator and never `_` (`auto-mode`,
`add-from-claude-desktop`, `reset-project-choices`). The atomic
build-into-staging-then-rename publish is unchanged.

### Pruning

Probing every node costs one process launch each. Two classes of node cannot
be command groups and are skipped:

- **`help`** — Commander's built-in help command is always a leaf.
- **A node whose term column shows a required `<arg>`** — e.g.
  `details [options] <name>`, `get <name>`.

This cuts the level-2 probes from 36 to 19 against today's CLI, and is most of
what keeps the build cost in hand (see "Build cost, measured" below).

The term column is the text before the first 2+ space gap; the description
must not be examined, because descriptions themselves contain angle
brackets (`plugin eval`'s mentions
`<eval dir>/**/case.yaml`) and would misclassify a real group as a leaf.

**The required-`<arg>` rule is a Commander convention, not a guarantee.** A
future `claude foo <bar> baz` would be silently missed. A guard test
therefore walks every node the heuristic prunes and asserts its `--help` has
no `Commands:` section, converting that silent gap into a failing check.

### Parallelism per shell

| Shell                   | Mechanism                     |
| ----------------------- | ----------------------------- |
| bash                    | `&` + `wait`                  |
| PowerShell 7+           | `ForEach-Object -Parallel`    |
| Windows PowerShell 5.1  | serial fallback               |

**Parity intent: all three paths must produce byte-identical cache files.
Only wall time may differ.** Parallelism is an optimization of *when* the
help text is fetched, never of *what* is written.

5.1 is a supported target (`README.md`) and is exercised in CI
(`.github/workflows/test.yml` includes `os: windows-latest, shell: powershell`
alongside the `pwsh` matrix), so the fallback is verified rather than assumed.
It is selected with the `$PSVersionTable.PSVersion.Major -le 5` pattern
already used elsewhere in `claude.ps1`.

PowerShell falls back to serial for a second reason as well: a `-Parallel`
runspace inherits neither this script's functions nor the session's aliases,
so a `claude` that is not a plain external executable would resolve to
something else inside the block, or to nothing. `_ClaudeCanProbeInParallel`
therefore requires `Get-Command claude` to report `Application`. A shell
wrapper function around `claude` probes serially and still gets a correct
cache. This is also why the Pester suite never exercises the parallel path —
its mock is a function — so that path is verified by hand against the real
CLI instead.

`ForEach-Object -Parallel` is safe to *mention* in a file that 5.1 parses:
`-Parallel` is an ordinary `CommandParameterAst`, and PowerShell binds
parameter names at runtime, so an unexecuted branch naming a parameter that
exists in no version still parses with zero errors. What does break 5.1 at
parse time is PowerShell 7-only *syntax* in any branch, live or dead.
**`claude.ps1` therefore admits no `??`, `?:`, or `&&`/`||` pipeline chains.**

### Resolution

The resolver walks the words left to right, extending the current path while
each next non-flag word appears in that path's subcommand list, instead of
filling two fixed variables. Flag scope follows the same path, which fixes a
related defect for free: `claude plugin marketplace -<TAB>` previously offered
`plugin`'s flags and now offers `marketplace`'s.

### Positional arguments

`_claude_complete_subcmd_arg` is keyed on the full path
(`plugin/marketplace/remove`) rather than a two-part key; existing `mcp/get`
and `plugin/enable` arms are unaffected.

`_claude_marketplace_names` is added, mirroring `_claude_plugin_names`
(`claude plugin marketplace list --json`, parsed with `jq` and falling back to
`grep`/`sed`), and wired to `plugin/marketplace/remove` and
`plugin/marketplace/update`.

## Cache version

`_CLAUDE_CACHE_VERSION` 8 → 9. The key naming scheme changes, so caches built
by an older copy of the script must not be read by this one.

## Result

```
claude plugin marketplace <TAB>         -> add  help  list  remove  update
claude plugin marketplace remove <TAB>  -> claude-plugins-official
claude plugin eval <TAB>                -> init
```

### Build cost, measured

Design-time estimate was that parallelism would drop the cold build from ~5s
to ~1-2s. **That was wrong**, and the measured figures are these (2-core
machine, CLI 2.1.275, mean of two runs):

| Build                                         | Probes | Time  |
| --------------------------------------------- | ------ | ----- |
| Before this change (2 levels, serial)          | 19     | 4.8s  |
| This change, pruned + parallel                 | 38     | 5.4s  |
| This change, pruned, serial                    | 38     | 8.1s  |
| This change, parallel, **no** pruning          | 55     | 9.3s  |

So the cold build gets roughly **0.6s slower**, once per CLI version, not
faster. `claude --help` is a CPU-bound Node cold start (0.21s in isolation),
so on two cores eight concurrent probes finish in 1.15s against 1.70s serial
— about 1.5x, nowhere near 8x. Doubling the probe count outruns that.

Both optimizations still pay for themselves: without them the same tree would
cost 9.3s, so pruning and parallelism together turn a +4.5s regression into
+0.6s. The speedup is core-count dependent and should be larger on wider
machines, but that has not been measured and is not claimed here.

Concurrency is derived from the core count rather than fixed, as
`cores * 2` clamped to `[2, 16]`. The multiplier follows the measurement: on
two cores, 4 and 8 tie at ~5.7s while 16 and 24 get *slower* (6.5s, 6.2s) from
oversubscription. The clamp bounds both extremes — a single-core container must
not launch eight Node processes, and a very wide machine must not launch dozens,
since each probe costs real memory.

Core detection mirrors the guarded-probe pattern `_claude_mtime` already uses
for its GNU/BSD `stat` split: bash tries `nproc`, then `sysctl -n hw.ncpu`,
then `getconf _NPROCESSORS_ONLN`, then `$NUMBER_OF_PROCESSORS`, range-checking
each result. `nproc` goes first because it honours CPU affinity — a cgroup- or
`taskset`-limited container reports the budget it actually has, which was
verified (`taskset -c 0 nproc` → `1`). PowerShell uses
`[Environment]::ProcessorCount`, which works on 5.1 and 7+ across platforms and
honours container CPU limits.

### A zero core count is reachable

`NUMBER_OF_PROCESSORS` is an ordinary environment variable, and detection only
checks that a probe's output is digits, so `NUMBER_OF_PROCESSORS=0` yields a
core count of `0`. Unclamped that is not merely a bad number: the build loop's
`(( launched % concurrency == 0 ))` raises `division by 0` on every probe.

The guard therefore clamps the **core count** to at least 1 rather than
clamping the resulting concurrency. One check covers every probe, including
any added later, and covers a non-numeric value too (bash evaluates it as 0).
Clamping cores also makes a separate lower bound on concurrency redundant,
since `1 * 2` already satisfies it.

### A caveat on these timings

Claude Code's native installs update themselves, and the trigger is invoking
`claude` — which is exactly what a cache build does, 38 times. During this
work the CLI moved from 2.1.275 to 2.1.276 mid-session, set off by the probes
themselves. The table above is a single-version comparison (2.1.275, old and
new interleaved inside one four-minute window); re-running it on 2.1.276 gave
5.1s old against 6.0s new, the same conclusion.

The documentation records no way to switch the updater off in user scope —
`autoUpdatesChannel: "stable"` only changes channel, and
`requiredMaximumVersion` is managed-settings-only. So any future measurement
has to *settle* it instead: install, invoke `claude` once to let a pending
update land, then assert the version is identical before and after the timed
section.
