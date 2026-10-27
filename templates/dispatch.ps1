# dispatch.ps1 -- invoked via forced SSH command (see docs/03). Four modes:
#   START::PROJECT::BRANCH::MODEL::TASK  -- launch a detached work container, return a ticket
#   WAIT::<ticket>                       -- block until that container exits, then finalize
#   STATUS::<ticket>                     -- non-blocking check, no side effects
#   SWEEP::                              -- finalize anything finished-but-unreported, flag long runs
#
# Windows PowerShell 5.1. If you port this, keep the invariants documented in docs/04
# and run its acceptance tests before trusting the port.
#
# Never commits/pushes the PROJECT repo (enforced again by the container's deny-list).
# DOES commit the MEMORY repo -- deterministically, only at finalize.

$env:GIT_TERMINAL_PROMPT = "0"

# ---- adjust these for your machine ----
$roots         = @("C:\Projects")                       # folders projects may be resolved under
$rootMemoryMap = @{ "C:\Projects" = "_projects" }       # per-root memory slice names
$baseDir       = "C:\AgentPipeline"
$worktreeRoot  = "$baseDir\worktrees"
$memoryRoot    = "$baseDir\memory"                      # the memory git repo (docs/06)
$settingsFile  = "$baseDir\claude-settings\settings.json"
$tokenFile     = "$baseDir\secrets\oauth-token.txt"     # restrict this file's permissions to your user
$ticketRoot    = "$baseDir\tickets"
$sessionRoot   = "$baseDir\sessions"
$imageName     = "agent-image"
$staleMinutes  = 15

# Model tiers: friendly tokens the gateway uses -> concrete model ids. A raw model id
# passes through untouched. Update ids here, never in the gateway's manual.
$modelMap = @{
    "planning" = "claude-fable-5-1"
    "impl"     = "claude-opus-5-5"
    "quick"    = "claude-sonnet-5-5"
}
$defaultTier = "quick"
# ---------------------------------------

New-Item -ItemType Directory -Force -Path $ticketRoot | Out-Null

# Shared by WAIT:: and SWEEP:: -- assumes the container has already exited.
function Invoke-Finalize {
    param($ticket, $meta, $ticketFile)

    Write-Host "----"
    Write-Host "Agent output:"
    & docker logs "work-$ticket" 2>&1 | ForEach-Object { Write-Host $_ }

    Write-Host "----"
    Write-Host "Uncommitted changes in the worktree (project repo -- review and commit yourself):"
    Push-Location $meta.worktreePath
    & git status --short 2>&1 | ForEach-Object { Write-Host $_ }
    Pop-Location

    Push-Location $memoryRoot
    $memChanges = & git status --porcelain
    if ($memChanges) {
        Write-Host "Persisting memory updates..."
        & git add -A 2>$null
        & git commit -m "Auto-update: $($meta.projectLeaf) / $($meta.branchName) (ticket $ticket)" -q 2>$null
        # Hard 20s cap on the push: in a forced-command SSH session, git's own spawned ssh can
        # deadlock indefinitely, and an unbounded hang here would take finalize past the
        # scheduler's job timeout (docs/05). The local commit above is the durable part; a daily
        # scheduled task pushes anything this bounded attempt misses.
        $pushProc = Start-Process -FilePath "git" -ArgumentList "push","-q" -WorkingDirectory $memoryRoot -PassThru -WindowStyle Hidden
        if ($pushProc.WaitForExit(20000)) {
            if ($pushProc.ExitCode -ne 0) {
                Write-Host "NOTE: memory push failed (exit $($pushProc.ExitCode)); commit is safe locally, daily sync will push it."
            }
        } else {
            $pushProc.Kill()
            Write-Host "NOTE: memory push timed out (20s cap); commit is safe locally, daily sync will push it."
        }
    } else {
        Write-Host "No memory changes to persist."
    }
    Pop-Location

    & docker rm "work-$ticket" | Out-Null
    Remove-Item $ticketFile -Force
    $warnFile = "$ticketFile.warned"
    if (Test-Path $warnFile) { Remove-Item $warnFile -Force }
    $taskFile = $ticketFile -replace '\.json$', '.task.txt'
    if (Test-Path $taskFile) { Remove-Item $taskFile -Force }
    Write-Host "----"
    Write-Host "DONE: ticket $ticket finalized."
}

$raw = $env:SSH_ORIGINAL_COMMAND
if (-not $raw) {
    Write-Host "ERROR: no command received."
    exit 1
}

# ---------- WAIT mode ----------
if ($raw -like "WAIT::*") {
    $ticket = $raw.Substring(6).Trim()
    $ticketFile = Join-Path $ticketRoot "$ticket.json"
    if (-not (Test-Path $ticketFile)) {
        Write-Host "ERROR: unknown ticket '$ticket'"
        exit 1
    }
    $meta = Get-Content $ticketFile -Raw | ConvertFrom-Json

    Write-Host "Waiting on work-$ticket ..."
    $exitCode = & docker wait "work-$ticket"
    Write-Host "Container exited with code $exitCode"

    Invoke-Finalize -ticket $ticket -meta $meta -ticketFile $ticketFile
    exit $exitCode
}

# ---------- SWEEP mode ----------
# Non-blocking. Silent when there is nothing actionable, so the standing watchdog that calls
# this every few minutes doesn't train you to ignore the channel (docs/05).
if ($raw -like "SWEEP::*") {
    $ticketFiles = Get-ChildItem -Path $ticketRoot -Filter "*.json" -File -ErrorAction SilentlyContinue
    foreach ($tf in $ticketFiles) {
        $ticket = $tf.BaseName
        $meta = Get-Content $tf.FullName -Raw | ConvertFrom-Json
        $containerName = "work-$ticket"
        $state = & docker inspect --format '{{.State.Status}}' $containerName 2>&1
        if ($LASTEXITCODE -ne 0) {
            Write-Host "ANOMALY: ticket $ticket ($($meta.projectLeaf)/$($meta.branchName)) has no matching container -- removing the orphaned ticket file."
            Remove-Item $tf.FullName -Force
            $warnFile = "$($tf.FullName).warned"
            if (Test-Path $warnFile) { Remove-Item $warnFile -Force }
            $orphanTask = $tf.FullName -replace '\.json$', '.task.txt'
            if (Test-Path $orphanTask) { Remove-Item $orphanTask -Force }
            continue
        }
        if ($state -eq "running") {
            $warnFile = "$($tf.FullName).warned"
            if (Test-Path $warnFile) { continue }  # already warned once, stay quiet until it resolves
            $startedAt = & docker inspect --format '{{.State.StartedAt}}' $containerName
            $elapsedMin = [math]::Round(((Get-Date).ToUniversalTime() - [DateTime]::Parse($startedAt).ToUniversalTime()).TotalMinutes, 1)
            if ($elapsedMin -ge $staleMinutes) {
                Write-Host "STILL RUNNING: ticket $ticket ($($meta.projectLeaf)/$($meta.branchName)) -- $elapsedMin minutes elapsed. Not necessarily stuck, just flagging."
                New-Item -ItemType File -Force -Path $warnFile | Out-Null
            }
            continue
        }
        Write-Host "FINALIZING (missed by the normal watcher): ticket $ticket ($($meta.projectLeaf)/$($meta.branchName))"
        Invoke-Finalize -ticket $ticket -meta $meta -ticketFile $tf.FullName
    }
    exit 0
}

# ---------- STATUS mode ----------
if ($raw -like "STATUS::*") {
    $ticket = $raw.Substring(8).Trim()
    $state = & docker inspect --format '{{.State.Status}}' "work-$ticket" 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "ERROR: unknown or already-finalized ticket '$ticket'"
        exit 1
    }
    Write-Host "Ticket $ticket status: $state"
    Write-Host "Recent output:"
    & docker logs --tail 20 "work-$ticket" 2>&1 | ForEach-Object { Write-Host $_ }
    exit 0
}

# ---------- START mode ----------
if ($raw -notlike "START::*") {
    Write-Host "ERROR: unrecognized command. Expected START::PROJECT::BRANCH::MODEL::TASK, WAIT::<ticket>, STATUS::<ticket>, or SWEEP::."
    exit 1
}
$raw = $raw.Substring(7)

# Split limit 4: the TASK field may itself contain '::' safely.
$parts = $raw -split '::', 4
if ($parts.Count -eq 4) {
    $projectName   = $parts[0].Trim()
    $branchName    = $parts[1].Trim()
    $modelOverride = $parts[2].Trim()
    $task          = $parts[3].Trim()
} else {
    Write-Host "ERROR: malformed command. Expected START::PROJECT::BRANCH::MODEL::TASK, got: $raw"
    exit 1
}
if (-not $modelOverride) { $modelOverride = $defaultTier }
if ($modelMap.ContainsKey($modelOverride.ToLower())) {
    $modelOverride = $modelMap[$modelOverride.ToLower()]
}

Write-Host "Requested: project='$projectName' branch='$branchName' model='$modelOverride'"
Write-Host "Task: $task"

# Resolve the project: direct child of a root first, then a bounded recursive search that only
# accepts real git repos. Ambiguity is an error, never a guess.
$found = @()
$matchedRoot = $null
foreach ($root in $roots) {
    $candidate = Join-Path $root $projectName
    if (Test-Path $candidate -PathType Container) { $found += $candidate; $matchedRoot = $root }
}
if ($found.Count -eq 0) {
    Write-Host "No direct match -- searching recursively under $($roots -join ', ')..."
    foreach ($root in $roots) {
        if (-not (Test-Path $root)) { continue }
        $leaf = Split-Path $projectName -Leaf
        $hits = Get-ChildItem -Path $root -Directory -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object {
                $_.Name -like "*$leaf*" -and
                $_.FullName -notmatch '\\node_modules\\|\\bin\\|\\obj\\' -and
                (Test-Path (Join-Path $_.FullName ".git"))
            }
        foreach ($m in $hits) { $found += $m.FullName; $matchedRoot = $root }
    }
}
if ($found.Count -eq 0) {
    Write-Host "ERROR: project '$projectName' not found under $($roots -join ', ')"
    exit 1
}
if ($found.Count -gt 1) {
    Write-Host "ERROR: '$projectName' is ambiguous, found in multiple places:"
    $found | ForEach-Object { Write-Host "  $_" }
    exit 1
}
$projectPath = $found[0]

if (-not (Test-Path (Join-Path $projectPath ".git"))) {
    Write-Host "ERROR: '$projectPath' has no .git folder -- not a repo."
    exit 1
}
Write-Host "Found project at: $projectPath (root: $matchedRoot)"

$projectLeaf   = Split-Path $projectPath -Leaf
$worktreePath  = Join-Path $worktreeRoot "$projectLeaf\$branchName"
$projMemory    = Join-Path $memoryRoot $projectLeaf
$rootMemory    = Join-Path $memoryRoot $rootMemoryMap[$matchedRoot]
$sharedMemory  = Join-Path $memoryRoot "_shared"

New-Item -ItemType Directory -Force -Path "$projMemory\.claude\skills" | Out-Null

# git can't check the same branch out twice: if the requested branch is what the main folder
# has checked out, work directly there and say so loudly.
$currentBranch = & git -C $projectPath branch --show-current
if ($currentBranch -eq $branchName) {
    Write-Host "NOTE: '$branchName' is currently checked out in the main project folder -- working directly in $projectPath instead of a separate worktree. Avoid hand-editing this project while this task runs."
    $worktreePath = $projectPath
} elseif (Test-Path $worktreePath) {
    Write-Host "Reusing existing worktree at $worktreePath"
} else {
    New-Item -ItemType Directory -Force -Path (Split-Path $worktreePath -Parent) | Out-Null
    Push-Location $projectPath
    & git fetch --quiet 2>&1 | ForEach-Object { Write-Host $_ }
    $localBranch  = & git branch --list $branchName
    $remoteBranch = & git branch -r --list "origin/$branchName"
    if ($localBranch -or $remoteBranch) {
        & git worktree add "$worktreePath" "$branchName" 2>&1 | ForEach-Object { Write-Host $_ }
    } else {
        & git worktree add "$worktreePath" -b "$branchName" 2>&1 | ForEach-Object { Write-Host $_ }
    }
    Pop-Location
    if (-not (Test-Path $worktreePath)) {
        Write-Host "ERROR: worktree creation failed."
        exit 1
    }
}

$token = (Get-Content $tokenFile -Raw).Trim()
$ticket = "$projectLeaf-$(Get-Date -Format 'yyyyMMddHHmmss')" -replace '[^a-zA-Z0-9\-]', ''

# Per-project-per-branch session storage: consecutive dispatches on the same branch continue
# the same agent conversation (--continue). Safe on first use -- an empty dir starts fresh.
$sessionDir = Join-Path $sessionRoot "$projectLeaf\$branchName"
New-Item -ItemType Directory -Force -Path $sessionDir | Out-Null
$isContinuing = $null -ne (Get-ChildItem -Path $sessionDir -Recurse -File -ErrorAction SilentlyContinue | Select-Object -First 1)

Write-Host "Launching detached work container, ticket: $ticket"
Write-Host "  + session: $sessionDir $(if ($isContinuing) { '(continuing prior conversation on this branch)' } else { '(fresh)' })"

# The task text never crosses an argv boundary: PowerShell 5.1 mangles native-exe arguments
# containing embedded double quotes (a task can arrive truncated while every log on the way
# looks fine). The task goes to a file, mounted read-only, read inside the container by a
# static launcher -- any characters are safe. Keep this in any port (docs/04 acceptance test 1).
$taskFile = Join-Path $ticketRoot "$ticket.task.txt"
[System.IO.File]::WriteAllText($taskFile, $task, (New-Object System.Text.UTF8Encoding($false)))

$launchFile = "$baseDir\launch-work.sh"
$launchScript = "#!/bin/sh`n" +
    "exec claude -p `"`$(cat /run/task.txt)`" --model `"`$WORK_MODEL`" --effort `"`$WORK_EFFORT`" --continue " +
    "--permission-mode dontAsk --settings /etc/claude-settings.json " +
    "--add-dir /mem-project --add-dir /mem-root --add-dir /mem-shared`n"
[System.IO.File]::WriteAllText($launchFile, $launchScript, (New-Object System.Text.UTF8Encoding($false)))

docker run -d --name "work-$ticket" `
    -v "${worktreePath}:/workspace" `
    -v "${settingsFile}:/etc/claude-settings.json:ro" `
    -v "${projMemory}:/mem-project" `
    -v "${rootMemory}:/mem-root" `
    -v "${sharedMemory}:/mem-shared" `
    -v "${sessionDir}:/root/.claude" `
    -v "${taskFile}:/run/task.txt:ro" `
    -v "${launchFile}:/run/launch.sh:ro" `
    -e "CLAUDE_CODE_OAUTH_TOKEN=$token" `
    -e "CLAUDE_CODE_ADDITIONAL_DIRECTORIES_CLAUDE_MD=1" `
    -e "WORK_MODEL=$modelOverride" `
    -e "WORK_EFFORT=high" `
    -w /workspace `
    --entrypoint sh `
    $imageName `
    /run/launch.sh `
    | Out-Null

if ($LASTEXITCODE -ne 0) {
    Write-Host "ERROR: failed to launch container."
    exit 1
}

@{
    worktreePath = $worktreePath
    projectLeaf  = $projectLeaf
    branchName   = $branchName
    model        = $modelOverride
} | ConvertTo-Json | Set-Content (Join-Path $ticketRoot "$ticket.json")

Write-Host "----"
Write-Host "TICKET: $ticket"
Write-Host "Started. Check back with WAIT::$ticket or STATUS::$ticket."
