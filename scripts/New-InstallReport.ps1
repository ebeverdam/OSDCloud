<#
.SYNOPSIS
    Connectium installatierapport: verzamelt de status van een vers geinstalleerde
    computer en toont een begrijpelijk HTML-rapport in Edge.

.DESCRIPTION
    - Draait als SYSTEM aan het einde van de eerste Windows Update-ronde bij aanmelding
      (FirstLogonUpdates.cmd), of handmatig als administrator.
    - Schrijft C:\ProgramData\Connectium\Installatierapport.html (zelfstandig bestand,
      logo ingebed, werkt offline).
    - Opent het rapport in Edge in de sessie van de aangemelde gebruiker.
    - Bovenaan uitleg voor de gebruiker, onderaan ingeklapt "Technische details voor IT".

.NOTES
    Auteur: Connectium B.V. / E. Beverdam
    Versie: 2026.10.19.04
    Bestand is bewust ASCII: niet-ASCII tekens staan als HTML-entity (PowerShell 5.1).
#>

param(
    [string]$OutFile = 'C:\ProgramData\Connectium\Installatierapport.html',
    [switch]$NoOpen
)

# === Instellingen ===============================================
$HelpPhone    = '+31 (0)548-722045'
$HelpMail     = 'support@connectium.nl'
$LogoPath     = 'C:\ProgramData\Scripts\WindowsUpdates\Connectium.png'
$LabelPattern = '^C\d{4,6}$'      # C-label, bijvoorbeeld C01234
$LogDir       = Split-Path $OutFile -Parent

New-Item -Path $LogDir -ItemType Directory -Force | Out-Null
Start-Transcript -Path (Join-Path $LogDir 'InstallReport.log') -Append | Out-Null

# === Hulpfuncties ===============================================
function Enc([object]$s) { [System.Net.WebUtility]::HtmlEncode([string]$s) }

function Get-Safe([scriptblock]$Block, $Default = $null) {
    $ErrorActionPreference = 'Stop'   # ook niet-afbrekende fouten opvangen
    try { $r = & $Block; if ($null -eq $r) { $Default } else { $r } } catch { $Default }
}

$NL = [System.Globalization.CultureInfo]::GetCultureInfo('nl-NL')

# === Gegevens verzamelen =========================================
Write-Host "Gegevens verzamelen..."

$cs   = Get-Safe { Get-CimInstance Win32_ComputerSystem }
$bios = Get-Safe { Get-CimInstance Win32_BIOS }
$os   = Get-Safe { Get-CimInstance Win32_OperatingSystem }
$cv   = Get-Safe { Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' }
$cpu  = Get-Safe { (Get-CimInstance Win32_Processor | Select-Object -First 1).Name.Trim() } '-'

$ComputerName = $env:COMPUTERNAME
$Manufacturer = Get-Safe { $cs.Manufacturer } '-'
$Model        = Get-Safe { $cs.Model } '-'
$Serial       = Get-Safe { $bios.SerialNumber.Trim() } '-'
$BiosVersion  = Get-Safe { $bios.SMBIOSBIOSVersion } '-'
$BiosDate     = Get-Safe { $bios.ReleaseDate.ToString('dd-MM-yyyy') } ''
$RamGB        = Get-Safe { [math]::Round($cs.TotalPhysicalMemory / 1GB) } '-'
$OsName       = Get-Safe { $os.Caption -replace '^Microsoft\s+', '' } 'Windows'
$OsVersion    = Get-Safe { $cv.DisplayVersion } ''
$OsBuild      = Get-Safe { "$($cv.CurrentBuild).$($cv.UBR)" } ''
$OsLanguage   = Get-Safe { (Get-WinSystemLocale).Name } ''
$InstallDate  = Get-Safe { $os.InstallDate } (Get-Date)
$InstallText  = $InstallDate.ToString('d MMMM yyyy', $NL)

# --- Gebruiker en organisatie ---
$UserName    = Get-Safe { $cs.UserName } ''
$DisplayName = Get-Safe { (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Authentication\LogonUI').LastLoggedOnDisplayName } ''
$FirstName   = if ($DisplayName) { ($DisplayName -split '\s+')[0] } elseif ($UserName) { ($UserName -split '\\')[-1] } else { '' }
$UserDomain  = if ($UserName -match '\\') { ($UserName -split '\\')[0] } else { '' }
$IsLocalUser = (-not $UserName) -or ($UserDomain -eq $ComputerName)

$Dsreg = Get-Safe { dsregcmd /status } @()
function Get-DsregValue([string]$Name) {
    $m = $Dsreg | Select-String -Pattern "^\s*$Name\s*:\s*(.+)$" | Select-Object -First 1
    if ($m) { $m.Matches[0].Groups[1].Value.Trim() } else { '' }
}
$AadJoined    = (Get-DsregValue 'AzureAdJoined') -eq 'YES'
$DomainJoined = (Get-DsregValue 'DomainJoined') -eq 'YES'
$TenantName   = Get-DsregValue 'TenantName'
$DomainName   = Get-DsregValue 'DomainName'
# Gegevens uit de deployment (WinPE-invulvenster): HKLM\SOFTWARE\Connectium\Deployment
$DeployReg    = Get-Safe { Get-ItemProperty 'HKLM:\SOFTWARE\Connectium\Deployment' }
$DeployCLabel = Get-Safe { [string]$DeployReg.CLabel } ''
$Customer     = Get-Safe { [string]$DeployReg.Customer } ''
$DeployDate   = Get-Safe { [string]$DeployReg.DeployDate } ''

$OrgName      = if ($TenantName) { $TenantName } elseif ($Customer) { $Customer } elseif ($DomainName) { $DomainName } else { 'je organisatie' }

$Intune = Get-Safe {
    [bool](Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\Enrollments' -ErrorAction Stop |
        ForEach-Object { Get-ItemProperty $_.PSPath } |
        Where-Object { $_.ProviderID -eq 'MS DM Server' })
} $false

$Autopilot        = Get-Safe { Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Provisioning\Diagnostics\AutoPilot' -ErrorAction Stop }
$AutopilotProfile = Get-Safe { [string]$Autopilot.DeploymentProfileName } ''
$AutopilotTenant  = Get-Safe { [string]$Autopilot.CloudAssignedTenantDomain } ''
# Nieuwere builds vullen DeploymentProfileName niet altijd; dan uit de policy-cache halen
if (-not $AutopilotProfile) {
    $AutopilotProfile = Get-Safe {
        $cache = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Provisioning\AutopilotPolicyCache' -ErrorAction Stop
        $json  = $cache.PolicyJsonCache | ConvertFrom-Json
        if ($json.DeploymentProfileName) { [string]$json.DeploymentProfileName }
        elseif (-not $AutopilotTenant -and $json.CloudAssignedTenantDomain) { $script:AutopilotTenant = [string]$json.CloudAssignedTenantDomain; '' }
        else { '' }
    } ''
}

# --- Activering ---
$License = Get-Safe {
    Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationID='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" |
        Select-Object -First 1
}
$Activated   = Get-Safe { $License.LicenseStatus -eq 1 } $false
$LicenseInfo = Get-Safe { $License.Description } ''

# --- Beveiliging ---
$Tpm        = Get-Safe { Get-Tpm }
$TpmOk      = Get-Safe { $Tpm.TpmPresent -and $Tpm.TpmReady } $false
$SecureBoot = Get-Safe { Confirm-SecureBootUEFI } $false
$Mp         = Get-Safe { Get-MpComputerStatus }
$AvOk       = Get-Safe { $Mp.AntivirusEnabled -and $Mp.RealTimeProtectionEnabled } $false
$AvSig      = Get-Safe { $Mp.AntivirusSignatureVersion } '-'
$FwOk       = Get-Safe { -not (Get-NetFirewallProfile | Where-Object { -not $_.Enabled }) } $false

# --- BitLocker ---
$Bl          = Get-Safe { Get-BitLockerVolume -MountPoint 'C:' -ErrorAction Stop }
$BlStatus    = Get-Safe { [string]$Bl.VolumeStatus } 'Onbekend'
$BlProtect   = Get-Safe { [string]$Bl.ProtectionStatus } 'Onbekend'
$BlPercent   = Get-Safe { $Bl.EncryptionPercentage } 0
$BlProtector = Get-Safe { ($Bl.KeyProtector | ForEach-Object { [string]$_.KeyProtectorType }) -join ', ' } ''
$BlPolicy    = Get-Safe { (Get-Item 'HKLM:\SOFTWARE\Microsoft\PolicyManager\current\device\BitLocker' -ErrorAction Stop).Property.Count -gt 0 } $false

if ($BlStatus -eq 'FullyEncrypted' -and $BlProtect -eq 'On') { $EncState = 'ok' }
elseif ($BlStatus -in @('EncryptionInProgress', 'FullyEncrypted')) { $EncState = 'busy' }   # bezig of wacht op activering
elseif ($Intune) { $EncState = 'later' }
else { $EncState = 'off' }

# --- Drivers ---
$PnP          = Get-Safe { @(Get-CimInstance Win32_PnPEntity) } @()
$ProblemDevs  = @($PnP | Where-Object { $_.ConfigManagerErrorCode -and $_.ConfigManagerErrorCode -ne 22 })
$MissingDrv   = @($ProblemDevs | Where-Object { $_.ConfigManagerErrorCode -eq 28 }).Count

# --- Opslag en netwerk ---
$Disk    = Get-Safe { Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='C:'" }
$DiskTot = Get-Safe { [math]::Round($Disk.Size / 1GB) } 0
$DiskFre = Get-Safe { [math]::Round($Disk.FreeSpace / 1GB) } 0
# Alle actieve adapters met hardware (ook virtuele Hyper-V-kaart), zonder VPN/loopback/virtuele switches
# @() buiten Get-Safe: een functie pakt een array met 1 element uit, en .Count op een
# losse CimInstance is in PowerShell 5.1 leeg -> gaf ten onrechte "Geen actieve verbinding".
$NetUp   = @(Get-Safe { Get-NetAdapter -ErrorAction Stop | Where-Object { $_.Status -eq 'Up' -and -not $_.Virtual } } | Where-Object { $_ })
$NetText = if ($NetUp.Count) {
    ($NetUp | ForEach-Object {
        $type = if ($_.NdisPhysicalMedium -eq 9) { 'WiFi' } else { 'Kabel' }
        "$type ($($_.InterfaceDescription))"
    }) -join ', '
} else { 'Geen actieve verbinding' }

# --- Herstart nodig? ---
$RebootPending = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
                 (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending')

# --- Windows Updates sinds installatie (Windows Update-historie) ---
$Updates = @()
try {
    $Searcher = (New-Object -ComObject Microsoft.Update.Session).CreateUpdateSearcher()
    $Count    = $Searcher.GetTotalHistoryCount()
    if ($Count -gt 0) {
        $Since = $InstallDate.ToUniversalTime()
        foreach ($h in $Searcher.QueryHistory(0, $Count)) {
            if ($h.Operation -ne 1 -or $h.Date -lt $Since) { continue }
            $kb = if ($h.Title -match '(KB\d{6,8})') { $Matches[1] } else { '-' }
            $result = switch ($h.ResultCode) {
                2 { 'Ge&iuml;nstalleerd' } 3 { 'Ge&iuml;nstalleerd' } 4 { 'Mislukt' } 5 { 'Afgebroken' } default { 'Bezig' }
            }
            $Updates += [pscustomobject]@{
                Date   = [DateTime]::SpecifyKind($h.Date, 'Utc').ToLocalTime()
                Title  = $h.Title
                KB     = $kb
                Ok     = $h.ResultCode -in 2, 3
                Result = $result
            }
        }
    }
} catch { Write-Warning "Windows Update-historie niet beschikbaar: $($_.Exception.Message)" }
# Per update maar een regel: drivers mislukken vaak bij de eerste poging (basisdriver nog niet
# aanwezig) en lukken daarna wel. Alleen de eindstand tonen.
# Store-apps (titel "9NBLGGH3FRZM-Microsoft.VCLibs...") krijgen een leesbare naam.
$Updates = @($Updates | Group-Object Title | ForEach-Object {
    $tries = @($_.Group | Sort-Object Date)
    $last  = $tries[-1]
    $okAny = [bool]($tries | Where-Object Ok)
    $title = $last.Title -replace '^[0-9A-Z]{12}-', '' -replace '^Microsoft\.', 'Microsoft '
    $res   = if ($okAny) { 'Ge&iuml;nstalleerd' } else { $last.Result }
    [pscustomobject]@{ Date = $last.Date; Title = $title; KB = $last.KB; Ok = $okAny; Result = $res }
} | Sort-Object Date)
$UpdatesOk = @($Updates | Where-Object Ok).Count

# === Teksten voor de gebruiker ===================================
$IconOk   = '<span class="ic ok" role="img" aria-label="Gereed"><svg width="16" height="16" viewBox="0 0 16 16"><path d="M3 8.5l3.2 3L13 4.5" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round"/></svg></span>'
$IconBusy = '<span class="ic busy" role="img" aria-label="Wordt nog afgerond"><svg width="16" height="16" viewBox="0 0 16 16"><circle cx="8" cy="8" r="5.5" fill="none" stroke="currentColor" stroke-width="1.8"/><path d="M8 5v3.2l2 1.3" fill="none" stroke="currentColor" stroke-width="1.8" stroke-linecap="round"/></svg></span>'
$IconInfo = '<span class="ic info" role="img" aria-label="Informatie"><svg width="16" height="16" viewBox="0 0 16 16"><path d="M8 7v5.5M8 3.8v.2" fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round"/></svg></span>'

$Done = @()
# 1. Windows
if ($UpdatesOk -gt 0) {
    $Done += @{ Icon = $IconOk; Title = 'Windows is bijgewerkt'; Detail = "$(Enc $OsName) ($(Enc $OsVersion)) met $UpdatesOk updates sinds de installatie." }
} else {
    $Done += @{ Icon = $IconOk; Title = 'Windows is ge&iuml;nstalleerd'; Detail = "$(Enc $OsName) ($(Enc $OsVersion)). Er waren geen extra updates nodig." }
}
# 2. Beveiliging
if ($AvOk -and $FwOk) {
    $Done += @{ Icon = $IconOk; Title = 'Je computer is beveiligd'; Detail = 'Virusscanner en firewall staan aan.' }
} else {
    $Done += @{ Icon = $IconBusy; Title = 'Beveiliging wordt ingesteld'; Detail = 'Dit gebeurt automatisch op de achtergrond.' }
}
# 3. Account
if (-not $IsLocalUser) {
    $Done += @{ Icon = $IconOk; Title = "Gekoppeld aan $(Enc $OrgName)"; Detail = 'Je logt in met je werkaccount; je instellingen en apps komen vanzelf.' }
} else {
    $Done += @{ Icon = $IconInfo; Title = 'Aangemeld met een lokaal account'; Detail = 'Deze computer gebruikt een lokaal account, niet gekoppeld aan een organisatieaccount.' }
}
# 4. Drivers
if ($ProblemDevs.Count -eq 0) {
    $Done += @{ Icon = $IconOk; Title = 'Alle onderdelen werken'; Detail = 'Scherm, geluid, wifi, camera en andere onderdelen zijn herkend.' }
} else {
    $n = $ProblemDevs.Count
    $word = if ($n -eq 1) { 'onderdeel' } else { 'onderdelen' }
    $Done += @{ Icon = $IconBusy; Title = 'Bijna alle onderdelen werken'; Detail = "Voor $n $word wordt nog een stuurprogramma gezocht. Werkt er iets niet? Neem contact met ons op." }
}
# 5. Versleuteling
switch ($EncState) {
    'ok'    { $Done += @{ Icon = $IconOk;   Title = 'Je gegevens zijn versleuteld'; Detail = 'Als je computer kwijtraakt, kan niemand bij je bestanden.' } }
    'busy'  { $Done += @{ Icon = $IconBusy; Title = 'Versleuteling wordt ingesteld'; Detail = 'Dit gebeurt automatisch op de achtergrond. Je hoeft niets te doen.' } }
    'later' { $Done += @{ Icon = $IconBusy; Title = 'Versleuteling wordt automatisch ingesteld'; Detail = 'Dit gebeurt op de achtergrond zodra het beleid van je organisatie binnen is.' } }
    'off'   { $Done += @{ Icon = $IconInfo; Title = 'Versleuteling staat niet aan'; Detail = 'Op deze computer is versleuteling (BitLocker) niet ingeschakeld.' } }
}

$Todo = @()
if ($RebootPending) {
    $Todo += @{ Title = 'Start je computer &eacute;&eacute;n keer opnieuw op'; Detail = 'Zo worden de laatste updates afgerond. Kies Start, dan Aan/uit en Opnieuw opstarten.' }
}
if ($Intune -or -not $IsLocalUser) {
    $Todo += @{ Title = 'Laat je computer vandaag een uur aan staan'; Detail = 'Met internet erbij worden je apps en instellingen op de achtergrond klaargezet.' }
}
if (-not $IsLocalUser) {
    $Todo += @{ Title = 'Controleer of je bestanden en mail er zijn'; Detail = 'Open Outlook en OneDrive. Mist er iets? Neem contact met ons op.' }
}
if ($Todo.Count -eq 0) {
    $Todo += @{ Title = 'Je kunt direct aan de slag'; Detail = 'Er hoeft niets meer te gebeuren.' }
}

# === HTML opbouwen ===============================================
$Logo = if (Test-Path $LogoPath) {
    "<img src=`"data:image/png;base64,$([Convert]::ToBase64String([IO.File]::ReadAllBytes($LogoPath)))`" alt=`"Connectium`" class=`"logo`">"
} else { '<span class="wordmark">CONNECTIUM</span>' }

$Greeting = if ($FirstName -and -not $IsLocalUser) { "Welkom, $(Enc $FirstName)" } else { 'Welkom' }

$DoneHtml = ($Done | ForEach-Object {
    "<li class=`"done`">$($_.Icon)<div><strong>$($_.Title)</strong><span>$($_.Detail)</span></div></li>"
}) -join "`n"

$i = 0
$TodoHtml = ($Todo | ForEach-Object {
    $i++
    "<li class=`"todo`"><span class=`"num`">$i</span><div><strong>$($_.Title)</strong><span>$($_.Detail)</span></div></li>"
}) -join "`n"

if ($DeployCLabel) {
    $LabelHtml = "<div><dt>C-label</dt><dd class=`"mono big`">$(Enc $DeployCLabel)</dd></div>"
    if ($ComputerName -ne $DeployCLabel) {
        $LabelHtml += "<div><dt>Computernaam</dt><dd class=`"mono`">$(Enc $ComputerName)</dd></div>"
    }
} elseif ($ComputerName -match $LabelPattern) {
    $LabelHtml = "<div><dt>C-label</dt><dd class=`"mono big`">$(Enc $ComputerName)</dd></div>"
} else {
    $LabelHtml = "<div><dt>C-label</dt><dd>Zie de sticker op je computer</dd></div><div><dt>Computernaam</dt><dd class=`"mono`">$(Enc $ComputerName)</dd></div>"
}

function Row([string]$k, [string]$v) { "<div><dt>$k</dt><dd>$v</dd></div>" }
function YesNo([bool]$b) { if ($b) { 'Aan' } else { 'Uit' } }

$Tech1 = @(
    Row 'Klant'             (Enc $(if ($Customer) { $Customer } else { '-' }))
    Row 'C-label / naam'    (Enc "$(if ($DeployCLabel) { $DeployCLabel } else { 'niet ingevuld' }) / $ComputerName")
    Row 'Fabrikant / model' (Enc $(if ($Model -like "$Manufacturer *") { $Model } else { "$Manufacturer $Model" }))
    Row 'Serienummer'       (Enc $Serial)
    Row 'BIOS'              (Enc "$BiosVersion $BiosDate")
    Row 'Processor'         (Enc $cpu)
    Row 'Geheugen'          "$RamGB GB"
    Row 'Windows'           (Enc "$OsName $OsVersion - build $OsBuild - $OsLanguage")
    Row 'Activering'        (Enc $(if ($Activated) { "Geactiveerd - $LicenseInfo" } else { "Niet geactiveerd - $LicenseInfo" }))
    Row 'TPM / Secure Boot' "$(YesNo $TpmOk) / $(YesNo $SecureBoot)"
    Row 'Schijf C:'         "$DiskFre GB vrij van $DiskTot GB"
) -join "`n"

$Tech2 = @(
    Row 'Aangemelde gebruiker' (Enc $(if ($UserName -and $DisplayName) { "$UserName ($DisplayName)" } elseif ($UserName) { $UserName } else { '-' }))
    Row 'Entra ID / domein'    (Enc "AzureAdJoined: $(if ($AadJoined) {'Ja'} else {'Nee'}) - DomainJoined: $(if ($DomainJoined) {'Ja'} else {'Nee'}) - $OrgName")
    Row 'Intune-inschrijving'  $(if ($Intune) { 'Ja' } else { 'Nee' })
    Row 'Autopilot-profiel'    (Enc $(if ($AutopilotProfile) { "$AutopilotProfile ($AutopilotTenant)" } elseif ($AutopilotTenant) { "Ja, naam onbekend ($AutopilotTenant)" } else { '-' }))
    Row 'Defender'             (Enc "$(YesNo $AvOk) - definities $AvSig - firewall $(YesNo $FwOk)")
    Row 'BitLocker C:'         (Enc "$BlStatus - beveiliging $BlProtect - $BlPercent% - $BlProtector")
    Row 'BitLocker-beleid'     $(if ($BlPolicy) { 'Aanwezig' } else { 'Nog niet ontvangen' })
    Row 'Apparaten met probleem' "$($ProblemDevs.Count) (zonder driver: $MissingDrv)"
    Row 'Netwerk'              (Enc $NetText)
    Row 'Herstart nodig'       $(if ($RebootPending) { 'Ja' } else { 'Nee' })
    Row 'Ge&iuml;nstalleerd'   (Enc $(if ($DeployDate) { "$DeployDate (deployment v2)" } else { $InstallText }))
) -join "`n"

$UpdRows = if ($Updates.Count) {
    ($Updates | ForEach-Object {
        "<tr><td class=`"mono`">$($_.Date.ToString('dd-MM HH:mm'))</td><td class=`"mono`">$(Enc $_.KB)</td><td>$(Enc $_.Title)</td><td>$($_.Result)</td></tr>"
    }) -join "`n"
} else { '<tr><td colspan="4">Geen updates gevonden in de Windows Update-historie.</td></tr>' }

$DevHtml = if ($ProblemDevs.Count) {
    $rows = ($ProblemDevs | ForEach-Object {
        "<tr><td>$(Enc $_.Name)</td><td class=`"mono`">$(Enc $_.ConfigManagerErrorCode)</td><td class=`"mono`">$(Enc ($_.HardwareID | Select-Object -First 1))</td></tr>"
    }) -join "`n"
    "<div class=`"scroll`"><table><caption>Apparaten met een probleem</caption><thead><tr><th scope=`"col`">Apparaat</th><th scope=`"col`">Code</th><th scope=`"col`">Hardware-ID</th></tr></thead><tbody>$rows</tbody></table></div>"
} else { '' }

$Generated = (Get-Date).ToString('d MMMM yyyy HH:mm', $NL)

$Html = @"
<!doctype html>
<html lang="nl">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Je nieuwe computer is klaar</title>
<style>
:root{--ink:#26324A;--muted:#5A6475;--line:#E3E6EB;--soft:#EEF0F3;--bg:#F4F5F7}
*{box-sizing:border-box}
body{margin:0;background:var(--bg);color:var(--ink);font-family:'Segoe UI Variable Text','Segoe UI',system-ui,sans-serif;font-size:16px;line-height:1.55}
.wrap{max-width:980px;margin:0 auto;padding:0 24px}
header{background:#fff;border-bottom:1px solid var(--line)}
header .wrap{display:flex;flex-wrap:wrap;align-items:center;justify-content:space-between;gap:16px;padding-top:16px;padding-bottom:16px}
.logo{height:40px;width:auto;display:block}
.wordmark{font-weight:600;letter-spacing:.18em}
.muted{color:var(--muted);font-size:14px}
main{display:flex;flex-direction:column;gap:28px;padding-top:40px;padding-bottom:56px}
.pill{display:inline-flex;align-items:center;gap:8px;padding:6px 14px;border-radius:999px;background:#E6F3EB;color:#17643B;font-weight:600;font-size:14px}
h1{margin:10px 0 6px;font-family:'Segoe UI Variable Display','Segoe UI',system-ui,sans-serif;font-size:40px;line-height:1.15;font-weight:600}
.lead{margin:0;font-size:19px;color:#3E4859;max-width:640px}
.card{background:#fff;border:1px solid var(--line);border-radius:16px;padding:28px}
h2{margin:0 0 18px;font-size:20px;font-weight:600}
ul,ol{list-style:none;margin:0;padding:0}
.grid{display:flex;flex-wrap:wrap;gap:16px}
.done{flex:1 1 260px;display:flex;gap:14px;align-items:flex-start;padding:16px;border-radius:12px;border:1px solid var(--soft)}
.done div,.todo div{display:flex;flex-direction:column;min-width:0}
.done span:not(.ic),.todo div span{font-size:15px;color:var(--muted)}
.ic{flex:none;width:34px;height:34px;border-radius:999px;display:flex;align-items:center;justify-content:center}
.ic.ok{background:#E6F3EB;color:#17643B}.ic.busy{background:#EAF0F8;color:#24508A}.ic.info{background:#EAF0F8;color:#24508A}
.steps{display:flex;flex-direction:column;gap:14px}
.todo{display:flex;gap:16px;align-items:flex-start}
.num{flex:none;width:34px;height:34px;border-radius:999px;background:var(--ink);color:#fff;font-weight:600;display:flex;align-items:center;justify-content:center}
.todo div{padding-top:4px}
.help{background:var(--ink);color:#fff;border-radius:16px;padding:28px;display:flex;flex-wrap:wrap;justify-content:space-between;gap:24px}
.help>div{flex:1 1 320px;display:flex;flex-direction:column;gap:8px}
.help h2{margin:0}.help p{margin:0;color:#D7DCE4}
.btns{display:flex;flex-wrap:wrap;gap:12px;margin-top:8px}
.btn{display:inline-flex;align-items:center;min-height:44px;padding:0 18px;border-radius:8px;font-weight:600;text-decoration:none}
.btn.primary{background:#fff;color:var(--ink)}.btn.ghost{border:1px solid #8D97A8;color:#fff}
.help dl{flex:0 1 300px;margin:0;display:flex;flex-direction:column;gap:12px;padding:18px 20px;border-radius:12px;background:#34415C}
.help dl div{display:flex;flex-direction:column}
.help dt{font-size:13px;color:#C3CAD6}.help dd{margin:0;font-size:15px;font-weight:600}
.mono{font-family:'Cascadia Mono',Consolas,monospace}
.big{font-size:22px}.help dd.mono{font-size:17px}.help dd.big{font-size:22px}
details{background:#fff;border:1px solid var(--line);border-radius:16px;padding:20px 28px}
summary{cursor:pointer;font-weight:600;color:var(--muted);min-height:44px;display:flex;align-items:center}
.tech{display:flex;flex-direction:column;gap:24px;padding:12px 0 8px;font-size:14px}
.cols{display:flex;flex-wrap:wrap;gap:24px}
.cols dl{flex:1 1 360px;min-width:0;margin:0}
.cols dl div{display:flex;flex-wrap:wrap;justify-content:space-between;gap:4px 16px;padding:8px 0;border-top:1px solid var(--soft)}
.cols dt{color:var(--muted)}.cols dd{margin:0;font-weight:500;text-align:right}
.scroll{overflow-x:auto}
table{width:100%;min-width:640px;border-collapse:collapse}
caption{text-align:left;font-weight:600;padding-bottom:8px}
th{text-align:left;color:var(--muted);font-weight:600;padding:8px 12px 8px 0;border-bottom:1px solid var(--line)}
td{padding:8px 12px 8px 0;border-bottom:1px solid var(--soft);vertical-align:top}
.logs{display:flex;flex-direction:column;gap:2px;color:var(--muted)}
@media print{details{display:block}details>*{display:block}body{background:#fff}}
</style>
</head>
<body>
<header><div class="wrap">$Logo<span class="muted">Ge&iuml;nstalleerd op $(Enc $InstallText)</span></div></header>
<main class="wrap">

<section aria-labelledby="welcome">
<span class="pill"><svg width="16" height="16" viewBox="0 0 16 16" aria-hidden="true"><path d="M3 8.5l3.2 3L13 4.5" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>Klaar voor gebruik</span>
<h1 id="welcome">$Greeting</h1>
<p class="lead">Je nieuwe computer is ingericht en bijgewerkt. Hieronder zie je wat we voor je hebben gedaan en wat je nog moet doen.</p>
</section>

<section class="card" aria-labelledby="done-title">
<h2 id="done-title">Wat we hebben gedaan</h2>
<ul class="grid">
$DoneHtml
</ul>
</section>

<section class="card" aria-labelledby="todo-title">
<h2 id="todo-title">Wat je nog moet doen</h2>
<ol class="steps">
$TodoHtml
</ol>
</section>

<section class="help" aria-labelledby="help-title">
<div>
<h2 id="help-title">Hulp nodig?</h2>
<p>Neem contact op met de servicedesk van Connectium. Noem dan je C-label: dat is het nummer op de sticker van je computer. Zo kunnen we je sneller helpen.</p>
<div class="btns">
<a class="btn primary" href="tel:$(Enc (($HelpPhone -replace '\(0\)', '') -replace '[^\d+]', ''))">$(Enc $HelpPhone)</a>
<a class="btn ghost" href="mailto:$(Enc $HelpMail)">$(Enc $HelpMail)</a>
</div>
</div>
<dl>
$LabelHtml
<div><dt>Serienummer</dt><dd class="mono">$(Enc $Serial)</dd></div>
</dl>
</section>

<details>
<summary>Technische details voor IT</summary>
<div class="tech">
<div class="cols">
<dl>
$Tech1
</dl>
<dl>
$Tech2
</dl>
</div>
<div class="scroll">
<table>
<caption>Windows Updates sinds de installatie</caption>
<thead><tr><th scope="col">Tijd</th><th scope="col">KB</th><th scope="col">Update</th><th scope="col">Resultaat</th></tr></thead>
<tbody>
$UpdRows
</tbody>
</table>
</div>
$DevHtml
<div class="logs">
<strong style="color:var(--ink)">Logbestanden</strong>
<span class="mono">C:\ProgramData\Scripts\WindowsUpdates\Wrapper.log</span>
<span class="mono">C:\ProgramData\Scripts\WindowsUpdates\Network.log</span>
<span class="mono">C:\ProgramData\Connectium\InstallReport.log</span>
<span class="mono">C:\Windows\Temp\osdcloud-logs</span>
<span>Rapport gemaakt op $(Enc $Generated)</span>
</div>
</div>
</details>

</main>
</body>
</html>
"@

# UTF-8 zonder problemen in elke browser
[IO.File]::WriteAllText($OutFile, $Html, (New-Object System.Text.UTF8Encoding($true)))
Write-Host "Rapport geschreven: $OutFile"

# Zelfde inhoud als JSON voor het rapportvenster in de popup (Start-UpdatePopup.ps1)
function Plain([string]$s) { [System.Net.WebUtility]::HtmlDecode(($s -replace '<[^>]+>', '')) }
function IconKind($i) { if ($i -eq $IconOk) { 'ok' } elseif ($i -eq $IconBusy) { 'busy' } else { 'info' } }
$Json = [ordered]@{
    greeting = Plain $Greeting
    intro    = 'Je nieuwe computer is ingericht en bijgewerkt. Hieronder zie je wat we hebben gedaan en wat je nog moet doen.'
    done     = @($Done | ForEach-Object { [ordered]@{ kind = (IconKind $_.Icon); title = (Plain $_.Title); detail = (Plain $_.Detail) } })
    todo     = @($Todo | ForEach-Object { [ordered]@{ title = (Plain $_.Title); detail = (Plain $_.Detail) } })
    phone    = $HelpPhone
    mail     = $HelpMail
    clabel   = $DeployCLabel
    serial   = $Serial
    html     = $OutFile
}
$JsonFile = [IO.Path]::ChangeExtension($OutFile, '.json')
[IO.File]::WriteAllText($JsonFile, ($Json | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))

# === Openen in Edge voor de aangemelde gebruiker ==================
function Open-ReportForUser([string]$Path) {
    $Edge = @(
        "${env:ProgramFiles(x86)}\Microsoft\Edge\Application\msedge.exe",
        "$env:ProgramFiles\Microsoft\Edge\Application\msedge.exe"
    ) | Where-Object { Test-Path $_ } | Select-Object -First 1

    $IsSystem = ([Security.Principal.WindowsIdentity]::GetCurrent()).User.Value -eq 'S-1-5-18'

    if (-not $Edge) {
        $Exe = 'explorer.exe'; $Arg = "`"$Path`""
    }
    else {
        # Rapport openen in een APART, tijdelijk Edge-profiel, InPrivate:
        # - het echte Edge-profiel van de gebruiker wordt niet aangeraakt (diens eerste start blijft normaal)
        # - geen aanmelden/synchroniseren-vragen
        $ProfileDir = Join-Path (Split-Path $Path -Parent) 'RapportBrowser'
        New-Item -Path $ProfileDir -ItemType Directory -Force | Out-Null
        if ($IsSystem) { $null = icacls.exe $ProfileDir /grant '*S-1-5-32-545:(OI)(CI)M' /T /Q }
        $Exe = $Edge
        $Arg = "--user-data-dir=`"$ProfileDir`" --inprivate --no-first-run --no-default-browser-check --start-maximized `"$Path`""
    }

    # Edge-welkomstwizard tijdelijk uitzetten (machinebeleid HideFirstRunExperience).
    # Alleen als het beleid nog niet bestaat; daarna weer verwijderd. Edge leest het alleen bij het starten.
    $PolicyKey   = 'HKLM:\SOFTWARE\Policies\Microsoft\Edge'
    $PolicyAdded = $false
    if ($Edge -and $IsSystem) {
        $Existing = (Get-ItemProperty -Path $PolicyKey -Name HideFirstRunExperience -ErrorAction SilentlyContinue).HideFirstRunExperience
        if ($null -eq $Existing) {
            New-Item -Path $PolicyKey -Force | Out-Null
            New-ItemProperty -Path $PolicyKey -Name HideFirstRunExperience -Value 1 -PropertyType DWord -Force | Out-Null
            $PolicyAdded = $true
        }
    }

    try {
        if (-not $IsSystem) { Start-Process -FilePath $Exe -ArgumentList $Arg; Start-Sleep -Seconds 15; return }

        # Als SYSTEM: via een tijdelijke taak in de sessie van de aangemelde gebruiker (groep Users, SID)
        $TaskName  = 'Connectium-OpenInstallReport'
        $Action    = New-ScheduledTaskAction -Execute $Exe -Argument $Arg
        $Principal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited
        $Settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries   # ook op accu
        Register-ScheduledTask -TaskName $TaskName -Action $Action -Principal $Principal -Settings $Settings -Force | Out-Null
        Start-ScheduledTask -TaskName $TaskName
        Start-Sleep -Seconds 20   # Edge laten starten (en het beleid laten inlezen)
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    }
    finally {
        if ($PolicyAdded) {
            Remove-ItemProperty -Path $PolicyKey -Name HideFirstRunExperience -ErrorAction SilentlyContinue
            # Lege beleidssleutel opruimen als wij die hebben aangemaakt en er verder niets in staat
            $Key = Get-Item -Path $PolicyKey -ErrorAction SilentlyContinue
            if ($Key -and $Key.ValueCount -eq 0 -and $Key.SubKeyCount -eq 0) { Remove-Item -Path $PolicyKey -Force -ErrorAction SilentlyContinue }
        }
    }
}

if (-not $NoOpen) {
    try { Open-ReportForUser -Path $OutFile; Write-Host "Rapport geopend." }
    catch { Write-Warning "Rapport kon niet worden geopend: $($_.Exception.Message)" }
}

Stop-Transcript | Out-Null
