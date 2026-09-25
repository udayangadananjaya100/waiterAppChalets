param([switch]$Release)

$ErrorActionPreference = 'Stop'
$projectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$mapping = (& subst.exe | Select-String -Pattern '^[A-Z]:\\: => ' | ForEach-Object { $_.Line })
$drive = $null
foreach ($entry in $mapping) {
    $parts = $entry -split ' => ', 2
    if ($parts.Count -eq 2 -and $parts[1].TrimEnd('\') -ieq $projectRoot.TrimEnd('\')) {
        $drive = $parts[0].Substring(0, 2)
        break
    }
}
if (-not $drive) {
    foreach ($candidate in @('J:', 'Q:', 'X:', 'Z:')) {
        if (-not (Test-Path "${candidate}\")) {
            & subst.exe $candidate $projectRoot
            if ($LASTEXITCODE -ne 0) { throw "Could not map $candidate to the app folder." }
            $drive = $candidate
            break
        }
    }
}
if (-not $drive) { throw 'No free temporary drive letter is available for the Flutter tools.' }

$flutter = "${drive}\.tools\flutter\bin\flutter.bat"
if (-not (Test-Path $flutter)) {
    $command = Get-Command flutter.bat -ErrorAction SilentlyContinue
    if (-not $command) { throw 'Flutter SDK not found. Install Flutter or restore .tools/flutter.' }
    $flutter = $command.Source
}
$jdk = Get-ChildItem -LiteralPath (Join-Path $projectRoot '.tools\java') -Directory -Filter 'jdk-*' -ErrorAction SilentlyContinue | Select-Object -First 1
if ($jdk) { $env:JAVA_HOME = "${drive}\.tools\java\$($jdk.Name)" }
if (-not $env:JAVA_HOME) { throw 'JDK 17 or newer is required. Install it or restore .tools/java.' }
$env:GRADLE_USER_HOME = "${drive}\.tools\gradle"
New-Item -ItemType Directory -Force -Path "${drive}\tmp" | Out-Null
$env:JAVA_TOOL_OPTIONS = "-Djdk.net.unixdomain.tmpdir=${drive}\tmp -Djava.io.tmpdir=${drive}\tmp"

if ($Release -and -not (Test-Path (Join-Path $projectRoot 'android\key.properties'))) {
    throw 'Release signing is not configured. Copy android/key.properties.example to android/key.properties and use your company upload key.'
}
Push-Location "${drive}\"
try {
    & $flutter pub get
    if ($LASTEXITCODE -ne 0) { throw 'Flutter dependency download failed.' }
    if ($Release) { & $flutter build apk --release } else { & $flutter build apk --debug }
    if ($LASTEXITCODE -ne 0) { throw 'Android APK build failed.' }
    Write-Host "APK: $projectRoot\build\app\outputs\flutter-apk"
} finally { Pop-Location }
