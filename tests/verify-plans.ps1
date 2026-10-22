param(
    [string]$ModulePath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'TeratermLogger.psm1'),
    [string]$CliPath = (Join-Path (Split-Path $PSScriptRoot -Parent) 'teraterm_logger.ps1')
)

# Run with Windows PowerShell 5.1. No device connection or UI is required.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
Import-Module $ModulePath -Force
$utf8 = New-Object System.Text.UTF8Encoding($false, $true)
$script:passed = 0
$scratchParent = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
$scratchRoot = [System.IO.Path]::GetFullPath((Join-Path $scratchParent ('teraterm_logger_plans_' + [guid]::NewGuid().ToString('N'))))
[void][System.IO.Directory]::CreateDirectory($scratchRoot)

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw $Message }
}

function Record-Pass {
    param([string]$Message)
    $script:passed++
    Write-Output ('PASS: ' + $Message)
}

function New-TestPlan {
    param([int]$Count = 4)
    $steps = @()
    for ($number = 1; $number -le $Count; $number++) {
        $steps += [pscustomobject]@{
            id = $number
            label = 'Step ' + $number
            command = 'echo DEMO_STEP_' + $number
            expect = '(?m)^mock-device# $'
            timeoutSeconds = 10
        }
    }
    return [pscustomobject]@{ name = 'Plan validation fixture'; steps = $steps }
}

function Write-TestPlan {
    param($Plan, [string]$Name)
    $path = Join-Path $scratchRoot ($Name + '.json')
    [System.IO.File]::WriteAllText($path, ($Plan | ConvertTo-Json -Depth 8), $utf8)
    return $path
}

function Assert-Rejected {
    param([scriptblock]$Action, [string]$Reason, [string]$Message)
    try { $null = & $Action }
    catch {
        if ($_.Exception.Message -notmatch $Reason) {
            throw ('{0}: rejected for an unexpected reason: {1}' -f $Message, $_.Exception.Message)
        }
        Record-Pass $Message
        return
    }
    throw ('Expected rejection: ' + $Message)
}

function Assert-PlanRejected {
    param($Plan, [string]$Name, [string]$Reason, [int]$FromStep = 2, [int]$ToStep = 3)
    $path = Write-TestPlan $Plan $Name
    Assert-Rejected { Get-TeraTermSelectedPlan -PlanPath $path -FromStep $FromStep -ToStep $ToStep } $Reason $Name
}

function Assert-CliRangeRequired {
    param([string]$Name, [string]$RangeArguments)
    $stdout = Join-Path $scratchRoot ($Name + '.stdout.txt')
    $stderr = Join-Path $scratchRoot ($Name + '.stderr.txt')
    $powershellExe = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    $arguments = '-NoProfile -NonInteractive -ExecutionPolicy Bypass -File "{0}" -Action Run -SessionId {1} -PlanPath "{2}" -StateRoot "{3}" {4}' -f $resolvedCli, $sessionId, $validPath, $scratchRoot, $RangeArguments
    $process = Start-Process -FilePath $powershellExe -ArgumentList $arguments -WindowStyle Hidden -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    try {
        if (-not $process.WaitForExit(60000)) { throw 'The CLI did not reject the missing range within 60 seconds.' }
        $process.WaitForExit()
        Assert-True ($process.ExitCode -ne 0) 'The CLI accepted a missing range endpoint.'
        $errorText = [System.IO.File]::ReadAllText($stderr, [System.Text.Encoding]::Default)
        # Windows PowerShell can wrap a Write-Error message within a word.
        $unwrappedError = $errorText -replace '\s', ''
        Assert-True ($unwrappedError -match 'both-FromStepand-ToStep') ('The CLI did not explain its explicit-range requirement: ' + $errorText)
        Assert-True (-not [System.IO.File]::Exists($requestPath)) 'A rejected CLI invocation published a request.'
        Record-Pass $Name
    }
    finally {
        if (-not $process.HasExited) { $process.Kill(); $process.WaitForExit() }
        $process.Dispose()
    }
}

try {
    $resolvedCli = (Resolve-Path -LiteralPath $CliPath).Path
    $validPath = Write-TestPlan (New-TestPlan) 'valid'
    $selected = Get-TeraTermSelectedPlan -PlanPath $validPath -FromStep 2 -ToStep 3
    Assert-True ($selected.Steps.Count -eq 2) 'The selected range must contain exactly two steps.'
    Assert-True (($selected.Steps.Id -join ',') -ceq '2,3') 'The selected range included a step outside 2 through 3.'
    Assert-True (($selected.Steps.Command -join ',') -ceq 'echo DEMO_STEP_2,echo DEMO_STEP_3') 'Commands did not preserve their selected order.'
    Record-Pass 'only steps 2 and 3 are selected in order'

    Assert-Rejected { Get-TeraTermSelectedPlan -PlanPath $validPath -FromStep 2 -ToStep 5 } 'endpoints must exist' 'absent upper endpoint'
    Assert-Rejected { Get-TeraTermSelectedPlan -PlanPath $validPath -FromStep 0 -ToStep 3 } 'positive inclusive' 'non-positive lower endpoint'
    Assert-Rejected { Get-TeraTermSelectedPlan -PlanPath $validPath -FromStep 3 -ToStep 2 } 'positive inclusive' 'reversed range'

    $plan = New-TestPlan
    $plan.steps[2].id = 2
    Assert-PlanRejected $plan 'duplicate-step-ids' 'strictly increasing'
    $plan = New-TestPlan
    $plan.steps[1].command = 'echo first' + [char]10 + 'echo second'
    Assert-PlanRejected $plan 'multiline-command' 'without control characters'
    $plan = New-TestPlan
    $plan.steps[1].command = 'echo first' + [char]13 + 'echo second'
    Assert-PlanRejected $plan 'carriage-return-command' 'without control characters'
    $plan = New-TestPlan
    $plan.steps[1].command = 'echo ' + [char]27 + '[31m'
    Assert-PlanRejected $plan 'terminal-control-command' 'without control characters'

    # Use character codes so this script stays readable by PowerShell 5.1 on any ACP.
    $plan = New-TestPlan
    $plan.steps[1].command = [string]::new([char]0x3042, 128)
    $boundaryPath = Write-TestPlan $plan 'utf8-at-limit'
    $null = Get-TeraTermSelectedPlan -PlanPath $boundaryPath -FromStep 2 -ToStep 3
    Record-Pass '384 UTF-8 bytes are accepted'
    $plan.steps[1].command += [char]0x3042
    Assert-PlanRejected $plan 'utf8-over-limit' '384 UTF-8 bytes'

    $plan = New-TestPlan
    $plan.steps[1].expect = '['
    Assert-PlanRejected $plan 'invalid-regex' 'Invalid expected-prompt regex'
    $plan = New-TestPlan
    $plan.steps[1].expect = '.*'
    Assert-PlanRejected $plan 'empty-matching-regex' 'must not match an empty string'
    foreach ($timeout in @(0, 301)) {
        $plan = New-TestPlan
        $plan.steps[1].timeoutSeconds = $timeout
        Assert-PlanRejected $plan ('timeout-' + $timeout) 'integer from 1 through 300'
    }
    Assert-PlanRejected (New-TestPlan 101) 'more-than-100-selected' 'between 1 and 100 steps' 1 101

    $sessionId = [guid]::NewGuid().ToString('N')
    $sessionDirectory = Join-Path (Join-Path $scratchRoot 'sessions') $sessionId
    [void][System.IO.Directory]::CreateDirectory($sessionDirectory)
    $metadata = [pscustomobject]@{
        Id = $sessionId; Host = 'stale-mock-session'; LogPath = (Join-Path $scratchRoot 'stale.log')
        CreatedAt = [DateTime]::UtcNow.ToString('o'); MacroProcessId = 0; MacroStartedAt = ''
    }
    [System.IO.File]::WriteAllText((Join-Path $sessionDirectory 'session.json'), ($metadata | ConvertTo-Json), $utf8)
    $statusLines = @('1', 'idle', '', '', '0', '0', 'Stale manual control.', 'END', '')
    [System.IO.File]::WriteAllText((Join-Path $sessionDirectory 'status.txt'), ($statusLines -join [char]10), $utf8)
    $requestPath = Join-Path $sessionDirectory 'request.ready'
    $status = Get-TeraTermStatus -SessionId $sessionId -StateRoot $scratchRoot
    Assert-True (-not $status.MacroAlive -and $status.State -ceq 'disconnected') 'A stale idle status must be reported as disconnected.'
    Assert-Rejected { Submit-TeraTermPlan -SessionId $sessionId -PlanPath $validPath -FromStep 2 -ToStep 3 -StateRoot $scratchRoot } 'no longer connected' 'stale idle session cannot receive a plan'
    Assert-True (-not [System.IO.File]::Exists($requestPath)) 'A stale session received a request.'
    $lockPath = Join-Path $sessionDirectory 'submit.lock'
    $reacquiredLock = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    $reacquiredLock.Dispose()
    Record-Pass 'rejected submission releases the exclusive session lock'

    Assert-CliRangeRequired 'CLI-requires-both-endpoints' ''
    Write-Output ('All {0} plan and submission checks passed.' -f $script:passed)
}
finally {
    $cleanupTarget = [System.IO.Path]::GetFullPath($scratchRoot)
    $cleanupParent = [System.IO.Path]::GetDirectoryName($cleanupTarget).TrimEnd('\')
    $leaf = [System.IO.Path]::GetFileName($cleanupTarget)
    if ($cleanupParent -ine $scratchParent -or $leaf -notmatch '^teraterm_logger_plans_[0-9a-f]{32}$') {
        throw 'Refusing to clean an unexpected plan-test directory.'
    }
    if (Test-Path -LiteralPath $cleanupTarget) { Remove-Item -LiteralPath $cleanupTarget -Recurse -Force }
}
