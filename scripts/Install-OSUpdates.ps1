<#
.SYNOPSIS
    Single-File Hybrid Windows Update Solution with LIVE RMM LOGGING.

.DESCRIPTION
    - Native: Uses built-in WUA COM API — no PSWindowsUpdate module required.
    - Context: Seamless System-to-User transition via ServiceUI.
    - UI: Fullscreen English WinForms GUI.
    - Exit 3010: Signals reboot required. In Intune/AutoPilot, Intune handles the reboot
      and resumes the ESP session automatically — do NOT use -AutoReboot in that context.
      Use -AutoReboot only for standalone RMM deployments outside of Intune.
#>

param(
    [switch]$ScanOnly,
    [switch]$DriversOnly,
    [switch]$SecurityUpdatesOnly,
    [switch]$IgnoreOOBECheck,
    [switch]$Silent,
    [switch]$LaunchGUI,
    [switch]$AutoReboot
)

# === Globals ===
$Global:LogDir       = "C:\ProgramData\Scripts\WindowsUpdates"
$Global:ToolsBaseUrl = "https://github.com/QuadNL/scripts/raw/9796203051aae195c8c7e2f11752135df6ab0b45/Install-OSUpdates"
$Global:LogFile      = Join-Path $Global:LogDir "LiveOutput.log"
$Global:WrapperLog   = Join-Path $Global:LogDir "Wrapper.log"

# === Silent Logic ===
function Start-SilentLogic {
    Add-Type -AssemblyName System.Windows.Forms   # nodig voor DoEvents() in Install-WUAUpdate
    Write-Log "Starting Silent Mode Logic."

# === Logger ===
function Write-Log {
    param([string]$Msg, [string]$Type="INFO")
    if (-not (Test-Path $Global:LogDir)) { New-Item -ItemType Directory -Path $Global:LogDir -Force | Out-Null }
    $TimeStamp = Get-Date -Format 'HH:mm:ss'
    $FullLine  = "[$TimeStamp] [$Type] $Msg"
    $FullLine | Out-File -FilePath $Global:WrapperLog -Append -Encoding utf8
    switch ($Type) {
        "ERROR" { Write-Host $FullLine -ForegroundColor Red }
        "WARN"  { Write-Host $FullLine -ForegroundColor Yellow }
        default { Write-Host $FullLine -ForegroundColor Cyan }
    }
}

# === Tool Helper ===
function Get-Tool {
    param([string]$FileName)
    $LocalPath = Join-Path $Global:LogDir $FileName
    if (-not (Test-Path $LocalPath)) {
        try {
            Write-Log "Downloading: $FileName"
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            Invoke-WebRequest -Uri "$Global:ToolsBaseUrl/$FileName" -OutFile $LocalPath -UseBasicParsing
        } catch {
            Write-Log "Download Failed: $FileName" "ERROR"
            throw $_
        }
    }
    return $LocalPath
}

# === PowerShell Path Resolver ===
function Get-PowerShellExePath {
    $candidates = @(
        "$env:WINDIR\System32\WindowsPowerShell\v1.0\powershell.exe",
        "$env:WINDIR\Sysnative\WindowsPowerShell\v1.0\powershell.exe"
    )
    foreach ($p in $candidates) { if (Test-Path $p) { return $p } }
    return "powershell.exe"
}

# === WUA COM API Helpers ===
function New-WUASession {
    # Register Microsoft Update service so drivers and Office updates are included
    try {
        $Svc = New-Object -ComObject Microsoft.Update.ServiceManager
        $Svc.AddService2("7971f918-a847-4430-9279-4a52d1efe18d", 7, "") | Out-Null
    } catch {}
    return New-Object -ComObject Microsoft.Update.Session
}

function Search-WUAUpdates {
    param($Session, [switch]$DriversOnly, [switch]$SecurityOnly)

    $Searcher = $Session.CreateUpdateSearcher()
    try {
        $Searcher.ServiceID     = "7971f918-a847-4430-9279-4a52d1efe18d"
        $Searcher.ServerSelection = 3  # ssOthers (Microsoft Update)
    } catch {}

    $Results = $Searcher.Search("IsInstalled=0 and BrowseOnly=0")

    $All = @()
    for ($i = 0; $i -lt $Results.Updates.Count; $i++) { $All += $Results.Updates.Item($i) }

    if ($DriversOnly) {
        return $All | Where-Object {
            $cats = @(); for ($j = 0; $j -lt $_.Categories.Count; $j++) { $cats += $_.Categories.Item($j).Name }
            ($cats -match "Driver").Count -gt 0
        }
    }
    if ($SecurityOnly) {
        return $All | Where-Object {
            $cats = @(); for ($j = 0; $j -lt $_.Categories.Count; $j++) { $cats += $_.Categories.Item($j).Name }
            ($cats -match "Security|Critical").Count -gt 0
        }
    }
    return $All
}

function Get-WUAKB {
    param($Update)
    if ($Update.KBArticleIDs.Count -gt 0) { return "KB$($Update.KBArticleIDs.Item(0))" }
    return "NoKB"
}

function Install-WUAUpdate {
    param($Session, $Update, [scriptblock]$OnProgress = $null)

    if (-not $Update.EulaAccepted) { $Update.AcceptEula() }

    $Coll = New-Object -ComObject Microsoft.Update.UpdateColl
    $Coll.Add($Update) | Out-Null

    if (-not $Update.IsDownloaded) {
        $Dl = $Session.CreateUpdateDownloader()
        $Dl.Updates = $Coll
        try {
            $DlJob = $Dl.BeginDownload($null, $null, $null)
            while (-not $DlJob.IsCompleted) {
                try {
                    if ($OnProgress) {
                        $Pct = $DlJob.GetProgress().CurrentUpdatePercentComplete
                        & $OnProgress "Downloading" $Pct
                    }
                } catch {}
                # Poll every 100ms with DoEvents so the UI stays scrollable
                for ($s = 0; $s -lt 5; $s++) {
                    [System.Windows.Forms.Application]::DoEvents()
                    Start-Sleep -Milliseconds 100
                }
            }
            $Dl.EndDownload($DlJob) | Out-Null
        } catch {
            $Dl.Download() | Out-Null
        }
    }

    if (-not $Update.IsDownloaded) { throw "Download failed for: $($Update.Title)" }

    $Inst = $Session.CreateUpdateInstaller()
    $Inst.Updates = $Coll

    try {
        $Job = $Inst.BeginInstall($null, $null, $null)
        while (-not $Job.IsCompleted) {
            try {
                if ($OnProgress) {
                    $Pct = $Job.GetProgress().CurrentUpdatePercentComplete
                    & $OnProgress "Installing" $Pct
                }
            } catch {}
            # Poll every 100ms with DoEvents so the UI stays scrollable
            for ($s = 0; $s -lt 5; $s++) {
                [System.Windows.Forms.Application]::DoEvents()
                Start-Sleep -Milliseconds 100
            }
        }
        $Result = $Inst.EndInstall($Job)
    } catch {
        $Result = $Inst.Install()
    }

    if ($Result.ResultCode -notin 2, 3) {
        $HR = "0x$($Result.GetUpdateResult(0).HResult.ToString('X8'))"
        throw "Install failed. Code: $($Result.ResultCode) HResult: $HR"
    }

    return $Result
}

# === GUI Payload (User Context) ===
function Start-UpdateGUI {
    $MarkerFile = Join-Path $Global:LogDir "OOBE_Updates_Completed.tag"

    $ShiftF10 = Join-Path $Global:LogDir "ShiftF10.exe"
    if (Test-Path $ShiftF10) { Start-Process -FilePath $ShiftF10 -WindowStyle Hidden }

    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
    $Win32 = Add-Type -MemberDefinition '[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow); [DllImport("kernel32.dll")] public static extern IntPtr GetConsoleWindow();' -Name "Win32" -Namespace Win32 -PassThru
    $hwnd = $Win32::GetConsoleWindow()
    if ($hwnd -ne [IntPtr]::Zero) { $Win32::ShowWindow($hwnd, 0) | Out-Null }

    $Script:AllowClose      = $false
    $Script:CancelRequested = $false
    $Script:AnyErrors       = $false
    $Script:RebootNeeded    = $false
    $Script:CountdownSecs   = 10
    $Script:Countdown       = 10

    # Form
    $Form = New-Object System.Windows.Forms.Form
    $Form.Text            = "System Management"
    $Form.WindowState     = "Maximized"
    $Form.FormBorderStyle = "None"
    $Form.TopMost         = $true
    $Form.BackColor       = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $Form.ForeColor       = [System.Drawing.Color]::FromArgb(240, 240, 240)
    $Form.Add_FormClosing({ if (-not $Script:AllowClose) { $_.Cancel = $true } })

    $Header = New-Object System.Windows.Forms.Panel
    $Header.Height    = 80
    $Header.BackColor = [System.Drawing.Color]::FromArgb(0, 120, 215)
    $Header.Dock      = "Top"
    $Form.Controls.Add($Header)

    $Title = New-Object System.Windows.Forms.Label
    $Title.Text      = "Installing Windows Updates"
    $Title.Font      = New-Object System.Drawing.Font("Segoe UI", 24, [System.Drawing.FontStyle]::Bold)
    $Title.ForeColor = [System.Drawing.Color]::White
    $Title.AutoSize  = $true
    $Title.Location  = New-Object System.Drawing.Point(30, 20)
    $Header.Controls.Add($Title)

    $BottomPanel = New-Object System.Windows.Forms.Panel
    $BottomPanel.Dock   = "Bottom"
    $BottomPanel.Height = 115
    $Form.Controls.Add($BottomPanel)

    $StatusLbl = New-Object System.Windows.Forms.Label
    $StatusLbl.Dock   = "Top"
    $StatusLbl.Height = 30
    $StatusLbl.Font   = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Italic)
    $BottomPanel.Controls.Add($StatusLbl)

    $Bar = New-Object System.Windows.Forms.ProgressBar
    $Bar.Dock   = "Bottom"
    $Bar.Height = 40
    $Bar.Style  = "Marquee"
    $BottomPanel.Controls.Add($Bar)

    $BtnPanel = New-Object System.Windows.Forms.Panel
    $BtnPanel.Dock      = "Bottom"
    $BtnPanel.Height    = 45
    $BtnPanel.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
    $BottomPanel.Controls.Add($BtnPanel)

    $CancelBtn = New-Object System.Windows.Forms.Button
    $CancelBtn.Text      = "Cancel"
    $CancelBtn.Width     = 130
    $CancelBtn.Height    = 35
    $CancelBtn.Dock      = "Right"
    $CancelBtn.BackColor = [System.Drawing.Color]::FromArgb(60, 60, 60)
    $CancelBtn.ForeColor = [System.Drawing.Color]::White
    $CancelBtn.FlatStyle = "Flat"
    $CancelBtn.Add_Click({
        if ($Script:CancelRequested) { return }
        $Script:CancelRequested  = $true
        $CancelBtn.Text          = "Cancelling..."
        $CancelBtn.BackColor     = [System.Drawing.Color]::FromArgb(140, 40, 40)
        $CancelBtn.Refresh()
    })
    $BtnPanel.Controls.Add($CancelBtn)

    $ContentPanel = New-Object System.Windows.Forms.Panel
    $ContentPanel.Dock    = "Fill"
    $ContentPanel.Padding = New-Object System.Windows.Forms.Padding(40, 20, 40, 0)
    $Form.Controls.Add($ContentPanel)
    $ContentPanel.BringToFront()

    $LogBox = New-Object System.Windows.Forms.RichTextBox
    $LogBox.ReadOnly    = $true
    $LogBox.ScrollBars  = "Vertical"
    $LogBox.Font        = New-Object System.Drawing.Font("Consolas", 12)
    $LogBox.BackColor   = [System.Drawing.Color]::FromArgb(50, 50, 50)
    $LogBox.ForeColor   = [System.Drawing.Color]::LightCyan
    $LogBox.BorderStyle = "None"
    $LogBox.Dock        = "Fill"
    $ContentPanel.Controls.Add($LogBox)

    $Form.Add_Load({   $LogBox.Height = $ContentPanel.Height - $BottomPanel.Height - 20 })
    $Form.Add_Resize({ $LogBox.Height = $ContentPanel.Height - $BottomPanel.Height - 20 })

    # Logger — DoEvents() keeps the UI responsive between log lines
    $Script:Logger = {
        param($Msg)
        [System.Windows.Forms.Application]::DoEvents()
        $Line = "[{0}] {1}" -f (Get-Date -Format 'HH:mm:ss'), $Msg

        $LogBox.SelectionStart  = $LogBox.TextLength
        $LogBox.SelectionLength = 0
        $LogBox.SelectionColor  = $LogBox.ForeColor

        if ($Msg -match "NOTE:")        { $LogBox.SelectionColor = [System.Drawing.Color]::Orange }
        if ($Msg -match "FAILED|ERROR") { $LogBox.SelectionColor = [System.Drawing.Color]::Red }
        if ($Msg -match "SUCCESS")      { $LogBox.SelectionColor = [System.Drawing.Color]::LimeGreen }

        $LogBox.AppendText($Line + "`r`n")
        $LogBox.ScrollToCaret()
        $StatusLbl.Text = $Msg
        $Line | Out-File -FilePath $Global:LogFile -Append -Encoding utf8
    }

    # All WUA work runs here — on the UI thread, inside Application.Run's message pump.
    # DoEvents() is called every 100ms inside Install-WUAUpdate, so scrolling always works.
    $Form.Add_Shown({
        [System.Windows.Forms.Application]::DoEvents()
        try {
            & $Script:Logger "Preparing system..."
            $WUASession = New-WUASession

            & $Script:Logger "Searching for updates..."
            if ($ScanOnly)             { & $Script:Logger "MODE: ScanOnly (Report only)." }
            if ($DriversOnly)          { & $Script:Logger "MODE: Drivers Only." }
            if ($SecurityUpdatesOnly)  { & $Script:Logger "MODE: Security Updates Only." }

            $Updates = $null
            if ($DriversOnly)             { $Updates = Search-WUAUpdates -Session $WUASession -DriversOnly }
            elseif ($SecurityUpdatesOnly)  { $Updates = Search-WUAUpdates -Session $WUASession -SecurityOnly }
            else                           { $Updates = Search-WUAUpdates -Session $WUASession }

            if ($Updates -and $Updates.Count -gt 0) {
                $Count = $Updates.Count
                & $Script:Logger "Scan complete. $Count update(s) found:"
                foreach ($u in $Updates) { & $Script:Logger " - [$(Get-WUAKB $u)] $($u.Title)" }

                if (-not $ScanOnly) {
                    & $Script:Logger "----------------------------------------------"
                    $Bar.Style   = "Continuous"
                    $Bar.Maximum = 100
                    $Bar.Value   = 0
                    $CompletedCount = 0

                    foreach ($Update in $Updates) {
                        if ($Script:CancelRequested) {
                            & $Script:Logger "NOTE: Cancelled by user."
                            break
                        }
                        $TitleShort = if ($Update.Title.Length -gt 60) { $Update.Title.Substring(0,57) + "..." } else { $Update.Title }
                        & $Script:Logger "Installing: $TitleShort"
                        try {
                            $capturedCompleted = $CompletedCount
                            $capturedCount     = $Count
                            $ProgressCb = {
                                param($Phase, $Pct)
                                $Overall        = [int](($capturedCompleted * 100 + $Pct) / $capturedCount)
                                $Bar.Value      = [Math]::Min($Overall, 100)
                                $StatusLbl.Text = "$Phase $($capturedCompleted + 1) of $capturedCount : $Pct%"
                            }.GetNewClosure()

                            $InstResult = Install-WUAUpdate -Session $WUASession -Update $Update -OnProgress $ProgressCb
                            & $Script:Logger " -> SUCCESS"
                            if ($InstResult.RebootRequired) { $Script:RebootNeeded = $true }
                        } catch {
                            & $Script:Logger " -> FAILED: $($_.Exception.Message)"
                            $Script:AnyErrors = $true
                        }
                        $CompletedCount++
                        $Bar.Value = [int](($CompletedCount * 100) / $Count)
                    }
                }
            } else {
                $Bar.Style = "Continuous"; $Bar.Value = 100
                & $Script:Logger "Info: No new updates available."
            }

            & $Script:Logger "----------------------------------------------"
            if ($Script:CancelRequested)   { & $Script:Logger "Final Status: Cancelled by user." }
            elseif ($ScanOnly)             { & $Script:Logger "Final Status: ScanOnly Completed." }
            elseif ($Script:AnyErrors)     { & $Script:Logger "Final Status: Completed with errors." }
            elseif ($Script:RebootNeeded)  { & $Script:Logger "Final Status: Success (Reboot Required)." }
            else                           { & $Script:Logger "Final Status: Success." }

        } catch {
            & $Script:Logger "CRITICAL ERROR: $($_.Exception.Message)"
            $Script:AnyErrors = $true
        }

        $CancelBtn.Enabled = $false
        $CancelBtn.Text    = "Done"
        $Bar.Style         = "Continuous"
        $Bar.Maximum       = 100
        $Bar.Value         = 0

        # Countdown via WinForms Timer — non-blocking, scroll still works during countdown
        $Script:CountdownSecs = if ($Script:RebootNeeded -and $AutoReboot) { 15 } else { 10 }
        $Script:Countdown     = $Script:CountdownSecs

        $CountdownTimer = New-Object System.Windows.Forms.Timer
        $CountdownTimer.Interval = 1000
        $CountdownTimer.Add_Tick({
            $Script:Countdown--
            $Bar.Value      = [int](($Script:CountdownSecs - $Script:Countdown) * 100 / $Script:CountdownSecs)
            $StatusLbl.Text = if ($Script:RebootNeeded -and $AutoReboot) {
                "Updates complete. Rebooting in $($Script:Countdown) seconds..."
            } else {
                "Process finished. Closing in $($Script:Countdown) seconds..."
            }
            if ($Script:Countdown -le 0) {
                $CountdownTimer.Stop()
                $Script:AllowClose = $true
                $Form.Close()
            }
        })
        $CountdownTimer.Start()
    })

    [System.Windows.Forms.Application]::Run($Form)

    # Post-close — form is gone, use Write-Log only
    if (-not $ScanOnly) {
        $StatusText = if ($Script:AnyErrors) { "Completed with errors" } else { "Success" }
        Set-Content -Path $MarkerFile -Value "Script finished at $(Get-Date). Status: $StatusText. User: $env:USERNAME" -Force
    }

    if ($Script:RebootNeeded) {
        if ($AutoReboot) { Write-Log "Auto-rebooting..."; Restart-Computer -Force }
        exit 3010
    }
    exit 0
}

# === Silent Payload (System Context) ===
function Start-SilentLogic {
    Write-Log "Starting Silent Mode Logic."
    try {
        $WUASession = New-WUASession

        Write-Log "Scanning for updates..."
        $Updates = $null
        if ($DriversOnly) {
            $Updates = Search-WUAUpdates -Session $WUASession -DriversOnly
        } elseif ($SecurityUpdatesOnly) {
            $Updates = Search-WUAUpdates -Session $WUASession -SecurityOnly
        } else {
            $Updates = Search-WUAUpdates -Session $WUASession
        }

        if ($Updates -and $Updates.Count -gt 0) {
            Write-Log "Found $($Updates.Count) update(s):"
            foreach ($u in $Updates) { Write-Log " - [$(Get-WUAKB $u)] $($u.Title)" }

            if (-not $ScanOnly) {
                Write-Log "Installing..."
                $RebootNeeded = $false
                foreach ($Update in $Updates) {
                    try {
                        $InstResult = Install-WUAUpdate -Session $WUASession -Update $Update
                        Write-Log " -> SUCCESS: $($Update.Title)"
                        if ($InstResult.RebootRequired) { $RebootNeeded = $true }
                    } catch {
                        Write-Log " -> FAILED: $($_.Exception.Message)" "ERROR"
                    }
                }
                if ($RebootNeeded) {
                    Write-Log "Done. Reboot required."
                    if ($AutoReboot) { Write-Log "Auto-rebooting..."; Restart-Computer -Force }
                    exit 3010
                }
                Write-Log "Done."
            } else {
                Write-Log "ScanOnly: No installation performed."
            }
        } else {
            Write-Log "No updates found."
        }
        exit 0
    } catch {
        Write-Log "Error: $($_.Exception.Message)" "ERROR"
        exit 1
    }
}

# === Main Wrapper Logic (Live Logging Bridge) ===
function Start-WrapperLogic {
    Write-Log "--- SCRIPT START ---"

    if ($Silent) { Write-Log "Mode: SILENT"; Start-SilentLogic; return }

    $IsSystem   = ([System.Security.Principal.WindowsIdentity]::GetCurrent()).User.Value -eq "S-1-5-18"
    $Explorer   = Get-Process explorer -ErrorAction SilentlyContinue | Select-Object -First 1
    $OobeActive = $false

    if ($Explorer) {
        try {
            $CimProc = Get-CimInstance Win32_Process -Filter "ProcessId=$($Explorer.Id)" -ErrorAction Stop
            $Owner   = (Invoke-CimMethod -InputObject $CimProc -MethodName GetOwner).User
            Write-Log "Explorer Owner: $Owner"
            if ($Owner -eq "defaultuser0") { $OobeActive = $true }
        } catch {}
    }

    $ScriptPath = $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($ScriptPath)) { $ScriptPath = $MyInvocation.MyCommand.Path }
    if (-not (Test-Path $ScriptPath)) {
        Write-Log "Fatal: Could not locate script file on disk." "ERROR"
        exit 1
    }

    $ScriptRoot = $PSScriptRoot
    if ([string]::IsNullOrWhiteSpace($ScriptRoot)) { $ScriptRoot = Split-Path $ScriptPath -Parent }

    if ($OobeActive -or $IgnoreOOBECheck) {
        if (-not $IsSystem) {
            Start-UpdateGUI
        } else {
            Write-Log "Mode: GUI LAUNCH (ServiceUI + Live Logging)"

            $ServiceUI = Join-Path $ScriptRoot "ServiceUI.exe"
            if (-not (Test-Path $ServiceUI)) { $ServiceUI = Get-Tool "ServiceUI.exe" }

            $PsExe = Get-PowerShellExePath
            $ArgString = @(
                "-NoProfile"
                "-ExecutionPolicy", "Bypass"
                "-File", "`"$ScriptPath`""
                "-LaunchGUI"
            )
            if ($ScanOnly)            { $ArgString += "-ScanOnly" }
            if ($DriversOnly)         { $ArgString += "-DriversOnly" }
            if ($SecurityUpdatesOnly) { $ArgString += "-SecurityUpdatesOnly" }
            if ($AutoReboot)          { $ArgString += "-AutoReboot" }

            $TargetProc = "explorer.exe"
            if (-not $Explorer) { $TargetProc = "winlogon.exe"; Write-Log "Fallback to winlogon.exe" }

            Write-Log "Invoking ServiceUI..."
            if (Test-Path $Global:LogFile) { Clear-Content $Global:LogFile -ErrorAction SilentlyContinue }

            $SvcArgs = @("-process:$TargetProc", $PsExe) + $ArgString
            $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
            $ProcessInfo.FileName       = $ServiceUI
            $ProcessInfo.Arguments      = $SvcArgs -join " "
            $ProcessInfo.UseShellExecute = $false

            $Proc = [System.Diagnostics.Process]::Start($ProcessInfo)

            $LastSize = 0
            while (-not $Proc.HasExited) {
                if (Test-Path $Global:LogFile) {
                    try {
                        $CurrentSize = (Get-Item $Global:LogFile).Length
                        if ($CurrentSize -gt $LastSize) {
                            $Stream = [System.IO.File]::Open($Global:LogFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                            $Stream.Seek($LastSize, [System.IO.SeekOrigin]::Begin) | Out-Null
                            $Reader  = New-Object System.IO.StreamReader($Stream)
                            $NewText = $Reader.ReadToEnd()
                            if (-not [string]::IsNullOrWhiteSpace($NewText)) { Write-Host $NewText -NoNewline }
                            $LastSize = $Stream.Position
                            $Reader.Close()
                            $Stream.Close()
                        }
                    } catch {}
                }
                Start-Sleep -Milliseconds 500
            }

            if (Test-Path $Global:LogFile) {
                try {
                    $Stream = [System.IO.File]::Open($Global:LogFile, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)
                    $Stream.Seek($LastSize, [System.IO.SeekOrigin]::Begin) | Out-Null
                    $Reader  = New-Object System.IO.StreamReader($Stream)
                    $NewText = $Reader.ReadToEnd()
                    if (-not [string]::IsNullOrWhiteSpace($NewText)) { Write-Host $NewText -NoNewline }
                    $Reader.Close()
                    $Stream.Close()
                } catch {}
                Remove-Item $Global:LogFile -Force -ErrorAction SilentlyContinue
            }

            $ExitCode = $Proc.ExitCode
            Write-Log "ServiceUI Exit Code: $ExitCode"

            if ($ExitCode -eq 1) {
                Write-Log "RMM Status: Failure" "ERROR"
                exit 1
            } elseif ($ExitCode -eq 3010) {
                Write-Log "RMM Status: Success (Reboot Required)"
                exit 3010
            } else {
                Write-Log "RMM Status: Success"
                exit 0
            }
        }
    } else {
        Write-Log "Mode: NO ACTION (Not OOBE, Not Silent). Add -IgnoreOOBECheck to bypass."
        exit 0
    }
}

if ($LaunchGUI) { Start-UpdateGUI } else { Start-WrapperLogic }
