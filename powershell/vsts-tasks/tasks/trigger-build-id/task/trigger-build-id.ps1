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
    [Parameter(Mandatory=$true)][string] $behaviorFailedBuildParam,
    [Parameter(Mandatory=$true)][string] $behaviorPartiallySucceededBuildParam
)

# Constants declarations
[int] $DefautPollingIntervalValue = 15
[int] $DefaultTfsIdUndefined = -1
[string] $BuildStateSucceeded = "succeeded"

# TFS REST API Uris
[string] $UriPartGetBuildDefinitionsList = "/_apis/build/definitions?api-version=2.0"
[string] $UriPartGetBuildDefinitionRequest = "/_apis/build/builds?api-version=2.0"
[string] $UriPartGetBuildDefinitionStatus = "/_apis/build/builds/{0}?api-version=2.0"

# System variables
[string] $Local_SYSTEM_TEAMFOUNDATIONCOLLECTIONURI = $Env:SYSTEM_TEAMFOUNDATIONCOLLECTIONURI
[string] $Local_SYSTEM_TEAMPROJECT = $Env:SYSTEM_TEAMPROJECT

# Stubs for debugging purposes
[string] $pollingIntervalParam = 5
[string] $enableParallelBuildParam = "false"
[string] $locateByTypeParam = "false"

[string] $enableBuildDefinitionsIdsParameter = "false"
[string] $enableBuildDefinitionsNamesParameter = "true"

[string] $Local_SYSTEM_TEAMFOUNDATIONCOLLECTIONURI = "http://tfs:8080/tfs/Collection/"
[string] $Local_SYSTEM_TEAMPROJECT = "TeamProject"

[string] $teamProjectUri = $Local_SYSTEM_TEAMFOUNDATIONCOLLECTIONURI + $Local_SYSTEM_TEAMPROJECT

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

    [bool] $global:enableBuildDefinitionsIds = [bool]::Parse($global:enableBuildDefinitionsIdsParameter)
    [bool] $global:enableBuildDefinitionsNames = [bool]::Parse($global:enableBuildDefinitionsNamesParameter)
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

    [bool] $res = ($global:enableBuildDefinitionsIds -and $global:enableBuildDefinitionsNames)

    if ($global:enableBuildDefinitionsIds -and $global:enableBuildDefinitionsNames)
    {
        Write-Host "Unsupported configuration. Both of list is enabled."
        Throw [System.InvalidOperationException] $failedBuilds
    }
    else
    {
        if (!($global:enableBuildDefinitionsIds -or $global:enableBuildDefinitionsNames))
        {
            Write-Host "Unsupported configuration. At least one of list should be enabled"
            Throw [System.InvalidOperationException] $failedBuilds
        }
    }
}

# Convert input list of build definitions into array to check success builds
function ConvertBuildDefinitionsList
{
    $global:buildDefinitionsHash = @{}
    $global:buildDefinitionsObjects = @()

    if ($global:enableBuildDefinitionsIds)
    {
        $listOfBuildDefinitions = $global:listOfBuildDefinitionsIdsParameter
    }
    else
    {
        if ($global:enableBuildDefinitionsNames)
        {
            $listOfBuildDefinitions = $global:listOfBuildDefinitionsNamesParameter
        }
    }

    [string] $teamProjectUriLocal
    [string] $nameLocal

    $listOfBuildDefinitions.Split(";") | ForEach {
        $teamProjectUriLocal = [string]::Empty
        if ($_.Contains("@"))
        {
            $parts = $_.Split("@")
            $teamProjectUriLocal = $parts[0]
            $nameLocal = $parts[1]
        }
        else
        {
            $nameLocal = $_
        }

        $buildDefinitionEntry = New-Object BuildDefinitionEntry($nameLocal)

        if ($global:enableBuildDefinitionsIds)
        {
            $buildDefinitionEntry.TfsId = $buildDefinitionEntry.Name
        }

        if (![string]::IsNullOrEmpty($teamProjectUriLocal))
        {
            $buildDefinitionEntry.TeamProjectUri = $Local_SYSTEM_TEAMFOUNDATIONCOLLECTIONURI + $teamProjectUriLocal
        }

        $global:buildDefinitionsHash.Add($buildDefinitionEntry.Name, $global:buildDefinitionsObjects.Count)
        $global:buildDefinitionsObjects += $buildDefinitionEntry
    }

    # Processing named server list of build definitions
    # Works now incorrect !!! teamProjectUri
    if ($global:enableBuildDefinitionsNames)
    {
        Write-Host "Processing named server list of build definitions..."

        # Create hashtable with all build definitions
        $allbuildDefs = @{}

        $allBuildDefsQuery = (Invoke-RestMethod -Uri ($teamProjectUri + $UriPartGetBuildDefinitionsList) -Method GET -UseDefaultCredentials).value | select name, id

        $allBuildDefsQuery.ForEach(
        {
            $allBuildDefs.Add($_.name, $_.id)
        })

        # Filtering list to leave only required build definitions
        $allBuildDefs.Keys.ForEach(
        {
            if ($global:buildDefinitionsHash.ContainsKey($_))
            {
                $global:buildDefinitionsObjects[$global:buildDefinitionsHash[$_]].TfsId = $allBuildDefs[$_]
            }
        })
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

# $buildState = Invoke-RestMethod -Method Get -Uri $uriRequestState -UseDefaultCredentials -ContentType 'application/json'

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
            WaitBuildForCompletion $buildDefinitionEntryParameter
        }
    }
}

# Trigger builds
function TriggerBuilds
{
    Write-Host "Trigger builds..."

    $global:buildDefinitionsObjects.ForEach(
    {
       TriggerOneBuild $_
    })
}

# Waiting builds for completion
function WaitingBuildsForCompletion
{
    Write-Host "Waiting builds for completion..."

    while ($global:buildDefinitionsList.Count -ne 0)
    {
        $global:buildDefinitionsList.Keys.ForEach(
        {
            if (WaitBuildForCompletion $global:buildDefinitionsList[$_])
            {
                $global:buildDefinitionsList.Remove($_)
            }
        })
    }
}

# Script Body
ProcessingParameters
ConvertBuildDefinitionsList
TriggerBuilds

if ($totalState -eq $BuildStateSucceeded)
{
    Write-Host ("Success")
}
else
{
    Throw [System.InvalidOperationException] $failedBuilds
}
