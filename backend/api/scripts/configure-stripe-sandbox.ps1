# Run interactively on the development PC. Secrets are never printed.
$ErrorActionPreference = 'Stop'
$envPath = Join-Path (Split-Path $PSScriptRoot -Parent) '.env'
if (!(Test-Path $envPath)) { throw 'Create the local API .env first.' }
function Read-PrivateValue([string]$prompt) {
    $secret = Read-Host $prompt -AsSecureString
    $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
    try { return [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer).Trim() }
    finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}
$key = Read-PrivateValue 'Paste your Stripe SANDBOX secret or restricted test key'
if ($key -notmatch '^(sk|rk)_test_[A-Za-z0-9_]+$') { throw 'Only test keys are accepted. No configuration changed.' }
# Validate the sandbox privately, using only read access to its three prices.
$env:REVERIE_STRIPE_SETUP_KEY = $key
Push-Location (Split-Path $PSScriptRoot -Parent)
try {
    & node --env-file=.env --import tsx scripts/verify-stripe-sandbox-key.mjs
    if ($LASTEXITCODE -ne 0) { throw 'Sandbox verification failed. No configuration changed.' }
} finally {
    Remove-Item Env:REVERIE_STRIPE_SETUP_KEY -ErrorAction SilentlyContinue
    Pop-Location
}
$signing = Read-PrivateValue 'Webhook secret (whsec_), or press Enter for local manual test verification'
if ($signing -and $signing -notmatch '^whsec_[A-Za-z0-9_]+$') { throw 'Invalid signing secret. No configuration changed.' }
$manual = [string]::IsNullOrEmpty($signing)
$lines = @(Get-Content -LiteralPath $envPath | Where-Object { $_ -notmatch '^\s*STRIPE_TEST_(ENABLED|SECRET_KEY|WEBHOOK_SECRET|MANUAL_RECONCILE)\s*=' })
$lines += 'STRIPE_TEST_ENABLED=true'
$lines += ('STRIPE_TEST_SECRET_KEY=' + $key)
$lines += ('STRIPE_TEST_WEBHOOK_SECRET=' + $signing)
$lines += ('STRIPE_TEST_MANUAL_RECONCILE=' + $manual.ToString().ToLowerInvariant())
[IO.File]::WriteAllLines($envPath, [string[]]$lines, [Text.UTF8Encoding]::new($false))
Remove-Variable key,signing,lines
Write-Host 'Sandbox configuration saved to ignored local .env. Restart the local API. Live payments remain blocked.'
if ($manual) { Write-Host 'Manual test mode: use Refresh payment status in the shop. Webhooks are disabled.' }
