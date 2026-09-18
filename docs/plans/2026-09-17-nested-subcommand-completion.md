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

Encoding is a second, independent way to break 5.1 at parse time, and it cost
a CI round to find. 5.1 decodes a BOM-less `.ps1` as ANSI, so a UTF-8 em dash
(`E2 80 94`) arrives as cp1252 `â€”` - and `0x94` there is a smart closing
quote, which PowerShell honours as a string delimiter. A dash inside a string
literal ends the string mid-line and the rest of the file parses as nonsense.
`claude.ps1` had survived only by placement, its non-ASCII sitting in comments
where a mangled character is still a comment. **The PowerShell sources this
branch owns are therefore kept ASCII-only.** Neither trap is visible to a
PowerShell 7 parse check; only the 5.1 CI job catches them.

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
to ~1-2s. The first measurement, on a two-core machine, said the opposite -
~0.9s *slower*. Both were wrong to generalise from, because the answer depends
on core count. CI measures it across runners (`.github/workflows/bench.yml`,
`origin/main` against the branch, three interleaved repetitions each):

| Runner | Cores | Concurrency | Probe path | `origin/main` | This branch |
| ------ | ----- | ----------- | ---------- | ------------- | ----------- |
| ubuntu-latest, bash      | 4 | 8 | parallel | 2.93s | **2.83s** |
| macos-latest, bash       | 3 | 6 | parallel | 2.35s | **1.95s** |
| windows-latest, pwsh 7.6 | 4 | 8 | parallel | 4.19s | **4.26s** |
| windows-latest, PS 5.1   | 4 | 8 | serial   | 4.69s | **8.11s** |
| dev machine, bash        | 2 | 4 | parallel | ~5.1s | ~6.0s     |

**On every machine with more than two cores the new build is break-even or
faster**, despite probing 38 nodes where the old one probed 19. The two-core
development machine is the outlier: `claude --help` is a CPU-bound Node cold
start, so two cores cap the parallel gain at about 1.5x and the doubled probe
count outruns it.

The 55-probe unpruned variant measured 9.3s against 5.4s pruned on the
two-core machine, so pruning is carrying real weight there regardless.

### The parallel probe path earns its keep

The last two rows above are the same machine with the same four cores running
the same branch code, differing only in whether probes run in parallel:
**4.26s against 8.11s**, a 1.9x gain. On two cores the same comparison gave
only 1.2x, which had made the parallel path look barely worth its complexity.

The two PowerShell engines are not confounding that. On the *baseline* they
differ by 0.5s (4.19s against 4.69s, ~12%); on the branch they differ by 3.85s
(~90%). The engine accounts for a small fraction and the probe path for the
rest.

Windows PowerShell 5.1 therefore pays ~3.4s more than the old build, being the
one configuration with no parallel option. That is the cost of the feature on
5.1, once per CLI version.

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
