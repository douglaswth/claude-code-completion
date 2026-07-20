# `--resume` Completion Ordering — Filter Before Capping

## Problem

Session ID completion for `--resume` / `-r` (`_claude_complete_sessions` in
`claude.bash`, `_ClaudeCompleteSessions` in `claude.ps1`) applies the
10-session cap **before** the typed-prefix filter:

1. List `*.jsonl` for the encoded CWD, sort by mtime descending.
2. Take the **10 newest**.
3. *Then* keep only IDs matching what the user typed.

Consequence: if a directory has more than 10 sessions and the user types a
prefix that uniquely matches a session **older than the newest 10**, that
session silently does not complete — a valid, unique match produces no
result and no error.

The original design (`2026-03-02-bash-completion-design.md`, step 5, "limit to
10 most recently modified files if many sessions exist") stated the cap as a
flat rule and did not consider its interaction with prefix filtering, so the
behavior was never a deliberate decision — just an artifact of applying the
cap to the file list rather than to the filtered candidate list.

## Decision

Reorder to **filter by prefix first, then cap to the 10 newest matches.**

- When nothing is typed (the common "browse my recent sessions" case), behavior
  is unchanged: the prefix filter is a no-op, so the result is still the 10
  newest sessions with message previews.
- When a prefix is typed, the cap now applies to *matching* sessions, so a
  unique older match is reachable. The 10-cap still bounds a wide-open prefix
  that matches many sessions.

The cap stays at 10 in both cases — it exists to avoid dumping hundreds of
candidates, and that guard is still wanted; it just belongs after the filter.

### Cost

Negligible. `ls -1t` / `Get-ChildItem | Sort-Object` already stats and sorts
every file regardless of order. The expensive per-match work — parsing the
session JSONL for its first user message (`_claude_session_message` /
`_ClaudeSessionMessage`) — already runs only for prefix matches, and continues
to. The only change is *which* set the `head -n 10` / `Select-Object -First 10`
truncates.

## Implementation

Both scripts, kept in lockstep for parity:

- **`claude.bash`** — drop `head -n 10` from the `ls -1t` pipeline; apply the
  cap after the prefix-filter loop builds `candidates` (e.g. truncate the array,
  or count matches and break at 10).
- **`claude.ps1`** — remove `Select-Object -First 10` from the file listing;
  cap the emitted `CompletionResult`s after the `-like` filter.

Newest-first ordering within the capped set is preserved (the mtime sort still
happens before truncation).

## Testing

Add a bash (bashunit) and PowerShell (Pester) case each:

- Create >10 mock session files with distinct mtimes; give the **11th-newest** a
  distinctive ID prefix.
- Complete `--resume <that-prefix>` and assert the older session's ID is
  returned. Before the fix this returns nothing; after, it completes.
- Keep an existing/added no-prefix case asserting the newest-10 browse behavior
  is unchanged.
