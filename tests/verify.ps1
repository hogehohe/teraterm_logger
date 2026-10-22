param(
    [string]$HelperPath = (Join-Path (Split-Path -Parent $PSScriptRoot) 'log_prompt.ps1')
)

# Run under Windows PowerShell 5.1 without loading WinForms or displaying the UI.
# Extract the production functions and write expression instead of copying them.
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)

    if (-not [object]::Equals($Expected, $Actual)) {
        throw ('{0} Expected: <{1}>; actual: <{2}>.' -f $Message, $Expected, $Actual)
    }
}

$tokens = $null
$parseErrors = $null
$helperAst = [System.Management.Automation.Language.Parser]::ParseFile(
    (Resolve-Path -LiteralPath $HelperPath).Path,
    [ref]$tokens,
    [ref]$parseErrors
)
if ($parseErrors.Count -gt 0) {
    throw ('Helper syntax errors: {0}' -f (($parseErrors | ForEach-Object { $_.Message }) -join '; '))
}
Write-Output 'PASS: helper parses without syntax errors'

$uniqueFunctions = @($helperAst.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
        $node.Name -eq 'Get-UniqueFileName'
}, $true))
Assert-Equal 1 $uniqueFunctions.Count 'Expected exactly one production filename helper.'
. ([scriptblock]::Create($uniqueFunctions[0].Extent.Text))

$writeCalls = @($helperAst.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
        $node.Static -and $node.Member.Value -eq 'WriteAllText' -and
        $node.Expression -is [System.Management.Automation.Language.TypeExpressionAst] -and
        $node.Expression.TypeName.FullName -eq 'System.IO.File'
}, $true))
Assert-Equal 1 $writeCalls.Count 'Expected exactly one production result-file write.'
$writeResult = [scriptblock]::Create($writeCalls[0].Extent.Text)

$scratchParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
$scratchRoot = Join-Path $scratchParent ('teraterm_logger_verify_' + [guid]::NewGuid().ToString('N'))
$scratchRoot = [System.IO.Path]::GetFullPath($scratchRoot)
$scratchParentPrefix = $scratchParent.TrimEnd('\', '/') + [System.IO.Path]::DirectorySeparatorChar
if (-not $scratchRoot.StartsWith($scratchParentPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'Scratch directory must be inside the system temporary directory.'
}
[void][System.IO.Directory]::CreateDirectory($scratchRoot)

try {
    $fixtureFolder = Join-Path $scratchRoot 'existing-logs'
    [void][System.IO.Directory]::CreateDirectory($fixtureFolder)
    $fileName = 'session.log'

    Assert-Equal 'session.log' (Get-UniqueFileName -Folder $fixtureFolder -FileName $fileName) `
        'A free base filename should be preserved.'
    Write-Output 'PASS: free base filename is preserved'

    [System.IO.File]::WriteAllText((Join-Path $fixtureFolder $fileName), '')
    Assert-Equal 'session_001.log' (Get-UniqueFileName -Folder $fixtureFolder -FileName $fileName) `
        'An occupied base filename should use the first suffix.'
    Write-Output 'PASS: occupied base filename uses _001'

    for ($suffix = 1; $suffix -le 998; $suffix++) {
        $existingName = 'session_{0:D3}.log' -f $suffix
        [System.IO.File]::WriteAllText((Join-Path $fixtureFolder $existingName), '')
    }
    Assert-Equal 'session_999.log' (Get-UniqueFileName -Folder $fixtureFolder -FileName $fileName) `
        'An available _999 filename must be returned.'
    Write-Output 'PASS: _999 is available after base and _001 through _998'

    [System.IO.File]::WriteAllText((Join-Path $fixtureFolder 'session_999.log'), '')
    Assert-Equal 'session_1000.log' (Get-UniqueFileName -Folder $fixtureFolder -FileName $fileName) `
        'Suffix generation must continue beyond _999.'
    Write-Output 'PASS: suffix generation continues to _1000'

    # Keep this test file ASCII so PowerShell 5.1 reads it independently of ACP.
    $japanese = -join ([char[]]@(0x65E5, 0x672C, 0x8A9E, 0x30C6, 0x30B9, 0x30C8))
    $emoji = [char]::ConvertFromUtf32(0x1F4DD)
    $fullPath = Join-Path $fixtureFolder ($japanese + '_' + $emoji + '.log')
    $OutputPath = Join-Path $scratchRoot 'result.txt'

    # Invoke the exact production expression with only its input values replaced.
    & $writeResult

    $actualBytes = [System.IO.File]::ReadAllBytes($OutputPath)
    if ($actualBytes.Length -ge 3 -and $actualBytes[0] -eq 0xEF -and
        $actualBytes[1] -eq 0xBB -and $actualBytes[2] -eq 0xBF) {
        throw 'The result file must not have a UTF-8 BOM before its path.'
    }
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $expectedText = $fullPath + [Environment]::NewLine
    $expectedBytes = $strictUtf8.GetBytes($expectedText)
    Assert-Equal ([Convert]::ToBase64String($expectedBytes)) ([Convert]::ToBase64String($actualBytes)) `
        'The result file must contain the exact UTF-8 bytes, including its newline.'
    Assert-Equal $expectedText ($strictUtf8.GetString($actualBytes)) `
        'Japanese and emoji must round-trip through the result file.'
    Write-Output 'PASS: actual production write preserves Japanese and emoji in UTF-8 without BOM'
}
finally {
    # Recheck the fully resolved target before any recursive deletion.
    $cleanupTarget = [System.IO.Path]::GetFullPath($scratchRoot)
    if (-not $cleanupTarget.StartsWith($scratchParentPrefix, [System.StringComparison]::OrdinalIgnoreCase) -or
        [System.IO.Path]::GetFileName($cleanupTarget) -notmatch '^teraterm_logger_verify_[0-9a-f]{32}$') {
        throw 'Refusing to remove an unexpected scratch directory.'
    }
    if (Test-Path -LiteralPath $cleanupTarget) {
        Remove-Item -LiteralPath $cleanupTarget -Recurse -Force
    }
}

Write-Output 'All headless regression checks passed. Tera Term connection and macro execution require a separate integration check.'
