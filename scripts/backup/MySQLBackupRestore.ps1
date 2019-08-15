[CmdletBinding(DefaultParametersetName='None')] 
param(
[Parameter(Mandatory=$true)] [string]$DefaultsFile,
[Parameter(Mandatory=$true)] [string]$MEBPath,
[Parameter(ParameterSetName='Backup',Mandatory=$false, Position=1)] [switch]$Backup,
[Parameter(ParameterSetName='Backup',Mandatory=$true, Position=2)][ValidateSet('full','inc')] [string]$BackupType,
[Parameter(ParameterSetName='Backup',Mandatory=$true, Position=3)][int]$DeleteBackupsOlderThanDays = 3,  #Default 
[Parameter(ParameterSetName='Restore',Mandatory=$false, Position=1)][switch]$Restore,
[Parameter(ParameterSetName='Restore',Mandatory=$true, Position=2)][string]$RestoreTempPath,
[Parameter(ParameterSetName='Backup',Mandatory=$true, Position=3)] [Parameter(ParameterSetName='Restore',Mandatory=$true, Position=3)] [string]$BackupPath
)


Function Get-Backups() {

    #Get all backups
    $aBackupsDir = Get-ChildItem -Directory -Path $BackupPath -Exclude "inc"
    $aBackups = @()
    foreach ($item in $aBackupsDir) {
        $oBackupItem = @{Type = "Full";Date = [datetime]::parseexact($item.Name, 'yyyy-MM-dd_HH-mm-ss', $null); FullPath = $item.FullName; Size = "{0:N2} MB" -f ((Get-ChildItem $item.FullName -Recurse | Measure-Object -Property Length -Sum -ErrorAction Stop).Sum / 1MB) }
        $aBackups+= New-Object PsObject -Property $oBackupItem
    }

    $aBackupsDir = Get-ChildItem -Directory -Path "$BackupPath\inc"
    foreach ($item in $aBackupsDir) {
        $oBackupItem = @{Type = "Inc";Date = [datetime]::parseexact($item.Name, 'yyyy-MM-dd_HH-mm-ss', $null); FullPath = $item.FullName; Size = "{0:N2} MB" -f ((Get-ChildItem $item.FullName -Recurse | Measure-Object -Property Length -Sum -ErrorAction Stop).Sum / 1MB)}
        $aBackups+=New-Object PsObject -Property $oBackupItem
    }

    $aBackups = $aBackups | Sort-Object -Property Date -Descending

    return $aBackups
}


if (-not (Test-Path $DefaultsFile)) {
    Write-Host "Can't find defaults file: $DefaultsFile"
    exit 1
}

if (-not (Test-Path $MEBPath)) {
    Write-Host "Can't find MySQL Enterprise backup: $MEBPath"
    exit 1
}

#Backup
if ($Backup)
{
    Write-Host "Backup DB"

    if (-not (Test-Path $BackupPath)) {
        Write-Host "Can't find backup path: $BackupPath"
        exit 1
    }


   $BackupPathFull = "$BackupPath\"
    if ($BackupType -eq "inc") {
        $BackupPathFull += 'inc\'
        #Cehck if inc directory exsit
        if (-not (Test-Path $BackupPathFull)) {
            New-Item -ItemType directory -Path $BackupPathFull;
        }
    }
    
    $MEBCommand = @();
    $MEBCommand+= "--defaults-file=$DefaultsFile"
    if ($BackupType -eq "full") {
        $MEBCommand+="--backup-dir=$BackupPathFull"
    }
    if ($BackupType -eq "inc") {
        $MEBCommand+="--incremental"
        $MEBCommand+="--incremental-backup-dir=$BackupPathFull"
        $MEBCommand+="--incremental-base=history:last_backup"
    }
    $MEBCommand+="--with-timestamp"
    $MEBCommand+="--show-progress=stdout"
    if ($BackupType -eq "inc") {
        $MEBCommand+="backup"
    }
    else{
        $MEBCommand+="backup-and-apply-log"
    }


    & $MEBPath $MEBCommand
    if ($LASTEXITCODE -ne 0) {
        exit $LASTEXITCODE
    }
    
    #Delete old backups
    if ($DeleteBackupsOlderThanDays -gt 0) {
        $aBackups = Get-Backups
        $dCurrentDate = Get-Date
        foreach ($oBackup in $aBackups) {
            $oTs = New-TimeSpan -Start $oBackup.Date -End $dCurrentDate
            if ($oTs.Days -ge $DeleteBackupsOlderThanDays) {
                Write-Host "Delete old backup $($oBackup.FullPath)"
                Remove-Item -Recurse -Force $oBackup.FullPath
                Remove-Item -Recurse -Force "$($oBackup.FullPath).log" -ErrorAction SilentlyContinue
            }
        }
    }
}
#Restore
elseif($Restore){
    Write-Host "Restore DB"
    Write-Host "==========================="
    
    if (-not (Test-Path $RestoreTempPath)) {
        Write-Host "Can't find restore temp path: $RestoreTempPath"
        exit 1
    }
    
    $aBackups = Get-Backups


    $Global:sequence = 1;
    $aBackups | Select  @{label = “Row”; Expression = {$Global:sequence; $Global:sequence++;}} , Date, Type, Size | Format-Table  -Autosize
    $Global:sequence--
    $bOK = $false
    do{
        [int]$nSelectedBackup = Read-Host "Select backup to restore (1-$Global:sequence)"
        if (($nSelectedBackup -ge 1) -and ($nSelectedBackup -le $Global:sequence)) {
            $bOK = $true
        }
        else {
            Write-Host -ForegroundColor red "INVALID INPUT!  Please enter a numeric value between 1 to $Global:sequence."
        }
    }
    while (-not $bOK)

    #Find the last full backup
    $i =$nSelectedBackup-1
    $bOK = $false
    do{
        if ($i -ge $aBackups.length) {
            Write-Host -ForegroundColor Red "Couldn't find a full backup, can't restore incremental backups"
            exit 2
        }
        elseif ($aBackups[$i].Type -eq "Full") {
            $bOK = $true
        }
        else {
            $i++
        }
    }
    while (-not $bOK)

    Write-Host "The following backups will be restored:"
    Write-Host "========================================="
    for ($j = $i ; $j -ge $nSelectedBackup-1; $j--)
    {
        Write-Host ($($aBackups[$j]) | Select Type, Date, Size |  Format-List | Out-String )
    }

    do {
        try {
            [ValidateSet('yes','no')]$sAnswer = Read-Host "Are you sure to continue (yes/no)?"
        }
        catch {
            Write-Host  -ForegroundColor red "Type 'yes' or 'no'"
        }
    }
    while (-not $sAnswer)
     
    if ($sAnswer -eq "yes") {
        #Prepare restore  folder, Copy full backup and apply incremental backups

        Remove-Item "$RestoreTempPath\*" -Recurse -Force -Confirm -ErrorAction Stop
        for ($j = $i ; $j -ge $nSelectedBackup-1; $j--)
        {
            Write-Host "========================================================="
            Write-Host ($($aBackups[$j]) | Select Type, Date, Size |  Format-Table -AutoSize | Out-String )
            Write-Host "========================================================="

            if ($aBackups[$j].Type -eq "full") {
                Write-Host "Copy full backup to TEMP folder $RestoreTempPath :"
                try {
                    Copy-item -Force -Recurse -Verbose "$($aBackups[$j].FullPath)\*" -Destination $RestoreTempPath -ErrorAction Stop
                }
                catch {
                    Write-Host "Error coping files"
                    exit 1
                }
            }
            elseif ($aBackups[$j].Type -eq "inc") {
                $MEBCommand = @();
                $MEBCommand+="--incremental-backup-dir=$($aBackups[$j].FullPath)"
                $MEBCommand+="--backup-dir=$RestoreTempPath"
                $MEBCommand+="apply-incremental-backup"
                #}
        
                & $MEBPath $MEBCommand

                if ($LASTEXITCODE -ne 0) {
                    exit $LASTEXITCODE
                }
            }
        }

        #Restore prepered backup to original DB
        $MEBCommand = @();
        $MEBCommand+= "--defaults-file=$DefaultsFile"
        $MEBCommand+="--backup-dir=$RestoreTempPath"
        $MEBCommand+="copy-back"
        
        & $MEBPath $MEBCommand

        if ($LASTEXITCODE -ne 0) {
            exit $LASTEXITCODE
        }
    }

}
