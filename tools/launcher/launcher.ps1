# BULLIT мини-лаунчер: при КАЖДОМ запуске сверяет локальную версию с последним
# playtest-релизом на GitHub и, если вышло обновление, качает и распаковывает
# свежий билд — затем запускает игру. Так фиксы хоста подтягиваются сами.
# Лаунчер и игра — разные бинарники; сетевого кода здесь нет.
# Запуск: двойной клик по launcher.bat (лежит рядом).

$Repo = "Fijekronk/bullit"
$GameDir = Join-Path $PSScriptRoot "game"
$VersionFile = Join-Path $GameDir "version.txt"
$Exe = Join-Path $GameDir "bullit.exe"
$Headers = @{ "User-Agent" = "bullit-launcher" }

function Get-LocalVersion {
    if (Test-Path $VersionFile) { (Get-Content $VersionFile -Raw).Trim() } else { "" }
}

# Запустить установленный билд и выйти (общий путь для «нет интернета/ошибка»).
function Start-GameOrExit([string]$reason) {
    if ($reason) { Write-Host $reason -ForegroundColor Yellow }
    if (Test-Path $Exe) {
        Write-Host "Запускаю установленную версию..." -ForegroundColor Cyan
        Start-Process $Exe -WorkingDirectory $GameDir
        exit 0
    }
    Write-Host "Игра ещё не установлена, а обновление скачать не вышло." -ForegroundColor Red
    Write-Host "Проверь интернет и запусти launcher.bat снова." -ForegroundColor Red
    Read-Host "Enter — выход"
    exit 1
}

# Достать последний релиз (playtest публикуются как prerelease — latest их
# может не отдать, поэтому берём первый из общего списка).
function Get-LatestRelease {
    try {
        $r = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases/latest" -Headers $Headers -TimeoutSec 15
        if ($r -and $r.assets) { return $r }
    } catch { }
    try {
        $all = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repo/releases?per_page=1" -Headers $Headers -TimeoutSec 15
        if ($all -and $all.Count -gt 0) { return $all[0] }
    } catch { }
    return $null
}

Write-Host "BULLIT launcher — проверяю обновления..." -ForegroundColor Cyan
$local = Get-LocalVersion
Write-Host "Локальная версия: $(if ($local) { $local } else { '(нет билда)' })"

$release = Get-LatestRelease
if (-not $release) {
    Start-GameOrExit "Не удалось связаться с GitHub (нет интернета или релизов пока нет)."
}

$remoteVersion = $release.tag_name -replace "^playtest-", ""
Write-Host "Последний релиз:  $remoteVersion"

if ($remoteVersion -eq $local -and (Test-Path $Exe)) {
    Write-Host "Версия актуальна." -ForegroundColor Green
    Start-Process $Exe -WorkingDirectory $GameDir
    exit 0
}

Write-Host "Обновляюсь до $remoteVersion..." -ForegroundColor Green
$asset = $release.assets | Where-Object { $_.name -eq "bullit_win.zip" } | Select-Object -First 1
if (-not $asset) {
    Start-GameOrExit "В релизе нет bullit_win.zip — запускаю, что установлено."
}

$zip = Join-Path $env:TEMP "bullit_update.zip"
try {
    Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $zip -Headers $Headers -TimeoutSec 120
    if (-not (Test-Path $GameDir)) { New-Item -ItemType Directory $GameDir | Out-Null }
    Expand-Archive -LiteralPath $zip -DestinationPath $GameDir -Force
    Remove-Item $zip -Force -ErrorAction SilentlyContinue
    Write-Host "Готово: $(Get-LocalVersion)" -ForegroundColor Green
} catch {
    Start-GameOrExit "Скачать обновление не вышло ($($_.Exception.Message)). Запускаю, что установлено."
}

if (Test-Path $Exe) {
    Write-Host "Запускаю игру..." -ForegroundColor Cyan
    Start-Process $Exe -WorkingDirectory $GameDir
} else {
    Write-Host "bullit.exe не найден в $GameDir" -ForegroundColor Red
    Read-Host "Enter — выход"
    exit 1
}
