# build-msi.ps1 — package Spring Boot JAR + JRE + WPF app (Windows x64)
# Align intent with oci-start-mac/build-dmg.sh. Phase 0: folder publish skeleton.
# Requires: Windows, .NET 8 SDK, Maven, JDK 11+ (for jlink)
$ErrorActionPreference = "Stop"

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Resolve-Path (Join-Path $ScriptDir "..")
$ServerDir = Join-Path $RepoRoot "oci-server"
$WinDir = $ScriptDir
$BuildDir = Join-Path $WinDir ".build"
$PublishDir = Join-Path $BuildDir "publish"
$CacheDir = Join-Path $BuildDir "cache"
$JarName = "oci-start-release"
$JavaVersion = 11

function Require-Cmd($name, $hint) {
    if (-not (Get-Command $name -ErrorAction SilentlyContinue)) {
        Write-Error "Missing tool: $name — $hint"
    }
}

Write-Host "==> oci-start-win package (Phase 0 skeleton)"
Require-Cmd "dotnet" "Install .NET 8 SDK: https://dotnet.microsoft.com/download"
Require-Cmd "mvn" "Install Maven"

New-Item -ItemType Directory -Force -Path $BuildDir, $CacheDir, $PublishDir | Out-Null

# 1) Build server jar
Write-Host "==> Maven package oci-server"
Push-Location $RepoRoot
try {
    mvn -pl oci-server -am package -DskipTests
} finally {
    Pop-Location
}

$JarSrc = Join-Path $ServerDir "target\$JarName.jar"
if (-not (Test-Path $JarSrc)) {
    # fallback common spring boot name
    $alt = Get-ChildItem (Join-Path $ServerDir "target") -Filter "*.jar" |
        Where-Object { $_.Name -notlike "*.original" } |
        Select-Object -First 1
    if ($alt) { $JarSrc = $alt.FullName }
}
if (-not (Test-Path $JarSrc)) {
    Write-Error "server jar not found under oci-server/target"
}

# 2) Publish WPF
Write-Host "==> dotnet publish"
$Csproj = Join-Path $WinDir "src\OciStart\OciStart.csproj"
dotnet publish $Csproj -c Release -r win-x64 --self-contained true -o $PublishDir

# 3) Inject jar
Copy-Item -Force $JarSrc (Join-Path $PublishDir "server.jar")
Write-Host "    server.jar -> publish\"

# 4) JRE (optional jlink) — Phase 0: copy JAVA_HOME if present
$JreOut = Join-Path $PublishDir "jre"
if (Test-Path $JreOut) { Remove-Item -Recurse -Force $JreOut }

$JavaHome = $env:JAVA_HOME
if (-not $JavaHome -or -not (Test-Path (Join-Path $JavaHome "bin\java.exe"))) {
    Write-Warning "JAVA_HOME not set; publish folder has no jre\. App may use PATH java in dev only."
} else {
    $Jlink = Join-Path $JavaHome "bin\jlink.exe"
    $Modules = "java.base,java.desktop,java.logging,java.management,java.naming,java.net.http,java.scripting,java.security.jgss,java.security.sasl,java.sql,java.xml,jdk.crypto.cryptoki,jdk.crypto.ec,jdk.unsupported,jdk.zipfs"
    if (Test-Path $Jlink) {
        Write-Host "==> jlink JRE ($JavaVersion modules)"
        & $Jlink `
            --add-modules $Modules `
            --strip-debug `
            --no-man-pages `
            --no-header-files `
            --compress=2 `
            --output $JreOut
    } else {
        Write-Host "==> copy JRE from JAVA_HOME (no jlink)"
        Copy-Item -Recurse -Force $JavaHome $JreOut
    }
}

Write-Host ""
Write-Host " OK publish folder:"
Write-Host "   $PublishDir"
Write-Host " Next: wire WiX/Inno for MSI; code-sign for SmartScreen."
Write-Host " Run:  $PublishDir\OciStart.exe"
