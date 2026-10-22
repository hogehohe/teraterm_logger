[CmdletBinding()]
param(
    [string]$TeraTermDirectory = 'C:\Program Files\teraterm5',
    [switch]$Native,
    [switch]$PauseAfterRange,
    [string]$WorkRoot
)

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$cli = Join-Path $repoRoot 'teraterm_logger.ps1'
$utf8 = New-Object System.Text.UTF8Encoding($false)
if ([string]::IsNullOrWhiteSpace($WorkRoot)) {
    $WorkRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('teraterm-workflow-test-' + [guid]::NewGuid().ToString('N'))
}
[void][System.IO.Directory]::CreateDirectory($WorkRoot)
$script:checks = 0

function Assert-True([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw $Message }
    $script:checks++
    Write-Host "PASS: $Message"
}

function Write-JsonFile([string]$Path, $Value) {
    [System.IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 12), $utf8)
}

function Invoke-LoggerProcess {
    param([string[]]$Arguments)
    $ErrorActionPreference = 'Continue'
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $cli @Arguments 2>&1
    $code = $LASTEXITCODE
    return [pscustomobject]@{ Code = $code; Output = ($output -join [Environment]::NewLine) }
}

function Invoke-Logger {
    param([string[]]$Arguments)
    $result = Invoke-LoggerProcess -Arguments $Arguments
    if ($result.Code -ne 0) { throw "Logger CLI failed ($($result.Code)): $($result.Output)" }
    return ($result.Output | ConvertFrom-Json)
}

function Assert-Throws([scriptblock]$Operation, [string]$Message) {
    $threw = $false
    try { & $Operation | Out-Null } catch { $threw = $true }
    Assert-True $threw $Message
}

function Wait-Until([scriptblock]$Condition, [string]$Description, [int]$Seconds = 45) {
    $deadline = [DateTime]::UtcNow.AddSeconds($Seconds)
    do {
        if (& $Condition) { return }
        Start-Sleep -Milliseconds 100
    } while ([DateTime]::UtcNow -lt $deadline)
    throw "Timed out waiting for $Description"
}

function Read-WireStatus([string]$SessionDirectory) {
    $path = Join-Path $SessionDirectory 'status.txt'
    if (-not (Test-Path -LiteralPath $path)) { return $null }
    try { $lines = [System.IO.File]::ReadAllLines($path, $utf8) } catch { return $null }
    if ($lines.Count -lt 8 -or $lines[0] -ne '1' -or $lines[7] -ne 'END') { return $null }
    [pscustomobject]@{
        State = $lines[1]; RunId = $lines[2]; Name = $lines[3]
        CurrentStep = $lines[4]; LastCompletedStep = $lines[5]; Message = $lines[6]
    }
}

function New-Step([int]$Id, [string]$Command, [int]$Timeout = 5) {
    return [ordered]@{ id = $Id; label = "Step $Id"; command = $Command; expect = '^mock> '; timeoutSeconds = $Timeout }
}

Import-Module (Join-Path $repoRoot 'TeratermLogger.psm1') -Force
$validationPlan = Join-Path $WorkRoot 'validation-plan.json'
Write-JsonFile $validationPlan @{ name = 'Range validation'; steps = @((New-Step 1 'one'), (New-Step 2 'two'), (New-Step 3 'three'), (New-Step 4 'four')) }
$selected = Get-TeraTermSelectedPlan -PlanPath $validationPlan -FromStep 2 -ToStep 3
Assert-True (($selected.Steps.Id -join ',') -eq '2,3') 'The selected range is inclusive and contains no outside steps'
Assert-Throws { Get-TeraTermSelectedPlan -PlanPath $validationPlan -FromStep 2 -ToStep 5 } 'A missing endpoint rejects the plan'
Assert-Throws { Get-TeraTermSelectedPlan -PlanPath $validationPlan -FromStep 3 -ToStep 2 } 'A reversed range rejects the plan'
$badPlanPath = Join-Path $WorkRoot 'invalid-plan.json'
foreach ($invalid in @(
    @{ Name = 'Commands containing line breaks are rejected'; Step = @{ id=1; label='test'; command="one`r`ntwo"; expect='mock> '; timeoutSeconds=1 } },
    @{ Name = 'Commands containing control characters are rejected'; Step = @{ id=1; label='test'; command=('one' + [char]27); expect='mock> '; timeoutSeconds=1 } },
    @{ Name = 'UTF-8 byte limits apply to multibyte commands'; Step = @{ id=1; label='test'; command=(([string][char]0x65E5) * 129); expect='mock> '; timeoutSeconds=1 } },
    @{ Name = 'An empty-match prompt regex is rejected'; Step = @{ id=1; label='test'; command='one'; expect='.*'; timeoutSeconds=1 } },
    @{ Name = 'An invalid prompt regex is rejected'; Step = @{ id=1; label='test'; command='one'; expect='['; timeoutSeconds=1 } },
    @{ Name = 'A zero timeout is rejected'; Step = @{ id=1; label='test'; command='one'; expect='mock> '; timeoutSeconds=0 } },
    @{ Name = 'A timeout over 300 seconds is rejected'; Step = @{ id=1; label='test'; command='one'; expect='mock> '; timeoutSeconds=301 } },
    @{ Name = 'A fractional timeout is rejected'; Step = @{ id=1; label='test'; command='one'; expect='mock> '; timeoutSeconds=1.5 } }
)) {
    Write-JsonFile $badPlanPath @{ name='Invalid'; steps=@($invalid.Step) }
    Assert-Throws { Get-TeraTermSelectedPlan -PlanPath $badPlanPath -FromStep 1 -ToStep 1 } $invalid.Name
}
Write-JsonFile $badPlanPath @{ name='Duplicate IDs'; steps=@((New-Step 1 'one'), (New-Step 1 'duplicate')) }
Assert-Throws { Get-TeraTermSelectedPlan -PlanPath $badPlanPath -FromStep 1 -ToStep 1 } 'Duplicate step IDs are rejected'
$manySteps = @(1..101 | ForEach-Object { New-Step $_ ('command-' + $_) })
Write-JsonFile $badPlanPath @{ name='Too many'; steps=$manySteps }
Assert-Throws { Get-TeraTermSelectedPlan -PlanPath $badPlanPath -FromStep 1 -ToStep 101 } 'More than 100 selected commands are rejected'
$implicitRange = Invoke-LoggerProcess -Arguments @('-Action','Run','-SessionId',([guid]::NewGuid().ToString('N')),'-PlanPath',$validationPlan,'-ToStep','3','-StateRoot',(Join-Path $WorkRoot 'empty-state'))
Assert-True ($implicitRange.Code -ne 0 -and (($implicitRange.Output -replace '\s','').Contains('requiresboth-FromStepand-ToStep'))) 'The CLI never selects a whole plan when a range endpoint is omitted'

if ($Native) {
    $macroExe = Join-Path $TeraTermDirectory 'ttpmacro.exe'
    Assert-True (Test-Path -LiteralPath $macroExe) 'Installed Tera Term macro runner is available'
    if (-not ('TeratermWorkflowMock' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Text;
using System.Threading;

public sealed class TeratermWorkflowMock : IDisposable {
    private readonly TcpListener listener;
    private readonly Thread thread;
    private TcpClient client;
    private readonly List<string> commands = new List<string>();
    private volatile bool disposed;
    public int Port { get; private set; }
    public bool Connected { get; private set; }
    public string Error { get; private set; }
    public TeratermWorkflowMock() {
        listener = new TcpListener(IPAddress.Loopback, 0);
        listener.Start();
        Port = ((IPEndPoint)listener.LocalEndpoint).Port;
        thread = new Thread(Serve);
        thread.IsBackground = true;
        thread.Start();
    }
    public string[] Commands { get { lock(commands) { return commands.ToArray(); } } }
    private void Send(NetworkStream stream, string value) {
        byte[] bytes = new UTF8Encoding(false).GetBytes(value);
        stream.Write(bytes, 0, bytes.Length);
        stream.Flush();
    }
    private void Serve() {
        try {
            client = listener.AcceptTcpClient();
            Connected = true;
            using (NetworkStream stream = client.GetStream()) {
                Thread.Sleep(500);
                Send(stream, "Local mock terminal ready\r\nmock> ");
                var line = new List<byte>();
                while (!disposed) {
                    int value = stream.ReadByte();
                    if (value < 0) break;
                    if (value == 10 && line.Count == 0) continue;
                    if (value != 13 && value != 10) { line.Add((byte)value); continue; }
                    string command = new UTF8Encoding(false, true).GetString(line.ToArray());
                    line.Clear();
                    lock(commands) { commands.Add(command); }
                    Send(stream, command + "\r\n");
                    if (command == "disconnect") break;
                    if (command == "never-complete") continue;
                    if (command == "hold") Thread.Sleep(3500);
                    Send(stream, "ok: " + command + "\r\nmock> ");
                }
            }
        } catch (Exception ex) { if (!disposed) Error = ex.ToString(); }
        finally { Connected = false; if (client != null) client.Close(); }
    }
    public void Dispose() {
        disposed = true;
        if (client != null) client.Close();
        listener.Stop();
        thread.Join(2000);
    }
}
'@
    }
}

if ($Native) {
    $stateRoot = Join-Path $WorkRoot 'state'
    $unicodeName = [string]([char]0x65E5) + [char]0x672C + [char]0x8A9E
    $logRoot = Join-Path $WorkRoot ('logs_' + $unicodeName)
    [void][System.IO.Directory]::CreateDirectory($stateRoot)
    Write-JsonFile (Join-Path $stateRoot 'config.json') @{ LogRoot = $logRoot }
    $previousStateRoot = $env:TERATERM_LOGGER_HOME
    $env:TERATERM_LOGGER_HOME = $stateRoot
    $mock = New-Object TeratermWorkflowMock
    $testTitle = 'teraterm-workflow-test-' + [guid]::NewGuid().ToString('N')
    $macroProcess = $null
    $terminalIds = @()
    try {
        $ini = Join-Path $WorkRoot 'isolated.ini'
        [System.IO.File]::WriteAllText($ini, "[Tera Term]`r`nLanguage=UTF-8`r`nKanjiReceive=UTF-8`r`nKanjiSend=UTF-8`r`nAutoWinClose=off`r`nStartupMacro=`r`nHostDialogOnStartup=off`r`n", $utf8)
        $wrapperPath = Join-Path $WorkRoot 'start-test.ttl'
        $wrapper = @"
connect '127.0.0.1:$($mock.Port) /nossh /T=0 /F="$ini" /KR=UTF-8 /KT=UTF-8 /W="$testTitle"'
timeout = 10
wait 'Local mock terminal ready'
showtt 1
setdir '$repoRoot'
include '$repoRoot\auto_log_prompt.ttl'
"@
        [System.IO.File]::WriteAllText($wrapperPath, $wrapper, $utf8)
        $macroProcess = Start-Process -FilePath $macroExe -ArgumentList @('/V', ('"' + $wrapperPath + '"')) -PassThru
        Wait-Until { $mock.Connected } 'localhost terminal connection'
        $terminalIds = @(Get-CimInstance Win32_Process -Filter ("ParentProcessId={0} AND Name='ttermpro.exe'" -f $macroProcess.Id) | ForEach-Object { [int]$_.ProcessId })
        Wait-Until {
            $script:sessionFile = Get-ChildItem -LiteralPath $stateRoot -Filter 'session.json' -File -Recurse | Select-Object -First 1
            return $null -ne $script:sessionFile
        } 'automatic session creation'
        $session = Get-Content -LiteralPath $script:sessionFile.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
        $sessionDirectory = $script:sessionFile.DirectoryName
        $sessionId = [string]$session.Id
        Wait-Until { Test-Path -LiteralPath $session.LogPath } 'automatic terminal log'
        Assert-True ($terminalIds.Count -eq 1) 'A dedicated Tera Term process owns the localhost session'
        Assert-True ($session.LogPath.StartsWith($logRoot, [StringComparison]::OrdinalIgnoreCase)) 'Automatic logs honor the configured Unicode root'
        Assert-True ([System.IO.Path]::GetExtension($session.LogPath) -eq '.log') 'Automatic logging chooses its own filename'
        Assert-True ($mock.Commands.Count -eq 0) 'Startup sends no device commands'

        $planPath = Join-Path $WorkRoot 'range-plan.json'
        Write-JsonFile $planPath ([ordered]@{ name = 'Exact range'; steps = @(
            (New-Step 1 'outside-before'), (New-Step 2 ('echo ' + $unicodeName)),
            (New-Step 3 'inside-three'), (New-Step 4 'outside-after')
        ) })
        $null = Invoke-Logger -Arguments @('-Action','Run','-SessionId',$sessionId,'-PlanPath',$planPath,'-FromStep','2','-ToStep','3','-StateRoot',$stateRoot)
        Wait-Until { $s = Read-WireStatus $sessionDirectory; $s -and $s.State -eq 'completed' } 'bounded plan completion'
        Assert-True (($mock.Commands -join '|') -eq (('echo ' + $unicodeName) + '|inside-three')) 'Only steps 2 through 3 reach the terminal, in order'
        $completed = Read-WireStatus $sessionDirectory
        Assert-True ($completed.LastCompletedStep -eq '3') 'Progress records the last completed step'
        Start-Sleep -Milliseconds 1200
        Assert-True ($mock.Connected -and $mock.Commands.Count -eq 2) 'Completion hands back the connected session without sending further commands'
        if ($PauseAfterRange) {
            Write-Host "Native range ready for observation. Tera Term PID: $($terminalIds -join ','). Log: $($session.LogPath)"
            Start-Sleep -Seconds 20
        }

        $stopPlan = Join-Path $WorkRoot 'stop-plan.json'
        Write-JsonFile $stopPlan @{ name = 'Stop boundary'; steps = @((New-Step 10 'hold' 10), (New-Step 11 'must-not-run-after-stop')) }
        $null = Submit-TeraTermPlan -SessionId $sessionId -PlanPath $stopPlan -FromStep 10 -ToStep 11 -StateRoot $stateRoot
        Wait-Until { $mock.Commands -contains 'hold' } 'in-flight command'
        Assert-Throws { Submit-TeraTermPlan -SessionId $sessionId -PlanPath $stopPlan -FromStep 10 -ToStep 11 -StateRoot $stateRoot } 'A concurrent plan cannot overwrite the active request'
        $null = Stop-TeraTermPlan -SessionId $sessionId -StateRoot $stateRoot
        Wait-Until { $s = Read-WireStatus $sessionDirectory; $s -and $s.State -eq 'stopped' } 'stop at next command boundary'
        Assert-True (-not ($mock.Commands -contains 'must-not-run-after-stop')) 'Stop prevents the next command after the current command finishes'

        $timeoutPlan = Join-Path $WorkRoot 'timeout-plan.json'
        Write-JsonFile $timeoutPlan @{ name = 'Timeout boundary'; steps = @((New-Step 20 'never-complete' 1), (New-Step 21 'must-not-run-after-timeout')) }
        $null = Invoke-Logger -Arguments @('-Action','Run','-SessionId',$sessionId,'-PlanPath',$timeoutPlan,'-FromStep','20','-ToStep','21','-StateRoot',$stateRoot)
        Wait-Until { $s = Read-WireStatus $sessionDirectory; $s -and $s.State -eq 'timeout' } 'command timeout'
        Assert-True (-not ($mock.Commands -contains 'must-not-run-after-timeout')) 'Timeout prevents every later command'

        $rejectedAfterTimeout = Invoke-LoggerProcess -Arguments @('-Action','Run','-SessionId',$sessionId,'-PlanPath',$validationPlan,'-FromStep','1','-ToStep','1','-StateRoot',$stateRoot)
        Assert-True ($rejectedAfterTimeout.Code -ne 0) 'A timed-out session cannot run another plan before terminal inspection is acknowledged'
        $null = Invoke-Logger -Arguments @('-Action','Acknowledge','-SessionId',$sessionId,'-StateRoot',$stateRoot)
        Wait-Until { $s = Read-WireStatus $sessionDirectory; $s -and $s.State -eq 'idle' } 'explicit return to manual control'
        Assert-True ($mock.Commands.Count -eq 4) 'Acknowledgement returns control without sending a device command'

        $disconnectPlan = Join-Path $WorkRoot 'disconnect-plan.json'
        Write-JsonFile $disconnectPlan @{ name = 'Disconnect boundary'; steps = @((New-Step 30 'disconnect' 2), (New-Step 31 'must-not-run-after-disconnect')) }
        $null = Invoke-Logger -Arguments @('-Action','Run','-SessionId',$sessionId,'-PlanPath',$disconnectPlan,'-FromStep','30','-ToStep','31','-StateRoot',$stateRoot)
        Wait-Until { $s = Read-WireStatus $sessionDirectory; $s -and $s.State -eq 'disconnected' } 'disconnect status'
        Assert-True (-not ($mock.Commands -contains 'must-not-run-after-disconnect')) 'Disconnect prevents the next command and does not reconnect'
        Start-Sleep -Milliseconds 1000
        $logText = [System.IO.File]::ReadAllText($session.LogPath, $utf8)
        Assert-True ($logText.Contains('echo ' + $unicodeName) -and $logText.Contains('ok: inside-three')) 'UTF-8 terminal logs contain the executed commands and responses'
        Assert-True ([string]::IsNullOrWhiteSpace($mock.Error)) 'The localhost mock completed without a transport error'
        Write-JsonFile (Join-Path $WorkRoot 'native-result.json') @{ Commands = @($mock.Commands); LogPath = $session.LogPath; Status = (Read-WireStatus $sessionDirectory); Checks = $script:checks }
    }
    finally {
        $mock.Dispose()
        if ($macroProcess -and -not $macroProcess.HasExited) { Stop-Process -Id $macroProcess.Id -ErrorAction SilentlyContinue }
        $remainingTestIds = @(Get-Process ttermpro -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like ('*' + $testTitle + '*') } | ForEach-Object { $_.Id })
        foreach ($terminalId in @($terminalIds + $remainingTestIds | Select-Object -Unique)) { Stop-Process -Id $terminalId -ErrorAction SilentlyContinue }
        $env:TERATERM_LOGGER_HOME = $previousStateRoot
    }
}

Write-Host "PASS: $script:checks workflow checks. Artifacts: $WorkRoot"
