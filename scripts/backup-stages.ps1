Param(
    [string]$ps_user,
    [string]$ps_pass,
    [string]$pathBackup,
    [string]$configPath
)

Import-Module Microsoft.PowerShell.Utility
Import-Module Microsoft.PowerShell.Archive
Import-Module Microsoft.PowerShell.Management
Import-Module WebAdministration
Import-Module IISAdministration

$date=$($(Get-Date -Format yyyyMMdd_HHmm))
$daysCount=[int](New-TimeSpan -Start $(Get-Date -Month 09 -Day 1 -Year 2022) -End $(Get-Date)).TotalDays
# Number day in week
$numDayWeek = (Get-Date).DayOfWeek.value__
# Number week on month
$numWeekMonth = (Get-WmiObject Win32_LocalTime).weekinmonth
# Date day
$dayNow = (Get-Date).Day

Set-Alias pg_dump ".\pg_dump\pg_dump.exe"
Set-Alias sz "C:\Program Files\7-Zip\7z.exe"

# Parse json config file
$json=Get-Content $configPath | ConvertFrom-Json
$stgnames = ($json.stages).stgname
$days = ($json.stages).days
$crons = ($json.stages).cron
$dayly = ($json.stages).dayly
$weekly = ($json.stages).weekly
$monthly = ($json.stages).monthly
# To array
$PSObjectArray = for ($i = 0; $i -lt $stgnames.Count; $i++) {
    [PSCustomObject]@{
        stgname = $stgnames[$i]
        days = $days[$i]
        cron = $crons[$i]
        dayly = $dayly[$i]
        weekly = $weekly[$i]
        monthly = $monthly[$i]
    }
}

$hosts_ips = ($json.hosts).ip

Write-Output "Stage Names: $stgnames"
Write-Output "Days List: $days"
Write-Output "Crons List: $crons"
Write-Output "Dayly List: $dayly"
Write-Output "Weekly List: $weekly"
Write-Output "Monthly List: $monthly"

foreach ($stgarray in $PSObjectArray)
{
$stgname=$stgarray.stgname
$day=$stgarray.days
$cron=$stgarray.cron
$dayly=$stgarray.dayly
$weekly=$stgarray.weekly
$monthly=$stgarray.monthly
Write-Output "---------------------------------"
Write-Output "stgname: $stgname"
Write-Output "Days: $day"
Write-Output "Cron: $cron"
Write-Output "Dayly: $dayly"
Write-Output "Weekly: $weekly"
Write-Output "Monthly: $monthly"
# Checking cron mod 0
$ostatok=$daysCount % $cron
if ($ostatok -eq 0)
{
  Write-Output "Starting cronBackup - Stage Name:$stgname Days:$day Cron:$cron Ostatok:$ostatok"
  # $consulHost = (Invoke-WebRequest -Uri "http://consul.domain.local:8500/v1/kv/Staging/stages/$stgname/proxy?raw" -UseBasicParsing)
  # foreach ($h in $consulHost)
  foreach ($h in $hosts_ips)
  {
  $pw = convertto-securestring -AsPlainText -Force -String "$ps_pass"
  $cred = new-object -typename System.Management.Automation.PSCredential -argumentlist "$ps_user",$pw

  # Checkin path to folder stage
  if ((Invoke-Command -ComputerName $h -Credential $cred  -ScriptBlock {$(Get-WebFilePath -PSPath "IIS:\Sites\$using:stgname")} -erroraction 'silentlycontinue'))
  {
    # Create folder for backup
    $webcatalog=$(Invoke-Command -ComputerName $h -Credential $cred -ScriptBlock {$(Get-WebFilePath -PSPath "IIS:\Sites\$using:stgname")})
    if (!(Test-Path -Path $pathBackup\$stgName)) 
    { 
        Write-Output "Create dir if it need $pathBackup\$stgName"
        New-Item -Type Directory $pathBackup\$stgName
    }

    $connstring="$webcatalog\ConnectionStrings.config"

    Write-Output "Web Directory: $h - $webcatalog"
    Write-Output "Connection String: $h - $connstring"

    # Parsing ConnectionStrings
    foreach ($stringdb in $connstring)
    {
    
    $PGHOST=$(Invoke-Command -ComputerName $h -Credential $cred -ScriptBlock {$(Get-Content $using:connstring | Where-Object {$_ -like '*name="db"*'}).split('"').split(";") | 
                %{[pscustomobject]@{Property=$_.Split("=")[0];Value=$_.Split("=")[1]}} |
                        where Property -eq "Server" | select Value})
    Write-Output "PGHOST: "$PGHOST.Value""

    $PGPORT=$(Invoke-Command -ComputerName $h -Credential $cred -ScriptBlock {$(Get-Content $using:connstring | Where-Object {$_ -like '*name="db"*'}).split('"').split(";") |
                %{[pscustomobject]@{Property=$_.Split("=")[0];Value=$_.Split("=")[1]}} |
                        where Property -eq "Port" | select Value})
    Write-Output "PGPORT: "$PGPORT.Value""

    $PGDATABASE=$(Invoke-Command -ComputerName $h -Credential $cred -ScriptBlock {$(Get-Content $using:connstring | Where-Object {$_ -like '*name="db"*'}).split('"').split(";") |
                %{[pscustomobject]@{Property=$_.Split("=")[0];Value=$_.Split("=")[1]}} |
                        where Property -eq "Database" | select Value})
    Write-Output "PGDATABASE: "$PGDATABASE.Value""

    $USER=$(Invoke-Command -ComputerName $h -Credential $cred -ScriptBlock {$(Get-Content $using:connstring | Where-Object {$_ -like '*name="db"*'}).split('"').split(";") | 
                %{[pscustomobject]@{Property=$_.Split("=")[0];Value=$_.Split("=")[1]}} |
                        where Property -eq "User ID" | select Value})
    Write-Output "USER: "$USER.Value""

    $PASSWORD=$(Invoke-Command -ComputerName $h -Credential $cred -ScriptBlock {$(Get-Content $using:connstring | Where-Object {$_ -like '*name="db"*'}).split('"').split(";") | 
                %{[pscustomobject]@{Property=$_.Split("=")[0];Value=$_.Split("=")[1]}} |
                        where Property -eq "Password" | select Value})
    Write-Output "PASSWORD: "$PASSWORD.Value""

    $msdatasource=$(Invoke-Command -ComputerName $h -Credential $cred -ScriptBlock {$(Get-Content $using:connstring | Where-Object {$_ -like '*name="db"*'}).split('"').split(";") | 
                %{[pscustomobject]@{Property=$_.Split("=")[0];Value=$_.Split("=")[1]}} |
                        where Property -eq "Data Source" | select Value})
    Write-Output "MS SQL Server: "$msdatasource.Value""

    $msdbname=$(Invoke-Command -ComputerName $h -Credential $cred -ScriptBlock {$(Get-Content $using:connstring | Where-Object {$_ -like '*name="db"*'}).split('"').split(";") | 
                %{[pscustomobject]@{Property=$_.Split("=")[0];Value=$_.Split("=")[1]}} |
                        where Property -eq "Initial Catalog" | select Value})
    Write-Output "MS SQL DB: "$msdbname.Value""
    }

    If (($monthly) -and ($dayNow -eq 1))
    {
        $prefix = "MONTHLY"
    }
    elseif (($weekly) -and ($numDayWeek -eq 7))
    {
        $prefix = "WEEKLY-$numWeekMonth"
    }
    else
    {
        $prefix = "DAYLY"
    }
    
    # Backup db if Postgres
    if ( $PGHOST.Value )
    {
    $env:PGPASSWORD = $PASSWORD.Value
    pg_dump -h $PGHOST.Value -d $PGDATABASE.Value -p $PGPORT.Value -U $USER.Value -F c -Z 9 --file="$pathBackup\$stgname\$stgname-$date-$prefix.backup"
    }

    # Backup db if MSSQL
    elseif ( $msdatasource.Value )
    {
    $secPassword = ConvertTo-SecureString $PASSWORD.Value -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential -ArgumentList $USER.Value,$secPassword
    Invoke-Command -ComputerName $h -Credential $cred  -ScriptBlock {Backup-SqlDatabase -ServerInstance $using:msdatasource.Value -Credential $using:credential -Database $using:msdbname.Value -CompressionOption "On" -BackupFile "$using:pathBackup\$using:stgname\$using:stgname-$using:date-$using:prefix.bak"}
    }

    # Backup web-folder
    Invoke-Command -ComputerName $h -Credential $cred -ScriptBlock {
    Get-PSDrive V -erroraction 'silentlycontinue' | Remove-PSDrive -erroraction 'silentlycontinue'
    New-PSDrive -Name 'V' -PSProvider 'FileSystem' -Root "$using:pathBackup\$using:stgname" -Persist -Scope 'Global' -Credential $using:cred
    & "C:\Program Files\7-Zip\7z.exe" "a" "V:\$using:stgname-$using:date-$using:prefix.zip" $using:webcatalog
    # Delete dayly backups
    Get-ChildItem "V:\$stgname\" -Recurse -File -Exclude *MONTHLY.*, *WEEKLY*.* | Where CreationTime -lt  (Get-Date).AddDays($using:day)  | Remove-Item -Exclude *MONTHLY.*, *WEEKLY*.* -Force -Verbose 4>&1 | Foreach-Object{ `
        Write-Host ($_.Message -replace'(.*)Target "(.*)"(.*)','Removing File $2') -ForegroundColor Yellow
}
    # Delete weekly backups
    Get-ChildItem "V:\$stgname\" -Recurse -File -Exclude *DAYLY.*, *MONTHLY.* | Where CreationTime -lt  (Get-Date).AddMonths($using:weekly)  | Remove-Item -Exclude *DAYLY.*, *MONTHLY.* -Force -Verbose 4>&1 | Foreach-Object{ `
        Write-Host ($_.Message -replace'(.*)Target "(.*)"(.*)','Removing File $2') -ForegroundColor Yellow
}
    # Delete monthly backups
    Get-ChildItem "V:\$stgname\" -Recurse -File -Exclude *DAYLY.*, *WEEKLY*.* | Where CreationTime -lt  (Get-Date).AddMonths($using:monthly)  | Remove-Item -Exclude *DAYLY.*, *WEEKLY*.* -Force -Verbose 4>&1 | Foreach-Object{ `
        Write-Host ($_.Message -replace'(.*)Target "(.*)"(.*)','Removing File $2') -ForegroundColor Yellow
}    
    Get-PSDrive V | Remove-PSDrive
    }
}
  else 
  {
  Write-Output "$h - Stage $stgname Does Not Exist on $h"
  }
}
}
else 
{
Write-Output "Today is not scheduled - Stage Name:$stgname Days:$day Cron:$cron Ostatok:$ostatok"
}
}
