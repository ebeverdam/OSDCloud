Write-Host  -ForegroundColor Yellow "OSDCloud wordt gestart.."
cls
Write-Host "===================== Hoofdmenu =======================" -ForegroundColor Yellow
Write-Host "================ Connectium B.V =================" -ForegroundColor Yellow
Write-Host "==================== OSDCloud =====================" -ForegroundColor Yellow
Write-Host "=======================================================" -ForegroundColor Yellow
Write-Host "1: Zero-Touch Win11 24H2 | NL | Professional"-ForegroundColor Yellow
Write-Host "2: Zero-Touch Win11 24H2 | NL | Home" -ForegroundColor Yellow
Write-Host "3: Zero-Touch Win11 24H2 | ENG | Professional" -ForegroundColor Yellow
Write-Host "4: Zelf bepalen welke editie en opties..."-ForegroundColor Yellow
Write-Host "5: Afsluiten`n"-ForegroundColor Yellow
$input = Read-Host "Maak aub een keuze"

Write-Host  -ForegroundColor Yellow "Loading OSDCloud..."

#Import-Module OSD -Force
#Install-Module OSD -Force

#Set OSDCloud Vars
$Global:MyOSDCloud = [ordered]@{
    Restart = [bool]$False
    RecoveryPartition = [bool]$true
    OEMActivation = [bool]$True
    WindowsUpdate = [bool]$true
    WindowsUpdateDrivers = [bool]$true
    WindowsDefenderUpdate = [bool]$true
    SetTimeZone = [bool]$true
    ClearDiskConfirm = [bool]$False
    ShutdownSetupComplete = [bool]$false
    SyncMSUpCatDriverUSB = [bool]$true
    CheckSHA1 = [bool]$true
}

switch ($input)
{
    '1' { Start-OSDCloud -OSName 'Windows 11 24H2 x64' -OSLanguage 'nl-nl' -OSEdition 'Pro' -OSActivation 'Volume'} 
    '2' { Start-OSDCloud -OSName 'Windows 11 24H2 x64' -OSLanguage 'nl-nl' -OSEdition 'Home' -OSActivation 'Volume' } 
    '3' { Start-OSDCloud -OSName 'Windows 11 24H2 x64' -OSLanguage 'en-us' -OSEdition 'Pro' -OSActivation 'Volume' } 
    '4' { Start-OSDCloudGui -v2}
    '5' { Exit		}
}

wpeutil reboot
