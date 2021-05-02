Set-StrictMode -Off;

function Write-Done {
    Write-Host 'DONE' -ForegroundColor Green
    Write-Host ''
}

function Write-Error {
    Write-Host 'Fatal error:' -ForegroundColor Red
    Write-Host $_
    exit 1
}

function Add-Target {

    param(
        [Parameter()]
        [string]$targetName,

        [Parameter()]
        [string]$sdkVersion
    )

    try {
        $file = ''
        if (Test-Path './.cargo/config') {
            $file = './.cargo/config'
        } elseif (Test-Path './.cargo/config.toml') {
            $file = './.cargo/config.toml'
        }

        Add-Content $file "[target.$targetName]"
        $ar_location = "$env:ANDROID_NDK_HOME\toolchains\llvm\prebuilt\windows-x86_64\$targetName\bin\ar.exe".Replace('\', '\\')
        $ar_field = 'ar = "' + $ar_location + '"'
        Add-Content $file $ar_field
        $linker_location = "$env:ANDROID_NDK_HOME\toolchains\llvm\prebuilt\windows-x86_64\bin\$targetName$sdkVersion-clang.cmd".Replace('\', '\\')
        if ($targetName -eq 'armv7-linux-androideabi') {
            $linker_location = "$env:ANDROID_NDK_HOME\toolchains\llvm\prebuilt\windows-x86_64\bin\armv7a-linux-androideabi$sdkVersion-clang.cmd".Replace('\', '\\')
        }
        $linker_field = 'linker = "' + $linker_location + '"'
        Add-Content $file $linker_field
        if ($targetName -ne 'x86_64-linux-android') {
            Add-Content $file ""
        }
    }
    catch {
        Write-Error
    }
}

function Build {

    param(
        [Parameter()]
        [string]$targetName,

        [Parameter()]
        [string]$folderName
    )

    try {
        Write-Host "Building";
        Write-Host "    $targetName" -ForegroundColor Yellow
        cargo build --target $targetName --release
        $libPath = Get-ChildItem -Path "./target/$targetName/release" lib*.so | Sort-Object LastWriteTime | Select-Object -First 1
        $libName = Split-Path $libPath -leaf
        $releaseFolder = "$jinLibs/$folderName"
        if (-NOT (Test-Path -Path $releaseFolder)) {
            New-Item -Path $jinLibs -Name $folderName -ItemType "directory"
        }
        Copy-Item "./target/$targetName/release/$libName" -Destination $releaseFolder -Force
        Write-Done
    }
    catch {
        Write-Error
    }
}

if (-NOT (Test-Path $env:ANDROID_NDK_HOME)) {
    Write-Host 'Error: Please, set the ANDROID_NDK_HOME env variable to point to your NDK folder'
    exit 1
} else {
    Write-Host "Found ANDROID_NDK_HOME=$env:ANDROID_NDK_HOME"
}

$jinLibs = "../android/app/src/main/jniLibs"

if (-NOT (Test-Path -Path $jinLibs)) {
    New-Item -Path "../android/app/src/main" -Name "jniLibs" -ItemType "directory"
}

$targets = @(
    'aarch64-linux-android',
    'armv7-linux-androideabi',
    'i686-linux-android',
    'x86_64-linux-android'
)

if (-NOT (Test-Path './.cargo')) {
    New-Item -Path . -Name '.cargo' -ItemType "directory"
    New-Item -Path ./.cargo -Name 'config.toml' -ItemType "file"
    foreach ($t in $targets) { Add-Target -targetName $t -sdkVersion '29' }
} elseif (-NOT ($(Test-Path './.cargo/config.toml') -OR $(Test-Path './.cargo/config'))) {
    New-Item -Path ./.cargo -Name 'config.toml' -ItemType "file"
    foreach ($t in $targets) { Add-Target -targetName $t -sdkVersion '29' }
}

Write-Host 'Making bindings:'
Write-Host '    rust/target/bindings.h' -ForegroundColor Yellow
try {
    cbindgen ./src/lib.rs --output target/bindings.h --lang c
}
catch {
    Write-Error
}
Write-Done

$info = @(
    [System.Tuple]::Create('aarch64-linux-android', 'arm64-v8a'),
    [System.Tuple]::Create('armv7-linux-androideabi', 'armeabi-v7a'),
    [System.Tuple]::Create('i686-linux-android', 'x86'),
    [System.Tuple]::Create('x86_64-linux-android', 'x86_x64')
)

foreach ($i in $info) {
    Build -targetName $i.Item1 -folderName $i.Item2
}

Write-Host 'Generating Bindings for Dart'
try {
    flutter pub run ffigen
}
catch {
    Write-Error
}
Write-Done
