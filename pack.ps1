Get-Content "$PSScriptRoot/pkgs/utils/re-entry.ps1" -Raw | Invoke-Expression
$ErrorActionPreference="Stop"

pushd $PSScriptRoot

$versionPrefix = 'v'

$rawVersion = git describe --long --match ($versionPrefix+'*')
Write-Host 'git version string:' $rawVersion

$time    = (Get-Date).ToUniversalTime().ToString("yyyyMMddHHmmssfffffff")
$iter    = $rawVersion.split('-')[-2]
$hash    = $rawVersion.split('-')[-1]
$tag     = $rawVersion.split('-')[0].split('/')[-1]

# NuGet drops some trailing zero.
$nullable_iter = '.' + $iter
if ($iter -eq '0')
{
    $nullable_iter = ''
}

$version = $tag.TrimStart($versionPrefix) + $nullable_iter + '-T' + $time + $hash

Write-Host 'tag'     $tag
Write-Host 'iter'    $iter
Write-Host 'hash'    $hash
Write-Host 'version' $version

if (Test-Path build)
{
    cmd /c rmdir /Q /S build
}
mkdir build
pushd build

Write-Host "Create NuGet Packages"

${Env:NUGET_HOME} = "$(Get-Command -Name nuget -ErrorAction SilentlyContinue | select -ExpandProperty Source | Split-Path -Parent)"

if (${Env:NUGET_HOME} -eq $null -or -not $(Test-Path ${Env:NUGET_HOME}/nuget.exe -ErrorAction SilentlyContinue))
{
    ${Env:NUGET_HOME} = $pwd.Path
}

# Download CredentialProviderBundle of Nuget.
if (${Env:NUGET_HOME} -eq $null -or -not $(Test-Path ${Env:NUGET_HOME}/nuget.exe -ErrorAction SilentlyContinue))
{
    & "${Env:ProgramFiles}/CURL/bin/curl.exe" -fkSL "https://msazure.pkgs.visualstudio.com/_apis/public/nuget/client/CredentialProviderBundle.zip" -o "CredentialProviderBundle.zip"
    if (Get-Command -Name unzip -ErrorAction SilentlyContinue)
    {
        unzip -ou "CredentialProviderBundle.zip" -d "CredentialProviderBundle"
    }
    else
    {
        Expand-Archive "CredentialProviderBundle.zip" "CredentialProviderBundle"
    }
    ${Env:NUGET_HOME} = "CredentialProviderBundle"
}

Test-Path ${Env:NUGET_HOME}/nuget.exe | Out-Null

$ErrorActionPreference="SilentlyContinue"
& ${Env:NUGET_HOME}/nuget.exe sources Add -Name "OneOCR" -Source "https://pkgs.dev.azure.com/msresearch/_packaging/OneOCR/nuget/v3/index.json"
& ${Env:NUGET_HOME}/nuget.exe sources Add -Name "API-OCR" -Source "https://msazure.pkgs.visualstudio.com/_packaging/API-OCR/nuget/v3/index.json"
$ErrorActionPreference="Stop"
& ${Env:NUGET_HOME}/nuget.exe sources Update -Name "OneOCR" -Source "https://pkgs.dev.azure.com/msresearch/_packaging/OneOCR/nuget/v3/index.json"
& ${Env:NUGET_HOME}/nuget.exe sources Update -Name "API-OCR" -Source "https://msazure.pkgs.visualstudio.com/_packaging/API-OCR/nuget/v3/index.json"
& ${Env:NUGET_HOME}/nuget.exe sources

Write-Host "--------------------------------------------------------------------------------"

Get-Job | Stop-Job
Get-Job | Wait-Job
Remove-Job *

Get-ChildItem ../nuget | Foreach-Object {
    $pkg = $_.Name
    if ($pkg -eq "eigen")
    {
        $prefix = "${Env:ProgramFiles}/Eigen3"
    }
    elseif ($pkg -eq "mkldnn")
    {
        $prefix = "${Env:ProgramFiles}/Intel(R) MKL-DNN"
    }
    elseif ($pkg -eq "ort")
    {
        $prefix = "${Env:ProgramFiles}/onnxruntime"
    }
    elseif ($pkg -eq "daal" -or $pkg -eq "iomp" -or $pkg -eq "ipp" -or $pkg -eq "mkl" -or $pkg -eq "mpi" -or $pkg -eq "tbb")
    {
        $prefix = "${Env:ProgramFiles(x86)}/IntelSWTools"
    }
    else
    {
        $prefix = "${Env:ProgramFiles}/$pkg"
    }
    if (Test-Path $prefix)
    {
        Start-Job {
            param(${pkg}, ${prefix}, ${version})

            Set-Location $using:PWD

            Write-Host "Packaging ${pkg}..."

            if (Test-Path "..\nuget\${pkg}\${pkg}")
            {
                cmd /c rmdir /Q "..\nuget\${pkg}\${pkg}"
            }
            cmd /c mklink /D "..\nuget\${pkg}\${pkg}" ${prefix}
            & ${Env:NUGET_HOME}/nuget.exe pack -version ${version} "../nuget/${pkg}/Roaster.${pkg}.v141.dyn.x64.nuspec"
            cmd /c rmdir /Q "..\nuget\${pkg}\${pkg}"

            ForEach (${feed} in @("OneOCR", "API-OCR"))
            {
                Start-Job {
                    param(${nupkg}, ${feed})

                    Set-Location $using:PWD

                    # Set 10 min timeout as the default (5 min) is not enough for MSAzure recently (Jan 2019).
                    & ${Env:NUGET_HOME}/nuget.exe push -Source ${feed} -ApiKey AzureDevOps ${nupkg} -Timeout 600
                } -ArgumentList @("./Roaster.${pkg}.v141.dyn.x64.${version}.nupkg", ${feed})
            }

            Get-Job | Wait-Job
            Get-Job | Receive-Job

            Remove-Job *

            Write-Host "--------------------------------------------------------------------------------"
        } -ArgumentList @(${pkg}, ${prefix}, ${version})
    }
}

While (Get-Job -State "Running")
{
    Write-Host (Get-Job -State "Completed").count "/" (Get-Job).count
    Start-Sleep 3
}
Get-Job | Receive-Job
Remove-Job *

& ${Env:NUGET_HOME}/nuget.exe locals http-cache -clear

popd

Write-Host "Completed!"

Write-Host "If you see `"Suggestion [3,General]: The command nuget was not found`" message below, please ignore."

popd
