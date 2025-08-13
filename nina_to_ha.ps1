# --- CONFIGURATION ---
# Please edit these three variables

# 1. Full path to your NINA Target Scheduler database file.
$dbPath = ""

# 2. Your Home Assistant URL.
$haUrl = ""

# 3. Your Home Assistant Long-Lived Access Token.
$haToken = ""


# --- SCRIPT LOGIC (No need to edit below this line) ---

Import-Module -Name PSSQLite -ErrorAction Stop

function Format-Seconds {
    param([int]$Seconds)
    if ($Seconds -le 0) { return "0m" }
    $h = [Math]::Floor($Seconds / 3600)
    $m = [Math]::Floor(($Seconds % 3600) / 60)
    return "$($h)h $($m)m"
}

function Get-TargetProgressDetails {
    param([string]$DatabasePath, [int]$TargetId)
    
    # CORRECTED QUERY: Now selects 'acquired' instead of 'accepted' and includes all plans, not just enabled ones.
    $query = @"
        SELECT
            et.filtername,
            ep.desired,
            ep.acquired, 
            CASE
                WHEN ep.exposure = -1.0 THEN et.defaultexposure
                ELSE ep.exposure
            END as exposure_seconds
        FROM exposureplan ep
        JOIN exposuretemplate et ON ep.exposureTemplateId = et.Id
        WHERE ep.targetid = $TargetId
"@
    $plans = Invoke-SqliteQuery -DataSource $DatabasePath -Query $query

    $progressByFilter = @{}
    $overallAcquired_s = 0; $overallTotal_s = 0

    foreach ($plan in $plans) {
        $filterName = $plan.filtername
        $desiredFrames = if ($plan.desired) { $plan.desired } else { 0 }
        # CORRECTED LOGIC: Using 'acquired' column now.
        $acquiredFrames = if ($plan.acquired) { $plan.acquired } else { 0 }
        $exposureTime = if ($plan.exposure_seconds) { $plan.exposure_seconds } else { 0 }

        $planTotal_s = $desiredFrames * $exposureTime; $planAcquired_s = $acquiredFrames * $exposureTime
        $overallTotal_s += $planTotal_s; $overallAcquired_s += $planAcquired_s

        if (-not $progressByFilter.ContainsKey($filterName)) {
            $progressByFilter[$filterName] = @{ acquired_s = 0; total_s = 0; acquired_frames = 0; desired_frames = 0 }
        }
        $progressByFilter[$filterName].total_s += $planTotal_s; $progressByFilter[$filterName].acquired_s += $planAcquired_s
        $progressByFilter[$filterName].desired_frames += $desiredFrames; $progressByFilter[$filterName].acquired_frames += $acquiredFrames
    }

    $filterProgressList = @()
    
    $filterOrder = @('Luminance', 'Red', 'Green', 'Blue', 'Sii', 'Ha', 'Oiii')
    $sortedFilters = $progressByFilter.Keys | Sort-Object { $idx = $filterOrder.IndexOf($_); if ($idx -eq -1) { $filterOrder.Count } else { $idx } }

    foreach ($f_name in $sortedFilters) {
        $data = $progressByFilter[$f_name]
        $percent = if ($data.total_s -gt 0) { [Math]::Round(($data.acquired_s / $data.total_s) * 100, 1) } else { 0 }
        
        $filterProgressList += [PSCustomObject]@{
            name = $f_name
            percent = $percent
        }
    }
    
    return $filterProgressList
}

# --- Main Script Execution ---
Write-Host "Fetching hierarchical status for all active projects and targets..."
$projects_list = @()
try {
    $activeProjects = Invoke-SqliteQuery -DataSource $dbPath -Query "SELECT Id, name FROM project WHERE state = 1 ORDER BY priority DESC"
    foreach ($project in $activeProjects) {
        $projectDict = [PSCustomObject]@{ project_name = $project.name; targets = @() }
        $activeTargets = Invoke-SqliteQuery -DataSource $dbPath -Query "SELECT Id, name FROM target WHERE projectId = $($project.Id) AND active = 1"
        foreach ($target in $activeTargets) {
            $progressDetails = Get-TargetProgressDetails -DatabasePath $dbPath -TargetId $target.Id
            $targetDict = [PSCustomObject]@{
                target_name     = $target.name
                filter_progress = $progressDetails
            }
            $projectDict.targets += $targetDict
        }
        if ($projectDict.targets.Count -gt 0) { $projects_list += $projectDict }
    }
}
catch { Write-Error "An error occurred during database processing: $_"; exit 1 }

# --- Send data to Home Assistant ---
Write-Host "Sending data to Home Assistant..."
$entity_id = "sensor.nina_scheduler_status"
$uri = "$haUrl/api/states/$entity_id"
$headers = @{ "Authorization"  = "Bearer $haToken"; "Content-Type"   = "application/json" }
$bodyObject = [PSCustomObject]@{ state = $projects_list.Count; attributes = @{ projects = $projects_list; last_update = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss") } }
$jsonBody = $bodyObject | ConvertTo-Json -Depth 10
try {
    Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -Body $jsonBody -ErrorAction Stop
    Write-Host "Successfully sent data for $($projects_list.Count) active project(s) to Home Assistant."
}
catch { Write-Error "Failed to send data to Home Assistant: $_" }
