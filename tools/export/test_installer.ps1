# Проверка установщика Windows: тихая установка, всё ли создано, запуск игры из установленной папки,
# тихое удаление, всё ли убрано. Ничего не оставляет после себя (сохранения игрока не трогает).
#   powershell -File tools\export\test_installer.ps1 [-Setup путь\к\ShootIn-1.0.0-Setup.exe]
param([string]$Setup = "$PSScriptRoot\..\..\export\windows\ShootIn-1.0.0-Setup.exe")

$ErrorActionPreference = 'Stop'
# Игра печатает UTF-8: читаем вывод в той же кодировке, иначе русский текст не распознать.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$Setup = (Resolve-Path $Setup).Path
$dir = Join-Path $env:TEMP 'ShootIn-installer-test\Game'
$log = Join-Path $env:TEMP 'ShootIn-installer-test.log'
$script:fails = 0
function Check($ok, $text) {
    if ($ok) { Write-Host "OK   $text" } else { Write-Host "FAIL $text"; $script:fails++ }
}
Remove-Item (Split-Path $dir) -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item $log -Force -ErrorAction SilentlyContinue

$regPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\ShootIn'
$hadReg = Test-Path $regPath
Check (-not $hadReg) 'перед проверкой ShootIn не установлена (иначе тест затёр бы настоящую установку)'
if ($hadReg) { exit 2 }

# --- установка ---
$p = Start-Process $Setup -ArgumentList '/S', "/D=$dir", "/LOG=$log" -Wait -PassThru
Check ($p.ExitCode -eq 0) "установщик завершился с кодом $($p.ExitCode)"
Check (Test-Path "$dir\ShootIn.exe") 'ShootIn.exe установлен'
Check (Test-Path "$dir\Uninstall.exe") 'Uninstall.exe установлен'
Check (Test-Path "$dir\mods") 'папка mods создана рядом с игрой'
Check (Test-Path "$dir\mods\Как установить моды.txt") 'в mods лежит подсказка'
Check (Test-Path "$env:APPDATA\Godot\app_userdata\ShootIn\mods") 'папка сохранений и модов игрока создана'
$vi = (Get-Item "$dir\ShootIn.exe").VersionInfo
Check ($vi.ProductName -eq 'ShootIn' -and $vi.FileVersion -like '1.0.0*') "сведения о файле: $($vi.ProductName) $($vi.FileVersion)"

$shell = New-Object -ComObject WScript.Shell
$desktopLink = Join-Path ([Environment]::GetFolderPath('DesktopDirectory')) 'ShootIn.lnk'
$menuDir = Join-Path ([Environment]::GetFolderPath('Programs')) 'ShootIn'
Check (Test-Path $desktopLink) 'ярлык на рабочем столе создан'
if (Test-Path $desktopLink) {
    $t = $shell.CreateShortcut($desktopLink)
    Check ($t.TargetPath -eq "$dir\ShootIn.exe" -and $t.WorkingDirectory -eq $dir) "ярлык ведёт на $($t.TargetPath)"
}
Check ((Test-Path "$menuDir\ShootIn.lnk") -and (Test-Path "$menuDir\Папка модов ShootIn.lnk") -and (Test-Path "$menuDir\Удалить ShootIn.lnk")) 'три ярлыка в меню «Пуск» созданы'
$reg = Get-ItemProperty $regPath -ErrorAction SilentlyContinue
Check ($null -ne $reg -and $reg.InstallLocation -eq $dir -and $reg.DisplayName -eq 'ShootIn' -and $reg.UninstallString -like '*Uninstall.exe*') 'запись в «Установке и удалении программ» создана'

# --- игра из установленной папки ---
# Движок пишет служебные сообщения в stderr; через cmd они не считаются ошибкой PowerShell.
$smoke = cmd /c "`"$dir\ShootIn.exe`" --headless --script `"$PSScriptRoot\smoke_test.gd`" 2>&1" | Out-String
Check ($smoke -match 'ИТОГ: ВСЁ ХОРОШО') 'игра из установленной папки запускается и грузит все уровни'

# --- повторная установка поверх (обновление) ---
$p = Start-Process $Setup -ArgumentList '/S', "/D=$dir", '/NODESKTOP', "/LOG=$log" -Wait -PassThru
Check ($p.ExitCode -eq 0 -and (Test-Path "$dir\ShootIn.exe")) 'установка поверх существующей проходит без ошибок'

# --- сторонний мод в папке mods не должен пропасть при удалении ---
Set-Content "$dir\mods\мой-мод.txt" 'тест' -Encoding UTF8

# --- удаление ---
$p = Start-Process "$dir\Uninstall.exe" -ArgumentList '/S', "/LOG=$log" -PassThru
$p.WaitForExit()
for ($i = 0; $i -lt 60 -and (Test-Path "$dir\ShootIn.exe"); $i++) { Start-Sleep -Milliseconds 500 }
for ($i = 0; $i -lt 60 -and (Test-Path "$dir\Uninstall.exe"); $i++) { Start-Sleep -Milliseconds 500 }
Check (-not (Test-Path "$dir\ShootIn.exe")) 'после удаления ShootIn.exe нет'
Check (-not (Test-Path "$dir\Uninstall.exe")) 'после удаления Uninstall.exe нет'
Check ((Test-Path "$dir\mods\мой-мод.txt") -and -not (Test-Path "$dir\mods\Как установить моды.txt")) 'пользовательские моды сохранены, служебная подсказка убрана'
Check (-not (Test-Path $desktopLink)) 'ярлык на рабочем столе удалён'
Check (-not (Test-Path $menuDir)) 'папка в меню «Пуск» удалена'
Check (-not (Test-Path $regPath)) 'запись в реестре удалена'
Check (Test-Path "$env:APPDATA\Godot\app_userdata\ShootIn") 'сохранения игрока не тронуты'

Remove-Item (Split-Path $dir) -Recurse -Force -ErrorAction SilentlyContinue
Write-Host "ИТОГ: $(if ($script:fails -eq 0) { 'ВСЁ ХОРОШО' } else { 'ЕСТЬ ОШИБКИ' }) ($($script:fails) ошибок)"
if (Test-Path $log) { Write-Host '--- журнал установщика ---'; Get-Content $log -Encoding UTF8 | Select-Object -Last 12 }
exit $script:fails
