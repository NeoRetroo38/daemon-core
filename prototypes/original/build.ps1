$ErrorActionPreference = 'Stop'

$env:PATH = 'C:\msys64\mingw64\bin;' + $env:PATH

$cliSource = Join-Path $PSScriptRoot 'main.cpp'
$guiSource = Join-Path $PSScriptRoot 'gui.cpp'

$cliOutput = Join-Path $PSScriptRoot 'neo-cube.exe'
$guiOutput = Join-Path $PSScriptRoot 'choisys-local.exe'

Write-Output 'Building Neo Cube CLI...'

& g++ `
    -std=c++17 `
    -Wall `
    -Wextra `
    -Wpedantic `
    -static `
    $cliSource `
    -o $cliOutput

if ($LASTEXITCODE -ne 0) {
    throw 'CLI compilation failed.'
}

Write-Output "Built: $cliOutput"

Write-Output 'Building Choisys GUI...'

& g++ `
    -std=c++17 `
    -Wall `
    -Wextra `
    -Wpedantic `
    -mwindows `
    $guiSource `
    -o $guiOutput `
    -lgdiplus `
    -lgdi32 `
    -luser32

if ($LASTEXITCODE -ne 0) {
    throw 'GUI compilation failed.'
}

Write-Output "Built: $guiOutput"

Write-Output 'Build completed.'