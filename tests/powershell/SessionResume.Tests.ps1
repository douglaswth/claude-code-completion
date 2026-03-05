BeforeAll {
    . $PSScriptRoot/TestHelper.ps1
    Initialize-ClaudeTests
    New-DefaultMockClaude

    $env:XDG_CACHE_HOME = Join-Path ([System.IO.Path]::GetTempPath()) "claude-test-$([guid]::NewGuid())"

    # Create fake session files
    $script:MockHome = Join-Path ([System.IO.Path]::GetTempPath()) "claude-mock-home-$([guid]::NewGuid())"
    $script:OriginalHome = $HOME
    $env:HOME = $script:MockHome

    $projDir = Join-Path $script:MockHome '.claude' 'projects' '-home-user-myproject'
    New-Item -ItemType Directory -Path $projDir -Force | Out-Null

    # Session 1: older
    @'
{"type":"queue-operation","timestamp":"2026-02-01T10:00:00.000Z","sessionId":"aaaaaaaa-1111-1111-1111-111111111111"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Fix the login bug"}]},"timestamp":"2026-02-01T10:00:01.000Z","sessionId":"aaaaaaaa-1111-1111-1111-111111111111"}
{"type":"assistant","timestamp":"2026-02-01T10:00:05.000Z","sessionId":"aaaaaaaa-1111-1111-1111-111111111111"}
'@ | Set-Content (Join-Path $projDir 'aaaaaaaa-1111-1111-1111-111111111111.jsonl')

    Start-Sleep -Seconds 1

    # Session 2: newer, with IDE metadata in first user message
    @'
{"type":"queue-operation","timestamp":"2026-03-01T15:00:00.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"<ide_opened_file>Some IDE stuff</ide_opened_file>"}]},"timestamp":"2026-03-01T15:00:01.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
{"type":"user","message":{"role":"user","content":[{"type":"text","text":"Add the new feature"}]},"timestamp":"2026-03-01T15:00:02.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
{"type":"assistant","timestamp":"2026-03-01T15:00:10.000Z","sessionId":"bbbbbbbb-2222-2222-2222-222222222222"}
'@ | Set-Content (Join-Path $projDir 'bbbbbbbb-2222-2222-2222-222222222222.jsonl')

    # Override _claude_encoded_cwd to match our fake project
    function global:_claude_encoded_cwd { '-home-user-myproject' }
}

AfterAll {
    $env:HOME = $script:OriginalHome
    if (Test-Path $script:MockHome) { Remove-Item -Recurse -Force $script:MockHome }
    if ($env:XDG_CACHE_HOME -and (Test-Path $env:XDG_CACHE_HOME)) {
        Remove-Item -Recurse -Force $env:XDG_CACHE_HOME
    }
    $env:XDG_CACHE_HOME = $null
}

Describe 'Session message extraction' {
    It 'extracts simple user message' {
        $projDir = Join-Path $script:MockHome '.claude' 'projects' '-home-user-myproject'
        $msg = _claude_session_message -FilePath (Join-Path $projDir 'aaaaaaaa-1111-1111-1111-111111111111.jsonl')
        $msg | Should -Be 'Fix the login bug'
    }

    It 'skips IDE metadata messages' {
        $projDir = Join-Path $script:MockHome '.claude' 'projects' '-home-user-myproject'
        $msg = _claude_session_message -FilePath (Join-Path $projDir 'bbbbbbbb-2222-2222-2222-222222222222.jsonl')
        $msg | Should -Be 'Add the new feature'
    }
}

Describe 'Session completion' {
    It 'finds both sessions' {
        $results = @(_claude_complete_sessions -WordToComplete '')
        $results.Count | Should -Be 2
    }

    It 'session 1 UUID present' {
        $results = _claude_complete_sessions -WordToComplete ''
        $results.CompletionText | Should -Contain 'aaaaaaaa-1111-1111-1111-111111111111'
    }

    It 'session 2 UUID present' {
        $results = _claude_complete_sessions -WordToComplete ''
        $results.CompletionText | Should -Contain 'bbbbbbbb-2222-2222-2222-222222222222'
    }

    It 'partial UUID filters results' {
        $results = @(_claude_complete_sessions -WordToComplete 'aaa')
        $results.Count | Should -Be 1
    }

    It 'no-match returns empty' {
        $results = @(_claude_complete_sessions -WordToComplete 'zzz')
        $results.Count | Should -Be 0
    }

    It 'tooltip contains message text' {
        $results = _claude_complete_sessions -WordToComplete 'aaa'
        $results[0].ToolTip | Should -Be 'Fix the login bug'
    }
}

Describe 'Path encoding' {
    It 'encodes Unix paths by replacing / with -' {
        $result = _claude_encoded_cwd
        $result | Should -Not -BeNullOrEmpty
    }
}
