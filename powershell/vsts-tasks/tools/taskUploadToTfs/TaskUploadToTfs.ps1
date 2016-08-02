# --------------------------------------------------------------------------------------------------------------------
# <copyright file="TaskUploadToTfs.ps1">
#   Copyright (c) 2016
#   Oleksiy Antonov. All Rights Reserved
# </copyright>
# <summary>
#   PowerShell: Upload custom TFS vNext Build Task to server
# </summary>
# --------------------------------------------------------------------------------------------------------------------

param(
   [Parameter(Mandatory=$true)][string]$TaskPath,
   [Parameter(Mandatory=$true)][string]$TaskName,
   [Parameter(Mandatory=$true)][string]$TfsUrl,
   [Parameter(Mandatory=$true)][switch]$Overwrite = $false
)

# Load task definition from the JSON file
$taskDefinition = (Get-Content $TaskName) -join "`n" | ConvertFrom-Json
$taskFolder = $TaskPath

# TODO:Obsolete Create temp folder
# TODO:Obsolete $pathToTempTaskFolder = $taskFolder+"\"+$taskDefinition.id
# TODO:Obsolete New-Item $pathToTempTaskFolder -type directory
# TODO:Obsolete Copy-Item $TaskName $pathToTempTaskFolder\task.json -Force

$pathToTempTaskFolder = $taskFolder+"\Task"

# Zip the task content
Write-Output "Zipping task content"
# TODO:Obsolete $taskZip = ("{0}\..\{1}.zip" -f $pathToTempTaskFolder, $taskDefinition.id)

$taskZip = ("{0}\..\{1}.zip" -f $pathToTempTaskFolder, $taskDefinition.id)
if (Test-Path $taskZip)
{
	Remove-Item $taskZip
}

Add-Type -AssemblyName "System.IO.Compression.FileSystem"
[IO.Compression.ZipFile]::CreateFromDirectory($pathToTempTaskFolder, $taskZip)

# Prepare to upload the task
Write-Output "Uploading task content"
$headers = @{ "Accept" = "application/json; api-version=2.0"; "X-TFS-FedAuthRedirect" = "Suppress" }
$taskZipItem = Get-Item $taskZip
$headers.Add("Content-Range", "bytes 0-$($taskZipItem.Length - 1)/$($taskZipItem.Length)")
$url = ("{0}/_apis/distributedtask/tasks/{1}" -f $TfsUrl, $taskDefinition.id)
if ($Overwrite)
{
	$url += "?overwrite=true"
}

# Actually upload it
Invoke-RestMethod -Uri $url -UseDefaultCredentials -Headers $headers -ContentType application/octet-stream -Method Put -InFile $taskZipItem

# Clean Up
Remove-Item $taskZip -Recurse