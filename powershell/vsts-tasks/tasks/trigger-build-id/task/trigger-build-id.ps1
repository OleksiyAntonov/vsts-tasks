# --------------------------------------------------------------------------------------------------------------------
# <copyright file="trigger-build-id.ps1"
#   Copyright (c) 2006 - 2016
#   Oleksiy Antonov
# </copyright>
# <summary>
#   PowerShell: TFS vNext Build Task: Run build in parallel
# </summary>
# --------------------------------------------------------------------------------------------------------------------

[cmdletbinding()]
param
(
    [Parameter(Mandatory=$true)][string] $pollingIntervalParam,
    [Parameter(Mandatory=$true)][string] $enableParallelBuildParam,
    [Parameter(Mandatory=$true)][string] $useSameAgentParam,
    [Parameter(Mandatory=$true)][string] $buildDefinitionIdParam,
    [Parameter(Mandatory=$true)][string] $useCurrentTeamProjectParam,
    [Parameter(Mandatory=$true)][string] $teamProjectNameParam,
    [Parameter(Mandatory=$true)][string] $behaviorFailedBuildParam,
    [Parameter(Mandatory=$true)][string] $behaviorPartiallySucceededBuildParam
)

# Constants declarations
[int] $DefautPollingIntervalValue = 15
[int] $DefaultTfsIdUndefined = -1
[string] $BuildStateSucceeded = "succeeded"
[string] $isAnotherProject = "anotherProject"

# TFS REST API Uris
[string] $UriPartGetBuildDefinitionsList = "/_apis/build/definitions?api-version=2.0"
[string] $UriPartGetBuildDefinitionRequest = "/_apis/build/builds?api-version=2.0"
[string] $UriPartGetBuildDefinitionStatus = "/_apis/build/builds/{0}?api-version=2.0"

# System variables
[string] $Local_SYSTEM_TEAMFOUNDATIONCOLLECTIONURI = $Env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI
[string] $Local_SYSTEM_TEAMPROJECT = $Env:SYSTEM_TEAMPROJECT

# Stubs for debugging purposes
#[string] $pollingIntervalParam = 5
#[string] $enableParallelBuildParam = "false"

#[string] $enableBuildDefinitionsIdsParameter = "false"
#[string] $enableBuildDefinitionsNamesParameter = "true"

#[string] $Local_SYSTEM_TEAMFOUNDATIONCOLLECTIONURI = "http://tfs:8080/tfs/Collection/"
#[string] $Local_SYSTEM_TEAMPROJECT = "TeamProject"

#[string] $teamProjectUri = $Local_SYSTEM_TEAMFOUNDATIONCOLLECTIONURI + $Local_SYSTEM_TEAMPROJECT

[string] $totalState = $BuildStateSucceeded
[string] $failedBuilds = "Builds was failed: "

# Debugging substitutions
[string] $global:enableParallelBuildParam = $enableParallelBuildParam
[string] $global:enableBuildDefinitionsIdsParameter = $enableBuildDefinitionsIdsParameter
[string] $global:enableBuildDefinitionsNamesParameter = $enableBuildDefinitionsNamesParameter

# Class Declarations
Add-Type -TypeDefinition @"
public class BuildDefinitionEntry
{
    public string Name;
    public bool Finished;
    public int TfsId;
    public int Id;
    public string Number;
    public string Status;
    public string TeamProjectUri;

    public BuildDefinitionEntry(string name)
    {
        Name = name;
        Finished = false;
        TfsId = $DefaultTfsIdUndefined;
        Id = $DefaultTfsIdUndefined;
        Number = string.Empty;
        Status = string.Empty;
        TeamProjectUri = "$teamProjectUri";
    }
}
"@

# Processing Parameters
function ProcessingParameters
{
    Write-Host "Processing parameters..."

    [bool] $global:enableParallelBuild = [bool]::Parse($global:enableParallelBuildParam)

    # These variables are provided by TFS
    $buildAgentHomeDirectory = $env:AGENT_HOMEDIRECTORY
    $buildSourcesDirectory = $Env:BUILD_SOURCESDIRECTORY
    $buildStagingDirectory = $Env:BUILD_STAGINGDIRECTORY
    $buildPlatform = $Env:BUILDPLATFORM
    $buildConfiguration = $Env:BUILDCONFIGURATION
    $packagesOutputDirectory = $buildStagingDirectory

    # Data preparation
    $pollingValue = $pollingIntervalParam -as [int]
    if ($pollingValue -ne $null)
    {
        if (($pollingValue -lt 5) -or ($pollingValue -gt 300))
        {
            Write-Output "Polling interval must be integer and in range 5-600 s"
            $pollingValue = $DefautPollingIntervalValue
        }
    }
}

# Prepare of build definition parameters
function PrepareBuildDefinition
{
  $global:buildDefinitionEntry = New-Object BuildDefinitionEntry($buildDefinitionIdParam)
  $global:buildDefinitionEntry.TfsId = $buildDefinitionEntry.Name

  if (![string]::Compare($useCurrentTeamProjectParam, $isAnotherProject))
  {
    $buildDefinitionEntry.TeamProjectUri = $Local_SYSTEM_TEAMFOUNDATIONCOLLECTIONURI + $teamProjectNameParam
  }
}

# Wait for one build completion
# function return $true if should remove item from list otherwise #false
function WaitBuildForCompletion([BuildDefinitionEntry] $buildDefinitionEntryParameter)
{
    if ($buildDefinitionEntryParameter.Id -ne $DefaultTfsIdUndefined)
    {
        [string] $uriRequestState = $buildDefinitionEntryParameter.TeamProjectUri + [string]::Format($UriPartGetBuildDefinitionStatus, $buildDefinitionEntryParameter.Id)

        Write-Output $uriRequestState

        $buildState = Invoke-RestMethod -Method Get -Uri $uriRequestState -UseDefaultCredentials -ContentType 'application/json'

        Write-Output $buildState.status

        if ($buildState.status -eq "completed")
        {
            if ($buildState.result -eq $BuildStateSucceeded)
            {

            }
            else
#                    if ($buildState.result -eq "failed")
            {
                $totalState = "failed"
                $failedBuilds = $failedBuilds + $buildDefinitionEntryParameter.Name + "/" + $buildDefinitionEntryParameter.Number + " "
            }
        }

        $buildDefinitionEntryParameter.Finished = $buildState.status -eq "completed"
        if ($buildDefinitionEntryParameter.Finished -eq $true)
        {
            return $true
        }
        else
        {
            Start-Sleep -s $pollingValue
            return $false
        }
    }
    else
    {
        return $true
    }
}

function TriggerOneBuild ([object] $buildDefinitionEntryParameter)
{
    if ($buildDefinitionEntryParameter.TfsId -ne $DefaultTfsIdUndefined)
    {
        $body = '{ "definition": { "id": '+ $buildDefinitionEntryParameter.TfsId + '}, reason: "Manual", priority: "Normal"}'
        $buildReqBodyJson =  $body | ConvertTo-Json

        $buildMessage = "Starting build: " + $buildDefinitionEntryParameter.Name
        Write-Host $buildMessage

        $buildRequest =
            Invoke-RestMethod -Method Post -Uri ($buildDefinitionEntryParameter.TeamProjectUri + $UriPartGetBuildDefinitionRequest) -UseDefaultCredentials -ContentType 'application/json' -Body $body | select id, buildNumber, status

        # Get Build Id
        $buildDefinitionEntryParameter.Id = $buildRequest.id
        $buildDefinitionEntryParameter.Status = $buildRequest.status
        $buildDefinitionEntryParameter.Number = $buildRequest.buildNumber

        $buildMessage = "Build started: " + $buildDefinitionEntryParameter.Name + "/" +$buildDefinitionEntryParameter.Number
        Write-Host $buildMessage

        if (!($enableParallelBuild))
        {
            Write-Host "Waiting build for completion..."
            WaitBuildForCompletion $buildDefinitionEntryParameter
        }
    }
}

# Script Body
ProcessingParameters
PrepareBuildDefinition

TriggerOneBuild $global:buildDefinitionEntry

if ($totalState -eq $BuildStateSucceeded)
{
    Write-Host ("Success")
}
else
{
    Throw [System.InvalidOperationException] $failedBuilds
}
