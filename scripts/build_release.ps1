# Builds the release Android App Bundle with required --dart-define values.
# Run this instead of a bare `flutter build appbundle` so Play Store uploads
# never ship with empty Supabase/PostHog/RevenueCat/MapTiler credentials.

$ErrorActionPreference = "Stop"

$repoRoot = Split-Path -Parent $PSScriptRoot
$defineFile = Join-Path $repoRoot "dart_defines.env"

if (-not (Test-Path $defineFile)) {
    Write-Error "dart_defines.env not found at $defineFile. Cannot build a release without it."
    exit 1
}

$requiredKeys = @(
    "SUPABASE_URL",
    "SUPABASE_ANON_KEY",
    "GOOGLE_WEB_CLIENT_ID",
    "POSTHOG_API_KEY",
    "POSTHOG_HOST",
    "REVENUECAT_ANDROID_KEY",
    "REVENUECAT_IOS_KEY",
    "MAPTILER_KEY"
)

$lines = Get-Content $defineFile
$values = @{}
foreach ($line in $lines) {
    if ($line -match "^\s*([A-Z_]+)\s*=\s*(.*)$") {
        $values[$matches[1]] = $matches[2].Trim()
    }
}

$missing = @()
foreach ($key in $requiredKeys) {
    if (-not $values.ContainsKey($key) -or [string]::IsNullOrWhiteSpace($values[$key])) {
        $missing += $key
    }
}

if ($missing.Count -gt 0) {
    Write-Error "dart_defines.env is missing values for: $($missing -join ', '). Fix this before building."
    exit 1
}

Write-Host "All required dart-define keys present. Building release AAB..." -ForegroundColor Green

Push-Location $repoRoot
try {
    flutter build appbundle --release --dart-define-from-file=dart_defines.env
    if ($LASTEXITCODE -ne 0) {
        throw "flutter build appbundle failed with exit code $LASTEXITCODE"
    }
    Write-Host "Build succeeded: build\app\outputs\bundle\release\app-release.aab" -ForegroundColor Green
}
finally {
    Pop-Location
}
