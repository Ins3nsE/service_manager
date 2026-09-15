# Восстанавливает каталог windows\flutter\ephemeral\.plugin_symlinks, создавая
# junction'ы (каталоги-переходы) на пакеты плагинов из pub-кеша.
#
# Зачем: Flutter создаёт симлинки плагинов при сборке Windows, но на машинах
# без включённого режима разработчика (Developer Mode) и без прав администратора
# создание симлинков запрещено. Junction не требует ни того, ни другого,
# поэтому мы создаём их вручную. Flutter при сборке (force = false) пропускает
# уже существующие ссылки.
#
# Запуск:  powershell -ExecutionPolicy Bypass -File .\scripts\restore_plugin_symlinks.ps1
# Нужно повторно выполнять после `flutter pub get`, если список плагинов менялся.

$ErrorActionPreference = 'Stop'
# Корректный вывод кириллицы в любой консоли (PowerShell 5/7).
if ($PSVersionTable.PSVersion.Major -le 5) {
    [Console]::OutputEncoding = [System.Text.Encoding]::UTF8
}

$root = Split-Path -Parent $PSScriptRoot
$pubCache = Join-Path $env:LOCALAPPDATA 'Pub\Cache\hosted\pub.dev'
$cmakeFile = Join-Path $root 'windows\flutter\generated_plugins.cmake'
$symlinksDir = Join-Path $root 'windows\flutter\ephemeral\.plugin_symlinks'

if (-not (Test-Path $cmakeFile)) {
    Write-Error "Файл $cmakeFile не найден. Сначала выполните: flutter pub get"
}

# Собираем имена плагинов (и FFI-плагинов) из generated_plugins.cmake.
$names = [System.Collections.Generic.List[string]]::new()
$cmakeContent = Get-Content $cmakeFile -Raw
foreach ($list in @('FLUTTER_PLUGIN_LIST', 'FLUTTER_FFI_PLUGIN_LIST')) {
    $m = [regex]::Match($cmakeContent, "$list\s*\r?\n([\s\S]*?)\r?\n\s*\)")
    if (-not $m.Success) { continue }
    foreach ($line in ($m.Groups[1].Value -split "\r?\n")) {
        $name = $line.Trim()
        if ($name -and -not $name.StartsWith('#')) { $names.Add($name) }
    }
}

if ($names.Count -eq 0) {
    Write-Error 'Не найдено ни одного плагина в generated_plugins.cmake.'
}

New-Item -ItemType Directory -Path $symlinksDir -Force | Out-Null

foreach ($name in $names) {
    $pkg = Get-ChildItem -Path $pubCache -Directory -Filter "$name-*" |
        Sort-Object Name | Select-Object -Last 1
    if (-not $pkg) {
        Write-Warning "Пакет плагина '$name' не найден в $pubCache"
        continue
    }
    $link = Join-Path $symlinksDir $name
    if (Test-Path $link) { Remove-Item -Recurse -Force $link }
    New-Item -ItemType Junction -Path $link -Target $pkg.FullName | Out-Null
    Write-Host "OK: $name -> $($pkg.FullName)"
}

Write-Host ''
Write-Host 'Готово. Можно выполнять: flutter build windows --release'
