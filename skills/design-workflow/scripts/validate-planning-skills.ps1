[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$skillsRoot = Join-Path $repoRoot 'skills'
$workflowRoot = Join-Path $skillsRoot 'design-workflow'
$manifestPath = Join-Path $workflowRoot 'references\skill-manifest.json'
$evalsPath = Join-Path $workflowRoot 'evals\evals.json'
$routeSchemaPath = Join-Path $workflowRoot 'evals\route-result.schema.json'
$errors = [System.Collections.Generic.List[string]]::new()

function Add-ValidationError {
    param([string]$Message)
    $script:errors.Add($Message)
}

function Test-Property {
    param($InputObject, [string]$Name)
    return $null -ne $InputObject -and $InputObject.PSObject.Properties.Name -contains $Name
}

function Test-ExactSet {
    param(
        [string]$Label,
        [string[]]$Expected,
        [string[]]$Actual
    )

    $differences = @(Compare-Object -ReferenceObject @($Expected | Sort-Object -Unique) -DifferenceObject @($Actual | Sort-Object -Unique))
    foreach ($difference in $differences) {
        if ($difference.SideIndicator -eq '=>') {
            Add-ValidationError "$Label has an unregistered entry: $($difference.InputObject)"
        }
        else {
            Add-ValidationError "$Label is missing a registered entry: $($difference.InputObject)"
        }
    }
}

$manifest = $null
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    Add-ValidationError "Missing skill manifest: $manifestPath"
}
else {
    try {
        $manifest = Get-Content -Raw -Encoding UTF8 -LiteralPath $manifestPath | ConvertFrom-Json
    }
    catch {
        Add-ValidationError "Invalid skill manifest JSON: $($_.Exception.Message)"
    }
}

$planningNames = @()
if ($null -ne $manifest) {
    if ($manifest.schema_version -ne 1) {
        Add-ValidationError "Unsupported skill manifest schema_version: $($manifest.schema_version)"
    }

    $entries = @($manifest.skills)
    $manifestNames = @($entries | ForEach-Object { [string]$_.name })
    foreach ($duplicate in @($manifestNames | Group-Object | Where-Object { $_.Count -gt 1 })) {
        Add-ValidationError "Duplicate skill manifest entry: $($duplicate.Name)"
    }

    $actualNames = @(
        Get-ChildItem -LiteralPath $skillsRoot -Directory |
            Where-Object { Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf } |
            ForEach-Object { $_.Name }
    )
    Test-ExactSet -Label 'Repository skill set' -Expected $manifestNames -Actual $actualNames

    $planningNames = @($entries | Where-Object { $_.kind -eq 'planning' } | ForEach-Object { [string]$_.name })
    $expectedPlanning = @('design-workflow', 'grill-me', 'design-evidence', 'design-inference', 'design-docs')
    Test-ExactSet -Label 'Planning skill set' -Expected $expectedPlanning -Actual $planningNames

    $routeContractNames = @($manifest.route_contract.PSObject.Properties | ForEach-Object { $_.Name })
    Test-ExactSet -Label 'Route contract skill set' -Expected $planningNames -Actual $routeContractNames

    foreach ($entry in $entries) {
        $name = [string]$entry.name
        $skillPath = Join-Path $skillsRoot "$name\SKILL.md"
        if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) {
            continue
        }

        $lines = @(Get-Content -Encoding UTF8 -LiteralPath $skillPath)
        if ($lines.Count -gt 500) {
            Add-ValidationError "$name/SKILL.md exceeds 500 lines: $($lines.Count)"
        }

        $nameLine = $lines | Where-Object { $_ -match '^name:\s*' } | Select-Object -First 1
        $frontmatterName = if ($nameLine) { ($nameLine -replace '^name:\s*', '').Trim('"', "'") } else { '' }
        if ($frontmatterName -ne $name) {
            Add-ValidationError "$name frontmatter name mismatch: $frontmatterName"
        }

        $descriptionLine = $lines | Where-Object { $_ -match '^description:\s*' } | Select-Object -First 1
        if (-not $descriptionLine) {
            Add-ValidationError "$name is missing a single-line description"
        }
        foreach ($term in @($entry.required_description_terms)) {
            if ($descriptionLine -notlike "*$term*") {
                Add-ValidationError "$name description is missing required trigger term: $term"
            }
        }
    }

    foreach ($relativePath in @($manifest.required_files)) {
        if (-not (Test-Path -LiteralPath (Join-Path $skillsRoot $relativePath) -PathType Leaf)) {
            Add-ValidationError "Missing required planning file: $relativePath"
        }
    }

    foreach ($forbiddenName in @($manifest.forbidden_skill_names)) {
        if (Test-Path -LiteralPath (Join-Path $skillsRoot "$forbiddenName\SKILL.md") -PathType Leaf) {
            Add-ValidationError "Forbidden legacy skill still exists: $forbiddenName"
        }
    }

    foreach ($relativePath in @($manifest.forbidden_repo_paths)) {
        if (Test-Path -LiteralPath (Join-Path $repoRoot ([string]$relativePath))) {
            Add-ValidationError "Forbidden repository path still exists: $relativePath"
        }
    }

    $forbiddenPattern = '(?<![A-Za-z0-9_-])(?:' + ((@($manifest.forbidden_skill_names) | ForEach-Object { [Regex]::Escape($_) }) -join '|') + ')(?![A-Za-z0-9_-])'
    $sourceMarkdown = @(
        Get-ChildItem -LiteralPath $skillsRoot -Recurse -Filter '*.md' -File
    )
    foreach ($file in $sourceMarkdown) {
        foreach ($match in @(Select-String -LiteralPath $file.FullName -Pattern $forbiddenPattern)) {
            $relative = $file.FullName.Substring($repoRoot.Length + 1)
            Add-ValidationError "Legacy skill token in source: ${relative}:$($match.LineNumber) $($match.Matches[0].Value)"
        }
    }
}

$routeSchema = $null
if (-not (Test-Path -LiteralPath $routeSchemaPath -PathType Leaf)) {
    Add-ValidationError "Missing route result schema: $routeSchemaPath"
}
else {
    try {
        $routeSchema = Get-Content -Raw -Encoding UTF8 -LiteralPath $routeSchemaPath | ConvertFrom-Json
    }
    catch {
        Add-ValidationError "Invalid route result schema JSON: $($_.Exception.Message)"
    }
}

if ($null -ne $manifest -and $null -ne $routeSchema) {
    $contractModes = @(
        $manifest.route_contract.PSObject.Properties |
            ForEach-Object { @($_.Value) } |
            ForEach-Object { [string]$_ }
    )
    Test-ExactSet -Label 'Route schema primary_skill enum' -Expected $planningNames -Actual @($routeSchema.properties.primary_skill.enum)
    Test-ExactSet -Label 'Route schema mode enum' -Expected $contractModes -Actual @($routeSchema.properties.mode.enum)
    Test-ExactSet -Label 'Route schema profile enum' -Expected @($manifest.profiles) -Actual @($routeSchema.properties.profile.enum)
}

$planningMarkdown = @()
foreach ($name in $planningNames) {
    $skillDirectory = Join-Path $skillsRoot $name
    if (Test-Path -LiteralPath $skillDirectory -PathType Container) {
        $planningMarkdown += @(Get-ChildItem -LiteralPath $skillDirectory -Recurse -Filter '*.md' -File)
    }
}
$contractTextFiles = @($planningMarkdown)
if (Test-Path -LiteralPath $evalsPath -PathType Leaf) {
    $contractTextFiles += Get-Item -LiteralPath $evalsPath
}
foreach ($term in @($manifest.forbidden_document_terms)) {
    foreach ($file in $contractTextFiles) {
        foreach ($match in @(Select-String -SimpleMatch -LiteralPath $file.FullName -Pattern ([string]$term))) {
            $relative = $file.FullName.Substring($repoRoot.Length + 1)
            Add-ValidationError "Forbidden monolithic-document term in source: ${relative}:$($match.LineNumber) $term"
        }
    }
}
$referencePattern = '(?<path>(?:\.\./|\./)*(?:[A-Za-z0-9_.-]+/)+[A-Za-z0-9_.-]+\.md)'
foreach ($file in $planningMarkdown) {
    $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName
    foreach ($match in [Regex]::Matches($content, $referencePattern)) {
        $rawPath = $match.Groups['path'].Value -replace '/', '\'
        $targetPath = [IO.Path]::GetFullPath((Join-Path $file.DirectoryName $rawPath))
        if (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
            $relative = $file.FullName.Substring($repoRoot.Length + 1)
            Add-ValidationError "Broken Markdown reference: $relative -> $($match.Groups['path'].Value)"
        }
    }
}

$evalDocument = $null
if (-not (Test-Path -LiteralPath $evalsPath -PathType Leaf)) {
    Add-ValidationError "Missing route eval file: $evalsPath"
}
else {
    try {
        $evalDocument = Get-Content -Raw -Encoding UTF8 -LiteralPath $evalsPath | ConvertFrom-Json
    }
    catch {
        Add-ValidationError "Invalid route eval JSON: $($_.Exception.Message)"
    }
}

if ($null -ne $evalDocument) {
    if ($evalDocument.schema_version -ne 2) {
        Add-ValidationError "Unsupported route eval schema_version: $($evalDocument.schema_version)"
    }
    if ($evalDocument.skill_name -ne 'design-workflow') {
        Add-ValidationError "Route eval skill_name must be design-workflow"
    }

    $evals = @($evalDocument.evals)
    if ($evals.Count -lt 17) {
        Add-ValidationError "Route eval coverage is too small: $($evals.Count)"
    }

    $seenIds = @{}
    $seenModes = @{}
    $seenPrimarySkills = @{}
    $seenTags = @{}
    $allowedProfiles = @($manifest.profiles | ForEach-Object { [string]$_ })
    $allowedModes = @(
        $manifest.route_contract.PSObject.Properties |
            ForEach-Object { @($_.Value) } |
            ForEach-Object { [string]$_ }
    )
    $unsupportedCount = 0

    foreach ($eval in $evals) {
        foreach ($property in @('id', 'prompt', 'expected_output', 'expected_route', 'files', 'expectations', 'tags')) {
            if (-not (Test-Property -InputObject $eval -Name $property)) {
                Add-ValidationError "Route eval is missing property '$property': $($eval.id)"
            }
        }

        $id = [string]$eval.id
        if ($seenIds.ContainsKey($id)) {
            Add-ValidationError "Duplicate route eval id: $id"
        }
        else {
            $seenIds[$id] = $true
        }

        if ([string]::IsNullOrWhiteSpace([string]$eval.prompt) -or [string]::IsNullOrWhiteSpace([string]$eval.expected_output)) {
            Add-ValidationError "Route eval $id has an empty prompt or expected_output"
        }
        if (@($eval.expectations).Count -eq 0) {
            Add-ValidationError "Route eval $id has no expectations"
        }

        $route = $eval.expected_route
        foreach ($property in @('primary_skill', 'mode', 'profile', 'supported')) {
            if (-not (Test-Property -InputObject $route -Name $property)) {
                Add-ValidationError "Route eval $id expected_route is missing '$property'"
            }
        }

        $primarySkill = [string]$route.primary_skill
        $mode = [string]$route.mode
        $profile = [string]$route.profile
        if ($planningNames -notcontains $primarySkill) {
            Add-ValidationError "Route eval $id uses an unknown primary skill: $primarySkill"
        }
        if ($allowedModes -notcontains $mode) {
            Add-ValidationError "Route eval $id uses an unknown mode: $mode"
        }
        if ($planningNames -contains $primarySkill) {
            $skillModes = @($manifest.route_contract.PSObject.Properties[$primarySkill].Value | ForEach-Object { [string]$_ })
            if ($skillModes -notcontains $mode) {
                Add-ValidationError "Route eval $id mode '$mode' is not owned by $primarySkill"
            }
        }
        if ($allowedProfiles -notcontains $profile) {
            Add-ValidationError "Route eval $id uses an unknown profile: $profile"
        }
        if ($route.supported -isnot [bool]) {
            Add-ValidationError "Route eval $id supported must be a JSON boolean"
        }

        $seenPrimarySkills[$primarySkill] = $true
        $seenModes[$mode] = $true
        foreach ($tag in @($eval.tags)) {
            $seenTags[[string]$tag] = $true
        }

        if (-not [bool]$route.supported) {
            $unsupportedCount++
            if ($primarySkill -ne 'design-workflow' -or $mode -ne 'unsupported' -or $profile -ne 'not-applicable') {
                Add-ValidationError "Unsupported route eval $id must use design-workflow/unsupported/not-applicable"
            }
        }
        else {
            if ($mode -eq 'unsupported' -or $profile -eq 'not-applicable') {
                Add-ValidationError "Supported route eval $id cannot use unsupported/not-applicable"
            }
            if ($profile -eq 'implementation-ready' -and ($primarySkill -ne 'design-docs' -or $mode -ne 'feature')) {
                Add-ValidationError "Route eval $id implementation-ready is only valid for design-docs/feature"
            }
            if ($profile -eq 'full-package' -and ($primarySkill -ne 'design-workflow' -or $mode -ne 'governance')) {
                Add-ValidationError "Route eval $id full-package is only valid for design-workflow/governance"
            }
        }

        $files = @($eval.files)
        if (($mode -eq 'playtest' -or $mode -eq 'implementation') -and $files.Count -eq 0) {
            Add-ValidationError "Evidence route eval $id requires a stable fixture"
        }
        foreach ($relativeFile in $files) {
            $resolvedFile = [IO.Path]::GetFullPath((Join-Path $workflowRoot ([string]$relativeFile)))
            if (-not $resolvedFile.StartsWith($workflowRoot, [StringComparison]::OrdinalIgnoreCase)) {
                Add-ValidationError "Route eval $id fixture escapes the skill root: $relativeFile"
            }
            elseif (-not (Test-Path -LiteralPath $resolvedFile -PathType Leaf)) {
                Add-ValidationError "Route eval $id fixture is missing: $relativeFile"
            }
        }
    }

    foreach ($name in $planningNames) {
        if (-not $seenPrimarySkills.ContainsKey($name)) {
            Add-ValidationError "No route eval covers primary skill: $name"
        }
    }
    foreach ($mode in @('governance', 'grill', 'competitor', 'playtest', 'implementation', 'decision', 'concept', 'system', 'feature', 'unsupported')) {
        if (-not $seenModes.ContainsKey($mode)) {
            Add-ValidationError "No route eval covers mode: $mode"
        }
    }
    foreach ($tag in @('trigger:implicit-grill', 'trigger:skip-grill', 'context:isolation', 'boundary:number', 'boundary:ui', 'boundary:review')) {
        if (-not $seenTags.ContainsKey($tag)) {
            Add-ValidationError "No route eval covers required tag: $tag"
        }
    }
    if ($unsupportedCount -lt 3) {
        Add-ValidationError "Route evals must cover number, UI, and review boundaries"
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { [Console]::Error.WriteLine($_) }
    $global:LASTEXITCODE = 1
    throw "Static planning contract validation failed with $($errors.Count) error(s)."
}

$global:LASTEXITCODE = 0
Write-Output "Static planning contract valid: $($planningNames.Count) planning skills, $(@($evalDocument.evals).Count) route eval definitions."
Write-Output 'Model route evals were not executed by this command.'
