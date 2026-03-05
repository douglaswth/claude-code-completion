# PowerShell completion for the claude CLI (Claude Code)
# https://github.com/anthropics/claude-code

function global:_claude_complete {
    param(
        [string]$WordToComplete,
        [string[]]$Elements
    )
    # TODO: implement
}

Register-ArgumentCompleter -CommandName claude -Native -ScriptBlock {
    param($wordToComplete, $commandAst, $cursorPosition)
    $elements = @($commandAst.CommandElements | ForEach-Object { $_.ToString() })
    _claude_complete -WordToComplete $wordToComplete -Elements $elements
}
