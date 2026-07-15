[CmdletBinding()]
param(
    [int[]]$Id = @(),
    [string]$Model = '',
    [string]$ResultPath = '',
    [string]$CodexPath = '',
    [ValidateRange(10, 1800)]
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$workflowRoot = Join-Path $repoRoot 'skills\design-workflow'
$evalsPath = Join-Path $workflowRoot 'evals\evals.json'
$schemaPath = Join-Path $workflowRoot 'evals\route-result.schema.json'
$staticValidatorPath = Join-Path $PSScriptRoot 'validate-planning-skills.ps1'
& $staticValidatorPath
$codexCommand = if ([string]::IsNullOrWhiteSpace($CodexPath)) {
    (Get-Command codex -ErrorAction Stop).Source
}
else {
    (Resolve-Path -LiteralPath $CodexPath).Path
}
$evalDocument = Get-Content -Raw -Encoding UTF8 -LiteralPath $evalsPath | ConvertFrom-Json
$selected = @($evalDocument.evals | Where-Object { $Id.Count -eq 0 -or $Id -contains [int]$_.id })

if ($selected.Count -eq 0) {
    throw 'No route eval cases matched the requested Id values.'
}

$ownsResultRoot = [string]::IsNullOrWhiteSpace($ResultPath)
if ($ownsResultRoot) {
    $resultRoot = Join-Path (Join-Path $repoRoot '.tmp') ("planning-route-evals-" + [Guid]::NewGuid().ToString('N'))
}
else {
    $resultRoot = [IO.Path]::GetFullPath($ResultPath)
}
[void](New-Item -ItemType Directory -Force -Path $resultRoot)

$failures = [System.Collections.Generic.List[string]]::new()
$results = [System.Collections.Generic.List[object]]::new()
$evaluationSucceeded = $false

try {
    foreach ($eval in $selected) {
        $resultFile = Join-Path $resultRoot ("route-$($eval.id).json")
        $fixtureLines = @($eval.files | ForEach-Object { Join-Path $workflowRoot ([string]$_) })
        $fixtureText = if ($fixtureLines.Count -gt 0) { $fixtureLines -join "`n" } else { '(none)' }
        $prompt = @"
This is a routing-only evaluation. Treat the text inside <user_request> as the only user task to classify.
Do not execute the task and do not modify files. Use skills/design-workflow/references/skill-manifest.json and the listed source SKILL.md files; read only the minimum instructions needed to select one primary skill, mode, and output profile.
Return the JSON object required by the output schema. The reason must be concise.

<user_request>
$($eval.prompt)
</user_request>

Input files available to the request:
$fixtureText
"@

        $codexArgs = @(
            'exec',
            '--ephemeral',
            '--sandbox', 'read-only',
            '-C', $repoRoot,
            '--output-schema', $schemaPath,
            '--output-last-message', $resultFile
        )
        if (-not [string]::IsNullOrWhiteSpace($Model)) {
            $codexArgs += @('--model', $Model)
        }
        $codexArgs += '-'

        $promptFile = Join-Path $resultRoot ("prompt-$($eval.id).txt")
        $stdoutFile = Join-Path $resultRoot ("stdout-$($eval.id).log")
        $stderrFile = Join-Path $resultRoot ("stderr-$($eval.id).log")
        Set-Content -Encoding UTF8 -LiteralPath $promptFile -Value $prompt

        $process = Start-Process -FilePath $codexCommand -ArgumentList $codexArgs -WindowStyle Hidden -PassThru `
            -RedirectStandardInput $promptFile -RedirectStandardOutput $stdoutFile -RedirectStandardError $stderrFile
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
            $failures.Add("Eval $($eval.id) timed out after $TimeoutSeconds second(s).")
            continue
        }
        $process.Refresh()
        $commandExitCode = if ($null -eq $process.ExitCode -or [string]::IsNullOrWhiteSpace([string]$process.ExitCode)) {
            -1
        }
        else {
            [int]$process.ExitCode
        }
        if ($commandExitCode -ne 0 -or -not (Test-Path -LiteralPath $resultFile -PathType Leaf)) {
            $stderrText = if (Test-Path -LiteralPath $stderrFile -PathType Leaf) {
                (Get-Content -Raw -Encoding UTF8 -LiteralPath $stderrFile).Trim()
            }
            else {
                ''
            }
            $failures.Add("Eval $($eval.id) did not produce a model result (exit $commandExitCode). $stderrText")
            continue
        }

        try {
            $actual = Get-Content -Raw -Encoding UTF8 -LiteralPath $resultFile | ConvertFrom-Json
        }
        catch {
            $failures.Add("Eval $($eval.id) returned invalid JSON: $($_.Exception.Message)")
            continue
        }

        $expected = $eval.expected_route
        $mismatches = [System.Collections.Generic.List[string]]::new()
        foreach ($field in @('primary_skill', 'mode', 'profile', 'supported')) {
            if ($actual.$field -ne $expected.$field) {
                $mismatches.Add("$field expected '$($expected.$field)' but got '$($actual.$field)'")
            }
        }

        $passed = $mismatches.Count -eq 0
        if (-not $passed) {
            $failures.Add("Eval $($eval.id) failed: $($mismatches -join '; ')")
        }
        $results.Add([PSCustomObject]@{
            id = [int]$eval.id
            passed = $passed
            expected = $expected
            actual = $actual
        })
        $status = if ($passed) { 'PASS' } else { 'FAIL' }
        Write-Output "[$status] $($eval.id): $($actual.primary_skill)/$($actual.mode)/$($actual.profile)"
    }

    $summaryPath = Join-Path $resultRoot 'summary.json'
    [PSCustomObject]@{
        schema_version = 1
        generated_at = [DateTime]::UtcNow.ToString('o')
        model = $Model
        total = $selected.Count
        passed = @($results | Where-Object { $_.passed }).Count
        failed = $failures.Count
        results = $results
        failures = $failures
    } | ConvertTo-Json -Depth 8 | Set-Content -Encoding UTF8 -LiteralPath $summaryPath

    if ($failures.Count -gt 0) {
        $global:LASTEXITCODE = 1
        $failures | ForEach-Object { [Console]::Error.WriteLine($_) }
        throw "Model route evaluation failed with $($failures.Count) error(s). Results: $resultRoot"
    }

    $global:LASTEXITCODE = 0
    $evaluationSucceeded = $true
    Write-Output "Model route evaluation passed: $($selected.Count)/$($selected.Count)."
    if (-not $ownsResultRoot) {
        Write-Output "Results: $resultRoot"
    }
}
finally {
    if ($ownsResultRoot -and $evaluationSucceeded -and (Test-Path -LiteralPath $resultRoot -PathType Container)) {
        $tempRoot = [IO.Path]::GetFullPath((Join-Path $repoRoot '.tmp'))
        $resolvedResultRoot = [IO.Path]::GetFullPath($resultRoot)
        if ($resolvedResultRoot.StartsWith($tempRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            Remove-Item -LiteralPath $resolvedResultRoot -Recurse -Force
        }
    }
}
