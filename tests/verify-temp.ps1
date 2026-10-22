param(
    [string]$SourcePath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'auto_log_prompt.ttl'),
    [string]$MacroExe = 'C:\Program Files\teraterm5\ttpmacro.exe',
    [ValidateRange(1, 128)]
    [int]$ProcessCount = 16,
    [switch]$KeepArtifacts
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$resolvedSource = (Resolve-Path -LiteralPath $SourcePath).Path
$source = [System.IO.File]::ReadAllText($resolvedSource)
$allocation = [regex]::Match($source, '(?ms)^chooser_ready = 0\r?\n.*?^next\r?$')
if (-not $allocation.Success) { throw 'Could not extract the production allocation block.' }
$cleanup = [regex]::Match($source, '(?m)^filedelete chooser_result\r?\nfolderdelete chooser_dir\r?$')
if (-not $cleanup.Success) { throw 'Could not extract the production cleanup block.' }

$helperPath = Join-Path (Split-Path $resolvedSource -Parent) 'log_prompt.ps1'
$helperSource = [System.IO.File]::ReadAllText($helperPath)
$writeStatement = [regex]::Match($helperSource, '(?m)^\s*\[System\.IO\.File\]::WriteAllText\([^\r\n]+\)\s*$')
if (-not $writeStatement.Success) { throw 'Could not extract the production result-writing statement.' }

$testTempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
$runRoot = Join-Path $testTempRoot ('teraterm_logger-tests-' + [guid]::NewGuid().ToString('N'))
[void][System.IO.Directory]::CreateDirectory($runRoot)
if ($runRoot.Contains("'")) { throw 'This isolated TTL harness requires a path without apostrophes.' }
$encoding = New-Object System.Text.UTF8Encoding($false)
$ownedProcesses = New-Object System.Collections.Generic.List[System.Diagnostics.Process]
$allPassed = $false

function Start-TestMacro {
    param([string]$Name, [string]$Text)
    $macroPath = Join-Path $runRoot ($Name + '.ttl')
    [System.IO.File]::WriteAllText($macroPath, $Text, $encoding)
    $process = Start-Process -FilePath $MacroExe -ArgumentList @('/V', ('"{0}"' -f $macroPath)) -WindowStyle Hidden -PassThru
    $ownedProcesses.Add($process)
    return $process
}

function Wait-TestMacros {
    param([System.Diagnostics.Process[]]$Processes)
    $deadline = [DateTime]::UtcNow.AddSeconds(20)
    while (@($Processes | Where-Object { -not $_.HasExited }).Count -gt 0) {
        if ([DateTime]::UtcNow -ge $deadline) { throw 'A test macro exceeded the 20-second deadline.' }
        Start-Sleep -Milliseconds 100
    }
    foreach ($process in $Processes) {
        $process.WaitForExit()
        if ($process.ExitCode -ne 0) {
            throw ('A test macro failed with exit code {0}.' -f $process.ExitCode)
        }
    }
}

try {
    # A deliberate shared timestamp gives every concurrent macro the same first candidate.
    $processes = @()
    for ($i = 0; $i -lt $ProcessCount; $i++) {
        $marker = Join-Path $runRoot ('allocation-{0:D2}.txt' -f $i)
        $harness = @"
temp_dir = '$runRoot'
timestamp = 'same_second'
$($allocation.Value)
if chooser_ready = 0 then
  setexitcode 10
  end
endif
fileopen marker_handle '$marker' 0
if marker_handle = -1 then
  setexitcode 11
  end
endif
filewriteln marker_handle chooser_dir
fileclose marker_handle
setexitcode 0
end
"@
        $processes += Start-TestMacro -Name ('allocate-{0:D2}' -f $i) -Text $harness
    }
    Wait-TestMacros -Processes $processes

    $allocated = @()
    for ($i = 0; $i -lt $ProcessCount; $i++) {
        $marker = Join-Path $runRoot ('allocation-{0:D2}.txt' -f $i)
        if (-not [System.IO.File]::Exists($marker)) { throw "Missing allocation marker: $marker" }
        $allocated += [System.IO.File]::ReadAllText($marker, $encoding).Trim()
    }
    if (@($allocated | Select-Object -Unique).Count -ne $ProcessCount) { throw 'Allocation paths collided.' }
    foreach ($directory in $allocated) {
        if (-not [System.IO.Directory]::Exists($directory)) { throw "Reserved directory missing: $directory" }
        if (-not $directory.StartsWith($runRoot + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
            throw 'Allocation escaped the isolated test directory.'
        }
    }

    # Exercise the exact production cleanup commands against each reservation.
    $cleanupProcesses = @()
    for ($i = 0; $i -lt $ProcessCount; $i++) {
        $directory = $allocated[$i]
        $harness = @"
chooser_dir = '$directory'
sprintf2 chooser_result '%s\result.txt' chooser_dir
fileopen result_handle chooser_result 0
if result_handle = -1 then
  setexitcode 12
  end
endif
filewriteln result_handle 'test log path'
fileclose result_handle
$($cleanup.Value)
setexitcode result
end
"@
        $cleanupProcesses += Start-TestMacro -Name ('cleanup-{0:D2}' -f $i) -Text $harness
    }
    Wait-TestMacros -Processes $cleanupProcesses
    foreach ($directory in $allocated) {
        if ([System.IO.Directory]::Exists($directory)) { throw "Cleanup left a reservation behind: $directory" }
    }

    # Run the helper's exact result-writing statement, then read it with real Tera Term 5.
    # Character codes keep this test script ASCII-compatible with Windows PowerShell 5.1.
    $unicodeFolder = Join-Path $runRoot (-join @([char]0x65e5, [char]0x672c, [char]0x8a9e))
    [void][System.IO.Directory]::CreateDirectory($unicodeFolder)
    $unicodeFileName = '20261022_' + (-join @([char]0x30c6, [char]0x30b9, [char]0x30c8)) + '_' + [char]::ConvertFromUtf32(0x1f600) + '.log'
    $fullPath = Join-Path $unicodeFolder $unicodeFileName
    $OutputPath = Join-Path $runRoot 'unicode-result.txt'
    [System.IO.File]::WriteAllText($fullPath, 'unicode path marker', $encoding)
    & ([scriptblock]::Create($writeStatement.Value))
    $unicodeMarker = Join-Path $runRoot 'unicode-roundtrip.txt'
    $unicodeHarness = @"
fileopen result_handle '$OutputPath' 0 1
if result_handle = -1 then
  setexitcode 20
  end
endif
filereadln result_handle log_path
fileclose result_handle
filesearch log_path
if result = 0 then
  setexitcode 21
  end
endif
fileopen marker_handle '$unicodeMarker' 0
if marker_handle = -1 then
  setexitcode 22
  end
endif
filewriteln marker_handle log_path
fileclose marker_handle
setexitcode 0
end
"@
    $unicodeProcess = Start-TestMacro -Name 'unicode-roundtrip' -Text $unicodeHarness
    Wait-TestMacros -Processes @($unicodeProcess)
    $roundtripPath = [System.IO.File]::ReadAllText($unicodeMarker, $encoding).Trim()
    if ($roundtripPath -cne $fullPath) { throw 'The Unicode path changed during the Tera Term round trip.' }

    $report = [pscustomobject]@{
        MacroExe = $MacroExe
        Version = (Get-Item -LiteralPath $MacroExe).VersionInfo.ProductVersion
        ProcessCount = $ProcessCount
        SharedTimestamp = 'same_second'
        UniqueAllocationCount = @($allocated | Select-Object -Unique).Count
        AllAllocationProcessesExitedZero = $true
        AllCleanupProcessesExitedZero = $true
        ReservationsRemaining = 0
        UnicodeRoundtripPassed = $true
        AllocationPaths = $allocated
        RunRoot = $runRoot
        ArtifactsRetained = [bool]$KeepArtifacts
    }
    $report | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $runRoot 'report.json') -Encoding UTF8
    $report | ConvertTo-Json -Depth 3
    $allPassed = $true
}
finally {
    foreach ($process in $ownedProcesses) {
        if (-not $process.HasExited) {
            Stop-Process -Id $process.Id -Force
        }
        $process.Dispose()
    }
    if ($allPassed -and -not $KeepArtifacts) {
        # Only remove our unique direct child of the selected TEMP directory.
        $resolvedRunRoot = [System.IO.Path]::GetFullPath($runRoot)
        $resolvedParent = [System.IO.Path]::GetDirectoryName($resolvedRunRoot).TrimEnd('\')
        $leaf = [System.IO.Path]::GetFileName($resolvedRunRoot)
        if ($resolvedParent -ine $testTempRoot -or $leaf -notmatch '^teraterm_logger-tests-[0-9a-f]{32}$') {
            throw 'Refusing to clean a path outside the isolated test directory.'
        }
        Remove-Item -LiteralPath $resolvedRunRoot -Recurse -Force
    }
}
