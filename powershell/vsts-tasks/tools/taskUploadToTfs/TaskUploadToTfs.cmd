rem --------------------------------------------------------------------------------------------------------------------
rem <copyright file="TaskUploadToTfs.cmd">
rem   This material is the exclusive property of Oleksiy Antonov.
rem   Copyright (c) 2016
rem   Oleksiy Antonov. All Rights Reserved
rem </copyright>
rem <summary>
rem   Upload custom TFS vNext Build Task to server.
rem </summary>
rem --------------------------------------------------------------------------------------------------------------------

@SET ScriptFileName=TaskUploadToTfs
@SET LogDir=%CD%\Logs\
@SET PShellDir=%~dp0\
@SET hour=%time:~0,2%
@IF "%hour:~0,1%" == " " SET hour=0%hour:~1,1%
@SET LogFileName=%ScriptFileName%_%date:~7,2%-%date:~4,2%-%date:~10,4%-%hour%-%time:~3,2%.txt
@SET LogPath=%LogDir%%LogFileName%

@SET PS=powershell.exe

@SET TfsUrl=http://tfs:8080/tfs

@mkdir %LogDir%
@cls

@%PS% "& '%PShellDir%%ScriptFileName%.ps1' '%1' '%2' '%TfsUrl%' -Overwrite >> %LogPath%
