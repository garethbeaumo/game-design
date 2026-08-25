[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$planningRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$repositoryRoot = (Resolve-Path (Join-Path $planningRoot '..')).Path
$manifestPath = Join-Path $planningRoot 'manifest.json'
$evalsPath = Join-Path $planningRoot 'evals\evals.json'
$behaviorEvalsPath = Join-Path $planningRoot 'evals\behavior-evals.json'
$routeSchemaPath = Join-Path $planningRoot 'route-result.schema.json'
$errors = [System.Collections.Generic.List[string]]::new()

function Add-ValidationError {
    param([string]$Message)
    $script:errors.Add($Message)
}

function Test-Property {
    param($InputObject, [string]$Name)
    return $null -ne $InputObject -and $InputObject.PSObject.Properties.Name -contains $Name
}

function Resolve-RepositoryPath {
    param([string]$RelativePath)
    $nativePath = $RelativePath -replace '/', [IO.Path]::DirectorySeparatorChar
    return [IO.Path]::GetFullPath((Join-Path $repositoryRoot $nativePath))
}

function Get-RelativePath {
    param([string]$BasePath, [string]$FullPath)
    $base = [IO.Path]::GetFullPath($BasePath).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $full = [IO.Path]::GetFullPath($FullPath)
    return $full.Substring($base.Length + 1).Replace('\', '/')
}

function Test-ExactSet {
    param([string]$Label, [string[]]$Expected, [string[]]$Actual)

    $expectedSet = @($Expected | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    $actualSet = @($Actual | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    if ($expectedSet.Count -eq 0) {
        foreach ($item in $actualSet) { Add-ValidationError "$Label has an unregistered entry: $item" }
        return
    }
    if ($actualSet.Count -eq 0) {
        foreach ($item in $expectedSet) { Add-ValidationError "$Label is missing a registered entry: $item" }
        return
    }

    foreach ($difference in @(Compare-Object -ReferenceObject $expectedSet -DifferenceObject $actualSet)) {
        $direction = if ($difference.SideIndicator -eq '=>') { 'has an unregistered entry' } else { 'is missing a registered entry' }
        Add-ValidationError "$Label $direction`: $($difference.InputObject)"
    }
}

function Read-Json {
    param([string]$Path, [string]$Label)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        Add-ValidationError "Missing ${Label}: $Path"
        return $null
    }
    try {
        return Get-Content -Raw -Encoding UTF8 -LiteralPath $Path | ConvertFrom-Json
    }
    catch {
        Add-ValidationError "Invalid $Label JSON: $($_.Exception.Message)"
        return $null
    }
}

function Read-SkillFrontmatter {
    param([string]$Path)

    $lines = @(Get-Content -Encoding UTF8 -LiteralPath $Path)
    if ($lines.Count -lt 5 -or $lines[0].Trim() -ne '---') { return $null }

    $frontmatterEnd = -1
    for ($i = 1; $i -lt $lines.Count; $i++) {
        if ($lines[$i].Trim() -eq '---') {
            $frontmatterEnd = $i
            break
        }
    }
    if ($frontmatterEnd -lt 0) { return $null }

    $nameLine = @($lines[1..($frontmatterEnd - 1)] | Where-Object { $_ -match '^name\s*:' } | Select-Object -First 1)
    $descriptionIndex = -1
    for ($i = 1; $i -lt $frontmatterEnd; $i++) {
        if ($lines[$i] -match '^description\s*:') {
            $descriptionIndex = $i
            break
        }
    }
    if ($nameLine.Count -eq 0 -or $descriptionIndex -lt 0) { return $null }

    $name = ($nameLine[0] -replace '^name\s*:\s*', '').Trim('"', "'")
    $descriptionValue = ($lines[$descriptionIndex] -replace '^description\s*:\s*', '').Trim()
    if ($descriptionValue -in @('>', '>-', '|', '|-')) {
        $description = @($lines[($descriptionIndex + 1)..($frontmatterEnd - 1)] | ForEach-Object { $_.Trim() }) -join ' '
    }
    else {
        $description = $descriptionValue.Trim('"', "'")
    }

    $bodyLines = @(Get-Content -Encoding UTF8 -LiteralPath $Path | Select-Object -Skip ($frontmatterEnd + 1))
    while ($bodyLines.Count -gt 0 -and [string]::IsNullOrWhiteSpace([string]$bodyLines[0])) {
        $bodyLines = @($bodyLines | Select-Object -Skip 1)
    }
    $body = ($bodyLines -join "`n").TrimEnd()

    return [PSCustomObject]@{ Name = $name; Description = $description; Lines = $lines; Body = $body }
}

$manifest = Read-Json -Path $manifestPath -Label 'planning manifest'
$routeSchema = Read-Json -Path $routeSchemaPath -Label 'route result schema'
$evalDocument = Read-Json -Path $evalsPath -Label 'route eval'
$behaviorEvalDocument = Read-Json -Path $behaviorEvalsPath -Label 'behavior eval'
$skillEntries = @()
$planningEntries = @()
$planningNames = @()
$sourceSkillRoot = $null

if ($null -ne $manifest) {
    if ($manifest.schema_version -ne 1) {
        Add-ValidationError "Unsupported planning manifest schema_version: $($manifest.schema_version)"
    }

    $sourceSkillRoot = Resolve-RepositoryPath -RelativePath ([string]$manifest.source_skill_root)
    if (-not (Test-Path -LiteralPath $sourceSkillRoot -PathType Container)) {
        Add-ValidationError "Source skill root is missing: $sourceSkillRoot"
    }

    $skillEntries = @($manifest.skills)
    $manifestNames = @($skillEntries | ForEach-Object { [string]$_.name })
    foreach ($duplicate in @($manifestNames | Group-Object | Where-Object { $_.Count -gt 1 })) {
        Add-ValidationError "Duplicate planning manifest skill entry: $($duplicate.Name)"
    }

    $planningEntries = @($skillEntries | Where-Object { $_.kind -eq 'planning' })
    $planningNames = @($planningEntries | ForEach-Object { [string]$_.name })
    if ($planningNames.Count -eq 0) {
        Add-ValidationError 'Planning manifest must register at least one planning skill.'
    }
    $planningNamePattern = [string]$manifest.planning_skill_name_pattern
    if ([string]::IsNullOrWhiteSpace($planningNamePattern)) {
        Add-ValidationError 'Planning manifest must define planning_skill_name_pattern.'
    }
    elseif (Test-Path -LiteralPath $sourceSkillRoot -PathType Container) {
        $actualPlanningNames = @(
            Get-ChildItem -LiteralPath $sourceSkillRoot -Directory |
                Where-Object {
                    $_.Name -match $planningNamePattern -and
                    (Test-Path -LiteralPath (Join-Path $_.FullName 'SKILL.md') -PathType Leaf)
                } |
                ForEach-Object { $_.Name }
        )
        Test-ExactSet -Label 'Planning source skill set' -Expected $planningNames -Actual $actualPlanningNames
    }

    foreach ($entry in $skillEntries) {
        $name = [string]$entry.name
        if ([string]::IsNullOrWhiteSpace($name)) {
            Add-ValidationError 'Planning manifest contains a skill with an empty name.'
            continue
        }
        if ([string]$entry.kind -ne 'planning') {
            Add-ValidationError "$name has unsupported skill kind: $($entry.kind)"
        }
        $modes = @($entry.modes | ForEach-Object { [string]$_ })
        if ($modes.Count -eq 0) { Add-ValidationError "$name must own at least one route mode." }
        foreach ($duplicate in @($modes | Group-Object | Where-Object { $_.Count -gt 1 })) {
            Add-ValidationError "$name has a duplicate route mode: $($duplicate.Name)"
        }

        $skillPath = Join-Path $sourceSkillRoot "$name\SKILL.md"
        if (-not (Test-Path -LiteralPath $skillPath -PathType Leaf)) { continue }
        $frontmatter = Read-SkillFrontmatter -Path $skillPath
        if ($null -eq $frontmatter) {
            Add-ValidationError "$name/SKILL.md has invalid frontmatter"
            continue
        }
        if ($frontmatter.Name -ne $name) {
            Add-ValidationError "$name/SKILL.md frontmatter name is '$($frontmatter.Name)'"
        }
        if ($frontmatter.Lines.Count -gt [int]$manifest.max_skill_entry_lines) {
            Add-ValidationError "$name/SKILL.md exceeds $($manifest.max_skill_entry_lines) lines: $($frontmatter.Lines.Count)"
        }
        foreach ($term in @($entry.required_description_terms)) {
            if ($frontmatter.Description -notlike "*$term*") {
                Add-ValidationError "$name description is missing required trigger term: $term"
            }
        }
        foreach ($relativePath in @($entry.required_files)) {
            $requiredPath = [IO.Path]::GetFullPath((Join-Path (Join-Path $sourceSkillRoot $name) (([string]$relativePath) -replace '/', [IO.Path]::DirectorySeparatorChar)))
            if (-not (Test-Path -LiteralPath $requiredPath -PathType Leaf)) {
                Add-ValidationError "Missing required skill file: $name/$relativePath"
            }
        }
    }

    foreach ($relativePath in @($manifest.control_files)) {
        if (-not (Test-Path -LiteralPath (Resolve-RepositoryPath -RelativePath ([string]$relativePath)) -PathType Leaf)) {
            Add-ValidationError "Missing planning control file: $relativePath"
        }
    }

    foreach ($forbiddenName in @($manifest.forbidden_skill_names)) {
        if (Test-Path -LiteralPath (Join-Path $sourceSkillRoot "$forbiddenName\SKILL.md") -PathType Leaf) {
            Add-ValidationError "Forbidden legacy skill still exists: $forbiddenName"
        }
    }
}

$planningMarkdown = @()
foreach ($entry in $planningEntries) {
    $directory = Join-Path $sourceSkillRoot ([string]$entry.name)
    if (Test-Path -LiteralPath $directory -PathType Container) {
        $planningMarkdown += @(Get-ChildItem -LiteralPath $directory -Recurse -Filter '*.md' -File)
    }
}

if ($null -ne $manifest -and @($manifest.forbidden_skill_names).Count -gt 0) {
    $forbiddenPattern = '(?<![A-Za-z0-9_-])(?:' + ((@($manifest.forbidden_skill_names) | ForEach-Object { [Regex]::Escape($_) }) -join '|') + ')(?![A-Za-z0-9_-])'
    foreach ($file in $planningMarkdown) {
        foreach ($match in @(Select-String -LiteralPath $file.FullName -Pattern $forbiddenPattern)) {
            Add-ValidationError "Legacy skill token in source: $(Get-RelativePath -BasePath $repositoryRoot -FullPath $file.FullName):$($match.LineNumber) $($match.Matches[0].Value)"
        }
    }
}

$repositoryPrefix = [IO.Path]::GetFullPath($repositoryRoot).TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
$referencePattern = '(?<path>(?:\.\./|\./)*(?:[A-Za-z0-9_.-]+/)+[A-Za-z0-9_.-]+\.md)'
foreach ($file in $planningMarkdown) {
    $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName
    foreach ($match in [Regex]::Matches($content, $referencePattern)) {
        $rawPath = $match.Groups['path'].Value -replace '/', [IO.Path]::DirectorySeparatorChar
        $targetPath = [IO.Path]::GetFullPath((Join-Path $file.DirectoryName $rawPath))
        if (-not $targetPath.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            Add-ValidationError "Markdown reference escapes repository: $(Get-RelativePath -BasePath $repositoryRoot -FullPath $file.FullName) -> $($match.Groups['path'].Value)"
        }
        elseif (-not (Test-Path -LiteralPath $targetPath -PathType Leaf)) {
            Add-ValidationError "Broken Markdown reference: $(Get-RelativePath -BasePath $repositoryRoot -FullPath $file.FullName) -> $($match.Groups['path'].Value)"
        }
    }
}

if ($null -ne $manifest -and $null -ne $routeSchema) {
    $schemaProperties = @($routeSchema.properties.PSObject.Properties.Name)
    Test-ExactSet -Label 'Route schema root properties' -Expected @('steps', 'reason') -Actual $schemaProperties
    Test-ExactSet -Label 'Route schema required properties' -Expected @('steps', 'reason') -Actual @($routeSchema.required | ForEach-Object { [string]$_ })

    $schemaText = Get-Content -Raw -Encoding UTF8 -LiteralPath $routeSchemaPath
    if ($schemaText -match '(?i)"(?:profile|supported)"\s*:') {
        Add-ValidationError 'Route schema must not define legacy profile or supported fields.'
    }

    $schemaStep = $routeSchema.definitions.routeStep
    $schemaAlternatives = @($schemaStep.anyOf)
    $schemaSkillNames = @($schemaAlternatives | ForEach-Object { [string]$_.properties.skill.const })
    Test-ExactSet -Label 'Route schema planning skills' -Expected $planningNames -Actual $schemaSkillNames
    foreach ($entry in $planningEntries) {
        $name = [string]$entry.name
        $matching = @($schemaAlternatives | Where-Object { [string]$_.properties.skill.const -eq $name })
        if ($matching.Count -ne 1) {
            Add-ValidationError "Route schema must define exactly one anyOf branch for $name"
            continue
        }
        Test-ExactSet -Label "Route schema modes for $name" -Expected @($entry.modes | ForEach-Object { [string]$_ }) -Actual @($matching[0].properties.modes.items.enum | ForEach-Object { [string]$_ })
        Test-ExactSet -Label "Route schema required step properties for $name" -Expected @('skill', 'modes') -Actual @($matching[0].required | ForEach-Object { [string]$_ })
        if ([int]$matching[0].properties.modes.minItems -lt 1) {
            Add-ValidationError "Route schema modes for $name must require at least one entry."
        }
    }
    if ([string]$schemaStep.description -notmatch 'runner' -or [string]$schemaStep.description -notmatch '所有权') {
        Add-ValidationError 'Route schema step description must document runner uniqueness checks and skill-mode ownership.'
    }
}

if ($null -ne $evalDocument -and $null -ne $manifest) {
    if ($evalDocument.schema_version -ne 1) {
        Add-ValidationError "Unsupported route eval schema_version: $($evalDocument.schema_version)"
    }
    if ($evalDocument.suite -ne 'planning-routing') {
        Add-ValidationError 'Route eval suite must be planning-routing.'
    }

    $evalText = Get-Content -Raw -Encoding UTF8 -LiteralPath $evalsPath
    if ($evalText -match '(?i)"(?:profile|supported)"\s*:') {
        Add-ValidationError 'Route evals must not use legacy profile or supported fields.'
    }
    if ($evalText -match '"mode"\s*:') {
        Add-ValidationError 'Route eval steps must use a modes array, not a singular mode field.'
    }

    $evals = @($evalDocument.evals)
    if ($evals.Count -lt [int]$manifest.eval_contract.minimum_cases) {
        Add-ValidationError "Route eval coverage is too small: $($evals.Count)"
    }

    $seenIds = @{}
    $seenSkills = @{}
    $seenModes = @{}
    $seenTags = @{}
    $seenHandoffs = @{}
    $noneRouteCount = 0
    $modeOwners = @{}
    foreach ($entry in $planningEntries) {
        $modeOwners[[string]$entry.name] = @($entry.modes | ForEach-Object { [string]$_ })
    }

    foreach ($eval in $evals) {
        foreach ($property in @('id', 'prompt', 'expected_steps', 'tags')) {
            if (-not (Test-Property -InputObject $eval -Name $property)) {
                Add-ValidationError "Route eval is missing property '$property': $($eval.id)"
            }
        }
        $id = [string]$eval.id
        if ($seenIds.ContainsKey($id)) {
            Add-ValidationError "Duplicate route eval id: $id"
        }
        else { $seenIds[$id] = $true }
        if ([string]::IsNullOrWhiteSpace([string]$eval.prompt)) {
            Add-ValidationError "Route eval $id has an empty prompt"
        }

        $steps = @($eval.expected_steps)
        if ($steps.Count -eq 0) {
            $noneRouteCount++
            foreach ($requiredTag in @('route:none', 'boundary:no-skill')) {
                if (@($eval.tags) -notcontains $requiredTag) {
                    Add-ValidationError "No-skill route eval $id is missing required tag: $requiredTag"
                }
            }
        }
        else {
            if (@($eval.tags) -contains 'route:none') {
                Add-ValidationError "Planning route eval $id must not use route:none"
            }
        }

        $routeSkills = @{}
        for ($index = 0; $index -lt $steps.Count; $index++) {
            $step = $steps[$index]
            foreach ($property in @('skill', 'modes')) {
                if (-not (Test-Property -InputObject $step -Name $property)) {
                    Add-ValidationError "Route eval $id step $($index + 1) is missing '$property'"
                }
            }
            $skill = [string]$step.skill
            $modes = @($step.modes | ForEach-Object { [string]$_ })
            if ($planningNames -notcontains $skill) {
                Add-ValidationError "Route eval $id uses an unknown planning skill: $skill"
            }
            elseif ($routeSkills.ContainsKey($skill)) {
                Add-ValidationError "Route eval $id repeats planning skill '$skill'; combine its affected modes into one step."
            }
            else {
                $routeSkills[$skill] = $true
            }
            if ($modes.Count -eq 0) {
                Add-ValidationError "Route eval $id step $($index + 1) must contain at least one mode."
            }
            foreach ($duplicate in @($modes | Group-Object | Where-Object { $_.Count -gt 1 })) {
                Add-ValidationError "Route eval $id step $($index + 1) repeats mode '$($duplicate.Name)'."
            }
            foreach ($mode in $modes) {
                if ($planningNames -contains $skill -and $modeOwners[$skill] -notcontains $mode) {
                    Add-ValidationError "Route eval $id mode '$mode' is not owned by $skill"
                }
                $seenModes["$skill/$mode"] = $true
            }
            $seenSkills[$skill] = $true

            if ($index -gt 0) {
                $previousSkill = [string]$steps[$index - 1].skill
                $seenHandoffs["$previousSkill>$skill"] = $true
            }
        }

        foreach ($tag in @($eval.tags)) { $seenTags[[string]$tag] = $true }
    }

    foreach ($entry in $planningEntries) {
        $name = [string]$entry.name
        if (-not $seenSkills.ContainsKey($name)) {
            Add-ValidationError "No route eval covers planning skill: $name"
        }
        foreach ($mode in @($entry.modes)) {
            if (-not $seenModes.ContainsKey("$name/$mode")) {
                Add-ValidationError "No route eval covers mode: $name/$mode"
            }
        }
    }
    foreach ($tag in @($manifest.eval_contract.required_tags)) {
        if (-not $seenTags.ContainsKey([string]$tag)) {
            Add-ValidationError "No route eval covers required tag: $tag"
        }
    }
    foreach ($handoff in @($manifest.eval_contract.required_handoffs)) {
        $key = "$($handoff.from)>$($handoff.to)"
        if (-not $seenHandoffs.ContainsKey($key)) {
            Add-ValidationError "No route eval covers required ordered handoff: $key"
        }
    }
    if ($noneRouteCount -lt [int]$manifest.eval_contract.minimum_none_cases) {
        Add-ValidationError "Route evals must include at least $($manifest.eval_contract.minimum_none_cases) no-skill near misses."
    }
}

if ($null -ne $behaviorEvalDocument -and $null -ne $manifest) {
    if ($behaviorEvalDocument.schema_version -ne 1) {
        Add-ValidationError "Unsupported behavior eval schema_version: $($behaviorEvalDocument.schema_version)"
    }
    if ($behaviorEvalDocument.suite -ne 'planning-behavior') {
        Add-ValidationError 'Behavior eval suite must be planning-behavior.'
    }

    $behaviorEvals = @($behaviorEvalDocument.evals)
    if ($behaviorEvals.Count -lt [int]$manifest.behavior_eval_contract.minimum_cases) {
        Add-ValidationError "Behavior eval coverage is too small: $($behaviorEvals.Count)"
    }

    $seenBehaviorIds = @{}
    $seenBehaviorNames = @{}
    $seenBehaviorTags = @{}
    foreach ($eval in $behaviorEvals) {
        foreach ($property in @('id', 'name', 'prompt', 'expected_output', 'expectations', 'tags')) {
            if (-not (Test-Property -InputObject $eval -Name $property)) {
                Add-ValidationError "Behavior eval is missing property '$property': $($eval.id)"
            }
        }
        $id = [string]$eval.id
        $name = [string]$eval.name
        if ($seenBehaviorIds.ContainsKey($id)) { Add-ValidationError "Duplicate behavior eval id: $id" }
        else { $seenBehaviorIds[$id] = $true }
        if ($seenBehaviorNames.ContainsKey($name)) { Add-ValidationError "Duplicate behavior eval name: $name" }
        else { $seenBehaviorNames[$name] = $true }
        foreach ($property in @('name', 'prompt', 'expected_output')) {
            if ([string]::IsNullOrWhiteSpace([string]$eval.$property)) {
                Add-ValidationError "Behavior eval $id has an empty $property"
            }
        }
        if (@($eval.expectations).Count -lt 3) {
            Add-ValidationError "Behavior eval $id must define at least three expectations"
        }
        foreach ($expectation in @($eval.expectations)) {
            if ([string]::IsNullOrWhiteSpace([string]$expectation)) {
                Add-ValidationError "Behavior eval $id contains an empty expectation"
            }
        }
        if (Test-Property -InputObject $eval -Name 'files') {
            $inputFiles = @($eval.files | ForEach-Object { [string]$_ })
            if ($inputFiles.Count -eq 0) {
                Add-ValidationError "Behavior eval $id declares files but the list is empty"
            }
            if (-not (Test-Property -InputObject $eval -Name 'output_files') -or @($eval.output_files).Count -eq 0) {
                Add-ValidationError "Behavior eval $id with input files must declare output_files"
            }
            foreach ($inputFile in $inputFiles) {
                if ([string]::IsNullOrWhiteSpace($inputFile)) {
                    Add-ValidationError "Behavior eval $id contains an empty input file path"
                    continue
                }
                $resolvedInputFile = Resolve-RepositoryPath -RelativePath $inputFile
                if (-not $resolvedInputFile.StartsWith($repositoryPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                    Add-ValidationError "Behavior eval $id input escapes the repository: $inputFile"
                }
                elseif (-not (Test-Path -LiteralPath $resolvedInputFile -PathType Leaf)) {
                    Add-ValidationError "Behavior eval $id input file is missing: $inputFile"
                }
            }
            foreach ($outputFile in @($eval.output_files | ForEach-Object { [string]$_ })) {
                if ([string]::IsNullOrWhiteSpace($outputFile) -or [IO.Path]::IsPathRooted($outputFile) -or $outputFile -match '(^|[\\/])\.\.([\\/]|$)') {
                    Add-ValidationError "Behavior eval $id has an unsafe output file path: $outputFile"
                }
            }
        }
        foreach ($tag in @($eval.tags)) { $seenBehaviorTags[[string]$tag] = $true }
    }
    foreach ($tag in @($manifest.behavior_eval_contract.required_tags)) {
        if (-not $seenBehaviorTags.ContainsKey([string]$tag)) {
            Add-ValidationError "No behavior eval covers required tag: $tag"
        }
    }
}

if ($errors.Count -gt 0) {
    $errors | ForEach-Object { [Console]::Error.WriteLine($_) }
    $global:LASTEXITCODE = 1
    throw "Static planning contract validation failed with $($errors.Count) error(s)."
}

$global:LASTEXITCODE = 0
$handoffCount = if ($null -eq $manifest) { 0 } else { @($manifest.eval_contract.required_handoffs).Count }
$evalCount = if ($null -eq $evalDocument) { 0 } else { @($evalDocument.evals).Count }
$behaviorEvalCount = if ($null -eq $behaviorEvalDocument) { 0 } else { @($behaviorEvalDocument.evals).Count }
Write-Output "Static planning contract valid: $($planningNames.Count) planning skills, $evalCount route eval definitions, $behaviorEvalCount behavior eval definitions, $handoffCount ordered handoff contracts."
Write-Output 'Forbidden legacy planning Skills are absent from the installable source.'
Write-Output 'Model route and behavior evals were not executed by this command.'
