BeforeAll {
    . $PSScriptRoot/TestHelper.ps1
    Initialize-ClaudeTests
    New-DefaultMockClaude

    $env:XDG_CACHE_HOME = Join-Path $TestDrive 'cache'

    # Create fake session files
    $script:MockHome = Join-Path $TestDrive 'home'
    $script:OriginalHome = $HOME
    $env:HOME = $script:MockHome

    $projDir = Join-Path (Join-Path (Join-Path $script:MockHome '.claude') 'projects') '-home-user-myproject'
    New-Item -ItemType Directory -Path $projDir -Force | Out-Null

    # Session 1: oldest
    $file = Join-Path $projDir 'aaaaaaaa-1111-1111-1111-111111111111.jsonl'
    @'
{"type":"queue-operation","timestamp":"2026-02-01T10:00:00.000Z","sessionId":"aaaaaaaa-1111-1111-1111-111111111111"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Fix the login bug"}]},"timestamp":"2026-02-01T10:00:01.000Z","sessionId":"aaaaaaaa-1111-1111-1111-111111111111"}
{"type":"assistant","timestamp":"2026-02-01T10:00:05.000Z","sessionId":"aaaaaaaa-1111-1111-1111-111111111111"}
'@ | Set-Content $file
    (Get-Item $file).LastWriteTime = [datetime]'2026-02-01'

    # Session 2: newer, with IDE metadata in first user message
    $file = Join-Path $projDir 'bbbbbbbb-2222-2222-2222-222222222222.jsonl'
    @'
{"type":"queue-operation","timestamp":"2026-03-01T15:00:00.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<ide_opened_file>Some IDE stuff</ide_opened_file>"}]},"timestamp":"2026-03-01T15:00:01.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Add the new feature"}]},"timestamp":"2026-03-01T15:00:02.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
{"type":"assistant","timestamp":"2026-03-01T15:00:10.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
'@ | Set-Content $file
    (Get-Item $file).LastWriteTime = [datetime]'2026-03-01'

    # Session 3: string content (not array)
    $file = Join-Path $projDir 'cccccccc-3333-3333-3333-333333333333.jsonl'
    @'
{"type":"queue-operation","timestamp":"2026-04-01T12:00:00.000Z","sessionId":"cccccccc-3333-3333-3333-333333333333"}
{"type":"user","message":{"role":"user","content":"Refactor the parser"},"timestamp":"2026-04-01T12:00:01.000Z","sessionId":"cccccccc-3333-3333-3333-333333333333"}
{"type":"assistant","timestamp":"2026-04-01T12:00:05.000Z","sessionId":"cccccccc-3333-3333-3333-333333333333"}
'@ | Set-Content $file
    (Get-Item $file).LastWriteTime = [datetime]'2026-04-01'

    # Session 4: no user message (only queue-operation and assistant)
    $file = Join-Path $projDir 'dddddddd-4444-4444-4444-444444444444.jsonl'
    @'
{"type":"queue-operation","timestamp":"2026-05-01T09:00:00.000Z","sessionId":"dddddddd-4444-4444-4444-444444444444"}
{"type":"assistant","timestamp":"2026-05-01T09:00:05.000Z","sessionId":"dddddddd-4444-4444-4444-444444444444"}
'@ | Set-Content $file
    (Get-Item $file).LastWriteTime = [datetime]'2026-05-01'

    # Session 5: long message (over 40 characters)
    $file = Join-Path $projDir 'eeeeeeee-5555-5555-5555-555555555555.jsonl'
    @'
{"type":"queue-operation","timestamp":"2026-06-01T08:00:00.000Z","sessionId":"eeeeeeee-5555-5555-5555-555555555555"}
{"type":"user","message":{"role":"user","content":"Refactor the entire authentication module to use OAuth2 with PKCE flow"},"timestamp":"2026-06-01T08:00:01.000Z","sessionId":"eeeeeeee-5555-5555-5555-555555555555"}
{"type":"assistant","timestamp":"2026-06-01T08:00:10.000Z","sessionId":"eeeeeeee-5555-5555-5555-555555555555"}
'@ | Set-Content $file
    (Get-Item $file).LastWriteTime = [datetime]'2026-06-01'

    # Override _ClaudeEncodedCwd to match our fake project
    function global:_ClaudeEncodedCwd { '-home-user-myproject' }
}

AfterAll {
    $env:HOME = $script:OriginalHome
    $env:XDG_CACHE_HOME = $null
}

Describe 'Session message extraction' {
    It 'extracts simple user message' {
        $projDir = Join-Path (Join-Path (Join-Path $script:MockHome '.claude') 'projects') '-home-user-myproject'
        $msg = _ClaudeSessionMessage -FilePath (Join-Path $projDir 'aaaaaaaa-1111-1111-1111-111111111111.jsonl')
        $msg | Should -Be 'Fix the login bug'
    }

    It 'skips IDE metadata messages' {
        $projDir = Join-Path (Join-Path (Join-Path $script:MockHome '.claude') 'projects') '-home-user-myproject'
        $msg = _ClaudeSessionMessage -FilePath (Join-Path $projDir 'bbbbbbbb-2222-2222-2222-222222222222.jsonl')
        $msg | Should -Be 'Add the new feature'
    }

    It 'extracts string content (non-array)' {
        $projDir = Join-Path (Join-Path (Join-Path $script:MockHome '.claude') 'projects') '-home-user-myproject'
        $msg = _ClaudeSessionMessage -FilePath (Join-Path $projDir 'cccccccc-3333-3333-3333-333333333333.jsonl')
        $msg | Should -Be 'Refactor the parser'
    }
}

Describe 'Session completion' {
    It 'finds all sessions' {
        $results = @(_ClaudeCompleteSessions -WordToComplete '')
        $results.Count | Should -Be 5
    }

    It 'session 1 UUID present' {
        $results = _ClaudeCompleteSessions -WordToComplete ''
        $results.CompletionText | Should -Contain 'aaaaaaaa-1111-1111-1111-111111111111'
    }

    It 'session 2 UUID present' {
        $results = _ClaudeCompleteSessions -WordToComplete ''
        $results.CompletionText | Should -Contain 'bbbbbbbb-2222-2222-2222-222222222222'
    }

    It 'session 3 UUID present' {
        $results = _ClaudeCompleteSessions -WordToComplete ''
        $results.CompletionText | Should -Contain 'cccccccc-3333-3333-3333-333333333333'
    }

    It 'partial UUID filters results' {
        $results = @(_ClaudeCompleteSessions -WordToComplete 'aaa')
        $results.Count | Should -Be 1
    }

    It 'no-match returns empty' {
        $results = @(_ClaudeCompleteSessions -WordToComplete 'zzz')
        $results.Count | Should -Be 0
    }

    It 'tooltip contains message text' {
        $results = _ClaudeCompleteSessions -WordToComplete 'aaa'
        $results[0].ToolTip | Should -Be 'Fix the login bug'
    }

    It 'no user message falls back to (session)' {
        $results = _ClaudeCompleteSessions -WordToComplete 'ddd'
        $results[0].ToolTip | Should -Be '(session)'
    }

    It 'long message is truncated in list text' {
        $results = _ClaudeCompleteSessions -WordToComplete 'eee'
        $ellipsis = [char]0x2026
        $results[0].ListItemText | Should -BeLike "*$ellipsis"
        $results[0].ListItemText.Length | Should -BeLessThan ($results[0].ToolTip.Length + 40)
    }

    It 'long message tooltip contains full text' {
        $results = _ClaudeCompleteSessions -WordToComplete 'eee'
        $results[0].ToolTip | Should -Be 'Refactor the entire authentication module to use OAuth2 with PKCE flow'
    }
}

Describe 'End-to-end resume completion' {
    It 'claude --resume shows sessions' {
        $results = Get-CompletionText 'claude --resume '
        $results | Should -Contain 'aaaaaaaa-1111-1111-1111-111111111111'
        $results | Should -Contain 'bbbbbbbb-2222-2222-2222-222222222222'
        $results | Should -Contain 'cccccccc-3333-3333-3333-333333333333'
    }

    It 'claude -r shows sessions' {
        $results = Get-CompletionText 'claude -r '
        $results | Should -Contain 'aaaaaaaa-1111-1111-1111-111111111111'
        $results | Should -Contain 'bbbbbbbb-2222-2222-2222-222222222222'
        $results | Should -Contain 'cccccccc-3333-3333-3333-333333333333'
    }

    It 'claude --resume with no match returns empty' {
        $results = @(Get-CompletionText 'claude --resume zzz')
        $results.Count | Should -Be 0
    }
}

Describe 'Resume completion with symlinked CWD' -Skip:($IsWindows -or $PSVersionTable.PSVersion.Major -le 5) {
    BeforeAll {
        # Create a real directory and a symlink to it
        $realDir = Join-Path (Join-Path $TestDrive 'real') 'myproject'
        $linkDir = Join-Path $TestDrive 'link'
        New-Item -ItemType Directory -Path $realDir -Force | Out-Null
        New-Item -ItemType SymbolicLink -Path $linkDir -Target (Join-Path $TestDrive 'real') | Out-Null

        # Encode the REAL (fully resolved) path the way Claude CLI would.
        # Must resolve $realDir itself since $TestDrive may contain symlinks
        # (e.g. /var -> /private/var on macOS).
        $realEncoded = (_ClaudeResolveSymlinks $realDir).Replace('/', '-')
        $projDir = Join-Path (Join-Path (Join-Path $script:MockHome '.claude') 'projects') $realEncoded
        New-Item -ItemType Directory -Path $projDir -Force | Out-Null

        $file = Join-Path $projDir 'ffffffff-6666-6666-6666-666666666666.jsonl'
        '{"type":"user","message":{"role":"user","content":"Symlink test"},"timestamp":"2026-04-01T10:00:00.000Z","sessionId":"ffffffff-6666-6666-6666-666666666666"}' |
            Set-Content $file

        # Re-source to get the real _ClaudeEncodedCwd (not the test override)
        Initialize-ClaudeTests
        New-DefaultMockClaude
    }

    AfterAll {
        Remove-Item $linkDir -Force -ErrorAction SilentlyContinue
        # Restore the test override
        function global:_ClaudeEncodedCwd { '-home-user-myproject' }
    }

    It 'finds sessions when CWD is a symlink' {
        Push-Location (Join-Path $linkDir 'myproject')
        try {
            $results = @(_ClaudeCompleteSessions -WordToComplete '')
            $results.CompletionText | Should -Contain 'ffffffff-6666-6666-6666-666666666666'
        } finally {
            Pop-Location
        }
    }
}
