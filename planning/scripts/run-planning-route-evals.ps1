[CmdletBinding()]
param(
    [int[]]$Id = @(),
    [string]$Model = '',
    [ValidateSet('low', 'medium', 'high', 'xhigh', 'max', 'ultra')]
    [string]$ReasoningEffort = 'low',
    [string]$ResultPath = '',
    [string]$CodexPath = '',
    [ValidateRange(10, 1800)]
    [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'

$planningRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repositoryRoot = (Resolve-Path (Join-Path $planningRoot '..')).Path
$manifestPath = Join-Path $planningRoot 'manifest.json'
$evalsPath = Join-Path $planningRoot 'evals\evals.json'
$schemaPath = Join-Path $planningRoot 'route-result.schema.json'
$routingMatrixPath = Join-Path $planningRoot 'routing-matrix.md'

& (Join-Path $PSScriptRoot 'validate-planning-skills.ps1')

$manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
$evalDocument = Get-Content -Raw -Encoding UTF8 -LiteralPath $evalsPath | ConvertFrom-Json
$planningEntries = @($manifest.skills | Where-Object { $_.kind -eq 'planning' })
$modeOwners = @{}
foreach ($entry in $planningEntries) {
    $modeOwners[[string]$entry.name] = @($entry.modes | ForEach-Object { [string]$_ })
}
$selected = @($evalDocument.evals | Where-Object { $Id.Count -eq 0 -or $Id -contains [int]$_.id })
if ($selected.Count -eq 0) {
    throw 'No route eval cases matched the requested Id values.'
}

$codexCommand = if ([string]::IsNullOrWhiteSpace($CodexPath)) {
    $codexApplication = @(Get-Command -Name 'codex.exe', 'codex.cmd' -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1)
    if ($codexApplication.Count -gt 0) { $codexApplication[0].Source }
    else { (Get-Command codex -ErrorAction Stop).Source }
}
else {
    (Resolve-Path -LiteralPath $CodexPath).Path
}
$codexLauncher = $codexCommand
$codexLauncherArgs = @()
if ([IO.Path]::GetExtension($codexCommand) -ieq '.ps1') {
    $codexLauncher = (Get-Command pwsh -CommandType Application -ErrorAction Stop | Select-Object -First 1).Source
    $codexLauncherArgs = @('-NoLogo', '-NoProfile', '-NonInteractive', '-File', $codexCommand)
}
$codexVersion = @(& $codexCommand --version 2>$null | Select-Object -First 1)
$effectiveModel = if ([string]::IsNullOrWhiteSpace($Model)) { '(codex built-in default)' } else { $Model }
if ([string]::IsNullOrWhiteSpace($Model)) {
    Write-Warning 'No -Model supplied; user config is ignored and the Codex built-in default will be recorded with the CLI version.'
}

function Stop-ProcessTree {
    param([int]$RootProcessId)

    $orderedIds = [System.Collections.Generic.List[int]]::new()
    $seenIds = @{}
    $pendingIds = [System.Collections.Generic.Queue[int]]::new()
    $pendingIds.Enqueue($RootProcessId)
    try {
        $processSnapshot = @(Get-CimInstance Win32_Process -ErrorAction Stop | Select-Object ProcessId, ParentProcessId)
        while ($pendingIds.Count -gt 0) {
            $currentId = $pendingIds.Dequeue()
            if ($seenIds.ContainsKey($currentId)) { continue }
            $seenIds[$currentId] = $true
            $orderedIds.Add($currentId)
            foreach ($child in @($processSnapshot | Where-Object { [int]$_.ParentProcessId -eq $currentId })) {
                $pendingIds.Enqueue([int]$child.ProcessId)
            }
        }
    }
    catch {
        $orderedIds.Clear()
        $orderedIds.Add($RootProcessId)
    }
    for ($index = $orderedIds.Count - 1; $index -ge 0; $index--) {
        Stop-Process -Id $orderedIds[$index] -Force -ErrorAction SilentlyContinue
    }
}

$ownsResultRoot = [string]::IsNullOrWhiteSpace($ResultPath)
if ($ownsResultRoot) {
    $temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
    $resultRoot = Join-Path $temporaryBase ("game-design-planning-route-evals-" + [Guid]::NewGuid().ToString('N'))
}
else {
    $resultRoot = [IO.Path]::GetFullPath($ResultPath)
    if (Test-Path -LiteralPath $resultRoot) {
        if (@(Get-ChildItem -LiteralPath $resultRoot -Force).Count -gt 0) {
            throw "ResultPath must be empty to avoid overwriting existing artifacts: $resultRoot"
        }
    }
}
[void](New-Item -ItemType Directory -Force -Path $resultRoot)

$temporaryBase = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
$modelWorkspace = Join-Path $temporaryBase ("game-design-planning-route-model-" + [Guid]::NewGuid().ToString('N'))
$modelSkillsRoot = Join-Path $modelWorkspace 'skills'
$snapshotWorkspace = Join-Path $resultRoot 'isolated-workspace'
$snapshotSkillsRoot = Join-Path $snapshotWorkspace 'skills'
$artifactRoot = Join-Path $resultRoot 'artifacts'
[void](New-Item -ItemType Directory -Force -Path $modelSkillsRoot)
[void](New-Item -ItemType Directory -Force -Path $snapshotSkillsRoot)
[void](New-Item -ItemType Directory -Force -Path $artifactRoot)

$sourceSkillRoot = [IO.Path]::GetFullPath((Join-Path $repositoryRoot (([string]$manifest.source_skill_root) -replace '/', [IO.Path]::DirectorySeparatorChar)))
foreach ($entry in $planningEntries) {
    $name = [string]$entry.name
    $source = Join-Path $sourceSkillRoot $name
    $target = Join-Path $modelSkillsRoot $name
    Copy-Item -LiteralPath $source -Destination $target -Recurse
    Copy-Item -LiteralPath $source -Destination (Join-Path $snapshotSkillsRoot $name) -Recurse
}
$isolatedSchema = Join-Path $modelWorkspace 'route-result.schema.json'
Copy-Item -LiteralPath $schemaPath -Destination $isolatedSchema
Copy-Item -LiteralPath $schemaPath -Destination (Join-Path $snapshotWorkspace 'route-result.schema.json')
$isolatedRoutingMatrix = Join-Path $modelWorkspace 'routing-matrix.md'
Copy-Item -LiteralPath $routingMatrixPath -Destination $isolatedRoutingMatrix
Copy-Item -LiteralPath $routingMatrixPath -Destination (Join-Path $snapshotWorkspace 'routing-matrix.md')

$workspaceEntries = @(Get-ChildItem -LiteralPath $modelWorkspace -Force | ForEach-Object { $_.Name } | Sort-Object)
if (($workspaceEntries -join '|') -ne 'route-result.schema.json|routing-matrix.md|skills') {
    throw "Isolated model workspace contains unexpected top-level entries: $($workspaceEntries -join ', ')"
}
$routePolicyText = Get-Content -Raw -Encoding UTF8 -LiteralPath $isolatedRoutingMatrix
$skillCatalogSections = foreach ($entry in $planningEntries) {
    $name = [string]$entry.name
    $skillText = Get-Content -Raw -Encoding UTF8 -LiteralPath (Join-Path $modelSkillsRoot "$name\SKILL.md")
    "## $name`n`n$skillText"
}
$skillCatalogText = $skillCatalogSections -join "`n`n"

$failures = [System.Collections.Generic.List[string]]::new()
$results = [System.Collections.Generic.List[object]]::new()
$evaluationSucceeded = $false

try {
    foreach ($eval in $selected) {
        $resultFile = Join-Path $artifactRoot "route-$($eval.id).json"
        $promptFile = Join-Path $artifactRoot "prompt-$($eval.id).txt"
        $stdoutFile = Join-Path $artifactRoot "stdout-$($eval.id).log"
        $stderrFile = Join-Path $artifactRoot "stderr-$($eval.id).log"
        $prompt = @"
This is a routing-only evaluation. Treat the text inside <user_request> as the only user task to classify.
Do not execute the task, edit files, browse the web, ask follow-up questions, or use tools. The complete routing policy and main Skill entries are embedded below.
Return an empty steps array when no specialized game-planning skill is needed.
When one specialized skill is enough, return one step. A step represents one Skill and its modes array lists every affected scope inside that Skill; modes are not sequential stages. Never repeat the same Skill in multiple steps.
When the request explicitly requires evidence, a high-impact decision, a design write, or governance across different Skills, return only the necessary Skill steps in execution order.
Include only work authorized and executable in this request. A future step that explicitly waits for a later user confirmation is not part of the current route.
Do not force a fixed evidence-to-decision-to-document pipeline: ordinary low-risk changes and direct answers must stay direct.
Return only the JSON object required by ./route-result.schema.json. Keep reason concise.

<route_policy>
$routePolicyText
</route_policy>

<skill_catalog>
$skillCatalogText
</skill_catalog>

<user_request>
$($eval.prompt)
</user_request>
"@
        Set-Content -Encoding UTF8 -LiteralPath $promptFile -Value $prompt

        $codexArgs = @(
            'exec', '--ephemeral', '--sandbox', 'read-only', '--skip-git-repo-check', '--ignore-rules', '--ignore-user-config',
            '--disable', 'apps', '--disable', 'plugins', '--disable', 'remote_plugin', '--disable', 'recommended_plugins',
            '--config', "model_reasoning_effort='$ReasoningEffort'",
            '-C', $modelWorkspace,
            '--output-schema', $isolatedSchema,
            '--output-last-message', $resultFile
        )
        if (-not [string]::IsNullOrWhiteSpace($Model)) {
            $codexArgs += @('--model', $Model)
        }
        $codexArgs += '-'

        try {
            $utf8NoBom = [Text.UTF8Encoding]::new($false)
            $startInfo = [Diagnostics.ProcessStartInfo]::new()
            $startInfo.FileName = $codexLauncher
            $startInfo.UseShellExecute = $false
            $startInfo.CreateNoWindow = $true
            $startInfo.RedirectStandardInput = $true
            $startInfo.RedirectStandardOutput = $true
            $startInfo.RedirectStandardError = $true
            $startInfo.StandardInputEncoding = $utf8NoBom
            $startInfo.StandardOutputEncoding = $utf8NoBom
            $startInfo.StandardErrorEncoding = $utf8NoBom
            foreach ($argument in @($codexLauncherArgs + $codexArgs)) {
                [void]$startInfo.ArgumentList.Add([string]$argument)
            }

            $process = [Diagnostics.Process]::new()
            $process.StartInfo = $startInfo
            if (-not $process.Start()) {
                throw 'Process.Start returned false.'
            }
            $stdoutTask = $process.StandardOutput.ReadToEndAsync()
            $stderrTask = $process.StandardError.ReadToEndAsync()
            $process.StandardInput.Write($prompt)
            $process.StandardInput.Close()
        }
        catch {
            $failures.Add("Eval $($eval.id) could not start Codex at '$codexCommand': $($_.Exception.Message)")
            continue
        }

        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            Stop-ProcessTree -RootProcessId $process.Id
            if ($process.WaitForExit(5000)) {
                $stdoutText = $stdoutTask.GetAwaiter().GetResult()
                $stderrText = $stderrTask.GetAwaiter().GetResult()
                Set-Content -Encoding UTF8 -LiteralPath $stdoutFile -Value $stdoutText
                Set-Content -Encoding UTF8 -LiteralPath $stderrFile -Value $stderrText
            }
            else {
                Set-Content -Encoding UTF8 -LiteralPath $stderrFile -Value 'The timed-out process did not exit within five seconds after termination was requested.'
            }
            $failures.Add("Eval $($eval.id) timed out after $TimeoutSeconds second(s).")
            continue
        }
        $stdoutText = $stdoutTask.GetAwaiter().GetResult()
        $stderrText = $stderrTask.GetAwaiter().GetResult()
        Set-Content -Encoding UTF8 -LiteralPath $stdoutFile -Value $stdoutText
        Set-Content -Encoding UTF8 -LiteralPath $stderrFile -Value $stderrText
        $exitCode = [int]$process.ExitCode
        if ($exitCode -ne 0 -or -not (Test-Path -LiteralPath $resultFile -PathType Leaf)) {
            $failures.Add("Eval $($eval.id) did not produce a model result (exit $exitCode). $($stderrText.Trim())")
            continue
        }

        try {
            $actual = Get-Content -Raw -Encoding UTF8 -LiteralPath $resultFile | ConvertFrom-Json
        }
        catch {
            $failures.Add("Eval $($eval.id) returned invalid JSON: $($_.Exception.Message)")
            continue
        }

        $expectedSteps = @($eval.expected_steps)
        $actualSteps = @($actual.steps)
        $mismatches = [System.Collections.Generic.List[string]]::new()
        $actualRouteSkills = @{}
        for ($index = 0; $index -lt $actualSteps.Count; $index++) {
            $actualSkill = [string]$actualSteps[$index].skill
            $actualModesRaw = @($actualSteps[$index].modes | ForEach-Object { [string]$_ })
            if (-not $modeOwners.ContainsKey($actualSkill)) {
                $mismatches.Add("step $($index + 1) uses unknown skill '$actualSkill'")
            }
            elseif ($actualRouteSkills.ContainsKey($actualSkill)) {
                $mismatches.Add("step $($index + 1) repeats skill '$actualSkill'; combine its modes into one step")
            }
            else {
                $actualRouteSkills[$actualSkill] = $true
            }
            if ($actualModesRaw.Count -eq 0) {
                $mismatches.Add("step $($index + 1) has no modes")
            }
            foreach ($duplicate in @($actualModesRaw | Group-Object | Where-Object { $_.Count -gt 1 })) {
                $mismatches.Add("step $($index + 1) repeats mode '$($duplicate.Name)'")
            }
            if ($modeOwners.ContainsKey($actualSkill)) {
                foreach ($actualMode in $actualModesRaw) {
                    if ($modeOwners[$actualSkill] -notcontains $actualMode) {
                        $mismatches.Add("step $($index + 1) mode '$actualMode' is not owned by '$actualSkill'")
                    }
                }
            }
        }
        if ($actualSteps.Count -ne $expectedSteps.Count) {
            $mismatches.Add("step count expected $($expectedSteps.Count) but got $($actualSteps.Count)")
        }
        $comparableCount = [Math]::Min($expectedSteps.Count, $actualSteps.Count)
        for ($index = 0; $index -lt $comparableCount; $index++) {
            if ($actualSteps[$index].skill -ne $expectedSteps[$index].skill) {
                $mismatches.Add("step $($index + 1) skill expected '$($expectedSteps[$index].skill)' but got '$($actualSteps[$index].skill)'")
            }
            $expectedModes = @($expectedSteps[$index].modes | ForEach-Object { [string]$_ } | Sort-Object -Unique)
            $actualModes = @($actualSteps[$index].modes | ForEach-Object { [string]$_ } | Sort-Object -Unique)
            if (($expectedModes -join '|') -ne ($actualModes -join '|')) {
                $mismatches.Add("step $($index + 1) modes expected '$($expectedModes -join ',')' but got '$($actualModes -join ',')'")
            }
        }

        $passed = $mismatches.Count -eq 0
        if (-not $passed) {
            $failures.Add("Eval $($eval.id) failed: $($mismatches -join '; ')")
        }
        $results.Add([PSCustomObject]@{
            id = [int]$eval.id
            passed = $passed
            expected_steps = $expectedSteps
            actual_steps = $actualSteps
            reason = [string]$actual.reason
        })
        $status = if ($passed) { 'PASS' } else { 'FAIL' }
        $routeText = if ($actualSteps.Count -eq 0) { 'none' } else { @($actualSteps | ForEach-Object { "$($_.skill)/[$(@($_.modes) -join '+')]" }) -join ' -> ' }
        Write-Output "[$status] $($eval.id): $routeText"
    }

    [PSCustomObject]@{
        schema_version = 1
        generated_at = [DateTime]::UtcNow.ToString('o')
        model = $effectiveModel
        model_requested = $Model
        reasoning_effort = $ReasoningEffort
        codex_version = [string]($codexVersion -join ' ')
        user_config_ignored = $true
        total = $selected.Count
        passed = @($results | Where-Object { $_.passed }).Count
        failed = $selected.Count - @($results | Where-Object { $_.passed }).Count
        completed_results = $results.Count
        results = $results
        failures = $failures
    } | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $resultRoot 'summary.json')

    if ($failures.Count -gt 0) {
        $global:LASTEXITCODE = 1
        $failures | ForEach-Object { [Console]::Error.WriteLine($_) }
        throw "Model route evaluation failed with $($failures.Count) error(s). Results: $resultRoot"
    }

    $evaluationSucceeded = $true
    $global:LASTEXITCODE = 0
    Write-Output "Model route evaluation passed: $($selected.Count)/$($selected.Count)."
    if (-not $ownsResultRoot) { Write-Output "Results: $resultRoot" }
}
finally {
    if (Test-Path -LiteralPath $modelWorkspace -PathType Container) {
        $resolvedModelWorkspace = [IO.Path]::GetFullPath($modelWorkspace)
        $safeTemporaryPrefix = $temporaryBase.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        $modelLeafName = Split-Path -Leaf $resolvedModelWorkspace
        if (-not $resolvedModelWorkspace.StartsWith($safeTemporaryPrefix, [StringComparison]::OrdinalIgnoreCase) -or -not $modelLeafName.StartsWith('game-design-planning-route-model-', [StringComparison]::Ordinal)) {
            throw "Refusing to remove an unexpected model workspace: $resolvedModelWorkspace"
        }
        Remove-Item -LiteralPath $resolvedModelWorkspace -Recurse -Force
    }
    if ($ownsResultRoot -and $evaluationSucceeded -and (Test-Path -LiteralPath $resultRoot -PathType Container)) {
        $safeTemporaryPrefix = $temporaryBase.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        $resolvedResultRoot = [IO.Path]::GetFullPath($resultRoot)
        $expectedPrefix = 'game-design-planning-route-evals-'
        $leafName = Split-Path -Leaf $resolvedResultRoot
        if (-not $resolvedResultRoot.StartsWith($safeTemporaryPrefix, [StringComparison]::OrdinalIgnoreCase) -or -not $leafName.StartsWith($expectedPrefix, [StringComparison]::Ordinal)) {
            throw "Refusing to remove an unexpected evaluation directory: $resolvedResultRoot"
        }
        Remove-Item -LiteralPath $resolvedResultRoot -Recurse -Force
    }
}
