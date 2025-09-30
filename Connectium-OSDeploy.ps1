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

Import-Module OSD -Force
Install-Module OSD -Force

switch ($input)
{
    '1' { Start-OSDCloud -OSLanguage nl-nl -OSBuild 24H2 -OSEdition Pro -ZTI } 
    '2' { Start-OSDCloud -OSLanguage nl-nl -OSBuild 24H2 -OSEdition Home -ZTI } 
    '3' { Start-OSDCloud -OSLanguage en-us -OSBuild 24H2 -OSEdition Pro -ZTI } 
    '4' { Start-OSDCloudGui -v2}
    '5' { Exit		}
}

wpeutil reboot
