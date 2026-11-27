#Requires -Version 5.1
<#
  Little Haven - Phase 0 system inventory (READ-ONLY)

  This script makes NO changes to your system. It only reads settings, device
  lists and launcher manifests, and writes a report folder to your Desktop.

  Run from an *elevated* PowerShell (some power/security queries need admin):
      powershell -ExecutionPolicy Bypass -File .\inventory.ps1

  Output: Desktop\LittleHaven-Inventory-<timestamp>\
      inventory.json      structured results
      powercfg-*.txt      raw power configuration output
      dxdiag.txt          DirectX diagnostics (display / HDR / driver detail)

  Privacy: monitor/disk serial numbers and network addresses are not collected.
  File paths will contain your Windows user name. Review before sharing.
#>

$ErrorActionPreference = 'SilentlyContinue'
$stamp  = Get-Date -Format 'yyyyMMdd-HHmm'
$out    = Join-Path ([Environment]::GetFolderPath('Desktop')) "LittleHaven-Inventory-$stamp"
New-Item -ItemType Directory -Path $out -Force | Out-Null

$report = [ordered]@{}
function Section([string]$Name, [scriptblock]$Block) {
    Write-Host "  - $Name"
    try   { $report[$Name] = & $Block }
    catch { $report[$Name] = "ERROR: $($_.Exception.Message)" }
}
function RegValue($Path, $Name) {
    $p = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
    if ($p) { return $p.$Name } else { return $null }
}
function Decode($bytes) { if ($bytes) { -join ($bytes | Where-Object { $_ -ne 0 } | ForEach-Object { [char]$_ }) } }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
            [Security.Principal.WindowsBuiltInRole]::Administrator)
$report['Meta'] = [ordered]@{ Collected = (Get-Date).ToString('s'); RunAsAdmin = $isAdmin; Script = 'little-haven/tools/inventory.ps1 v1' }
if (-not $isAdmin) { Write-Warning 'Not elevated: wake-device, Secure Boot and TPM results will be incomplete.' }

Write-Host 'Collecting hardware...'
Section 'OS' {
    $os = Get-CimInstance Win32_OperatingSystem
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    [ordered]@{ Caption = $os.Caption; EditionID = $cv.EditionID; DisplayVersion = $cv.DisplayVersion
                Build = "$($cv.CurrentBuild).$($cv.UBR)"; LastBoot = $os.LastBootUpTime.ToString('s') }
}
Section 'CPU'    { Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors, MaxClockSpeed }
Section 'Board'  { [ordered]@{ Board = (Get-CimInstance Win32_BaseBoard | Select-Object Manufacturer, Product)
                               BIOS  = (Get-CimInstance Win32_BIOS | Select-Object Manufacturer, SMBIOSBIOSVersion, ReleaseDate) } }
Section 'Memory' { Get-CimInstance Win32_PhysicalMemory | Select-Object Manufacturer, PartNumber, Capacity, ConfiguredClockSpeed }
Section 'GPU'    { Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, DriverDate, CurrentHorizontalResolution, CurrentVerticalResolution, CurrentRefreshRate }
Section 'NvidiaSmi' {
    $smi = Join-Path $env:SystemRoot 'System32\nvidia-smi.exe'
    if (-not (Test-Path $smi)) { $smi = Join-Path $env:ProgramFiles 'NVIDIA Corporation\NVSMI\nvidia-smi.exe' }
    if (Test-Path $smi) { & $smi --query-gpu=name,driver_version,pstate,power.draw,temperature.gpu --format=csv } else { 'nvidia-smi not found' }
}
Section 'NvidiaApps' {
    Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*','HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*' |
        Where-Object { $_.DisplayName -match 'NVIDIA (app|GeForce Experience|Graphics Driver|Control Panel)' } |
        Select-Object DisplayName, DisplayVersion
}
Section 'Monitors' {
    Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorID | ForEach-Object {
        [ordered]@{ Manufacturer = Decode $_.ManufacturerName; Model = Decode $_.UserFriendlyName
                    ProductCode = Decode $_.ProductCodeID; YearOfManufacture = $_.YearOfManufacture; Active = $_.Active }
    }
}
Section 'MonitorConnection' {
    Get-CimInstance -Namespace root\wmi -ClassName WmiMonitorConnectionParams |
        Select-Object InstanceName, VideoOutputTechnology   # 10 = DisplayPort external, 5 = HDMI
}

Write-Host 'Collecting display diagnostics (dxdiag, ~30s)...'
$dx = Join-Path $out 'dxdiag.txt'
Start-Process -FilePath dxdiag.exe -ArgumentList "/t `"$dx`"" -Wait -WindowStyle Hidden
Section 'DisplayHighlights' {
    if (Test-Path $dx) {
        Select-String -Path $dx -Pattern 'Monitor Model|Current Mode|Native Mode|HDR|Advanced Color|Color Space|Driver Version|Hardware Scheduling|Variable Refresh|DDI Version' |
            ForEach-Object { $_.Line.Trim() } | Select-Object -Unique
    } else { 'dxdiag output missing' }
}

Write-Host 'Collecting power configuration...'
$pc = @{
    'available-states'  = '/a'
    'wake-armed'        = '/devicequery wake_armed'
    'wake-programmable' = '/devicequery wake_programmable'
    'active-scheme'     = '/getactivescheme'
    'sleep-settings'    = '/query SCHEME_CURRENT SUB_SLEEP'
    'button-settings'   = '/query SCHEME_CURRENT SUB_BUTTONS'
    'console-lock'      = '/query SCHEME_CURRENT SUB_NONE CONSOLELOCK'
    'last-wake'         = '/lastwake'
    'wake-timers'       = '/waketimers'
    'requests'          = '/requests'
}
foreach ($k in $pc.Keys) {
    $file = Join-Path $out "powercfg-$k.txt"
    cmd.exe /c "powercfg $($pc[$k])" 2>&1 | Out-File -FilePath $file -Encoding utf8
}
Section 'Power' {
    [ordered]@{
        AvailableStates   = Get-Content (Join-Path $out 'powercfg-available-states.txt')
        WakeArmed         = Get-Content (Join-Path $out 'powercfg-wake-armed.txt')
        WakeProgrammable  = Get-Content (Join-Path $out 'powercfg-wake-programmable.txt')
        ActiveScheme      = Get-Content (Join-Path $out 'powercfg-active-scheme.txt')
        FastStartup       = RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' 'HiberbootEnabled'
        PlatformAoAcOverride = RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\Power' 'PlatformAoAcOverride'
    }
}

Write-Host 'Collecting controllers / Bluetooth / USB...'
Section 'InputAndRadioDevices' {
    Get-PnpDevice -PresentOnly |
        Where-Object { $_.FriendlyName -match 'Xbox|XINPUT|Game ?pad|Controller|Bluetooth|Wireless Adapter|Gaming' -or $_.Class -in @('Bluetooth','XnaComposite','XboxComposite') } |
        Select-Object Class, FriendlyName, Status, Manufacturer
}
Section 'BluetoothRadios' { Get-PnpDevice -Class Bluetooth -PresentOnly | Where-Object { $_.FriendlyName -notmatch 'Enumerator|Protocol|Service|LE Generic|Avrcp' } | Select-Object FriendlyName, Status, Manufacturer }
Section 'UsbControllers'  { Get-CimInstance Win32_USBController | Select-Object Name, Manufacturer }
Section 'Biometrics'      { Get-PnpDevice -Class Biometric -PresentOnly | Select-Object FriendlyName, Status }

Write-Host 'Collecting sign-in and gaming settings...'
Section 'SignIn' {
    $wl = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon'
    [ordered]@{
        AutoAdminLogon          = RegValue $wl 'AutoAdminLogon'          # password values are deliberately NOT read
        PasswordlessDeviceOnly  = RegValue 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\PasswordLess\Device' 'DevicePasswordLessBuildVersion'
        RequireSignInOnWake     = Get-Content (Join-Path $out 'powercfg-console-lock.txt')
        MicrosoftAccountLinked  = [bool](Get-ChildItem 'HKCU:\Software\Microsoft\IdentityCRL\StoredIdentities' -ErrorAction SilentlyContinue)
    }
}
Section 'GamingSettings' {
    [ordered]@{
        GameBarControllerButton = RegValue 'HKCU:\Software\Microsoft\GameBar' 'UseNexusForGameBarEnabled'
        AutoGameMode            = RegValue 'HKCU:\Software\Microsoft\GameBar' 'AutoGameModeEnabled'
        GameDVR                 = RegValue 'HKCU:\System\GameConfigStore' 'GameDVR_Enabled'
        HardwareGpuScheduling   = RegValue 'HKLM:\SYSTEM\CurrentControlSet\Control\GraphicsDrivers' 'HwSchMode'   # 2 = on
        WindowedOptimizations   = RegValue 'HKCU:\Software\Microsoft\DirectX\UserGpuPreferences' 'DirectXUserGlobalSettings'
        XboxPackages = Get-AppxPackage | Where-Object { $_.Name -match 'Microsoft\.(GamingApp|GamingServices|XboxGamingOverlay|XboxIdentityProvider|Xbox\.TCUI)' } |
                       Select-Object Name, Version
        XboxModeNote = 'Also check manually: Settings > Gaming > Xbox mode (present? boot-into option?)'
    }
}
Section 'Security' {
    $dg = Get-CimInstance -Namespace root\Microsoft\Windows\DeviceGuard -ClassName Win32_DeviceGuard
    [ordered]@{
        SecureBoot          = $(try { Confirm-SecureBootUEFI } catch { 'unknown (needs admin / UEFI)' })
        TPM                 = $(try { Get-Tpm | Select-Object TpmPresent, TpmReady, ManufacturerVersion } catch { 'unknown (needs admin)' })
        VBSStatus           = $dg.VirtualizationBasedSecurityStatus   # 2 = running
        SecurityServices    = $dg.SecurityServicesRunning             # 2 = HVCI / memory integrity
        AntiCheatServices   = Get-Service | Where-Object { $_.Name -match 'EasyAntiCheat|BEService|^vgc$|^vgk$|FACEIT|AntiCheat|Javelin|EAAntiCheat' } |
                              Select-Object Name, DisplayName, Status, StartType
    }
}
Section 'WindowsUpdate' {
    [ordered]@{
        ActiveHoursStart = RegValue 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' 'ActiveHoursStart'
        ActiveHoursEnd   = RegValue 'HKLM:\SOFTWARE\Microsoft\WindowsUpdate\UX\Settings' 'ActiveHoursEnd'
        PolicyAU         = Get-ItemProperty 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU' | Select-Object * -ExcludeProperty PS*
        RecentHotfixes   = Get-HotFix | Sort-Object InstalledOn -Descending | Select-Object -First 5 HotFixID, InstalledOn
    }
}

Write-Host 'Collecting storefronts and games...'
$uninstall = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
                              'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*',
                              'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*'
Section 'Launchers' {
    $uninstall | Where-Object { $_.DisplayName -match '^(Steam|Epic Games Launcher|EA app|EA Desktop|Ubisoft Connect|GOG GALAXY|Playnite|Battle\.net|Rockstar Games Launcher|Amazon Games|Heroic)' } |
        Select-Object DisplayName, DisplayVersion, InstallLocation
}
Section 'Steam' {
    $steamPath = RegValue 'HKCU:\Software\Valve\Steam' 'SteamPath'
    if (-not $steamPath) { return 'not installed' }
    $vdf = Join-Path $steamPath 'steamapps\libraryfolders.vdf'
    $libs = @(Select-String -Path $vdf -Pattern '"path"\s+"(.+)"' | ForEach-Object { $_.Matches[0].Groups[1].Value -replace '\\\\','\' })
    $games = foreach ($lib in $libs) {
        Get-ChildItem (Join-Path $lib 'steamapps\appmanifest_*.acf') | ForEach-Object {
            $t = Get-Content $_.FullName -Raw
            [ordered]@{ AppId = ([regex]'"appid"\s+"(\d+)"').Match($t).Groups[1].Value
                        Name  = ([regex]'"name"\s+"([^"]+)"').Match($t).Groups[1].Value
                        StateFlags = ([regex]'"StateFlags"\s+"(\d+)"').Match($t).Groups[1].Value
                        Library = $lib }
        }
    }
    [ordered]@{ SteamPath = $steamPath; Libraries = $libs; InstalledCount = @($games).Count; Installed = $games
                BigPictureOnStart = RegValue 'HKCU:\Software\Valve\Steam' 'StartupMode' }
}
Section 'Epic' {
    $dir = Join-Path $env:ProgramData 'Epic\EpicGamesLauncher\Data\Manifests'
    if (-not (Test-Path $dir)) { return 'no manifests found' }
    Get-ChildItem (Join-Path $dir '*.item') | ForEach-Object {
        $j = Get-Content $_.FullName -Raw | ConvertFrom-Json
        [ordered]@{ DisplayName = $j.DisplayName; AppName = $j.AppName; Namespace = $j.CatalogNamespace
                    InstallLocation = $j.InstallLocation; SizeGB = [math]::Round($j.InstallSize / 1GB, 1) }
    }
}
Section 'GOG' {
    Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\GOG.com\Games' | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath; [ordered]@{ Name = $p.gameName; GameId = $p.gameID; Path = $p.path }
    }
}
Section 'Ubisoft' {
    Get-ChildItem 'HKLM:\SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs' | ForEach-Object {
        [ordered]@{ InstallId = $_.PSChildName; InstallDir = (Get-ItemProperty $_.PSPath).InstallDir }
    }
}
Section 'EA' {
    $uninstall | Where-Object { $_.Publisher -match 'Electronic Arts' -and $_.DisplayName -notmatch '^EA app' } |
        Select-Object DisplayName, DisplayVersion, InstallLocation
}
Section 'XboxPC' {
    $folders = Get-PSDrive -PSProvider FileSystem | ForEach-Object { Join-Path $_.Root 'XboxGames' } | Where-Object { Test-Path $_ }
    [ordered]@{ XboxGamesFolders = $folders
                Games = foreach ($f in $folders) { Get-ChildItem $f -Directory | Select-Object -ExpandProperty Name } }
}
Section 'Playnite' {
    $pn = Join-Path $env:APPDATA 'Playnite'
    [ordered]@{ DataFolderExists = (Test-Path $pn)
                Extensions = if (Test-Path (Join-Path $pn 'Extensions')) { Get-ChildItem (Join-Path $pn 'Extensions') -Directory | Select-Object -ExpandProperty Name } }
}

Write-Host 'Collecting storage, network, audio, background load...'
Section 'Storage' {
    [ordered]@{
        Physical = Get-PhysicalDisk | Select-Object FriendlyName, MediaType, BusType, @{n='SizeGB';e={[math]::Round($_.Size/1GB)}}
        Volumes  = Get-Volume | Where-Object DriveLetter | Select-Object DriveLetter, FileSystemLabel, FileSystem,
                   @{n='SizeGB';e={[math]::Round($_.Size/1GB)}}, @{n='FreeGB';e={[math]::Round($_.SizeRemaining/1GB)}}
    }
}
Section 'Network' { Get-NetAdapter | Where-Object Status -eq 'Up' | Select-Object Name, InterfaceDescription, MediaType, LinkSpeed }
Section 'Audio'   { Get-CimInstance Win32_SoundDevice | Select-Object Name, Status }
Section 'Startup' {
    [ordered]@{
        StartupCommands = Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location
        ScheduledTasksAtLogon = Get-ScheduledTask | Where-Object { $_.Triggers.CimClass.CimClassName -contains 'MSFT_TaskLogonTrigger' -and $_.State -ne 'Disabled' -and $_.TaskPath -notmatch '^\\Microsoft\\' } |
                                Select-Object TaskName, TaskPath
    }
}
Section 'TopProcessesByMemory' {
    Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 20 Name, @{n='WorkingSetMB';e={[math]::Round($_.WorkingSet64/1MB)}}, @{n='CPUSeconds';e={[math]::Round($_.CPU,1)}}
}

$json = Join-Path $out 'inventory.json'
$report | ConvertTo-Json -Depth 6 | Out-File -FilePath $json -Encoding utf8
Write-Host ''
Write-Host "Done. Nothing on your system was changed." -ForegroundColor Green
Write-Host "Report folder: $out"
