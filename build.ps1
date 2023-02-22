## Copyright (c) Microsoft Corporation.
## Licensed under the MIT License.
# default behavior is build only
[CmdletBinding(SupportsShouldProcess=$true)]
param (
    [Parameter()]
    [string]
    $Configuration = "Debug",

    [Parameter()]
    [switch]$Publish,

    [Parameter()]
    [switch]$Test,

    [Parameter()]
    [switch]$NoBuild,

    [Parameter()]
    [switch]$Clean
)

$moduleName = "Microsoft.PowerShell.TextUtility"
$projectRoot = $PSScriptRoot

$srcRoot = Join-Path $ProjectRoot src
$codeRoot = Join-Path $srcRoot code
$tstRoot = Join-Path $ProjectRoot test
$modManifest = Join-Path $srcRoot "${ModuleName}.psd1"


function AssertFile {
    param (
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    if (-not (Test-Path $Path)) {
        throw "File not found: $Path"
    }
}

function Assert {
    param ([Parameter(Mandatory=$true)][bool]$Condition, [Parameter(Mandatory=$true)][string]$Message)
    if (! $Condition) {
        throw $Message
    }
}

foreach ($path in $srcRoot, $codeRoot, $tstRoot, $modManifest) {
    AssertFile $path
}

$modInfo = Import-PowerShellDataFile $modManifest
$modVersion = $modInfo.ModuleVersion
Assert ($null -ne $modVersion) "ModuleVersion is null"
$pubRoot = "${PSScriptRoot}/out/${ModuleName}/${modVersion}"

function Build-Assembly {
    if (Test-ShouldBuild) {
        try {
            Push-Location $codeRoot
            if($PSCmdlet.ShouldProcess($Configuration)) {
                dotnet build --configuration $Configuration
            }
        }
        finally {
            Pop-Location
        }
    }
    else {
        Write-Verbose -Verbose "No changes to build"
    }
}

function Test-ShouldBuild {
    $latestSourceTime = Get-LatestSourceTime
    $latestBuildTime = Get-LatestBuildTime
    return ($latestBuildTime -lt $latestSourceTime)
}

function Get-LatestFile {
    param ([string[]]$Path)
    Get-ChildItem -ErrorAction Ignore -File -Path $Path | Sort-Object LastWriteTime | Select-Object -Last 1
}

function Get-LatestSourceTime {
    $latestFile = Get-LatestFile -path $codeRoot,"${srcRoot}/${moduleName}*"
    ($null -eq $latestFile) ? ([datetime]0) : $latestFile.LastWriteTime
}

function Get-LatestPublishTime {
    $latestFile = Get-LatestFile $pubRoot
    ($null -eq $latestFile) ? ([datetime]0) : $latestFile.LastWriteTime
}

function Get-TargetFramework {
    [xml]$x = Get-Content "${codeRoot}/${ModuleName}.csproj"
    $x.Project.PropertyGroup.TargetFramework
}

function Get-LatestBuildTime {
    $targetFramework = Get-TargetFramework
    $dllLocation = "${codeRoot}/bin/${Configuration}/${targetFramework}/${ModuleName}.dll"
    $latestFile = Get-LatestFile "${dllLocation}"
    ($null -eq $latestFile) ? ([datetime]0) : $latestFile.LastWriteTime
}

# determine if the sources are younger than the published
function Test-ShouldPublish {
    if (-not (Test-Path $pubRoot)) {
        return $true
    }
    $latestSourceTime = Get-LatestSourceTime
    $latestPublishTime = Get-LatestPublishTime
    return ($latestPublishTime -lt $latestSourceTime)
}

function Test-Module {
    if (Test-ShouldPublish) {
       Publish-Assembly
    }
    else {
        Write-Verbose -Verbose "No changes to publish"
    }
    try {
        $PSVersionTable | Out-String -Stream | Write-Verbose -Verbose
        $pesterInstallations = Get-Module -ListAvailable -Name Pester
        if ($pesterInstallations.Version -notcontains "4.10.1") {
            Install-Module -Name Pester -RequiredVersion 4.10.1 -Force -Scope CurrentUser
        }
        $command = "Import-Module ${PSScriptRoot}/out/${ModuleName}; Import-Module Pester -Max 4.10.1; Invoke-Pester -OutputFormat NUnitXml -EnableExit -OutputFile ../Microsoft.PowerShell.TextUtility.xml"
        Push-Location $tstRoot
        pwsh -noprofile -command $command
    }
    finally {
        Pop-Location
    }
}

function Publish-Assembly {
    Build-Assembly # check again - the user may have used -noBuild
    if (Test-ShouldPublish) {
        if (-not (test-path $pubRoot)) {
            $null = New-Item -ItemType Directory -Force -Path $pubRoot
        }
        $targetFramework = Get-TargetFramework

        # this needs to be the list of assemblies
        Copy-Item "${codeRoot}/bin/${Configuration}/${targetFramework}/${ModuleName}.dll" $pubRoot -Force
        # module manifest and formatting
        Copy-Item "${SrcRoot}/dictionary.txt" $pubRoot -Force
        Copy-Item "${SrcRoot}/${ModuleName}.psd1" $pubRoot -Force
        Copy-Item "${SrcRoot}/${ModuleName}.*.ps1xml" $pubRoot -Force
        Write-Verbose -Verbose "Module published to $pubRoot"
    }
    else {
        Write-Verbose -Verbose "No changes to publish"
    }
}

if ( $Clean ) {
    $dirsToRemove = "${PSScriptRoot}/out",
        "${codeRoot}/bin",
        "${codeRoot}/obj"

    foreach ( $dir in $dirsToRemove ) {
        if ( Test-Path $dir ) {
            Remove-Item -Force -Recurse $dir
        }
    }
}

if (-not $NoBuild ) {
    Build-Assembly
}

if ( $Publish ) {
    Publish-Assembly
}

if ( $Test ) {
    Test-Module
}

