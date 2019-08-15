# MySQL Backup & Restore  - Powershell script

This script handles backup and restore **MySQL Enterprise** DB on Windows,
using *mysqlbackup.exe* which included with the enterprise package.

## Preriquestis

Create backup and restore parameters file using MySQL Workbench:

1. Open MySQL Workbench.
2. Click on Online Backup.
3. (First Time) Click on *Settings...* on the top-right corner of the screen.
   1. Set the path of mysqlbackup.exe
   2. Set the backup path
   3. Create a backup user & password.
4. Create new full backup job - this will create a configuration file like
   ```
   <BackupDir>\<JobName>.cnf
   ```

## Backup

### Full Backup

```
MySQLBackupRestore.ps1 -DefaultsFile <BackupDir>\<JobName>.cnf -MEBPath <MySQL>\bin\mysqlbackup.exe -Backup -BackupType full -BackupPath <BackupDir>\Instance -DeleteBackupsOlderThanDays <N>
```

### Incremenal Backup

```
MySQLBackupRestore.ps1 -DefaultsFile <BackupDir>\<JobName>.cnf -MEBPath <MySQL>\bin\mysqlbackup.exe -Backup -BackupType inc -BackupPath "<BackupDir>\Instance" -DeleteBackupsOlderThanDays <N>
```

## Restore

```
.\MySQLBackupRestore.ps1 -Restore -RestoreTempPath <TempDir> -BackupPath <BackupDir>\Instance -DefaultsFile <BackupDir>\<JobName>.cnf -MEBPath <MySQL>\bin\mysqlbackup.exe
```

*Example of the output:*
```
Restore DB
===========================

Row Date                Type Size
--- ----                ---- ----
  1 14/08/2019 19:00:40 Inc  500 MB
  2 14/08/2019 17:00:30 Inc  500 MB
  3 14/08/2019 15:02:47 Full 2,021.42 MB
  4 13/08/2019 15:01:32 Full 2,021.10 MB


Select backup to restore (1-4):
```

- In case of *Incremental* restore, the script will restore the **LAST** full backup and all the incremental backups till the selected option.
  In the example above, restore of row 1 will restore the backups in the following order: 3 (full), 2 (inc), 1 (inc)

# **- Please test this script before using it.**

Enjoy :smiley:
