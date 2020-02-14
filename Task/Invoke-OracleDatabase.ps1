[CmdletBinding()]
param ()

$ScriptPath = Get-VstsInput -Name 'scriptPath' -Require
$ScriptOrderFile = Get-VstsInput -Name 'scriptOrder'
$ConnectionSet = Get-VstsInput -Name 'scriptMultiDBRun'
$User = Get-VstsInput -Name 'user'
$Password = Get-VstsInput -Name 'password' 
$DatabaseName = Get-VstsInput -Name 'databaseName'
$LogPath = Get-VstsInput -Name 'logPath'
$TopLine = Get-VstsInput -Name 'topLine'
$Define = Get-VstsInput -Name 'define'
$Echo = Get-VstsInput -Name 'echo'
$Timing = Get-VstsInput -Name 'timing'
$SqlError = Get-VstsInput -Name 'sqlError'
$OraError = Get-VstsInput -Name 'failOnOraError'
$NullFilesError = Get-VstsInput -Name 'failOnNullFiles'
$Copy = Get-VstsInput -Name 'copy' -Default true

. $PSScriptRoot\HelperFunctions.ps1

$ScriptOrderFile = Find-VstsFiles -LiteralDirectory $ScriptPath -LegacyPattern **.txt
$ConnectionSet = Find-VstsFiles -LiteralDirectory $ScriptPath -LegacyPattern **.json

if ($ScriptOrderFile) {
    $SqlPath = Get-Content -Path $ScriptOrderFile
}
else {
    $SqlPath = Find-VstsFiles -LiteralDirectory $ScriptPath -LegacyPattern **.sq?
}
## $SqlPath = Find-VstsFiles -LiteralDirectory $ScriptPath -LegacyPattern **.sq?
if ($SqlPath) {
    Try {
        New-Item -Path env:NLS_LANG -Value .AL32UTF8 -ErrorAction Stop
    }
    Catch {
        if ($_ -like '*access denied*') {
            throw $_
        }
        else {
            return 'NLS_LANG environment variable already set.'
        }
    }
    foreach ($SqlFile in $SqlPath) {	
        if ($SqlError) {
            Write-Output "whenever sqlerror exit sql.sqlcode rollback;" | Write-File -FilePath $SqlFile -Top
        }
        if ($Timing) {
            Write-Output "set timing on;" | Write-File -FilePath $SqlFile -Top
        }	
        if ($Echo) {
            Write-Output "set echo on;" | Write-File -FilePath $SqlFile -Top
        }
        if ($Define) {
            Write-Output "set define off;" | Write-File -FilePath $SqlFile -Top 
        }
        if ($TopLine) {
            Write-Output "-- top line" | Write-File -FilePath $SqlFile -Top
        }
        Write-Output "spool $($SqlFile).log" | Write-File -FilePath $SqlFile -Top
        Write-Output "spool off" | Write-File -FilePath $SqlFile
        Write-Output "exit" | Write-File -FilePath $SqlFile	
        IF ($ConnectionSet) {
            $connectionObjects = Get-Content -Path $ConnectionSet | ConvertFrom-Json
            foreach ($connectionObj in $connectionObjects.connections) {
                $connectionString = $connectionObj.connection | Where-Object { $connectionObj.environment -eq $env:COMPUTERNAME }
                if ($connectionString) {
                    sqlplus "$connectionString" "@$($SqlFile)"
                    if ($OraError -eq 'true') {
                        if ($LASTEXITCODE -ne 0) {
                            throw "An error has occured in $SqlFile. Please check the logs for error."
                        }
                    }
                    if ($LogPath) {
                        _Copy -Path "$($SqlFile).log" -Destination $LogPath
                        if ($Copy) {
                            _Copy -Path $SqlFile -Destination $LogPath
                        }
                    }
                    else {
                        Write-VstsTaskWarning -Message "No log path specified." 
                        Write-VstsTaskWarning -Message "Log files are located: $ScriptPath"
                    }
                }
            }
        }
        else {
            sqlplus "$User/$Password@$DatabaseName" "@$($SqlFile)"
        }
        if ($OraError -eq 'true') {
            if ($LASTEXITCODE -ne 0) {
                throw "An error has occured in $SqlFile. Please check the logs for error."
            }
        }
        if ($LogPath) {
            _Copy -Path "$($SqlFile).log" -Destination $LogPath
            if ($Copy) {
                _Copy -Path $SqlFile -Destination $LogPath
            }
        }
        else {
            Write-VstsTaskWarning -Message "No log path specified." 
            Write-VstsTaskWarning -Message "Log files are located: $ScriptPath"
        }
    }
}
else {
    if ($NullFilesError -eq 'true') {
        throw "No sql files exist at $ScriptPath"
    }
    else {
        return "No sql files exist at $ScriptPath"
    }
}