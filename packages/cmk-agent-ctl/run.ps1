# Copyright (C) 2023 Checkmk GmbH - License: GNU General Public License v2
# This file is part of Checkmk (https://checkmk.com). It is subject to the terms and
# conditions defined in the file COPYING, which is part of this source code package.

# This is reinterpretation of our standard run script

if ((get-host).version.major -lt 7) {
    Write-Host "PowerShell version 7 or higher is required." -ForegroundColor Red
    exit
}

$package = Split-Path -Path (Get-Location) -Leaf

$exe_name = "$package.exe"
$root_dir = "$pwd/../.."
$work_dir = "$pwd"
$arte = "$root_dir/artefacts"
#set target=x86_64-pc-windows-mscvc
$cargo_target = "i686-pc-windows-msvc"
$exe_dir = "target/$cargo_target/release"


$packBuild = $false
$packClippy = $false
$packFormat = $false
$packCheckFormat = $false
$packTest = $false
$packDoc = $false

$shortenPath = ""
$shortenLink = ""


if ("$env:arg_var_value" -ne "") {
    $env:arg_val_name = $env:arg_var_value
}
else {
    $env:arg_val_name = ""
}

function Write-Help() {
    $x = Get-Item $PSCommandPath
    $x.BaseName
    $name = "pwsh -File " + $x.BaseName + ".ps1"

    Write-Host "Usage:"
    Write-Host ""
    Write-Host "$name [arguments]"
    Write-Host ""
    Write-Host "Available arguments:"
    Write-Host "  -?, -h, --help       display help and exit"
    Write-Host "  -A, --all            shortcut to -B -C -T -F:  build, cluippy, test, check format"
    Write-Host "  --clean              clean"
    Write-Host "  -C, --clippy         run  $package clippy"
    Write-Host "  -D, --documentation  create  $package documentation"
    Write-Host "  -f, --format         format  $package sources"
    Write-Host "  -F, --check-format   check for  $package correct formatting"
    Write-Host "  -B, --build          build binary $package"
    Write-Host "  -T, --test           run  $package unit tests"
    Write-Host "  --shorten link path  change dir from current using link"
    Write-Host ""
    Write-Host "Examples:"
    Write-Host ""
    Write-Host "$name --clippy"
    Write-Host "$name --build --test"
    Write-Host "$name --shorten y workspace\checkout"
}


if ($args.Length -eq 0) {
    Write-Host "No arguments provided. Running with default flags." -ForegroundColor Yellow
    $packAll = $true
}
else {
    for ($i = 0; $i -lt $args.Length; $i++) {
        switch ($args[$i]) {
            { $("-?", "-h", "--help") -contains "$_" } { Write-Help; return }
            { $("-A", "--all") -contains $_ } { $packAll = $true }
            { $("-f", "--format") -contains $_ } { $packFormat = $true }
            { $("-F", "--check-format") -contains $_ } { $packCheckFormat = $true }
            { $("-B", "--build") -contains $_ } { $packBuild = $true }
            { $("-C", "--clippy") -contains $_ } { $packClippy = $true }
            { $("-T", "--test") -contains $_ } { $packTest = $true }
            { $("-D", "--documentation") -contains $_ } { $packDoc = $true }
            "--clean" { $packClean = $true }
            "--var" {
                [Environment]::SetEnvironmentVariable($args[++$i], $args[++$i])
            }
            "--shorten" { 
                $shortenLink = $args[++$i] 
                $shortenPath = $args[++$i] 
            }
        }
    }
}


if ($packAll) {
    $packBuild = $true
    $packClippy = $true
    $packCheckFormat = $true
    $packTest = $true
}


function Start-ShortenPath($tgt_link, $path) {
    if ($tgt_link -eq "" -and $path -eq "") {
        Write-Host "No path shortening $tgt_link $path" -ForegroundColor Yellow
        return
    }

    [string]$inp = Get-Location
    [string]$new = $inp.tolower().replace($path, $tgt_link)
    if ($new.tolower() -eq $inp) {
        Write-Host "Can't to shorten path $inp doesn't contain $path" -ForegroundColor Yellow
        return
    }
    Write-Host "propose to shorten to: $new ($path, $tgt_link)"
    try {
        Set-Location $new -ErrorAction Stop
    }
    catch {
        Write-Host "Failed to shorten path, $new doesn't exist" -ForegroundColor Yellow
    }
}


function Invoke-Cargo($cmd) {
    Write-Host "$cmd $package" -ForegroundColor White
    & cargo $cmd

    if ($lastexitcode -ne 0) {
        Write-Error "Failed to $cmd $package with code $lastexitcode" -ErrorAction Stop
    }
}

function Invoke-Cargo($cmd) {
    Write-Host "$cmd $package" -ForegroundColor White
    & cargo $cmd

    if ($lastexitcode -ne 0) {
        Write-Error "Failed to $cmd $package with code $lastexitcode" -ErrorAction Stop
    }
}

function Test-Administrator {  
    [OutputType([bool])]
    param()
    process {
        [Security.Principal.WindowsPrincipal]$user = [Security.Principal.WindowsIdentity]::GetCurrent();
        return $user.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator);
    }
}

$result = 1
try {
    $mainStartTime = Get-Date
    & cargo --version > nul
    if ($lastexitcode -ne 0) {
        Write-Error "Cargo not found, please install it and/or add to PATH" -ErrorAction Stop
    }
    &rustup update
    &rustup target add $cargo_target
    rustc -V
    & cargo -V

    # Disable assert()s in C/C++ parts (e.g. wepoll-ffi), they map to _assert()/_wassert(),
    # which is not provided by libucrt. The latter is needed for static linking.
    # https://github.com/rust-lang/cc-rs#external-configuration-via-environment-variables
    $env:CFLAGS = "-DNDEBUG"

    # shorten path 
    Start-ShortenPath "$shortenLink" "$shortenPath"

    if ($packClean) {
        Invoke-Cargo "clean"
    }
    if ($packBuild) {
        &cargo build --release --target $cargo_target
        if ($lastexitcode -ne 0) {
            Write-Error "Failed to build $package with code $lastexitcode" -ErrorAction Stop
        }
    }
    if ($packClippy) {
        &cargo clippy --release --target $cargo_target --tests -- --deny warnings
        if ($lastexitcode -ne 0) {
            Write-Error "Failed to clippy $package with code $lastexitcode" -ErrorAction Stop
        }
    }

    if ($packFormat) {
        Invoke-Cargo "fmt"
    }

    if ($packCheckFormat) {
        Write-Host "test format $package" -ForegroundColor White
        cargo fmt -- --check
        if ($lastexitcode -ne 0) {
            Write-Error "Failed to test format $package" -ErrorAction Stop
        }
    }
    if ($packTest) {
        if (-not (Test-Administrator)) {
            Write-Error "Testing must be executed as Administrator." -ErrorAction Stop
        }
        cargo test --release --target $cargo_target -- --test-threads=4
        if ($lastexitcode -ne 0) {
            Write-Error "Failed to test $package" -ErrorAction Stop
        }
    }
    if ($packBuild -and $packTest -and $packClippy) {
        Write-Host "Uploading artifacts: [ $exe_dir/$exe_name ] ..." -Foreground White
        Copy-Item $exe_dir/$exe_name $arte/$exe_name -Force -ErrorAction Stop
    }
    if ($packDoc) {
        Invoke-Cargo "doc"
    }

    Write-Host "SUCCESS" -ForegroundColor Green
    $result = 0
}
catch {
    Write-Host "Error: " $_ -ForegroundColor Red
    Write-Host "Trace stack: " -ForegroundColor Yellow
    Write-Host $_.ScriptStackTrace -ForegroundColor Yellow
}
finally {
    Write-Host "Restore path to $work_dir" -ForegroundColor White
    Set-Location $work_dir
    $endTime = Get-Date
    $elapsedTime = $endTime - $mainStartTime
    Write-Host "Elapsed time: $($elapsedTime.Hours):$($elapsedTime.Minutes):$($elapsedTime.Seconds)"
}


[Environment]::Exit($result)