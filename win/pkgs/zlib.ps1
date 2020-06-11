#Requires -RunAsAdministrator

Get-Content "$PSScriptRoot/utils/re-entry.ps1" -Raw | Invoke-Expression
$ErrorActionPreference="Stop"

. "$PSScriptRoot/env/mirror.ps1"
. "$PSScriptRoot/env/toolchain.ps1"

pushd ${Env:SCRATCH}
$repo="${Env:GIT_MIRROR}/madler/zlib.git"
$proj="$($repo -replace '.*/','' -replace '.git$','')"
$root="${Env:SCRATCH}/$proj"

rm -Force -Recurse -ErrorAction SilentlyContinue -WarningAction SilentlyContinue "$root"
if (Test-Path "$root")
{
    echo "Failed to remove `"$root`""
    Exit 1
}

$latest_ver='v' + $($(git ls-remote --tags "$repo") -match '.*refs/tags/v[0-9\.]*$' -replace '.*refs/tags/v','' | sort {[Version]$_})[-1]
git clone --depth 1 --recursive --single-branch -b "$latest_ver" -j8 "$repo"
pushd "$root"

mkdir build
pushd build

# Currently (v1.2.11) there's a bug related to AMD64 flag.
cmake                                                                           `
    -DAMD64=OFF                                                                 `
    -DCMAKE_BUILD_TYPE=Release                                                  `
    -DCMAKE_C_FLAGS="/GL /MP /Zi /guard:cf"                                     `
    -DCMAKE_EXE_LINKER_FLAGS="/DEBUG:FASTLINK /LTCG:incremental /guard:cf"      `
    -DCMAKE_INSTALL_PREFIX="${Env:ProgramFiles}/zlib"                           `
    -DCMAKE_PDB_OUTPUT_DIRECTORY="${PWD}/pdb"                                   `
    -DCMAKE_SHARED_LINKER_FLAGS="/DEBUG:FASTLINK /LTCG:incremental /guard:cf"   `
    -DCMAKE_STATIC_LINKER_FLAGS="/LTCG:incremental"                             `
    -G"Ninja"                                                                   `
    ..

cmake --build .
if (-Not $?)
{
    echo "Failed to build."
    echo "Retry with best-effort for logging."
    echo "You may Ctrl-C this if you don't need the log file."
    cmake --build . -- -k0
    cmake --build . 2>&1 | tee ${Env:SCRATCH}/${proj}.log
    exit 1
}

$ErrorActionPreference="SilentlyContinue"
cmake --build . --target test
if (-Not $?)
{
    echo "Oops! Expect to pass all tests."
    exit 1
}
$ErrorActionPreference="Stop"

rm -Force -Recurse -ErrorAction SilentlyContinue -WarningAction SilentlyContinue "${Env:ProgramFiles}/zlib"
cmake --build . --target install
cmd /c xcopy /i /f /y "pdb\*.pdb" "${Env:ProgramFiles}\zlib\bin"
Get-ChildItem "${Env:ProgramFiles}/zlib" -Filter *.dll -Recurse | Foreach-Object { New-Item -Force -ItemType SymbolicLink -Path "${Env:SystemRoot}\System32\$_" -Value $_.FullName }

popd
popd
rm -Force -Recurse "$root"
popd
