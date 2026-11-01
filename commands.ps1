# =============================================================================
# commands.ps1 - shared quick commands for Windows PowerShell 5.1 and PowerShell 7+
# =============================================================================
#
# Reload in the current terminal session after editing this file:
#   . $PROFILE.CurrentUserAllHosts
# or load this file directly:
#   . "$env:USERPROFILE\.quick\commands.ps1"
#
# Usage:
#   qc          - list groups with their shortcuts
#   qca         - list all commands (qca <filter> to search)
#   qcgit, ...  - list commands of one group (qcgit <filter> to search)
#   qci         - show location of this file
#
# Setup (run once in PS7 AND once in PS5 - each edition has its own profile):
#   $target = $PROFILE.CurrentUserAllHosts
#   New-Item -ItemType File -Path $target -Force -ErrorAction SilentlyContinue | Out-Null
#   $line = '. "$env:USERPROFILE\.quick\commands.ps1"'
#   if (-not (Select-String -Path $target -SimpleMatch $line -Quiet)) { Add-Content -Path $target -Value $line }
#
# Notes:
#   - Keep this file ASCII-only or save it as UTF-8 with BOM. PS 5.1 reads
#     BOM-less files as ANSI and breaks non-ASCII characters.
#   - If PS 5.1 refuses to run scripts and the execution policy cannot be changed
#     (Set-ExecutionPolicy writes to the registry), start it with a process-scoped
#     policy instead: powershell.exe -NoLogo -ExecutionPolicy Bypass
#     (Windows Terminal profile command line / VS Code terminal profile args).
#   - Built-in aliases (gl, gp, gc, gcm, ni, sl, ...) take precedence over
#     functions, so quick command names must not clash with them.
#     Register-QuickCommand warns about such clashes.
# =============================================================================

# Display order of groups and the shortcut that lists each group's commands
$global:QuickCommandGroups = [ordered]@{
    'Network'    = 'qcnet'
    'npm'        = 'qcnpm'
    'Playwright' = 'qcpw'
    'System'     = 'qcsys'
    'Git'        = 'qcgit'
}

# Start fresh on every load so a profile reload does not keep stale entries
$global:QuickCommands = [ordered]@{}

# Path of this file, captured at load time (used by qci)
$global:QuickCommandsPath = $PSCommandPath

function Register-QuickCommand {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string]$Group,
        [Parameter(Mandatory)][string]$Description,
        [Parameter(Mandatory)][scriptblock]$Action
    )
    if (-not $global:QuickCommandGroups.Contains($Group)) {
        throw "Unknown group '$Group'. Add it to `$QuickCommandGroups first."
    }
    # Aliases take precedence over functions, so a clash would silently hide the command
    if (Get-Alias -Name $Name -ErrorAction SilentlyContinue) {
        Write-Warning "Quick command '$Name' is shadowed by a built-in alias. Choose another name."
    }
    Set-Item -Path "function:global:$Name" -Value $Action
    $global:QuickCommands[$Name] = [pscustomobject]@{
        Name        = $Name
        Group       = $Group
        Description = $Description
    }
}

# Lists groups with their shortcuts
function qc {
    $global:QuickCommandGroups.GetEnumerator() |
        ForEach-Object {
            $groupName = $_.Key
            [pscustomobject]@{
                Group    = $groupName
                Shortcut = $_.Value
                Commands = @($global:QuickCommands.Values | Where-Object Group -eq $groupName).Count
            }
        } |
        Format-Table -AutoSize |
        # Out-Host forces the table to render before the hint below (PS 5.1 may reorder otherwise)
        Out-Host
    Write-Host 'qca  - show all commands (qca <filter> to search)' -ForegroundColor Cyan
    Write-Host 'qci  - show location of commands.ps1' -ForegroundColor Cyan
}

# Shows where this file lives and which profile loads it
function qci {
    Write-Host 'Commands file:' -ForegroundColor Cyan
    Write-Host "  $global:QuickCommandsPath"
    Write-Host 'Loaded by profile:' -ForegroundColor Cyan
    Write-Host "  $($PROFILE.CurrentUserAllHosts)"
    Write-Host ''
    Write-Host 'Open in VS Code:   ' -NoNewline -ForegroundColor DarkGray
    Write-Host "code `"$global:QuickCommandsPath`""
    Write-Host 'Show in Explorer:  ' -NoNewline -ForegroundColor DarkGray
    Write-Host "explorer /select,`"$global:QuickCommandsPath`""
}

# Lists all quick commands: qca | qca <filter> | qca -Group Git
function qca {
    param(
        [string]$Filter,
        [string]$Group
    )
    $groupOrder = @($global:QuickCommandGroups.Keys)
    $global:QuickCommands.Values |
        Where-Object { -not $Group -or $_.Group -eq $Group } |
        Where-Object {
            -not $Filter -or
            $_.Name -like "*$Filter*" -or
            $_.Description -like "*$Filter*"
        } |
        Sort-Object @{ Expression = { $groupOrder.IndexOf($_.Group) } }, Name |
        Format-Table -Property Name, Description -AutoSize -GroupBy @{
            Label      = 'Group'
            Expression = { '{0} ({1})' -f $_.Group, $global:QuickCommandGroups[$_.Group] }
        }
}

# Create one listing shortcut per group, e.g. qcgit or qcgit push
foreach ($entry in $global:QuickCommandGroups.GetEnumerator()) {
    $body = [scriptblock]::Create("qca -Group '$($entry.Key)' @args")
    Set-Item -Path "function:global:$($entry.Value)" -Value $body
}

# Runs steps in order and stops at the first failing native command.
# Replacement for && which is not available in PS 5.1.
# Example: nothing to commit -> git commit fails -> git push is skipped.
function Invoke-QuickSteps {
    param([scriptblock[]]$Steps)
    foreach ($step in $Steps) {
        & $step
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Stopped at '$($step.ToString().Trim())' (exit code $LASTEXITCODE)" -ForegroundColor Red
            return
        }
    }
}

# ---------------------------------------------------------------- Network

Register-QuickCommand -Name 'pingip' -Group 'Network' `
    -Description 'Ping a host: pingip 192.168.1.10 [count]' -Action {
    param([Parameter(Mandatory)][string]$Target, [int]$Count = 4)
    ping.exe -n $Count $Target
}

# TcpClient is used instead of Test-NetConnection, which is very slow when the port is closed
Register-QuickCommand -Name 'port' -Group 'Network' `
    -Description 'Check if TCP port is open: port 192.168.1.10 443 [timeoutMs]' -Action {
    param(
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutMs = 2000
    )
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $ok = $client.ConnectAsync($Target, $Port).Wait($TimeoutMs)
        if ($ok -and $client.Connected) {
            Write-Host "OPEN    ${Target}:$Port" -ForegroundColor Green
        } else {
            Write-Host "CLOSED  ${Target}:$Port" -ForegroundColor Red
        }
    } catch {
        Write-Host "ERROR   ${Target}:$Port - $($_.Exception.InnerException.Message)" -ForegroundColor Red
    } finally {
        $client.Dispose()
    }
}

Register-QuickCommand -Name 'myip' -Group 'Network' `
    -Description 'Show local IPv4 addresses' -Action {
    Get-NetIPAddress -AddressFamily IPv4 |
        Where-Object { $_.IPAddress -notlike '127.*' -and $_.IPAddress -notlike '169.254.*' } |
        Select-Object InterfaceAlias, IPAddress |
        Format-Table -AutoSize
}

Register-QuickCommand -Name 'whoport' -Group 'Network' `
    -Description 'Show process listening on a local port: whoport 3000' -Action {
    param([Parameter(Mandatory)][int]$Port)
    $conns = Get-NetTCPConnection -LocalPort $Port -State Listen -ErrorAction SilentlyContinue
    if (-not $conns) { Write-Host "Nothing is listening on port $Port"; return }
    $conns | ForEach-Object { Get-Process -Id $_.OwningProcess } |
        Select-Object Id, ProcessName, Path -Unique |
        Format-Table -AutoSize
}

# ---------------------------------------------------------------- npm

Register-QuickCommand -Name 'nci' -Group 'npm' -Description 'Clean install (npm ci)' -Action {
    npm ci @args
}

Register-QuickCommand -Name 'nup' -Group 'npm' -Description 'Update packages (npm up)' -Action {
    npm up @args
}

Register-QuickCommand -Name 'nout' -Group 'npm' -Description 'Show outdated packages (npm out)' -Action {
    npm outdated
}

Register-QuickCommand -Name 'nls' -Group 'npm' -Description 'List top-level packages (npm list --depth=0)' -Action {
    npm list --depth=0
}

Register-QuickCommand -Name 'nrun' -Group 'npm' -Description 'List scripts or run one: nrun [script]' -Action {
    npm run @args
}

Register-QuickCommand -Name 'nreset' -Group 'npm' -Description 'Delete node_modules and reinstall' -Action {
    if (Test-Path node_modules) { Remove-Item node_modules -Recurse -Force }
    npm ci
}

# ---------------------------------------------------------------- Playwright

Register-QuickCommand -Name 'pwv' -Group 'Playwright' -Description 'Show installed Playwright version' -Action {
    npx playwright --version
}

Register-QuickCommand -Name 'pwi' -Group 'Playwright' `
    -Description 'Install browsers: pwi [chromium|firefox|webkit] [--with-deps]' -Action {
    npx playwright install @args
}

# Extra Playwright args are passed through, e.g. pwf tests/login.spec.ts --headed
Register-QuickCommand -Name 'pwf' -Group 'Playwright' `
    -Description 'Run tests from file: pwf <file> [playwright args]' -Action {
    param([string]$File)
    if (-not $File) { Write-Host 'Usage: pwf <file> [playwright args]' -ForegroundColor Yellow; return }
    npx playwright test $File @args
}

# Pass the tag WITHOUT @, e.g. pwtag smoke --headed.
# An unquoted @smoke in PowerShell triggers splatting and would pass an empty value,
# so the @ prefix is added here.
Register-QuickCommand -Name 'pwtag' -Group 'Playwright' `
    -Description 'Run tests by tag (without @): pwtag smoke [playwright args]' -Action {
    param([string]$Tag)
    if (-not $Tag) { Write-Host 'Usage: pwtag <tag> [playwright args]' -ForegroundColor Yellow; return }
    if (-not $Tag.StartsWith('@')) { $Tag = "@$Tag" }
    npx playwright test --grep $Tag @args
}

# ---------------------------------------------------------------- System

# Best run from PS 5.1 or cmd: the installer replaces pwsh.exe, which is in use
# when running from PS7. If PS7 was installed from Microsoft Store, winget will
# not update it - updates then come through the Store.
Register-QuickCommand -Name 'psup' -Group 'System' `
    -Description 'Update PowerShell 7 via winget (best run from PS5 or cmd)' -Action {
    if ($PSVersionTable.PSEdition -eq 'Core') {
        Write-Warning 'Running from PowerShell 7 - the installer may need to close this session.'
    }
    winget upgrade --id Microsoft.PowerShell --source winget @args
}

# ---------------------------------------------------------------- Git

Register-QuickCommand -Name 'gst' -Group 'Git' -Description 'Short status' -Action {
    git status -sb
}

Register-QuickCommand -Name 'grv' -Group 'Git' -Description 'Show remotes (git remote -v)' -Action {
    git remote -v
}

Register-QuickCommand -Name 'glast' -Group 'Git' -Description 'Show last commit (git log -1 HEAD)' -Action {
    git log -1 HEAD
}

Register-QuickCommand -Name 'glog' -Group 'Git' -Description 'Graph log: glog [count]' -Action {
    param([int]$Count = 20)
    git log --oneline --graph --decorate -n $Count
}

Register-QuickCommand -Name 'gbr' -Group 'Git' -Description 'Local branches sorted by last commit' -Action {
    git branch --sort=-committerdate --format='%(committerdate:relative)%09%(refname:short)'
}

Register-QuickCommand -Name 'gsw' -Group 'Git' -Description 'Switch branch: gsw <branch>' -Action {
    git switch @args
}

Register-QuickCommand -Name 'gpl' -Group 'Git' -Description 'Pull with rebase' -Action {
    git pull --rebase @args
}

Register-QuickCommand -Name 'gfp' -Group 'Git' -Description 'Fetch all and prune deleted remote branches' -Action {
    git fetch --all --prune
}

Register-QuickCommand -Name 'gundo' -Group 'Git' -Description 'Undo last commit, keep changes staged' -Action {
    git reset --soft HEAD~1
}

Register-QuickCommand -Name 'gma' -Group 'Git' -Description 'Abort current merge' -Action {
    git merge --abort
}

# Ticket defaults to MK-2871, another one can be passed: gupd MK-3001
Register-QuickCommand -Name 'gupd' -Group 'Git' `
    -Description 'Commit tracked as "<ticket>: update" and push: gupd [ticket=MK-2871]' -Action {
    param([string]$Ticket = 'MK-2871')
    # ${Ticket} braces are required - "$Ticket:" would be parsed as a scoped variable
    Invoke-QuickSteps { git commit -am "${Ticket}: update" }, { git push }
}

# The message can be typed without quotes: gacp fix login test
# Quotes are only needed for PowerShell special characters such as ; | $
Register-QuickCommand -Name 'gacp' -Group 'Git' `
    -Description 'Add all, commit, push: gacp <message>' -Action {
    $msg = $args -join ' '
    if (-not $msg) { Write-Host 'Usage: gacp <message>' -ForegroundColor Yellow; return }
    Invoke-QuickSteps { git add . }, { git commit -am $msg }, { git push }
}

Register-QuickCommand -Name 'gacpu' -Group 'Git' `
    -Description 'Add all, commit "update" --no-verify, push' -Action {
    Invoke-QuickSteps { git add . }, { git commit -am 'update' --no-verify }, { git push }
}

# The message can be typed without quotes: gacpn fix login test
# Quotes are only needed for PowerShell special characters such as ; | $
Register-QuickCommand -Name 'gacpn' -Group 'Git' `
    -Description 'Add all, commit --no-verify, push: gacpn <message>' -Action {
    $msg = $args -join ' '
    if (-not $msg) { Write-Host 'Usage: gacpn <message>' -ForegroundColor Yellow; return }
    Invoke-QuickSteps { git add . }, { git commit -am $msg --no-verify }, { git push }
}

# Fails when the branch is the currently checked out one - git refuses to update
# the current branch this way. Use gpl instead in that case.
# Branch defaults to master, another one can be passed: gfm main
Register-QuickCommand -Name 'gfm' -Group 'Git' `
    -Description 'Update local base branch without checkout: gfm [base_branch=master]' -Action {
    param([string]$Branch = 'master')
    # ${Branch} braces are required - "$Branch:" would be parsed as a scoped variable
    git fetch origin "${Branch}:${Branch}"
}

# Fails when the branch is the currently checked out one (see gfm)
Register-QuickCommand -Name 'gfmm' -Group 'Git' `
    -Description 'Update local base branch, merge it into current branch, push: gfmm [base_branch=master]' -Action {
    param([string]$Branch = 'master')
    Invoke-QuickSteps { git fetch origin "${Branch}:${Branch}" }, { git merge $Branch }, { git push }
}

# Uses safe -d by default, which refuses to delete unmerged branches.
# -Force switches to -D and deletes regardless of merge state.
Register-QuickCommand -Name 'gbd' -Group 'Git' `
    -Description 'Delete local branch: gbd <branch> [-Force]' -Action {
    param([string]$Branch, [switch]$Force)
    if (-not $Branch) { Write-Host 'Usage: gbd <branch> [-Force]' -ForegroundColor Yellow; return }
    if ($Force) { git branch -D $Branch } else { git branch -d $Branch }
}

Register-QuickCommand -Name 'gbdr' -Group 'Git' `
    -Description 'Delete remote branch: gbdr <branch>' -Action {
    param([string]$Branch)
    if (-not $Branch) { Write-Host 'Usage: gbdr <branch>' -ForegroundColor Yellow; return }
    git push origin --delete $Branch
}

# Protected names are matched exactly (-notcontains), so e.g. feature/develop-login
# IS deleted while develop and master are kept. Extend $protected as needed,
# e.g. @('develop', 'master', 'main', ...).
# --format returns bare branch names (no '*' or indentation) so no parsing is needed.
# Branches checked out in other worktrees cannot be deleted - git reports an error
# for them and skips them.
Register-QuickCommand -Name 'gbclean' -Group 'Git' `
    -Description 'Force delete all local branches except current, develop and master' -Action {
    $protected = @('develop', 'master', (git branch --show-current))
    $toDelete = git branch --format='%(refname:short)' |
        Where-Object { $protected -notcontains $_ }

    if (-not $toDelete) { Write-Host 'Nothing to delete.' -ForegroundColor Green; return }

    $toDelete | ForEach-Object { git branch -D $_ }
}