Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Utf8 = [System.Text.UTF8Encoding]::new($false, $true)

function Get-TeraTermStateRoot {
    param([string]$StateRoot)
    if ([string]::IsNullOrWhiteSpace($StateRoot)) { $StateRoot = $env:TERATERM_LOGGER_HOME }
    if ([string]::IsNullOrWhiteSpace($StateRoot)) {
        $StateRoot = Join-Path ([Environment]::GetFolderPath('LocalApplicationData')) 'teraterm_logger'
    }
    return [System.IO.Path]::GetFullPath($StateRoot)
}

function Assert-TeraTermField {
    param([string]$Value, [string]$Name, [switch]$AllowEmpty)
    if (-not $AllowEmpty -and [string]::IsNullOrWhiteSpace($Value)) { throw "$Name must not be empty." }
    if ($Value -match '[\x00-\x1f\x7f-\x9f]') { throw "$Name must be a single line without control characters." }
    if ($script:Utf8.GetByteCount($Value) -gt 384) { throw "$Name exceeds 384 UTF-8 bytes." }
}

function Get-TeraTermSessionDirectory {
    param([string]$SessionId, [string]$StateRoot)
    if ($SessionId -cnotmatch '^[0-9a-f]{32}$') { throw 'Specify an exact session ID from -Action Sessions.' }
    return Join-Path (Join-Path (Get-TeraTermStateRoot $StateRoot) 'sessions') $SessionId
}

function Get-TeraTermMetadata {
    param([string]$SessionId, [string]$StateRoot)
    $path = Join-Path (Get-TeraTermSessionDirectory $SessionId $StateRoot) 'session.json'
    if (-not [System.IO.File]::Exists($path)) { throw "Session not found: $SessionId" }
    return ([System.IO.File]::ReadAllText($path, $script:Utf8) | ConvertFrom-Json)
}

function Test-TeraTermMacroAlive {
    param($Metadata)
    try {
        if ([int]$Metadata.MacroProcessId -le 0) { return $false }
        $process = Get-Process -Id ([int]$Metadata.MacroProcessId) -ErrorAction Stop
        return ($process.ProcessName -ieq 'ttpmacro' -and
            $process.StartTime.ToUniversalTime().ToString('o') -ceq [string]$Metadata.MacroStartedAt)
    }
    catch { return $false }
}

function New-TeraTermSession {
    param([Parameter(Mandatory = $true)][string]$RequestPath, [string]$StateRoot)
    $request = [System.IO.File]::ReadAllLines($RequestPath, $script:Utf8)
    if ($request.Count -ne 1) { throw 'The initialization request must contain the connected host.' }
    $targetHost = $request[0]
    if ([string]::IsNullOrWhiteSpace($targetHost)) { $targetHost = 'session' }
    Assert-TeraTermField $targetHost 'Connected host'
    $root = Get-TeraTermStateRoot $StateRoot
    $logRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'TeraTermLogs'
    $configPath = Join-Path $root 'config.json'
    if ([System.IO.File]::Exists($configPath)) {
        $config = [System.IO.File]::ReadAllText($configPath, $script:Utf8) | ConvertFrom-Json
        if ($config.PSObject.Properties.Name -contains 'LogRoot' -and
            -not [string]::IsNullOrWhiteSpace([string]$config.LogRoot)) {
            if (-not [System.IO.Path]::IsPathRooted([string]$config.LogRoot)) { throw 'LogRoot must be an absolute path.' }
            $logRoot = [System.IO.Path]::GetFullPath([string]$config.LogRoot)
        }
    }
    # The bootstrap process is a child of the owning macro, not a device client.
    try {
        $parentId = (Get-CimInstance Win32_Process -Filter ("ProcessId={0}" -f $PID)).ParentProcessId
        $macro = Get-Process -Id $parentId -ErrorAction Stop
        if ($macro.ProcessName -ine 'ttpmacro') { throw 'Not invoked by a macro.' }
        $macroId = $macro.Id
        $macroStartedAt = $macro.StartTime.ToUniversalTime().ToString('o')
    }
    catch { throw 'Could not identify the owning Tera Term macro. Start auto_log_prompt.ttl from Tera Term.' }
    $stamp = Get-Date
    $logFolder = Join-Path $logRoot $stamp.ToString('yyyy-MM-dd')
    $safeHost = [regex]::Replace($targetHost, '[<>:"/\\|?*\x00-\x20\x7f-\x9f]', '_').Trim(' ', '.', '_')
    if ([string]::IsNullOrWhiteSpace($safeHost)) { $safeHost = 'session' }
    if ($safeHost.Length -gt 48) {
        $safeHost = $safeHost.Substring(0, 48)
        if ([char]::IsHighSurrogate($safeHost[$safeHost.Length - 1])) { $safeHost = $safeHost.Substring(0, $safeHost.Length - 1) }
    }
    $sessionId = [guid]::NewGuid().ToString('N')
    $sessionDirectory = Get-TeraTermSessionDirectory $sessionId $root
    $logPath = Join-Path $logFolder ('{0}_{1}_{2}.log' -f $stamp.ToString('yyyyMMdd_HHmmssfff'), $safeHost, $sessionId)
    Assert-TeraTermField $sessionDirectory 'Session directory'
    Assert-TeraTermField $logPath 'Log path'
    [void][System.IO.Directory]::CreateDirectory($logFolder)
    [void][System.IO.Directory]::CreateDirectory($sessionDirectory)
    $reservation = [System.IO.File]::Open($logPath, [System.IO.FileMode]::CreateNew,
        [System.IO.FileAccess]::Write, [System.IO.FileShare]::ReadWrite)
    $reservation.Dispose()
    $metadata = [pscustomobject][ordered]@{
        Id = $sessionId; Host = $targetHost; LogPath = $logPath
        CreatedAt = $stamp.ToUniversalTime().ToString('o')
        MacroProcessId = $macroId; MacroStartedAt = $macroStartedAt
    }
    [System.IO.File]::WriteAllText((Join-Path $sessionDirectory 'session.json'),
        ($metadata | ConvertTo-Json -Depth 4), $script:Utf8)
    [System.IO.File]::WriteAllText(($RequestPath + '.result'),
        ($logPath + [char]10 + $sessionDirectory + [char]10), $script:Utf8)
    return $metadata
}

function Get-TeraTermStatus {
    param([Parameter(Mandatory = $true)][string]$SessionId, [string]$StateRoot)
    $metadata = Get-TeraTermMetadata $SessionId $StateRoot
    $directory = Get-TeraTermSessionDirectory $SessionId $StateRoot
    $path = Join-Path $directory 'status.txt'
    $lines = $null
    for ($attempt = 0; $attempt -lt 8; $attempt++) {
        try {
            $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read,
                ([System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete))
            try {
                $reader = [System.IO.StreamReader]::new($stream, $script:Utf8, $false)
                try { $text = $reader.ReadToEnd() } finally { $reader.Dispose() }
            }
            finally { $stream.Dispose() }
            $candidate = @($text -split '\r?\n')
            if ($candidate.Count -ge 8 -and $candidate[0] -eq '1' -and $candidate[7] -eq 'END' -and
                $candidate[4] -match '^[0-9]+$' -and $candidate[5] -match '^[0-9]+$') {
                $lines = $candidate
                break
            }
        }
        catch [System.IO.IOException] { }
        Start-Sleep -Milliseconds 40
    }
    $alive = Test-TeraTermMacroAlive $metadata
    $state = 'starting'
    $runId = ''; $planName = ''; $currentStep = 0; $lastCompleted = 0; $message = 'Waiting for the logging macro.'
    if ($null -ne $lines) {
        $state = $lines[1]; $runId = $lines[2]; $planName = $lines[3]
        $currentStep = [int]$lines[4]; $lastCompleted = [int]$lines[5]; $message = $lines[6]
    }
    if (-not $alive) { $state = 'disconnected'; $message = 'The owning macro has exited. An in-flight step has an unknown outcome.' }
    $requestPath = Join-Path $directory 'request.ready'
    if ($alive -and $state -in @('idle', 'completed', 'stopped') -and [System.IO.File]::Exists($requestPath)) {
        try {
            $queued = [System.IO.File]::ReadAllLines($requestPath, $script:Utf8)
            if ($queued.Count -ge 3 -and $queued[1] -cne $runId) {
                $state = 'queued'; $runId = $queued[1]; $planName = $queued[2]
                $currentStep = 0; $lastCompleted = 0; $message = 'Waiting for the resident macro to start the selected range.'
            }
        }
        catch [System.IO.IOException] { }
    }
    $events = @()
    $eventsPath = Join-Path $directory 'events.tsv'
    if ([System.IO.File]::Exists($eventsPath)) {
        try { $events = @([System.IO.File]::ReadAllLines($eventsPath, $script:Utf8)) }
        catch [System.IO.IOException] { }
    }
    return [pscustomobject][ordered]@{
        SessionId = $metadata.Id; Host = $metadata.Host; LogPath = $metadata.LogPath; CreatedAt = $metadata.CreatedAt
        State = $state; RunId = $runId; PlanName = $planName
        CurrentStep = $currentStep; LastCompletedStep = $lastCompleted; Message = $message
        MacroAlive = $alive; RequestPending = [System.IO.File]::Exists($requestPath); Events = $events
    }
}

function Get-TeraTermSessions {
    param([string]$StateRoot, [switch]$IncludeInactive)
    $sessions = Join-Path (Get-TeraTermStateRoot $StateRoot) 'sessions'
    if (-not [System.IO.Directory]::Exists($sessions)) { return }
    foreach ($directory in Get-ChildItem -LiteralPath $sessions -Directory) {
        if ($directory.Name -cnotmatch '^[0-9a-f]{32}$') { continue }
        try {
            $status = Get-TeraTermStatus $directory.Name $StateRoot
            if ($IncludeInactive -or $status.MacroAlive) { $status }
        }
        catch { Write-Warning ("Could not read session {0}: {1}" -f $directory.Name, $_.Exception.Message) }
    }
}

function Get-TeraTermSelectedPlan {
    param([string]$PlanPath, [int]$FromStep, [int]$ToStep)
    if ($FromStep -le 0 -or $ToStep -lt $FromStep) { throw 'Specify a positive inclusive -FromStep and -ToStep range.' }
    $plan = [System.IO.File]::ReadAllText((Resolve-Path -LiteralPath $PlanPath).Path, $script:Utf8) | ConvertFrom-Json
    if ($plan.PSObject.Properties.Name -notcontains 'name' -or $plan.PSObject.Properties.Name -notcontains 'steps') {
        throw 'A plan requires name and steps.'
    }
    Assert-TeraTermField ([string]$plan.name) 'Plan name'
    $previous = 0
    $selected = @()
    $allIds = @()
    foreach ($step in @($plan.steps)) {
        foreach ($field in @('id', 'label', 'command', 'expect', 'timeoutSeconds')) {
            if ($step.PSObject.Properties.Name -notcontains $field) { throw "Each step requires $field." }
        }
        $idText = [string]$step.id
        $timeoutText = [string]$step.timeoutSeconds
        if ($idText -cnotmatch '^[1-9][0-9]{0,8}$' -or [int]$idText -le $previous) {
            throw 'Step IDs must be strictly increasing positive integers (at most 9 digits).'
        }
        $previous = [int]$idText
        $allIds += $previous
        if ($previous -lt $FromStep -or $previous -gt $ToStep) { continue }
        Assert-TeraTermField ([string]$step.label) 'Step label'
        Assert-TeraTermField ([string]$step.command) 'Command'
        Assert-TeraTermField ([string]$step.expect) 'Expected prompt'
        if ($timeoutText -cnotmatch '^[1-9][0-9]{0,2}$' -or [int]$timeoutText -gt 300) {
            throw 'timeoutSeconds must be an integer from 1 through 300.'
        }
        try {
            $expression = [regex]::new([string]$step.expect)
            if ($expression.IsMatch('')) { throw 'The expected prompt must not match an empty string.' }
        }
        catch { throw ('Invalid expected-prompt regex: ' + $_.Exception.Message) }
        $selected += [pscustomobject]@{
            Id = $previous; Label = [string]$step.label; Command = [string]$step.command
            Expect = [string]$step.expect; TimeoutSeconds = [int]$timeoutText
        }
    }
    if ($allIds -notcontains $FromStep -or $allIds -notcontains $ToStep) { throw 'Both range endpoints must exist in the plan.' }
    if ($selected.Count -lt 1 -or $selected.Count -gt 100) { throw 'Select between 1 and 100 steps.' }
    return [pscustomobject]@{ Name = [string]$plan.name; Steps = $selected }
}

function Submit-TeraTermPlan {
    param([Parameter(Mandatory = $true)][string]$SessionId, [string]$PlanPath,
        [int]$FromStep, [int]$ToStep, [string]$StateRoot)
    $plan = Get-TeraTermSelectedPlan $PlanPath $FromStep $ToStep
    $directory = Get-TeraTermSessionDirectory $SessionId $StateRoot
    $lockPath = Join-Path $directory 'submit.lock'
    $lock = $null
    $temporary = $null
    try {
        # A persistent file with an exclusive OS handle survives caller crashes
        # without becoming a stale lock. Never delete it after releasing the handle.
        try { $lock = [System.IO.File]::Open($lockPath, [System.IO.FileMode]::OpenOrCreate, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None) }
        catch [System.IO.IOException] { throw 'Another submission is in progress for this session.' }
        $status = Get-TeraTermStatus $SessionId $StateRoot
        if (-not $status.MacroAlive) { throw 'This session is no longer connected to its owning macro.' }
        if ($status.RequestPending) { throw 'This session already has a pending or running plan.' }
        if ($status.State -notin @('idle', 'completed', 'stopped')) {
            throw ("Session is {0}. Check the terminal before starting another plan; timeouts are not retried automatically." -f $status.State)
        }
        $runId = [guid]::NewGuid().ToString('N')
        $lines = [System.Collections.Generic.List[string]]::new()
        foreach ($line in @('1', $runId, $plan.Name, [string]$FromStep, [string]$ToStep, [string]$plan.Steps.Count)) { $lines.Add($line) }
        foreach ($step in $plan.Steps) {
            foreach ($line in @([string]$step.Id, $step.Label, $step.Command, $step.Expect, [string]$step.TimeoutSeconds)) { $lines.Add($line) }
        }
        $temporary = Join-Path $directory ("request.{0}.tmp" -f $runId)
        [System.IO.File]::WriteAllText($temporary, (($lines -join [char]10) + [char]10), $script:Utf8)
        [System.IO.File]::Move($temporary, (Join-Path $directory 'request.ready'))
        $temporary = $null
        return [pscustomobject]@{
            SessionId = $SessionId; RunId = $runId; PlanName = $plan.Name
            FromStep = $FromStep; ToStep = $ToStep; StepCount = $plan.Steps.Count
            State = 'queued'; LogPath = $status.LogPath
        }
    }
    finally {
        if ($null -ne $temporary -and [System.IO.File]::Exists($temporary)) { [System.IO.File]::Delete($temporary) }
        if ($null -ne $lock) { $lock.Dispose() }
    }
}

function Stop-TeraTermPlan {
    param([Parameter(Mandatory = $true)][string]$SessionId, [string]$StateRoot)
    $directory = Get-TeraTermSessionDirectory $SessionId $StateRoot
    $path = Join-Path $directory 'request.ready'
    if (-not [System.IO.File]::Exists($path)) { throw 'There is no pending or running plan to stop.' }
    $request = [System.IO.File]::ReadAllLines($path, $script:Utf8)
    if ($request.Count -lt 2 -or $request[1] -cnotmatch '^[0-9a-f]{32}$') { throw 'The current request has no valid run ID.' }
    [System.IO.File]::WriteAllText((Join-Path $directory ('stop.' + $request[1])), 'Stop before the next command.', $script:Utf8)
    return [pscustomobject]@{
        SessionId = $SessionId; RunId = $request[1]; State = 'stop-requested'
        Message = 'No further command will be sent after the current command completes or reaches its timeout.'
    }
}

function Confirm-TeraTermHandoff {
    param([Parameter(Mandatory = $true)][string]$SessionId, [string]$StateRoot)
    $status = Get-TeraTermStatus $SessionId $StateRoot
    if (-not $status.MacroAlive -or $status.RequestPending -or $status.State -notin @('timeout', 'error')) {
        throw 'Acknowledge requires a live session stopped by a timeout or error, with no pending plan.'
    }
    $directory = Get-TeraTermSessionDirectory $SessionId $StateRoot
    # Bind the acknowledgment to the inspected run, and publish only a complete
    # file, so a delayed caller cannot re-arm a different run's unknown result.
    $ackTemporary = Join-Path $directory ('ack.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        [System.IO.File]::WriteAllText($ackTemporary, ($status.RunId + [char]10), $script:Utf8)
        [System.IO.File]::Move($ackTemporary, (Join-Path $directory 'ack.ready'))
    }
    finally {
        if ([System.IO.File]::Exists($ackTemporary)) { [System.IO.File]::Delete($ackTemporary) }
    }
    return [pscustomobject]@{
        SessionId = $SessionId; State = 'acknowledgment-requested'
        Message = 'The resident macro will return to idle without resending any command.'
    }
}

Export-ModuleMember -Function Get-TeraTermStateRoot, New-TeraTermSession, Get-TeraTermStatus,
    Get-TeraTermSessions, Get-TeraTermSelectedPlan, Submit-TeraTermPlan, Stop-TeraTermPlan, Confirm-TeraTermHandoff
