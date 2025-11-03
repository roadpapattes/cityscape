# --- CONFIG ---
$ServerUser = "deploy"
$ServerHost = "api.cityscape.ovh"
$RemoteDir  = "/var/www/cityscape/downloads"
$Notes      = "Publication auto"

# 1) (optionnel) Build
# flutter clean
# flutter pub get
# flutter build apk --release --dart-define=API_BASE_URL=https://api.cityscape.ovh

# 2) Trouver l'APK + métadonnées (versionCode/versionName)
$apk = "build\app\outputs\flutter-apk\app-release.apk"
if (-not (Test-Path $apk)) {
  Write-Error "APK introuvable: $apk"; exit 1
}

# output-metadata.json chemins possibles
$metaCandidates = @(
  "android\app\build\outputs\apk\release\output-metadata.json",
  "build\app\outputs\apk\release\output-metadata.json"
) | Where-Object { Test-Path $_ }

$versionCode = $null
$versionName = $null
if ($metaCandidates.Count -gt 0) {
  $meta = Get-Content $metaCandidates[0] -Raw | ConvertFrom-Json
  # AGP format
  $first = $meta.elements[0]
  $versionCode = $first.versionCode
  $versionName = $first.versionName
}

# fallback: lire dans build.gradle.kts
if (-not $versionCode -or -not $versionName) {
  $gradle = Get-Content "android\app\build.gradle.kts" -Raw
  if ($gradle -match "versionCode\s*=\s*(\d+)") { $versionCode = [int]$Matches[1] }
  if ($gradle -match "versionName\s*=\s*""([^""]+)""") { $versionName = $Matches[1] }
}

if (-not $versionCode) { $versionCode = 0 }
if (-not $versionName) { $versionName = "0.0.0" }

# 3) Nom distant horodaté
$stamp = Get-Date -Format "yyyyMMddHHmm"
$remoteName = "app-cityscape-$stamp.apk"
$remotePath = "$RemoteDir/$remoteName"

Write-Host "Upload => $remoteName (vCode=$versionCode, vName=$versionName)"

# 4) Upload
scp $apk "$ServerUser@$ServerHost:$remotePath"

# 5) Mise à jour latest + manifest côté serveur
# (on passe les variables d'env au script pour renseigner manifest.json)
$envCmd = "VERSION_CODE=$versionCode VERSION_NAME='$versionName' NOTES='$Notes'"
$remoteCmd = "$envCmd /usr/local/bin/update_apk_latest.sh && ls -lh $RemoteDir/app-latest.apk $RemoteDir/manifest.json $RemoteDir/app-latest.apk.sha256"
ssh --% "$ServerUser@$ServerHost" $remoteCmd

# 6) Vérifs HTTP
& curl.exe -I "https://api.cityscape.ovh/downloads/app-latest.apk"
& curl.exe -I "https://api.cityscape.ovh/downloads/manifest.json"