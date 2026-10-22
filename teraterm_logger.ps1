param(
    [ValidateSet('Initialize', 'Sessions', 'Run', 'Status', 'Stop', 'Acknowledge')]
    [string]$Action = 'Sessions',
    [string]$SessionId,
    [string]$PlanPath,
    [int]$FromStep,
    [int]$ToStep,
    [string]$StateRoot,
    [string]$RequestPath,
    [switch]$IncludeInactive
)

$ErrorActionPreference = 'Stop'
try {
    Import-Module (Join-Path $PSScriptRoot 'TeratermLogger.psm1') -Force
    switch ($Action) {
        'Initialize' {
            if ([string]::IsNullOrWhiteSpace($RequestPath)) { throw 'Initialize requires RequestPath.' }
            $result = New-TeraTermSession -RequestPath $RequestPath -StateRoot $StateRoot
        }
        'Sessions' { $result = @(Get-TeraTermSessions -StateRoot $StateRoot -IncludeInactive:$IncludeInactive) }
        'Status' { $result = Get-TeraTermStatus -SessionId $SessionId -StateRoot $StateRoot }
        'Run' {
            if (-not $PSBoundParameters.ContainsKey('FromStep') -or -not $PSBoundParameters.ContainsKey('ToStep')) {
                throw 'Run requires both -FromStep and -ToStep. A whole plan is never selected implicitly.'
            }
            $result = Submit-TeraTermPlan -SessionId $SessionId -PlanPath $PlanPath -FromStep $FromStep -ToStep $ToStep -StateRoot $StateRoot
        }
        'Stop' { $result = Stop-TeraTermPlan -SessionId $SessionId -StateRoot $StateRoot }
        'Acknowledge' { $result = Confirm-TeraTermHandoff -SessionId $SessionId -StateRoot $StateRoot }
    }
    ConvertTo-Json -InputObject $result -Depth 8
}
catch {
    if ($Action -eq 'Initialize' -and -not [string]::IsNullOrWhiteSpace($RequestPath)) {
        [System.IO.File]::WriteAllText(($RequestPath + '.error.txt'), $_.Exception.Message, [System.Text.UTF8Encoding]::new($false))
    }
    Write-Error $_
    exit 1
}
