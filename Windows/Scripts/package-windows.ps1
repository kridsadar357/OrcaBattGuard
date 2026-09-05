$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$solution = Join-Path $root "OrcaBattGuard.Windows.sln"
$project = Join-Path $root "src/OrcaBattGuard.Windows/OrcaBattGuard.Windows.csproj"
$publish = Join-Path $root "artifacts/win-x64"
$archive = Join-Path $root "artifacts/OrcaBattGuard-Windows-x64.zip"

dotnet test $solution -c Release
dotnet publish $project -c Release -r win-x64 --self-contained true -o $publish

if (Test-Path $archive) {
    Remove-Item $archive -Force
}
Compress-Archive -Path (Join-Path $publish "*") -DestinationPath $archive
Write-Host "Created $archive"
