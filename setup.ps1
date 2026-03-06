# ==========================================================
# Chrome Utility (Site Lock) Installer
# Designed for execution via: irm https://<url>/setup.ps1 | iex
# ==========================================================

# NOTE: YOU MUST HOST YOUR .CRX FILE SOMEWHERE PUBLICLY ACCESSIBLE
# AND UPDATE THIS URL BEFORE USING `irm | iex`!
$CrxDownloadUrl = "https://raw.githubusercontent.com/rakinthegreat/Updates/main/SiteLock.crx" 
$ExtensionId = "kkjdhpiglfjgdodaeokkbnikhhoghpmk"

# Dedicated hidden system folder for the extension
$InstallDir = "C:\ProgramData\ChromeUtility"
$CrxFilePath = Join-Path $InstallDir "SiteLock.crx"
$UpdateXmlPath = Join-Path $InstallDir "update.xml"
$RegistryPath = "HKLM:\Software\Policies\Google\Chrome\ExtensionInstallForcelist"

# 1. Require Admin Privileges (Auto-Elevate)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "Elevating to Administrator privileges..." -ForegroundColor Yellow
    if ($PSCommandPath) {
        # Script was run from a saved local file
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`"" -Verb RunAs
    } else {
        # Script was run from memory (e.g. irm | iex)
        $scriptContents = $MyInvocation.MyCommand.ScriptBlock.ToString()
        $encodedCommand = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($scriptContents))
        Start-Process powershell -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $encodedCommand" -Verb RunAs
    }
    exit
}

Write-Host "==================" -ForegroundColor Cyan
Write-Host "  CHROME UTILITY  " -ForegroundColor White
Write-Host "==================" -ForegroundColor Cyan
Write-Host "1. Install and Lock Extension"
Write-Host "2. Uninstall and Unlock Extension"
Write-Host "3. Exit"

$choice = Read-Host "`nSelect an action (1/2/3)"

if ($choice -eq '1') {
    Write-Host "`n[+] Starting Installation..." -ForegroundColor Yellow
    
    # Create system directory
    if (-not (Test-Path $InstallDir)) {
        New-Item -ItemType Directory -Force -Path $InstallDir | Out-Null
    }
    
    # Download CRX
    Write-Host "[+] Downloading .crx payload..."
    try {
        Invoke-WebRequest -Uri $CrxDownloadUrl -OutFile $CrxFilePath -UseBasicParsing
    } catch {
        Write-Host "[-] FATAL: Could not download the extension from $CrxDownloadUrl" -ForegroundColor Red
        Write-Host "Have you uploaded your SiteLock.crx to that URL yet?" -ForegroundColor Yellow
        exit
    }

    # Generate XML
    $xmlContent = @"
<?xml version='1.0' encoding='UTF-8'?>
<gupdate xmlns='http://www.google.com/update2/response' protocol='2.0'>
  <app appid='$ExtensionId'>
    <updatecheck codebase='file:///$($CrxFilePath -replace '\\', '/')' version='1.0' />
  </app>
</gupdate>
"@
    Set-Content -Path $UpdateXmlPath -Value $xmlContent -Encoding UTF8
    Write-Host "[+] Configured update manifest."

    # Update Registry
    if (!(Test-Path $RegistryPath)) {
        New-Item -Path $RegistryPath -Force | Out-Null
    }

    $updateUrl = "file:///$($UpdateXmlPath -replace '\\', '/')"
    $policyValue = "$ExtensionId;$updateUrl"

    $index = 1
    while ($true) {
        $existing = (Get-ItemProperty -Path $RegistryPath -Name $index.ToString() -ErrorAction SilentlyContinue).$index
        if ($null -eq $existing -or $existing -match "^$ExtensionId") {
            break
        }
        $index++
    }

    Set-ItemProperty -Path $RegistryPath -Name $index.ToString() -Value $policyValue
    
    Write-Host "`n[✓] INSTALLATION COMPLETE!" -ForegroundColor Green
    Write-Host "The extension is now forced. Restart Google Chrome for it to take effect." -ForegroundColor Cyan
} 
elseif ($choice -eq '2') {
    Write-Host "`n[+] Starting Uninstallation..." -ForegroundColor Yellow
    
    # Remove Registry Policy
    if (Test-Path $RegistryPath) {
        $properties = (Get-Item $RegistryPath).Property
        $removed = $false
        foreach ($prop in $properties) {
            $val = (Get-ItemProperty -Path $RegistryPath -Name $prop -ErrorAction SilentlyContinue).$prop
            if ($null -ne $val -and $val -match "^$ExtensionId") {
                Remove-ItemProperty -Path $RegistryPath -Name $prop
                Write-Host "[+] Removed Enterprise Policy lock."
                $removed = $true
            }
        }
        if (-not $removed) {
             Write-Host "[-] Policy already unlocked or does not exist." -ForegroundColor Gray
        } else {
             # Check if the registry key is now empty and remove the "Managed" status if possible
             try {
                 if ((Get-Item $RegistryPath).Property.Count -eq 0) {
                     Remove-Item -Path $RegistryPath -Force -ErrorAction SilentlyContinue
                     Write-Host "[+] Removed empty ExtensionInstallForcelist key."
                 }
                 $chromePath = "HKLM:\Software\Policies\Google\Chrome"
                 if (Test-Path $chromePath) {
                     if ((Get-ChildItem -Path $chromePath -ErrorAction SilentlyContinue).Count -eq 0 -and (Get-Item $chromePath).Property.Count -eq 0) {
                         Remove-Item -Path $chromePath -Force -ErrorAction SilentlyContinue
                         Write-Host "[+] Removed empty Chrome policy key to clear 'Managed' status."
                     }
                 }
             } catch {}
        }
    }
    
    # Delete localized files
    if (Test-Path $InstallDir) {
        Remove-Item -Path $InstallDir -Recurse -Force
        Write-Host "[+] Wiped local extension payload from C:\ProgramData."
    }
    
    # 3. Forcefully wipe the extension from Chrome's AppData directories
    $chromeProfiles = @("Default", "Profile 1", "Profile 2", "Profile 3", "Profile 4")
    $appData = $env:LOCALAPPDATA
    
    foreach ($profile in $chromeProfiles) {
        $extPath = Join-Path $appData "Google\Chrome\User Data\$profile\Extensions\$ExtensionId"
        if (Test-Path $extPath) {
            Remove-Item -Path $extPath -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "[+] Wiped extension data from browser profile: $profile"
        }
    }
    
    Write-Host "`n[✓] UNINSTALLATION COMPLETE!" -ForegroundColor Green
    Write-Host "[+] Restarting Google Chrome to apply changes..." -ForegroundColor Yellow
    
    # Forcefully close Chrome and reopen it to the extensions page
    Stop-Process -Name "chrome" -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
    Start-Process -FilePath "chrome.exe" -ArgumentList "chrome://extensions" -ErrorAction SilentlyContinue
    
    Write-Host "Chrome has been restarted. You can now remove the extension normally from the newly opened tab." -ForegroundColor Cyan
}
else {
    Write-Host "Exiting." -ForegroundColor Gray
}

