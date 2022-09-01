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

$date=$($(Get-Date -Format yyyyMMdd_HHmmss))
$daysCount=(New-TimeSpan -Start $(Get-Date -Month 09 -Day 1 -Year 2022) -End $(Get-Date)).TotalDays

Set-Alias pg_dump "C:\Program Files\PostgreSQL\12\bin\pg_dump.exe"
Set-Alias sz "C:\Program Files\7-Zip\7z.exe"

# Разбираем json
$json=Get-Content $configPath | ConvertFrom-Json
$stgnames = ($json.stages).stgname
$days = ($json.stages).days
$crons = ($json.stages).cron
# Собираем в массив
$PSObjectArray = for ($i = 0; $i -lt $stgnames.Count; $i++) {
    [PSCustomObject]@{
        stgname = $stgnames[$i]
        days = $days[$i]
        cron = $crons[$i]
    }
}

$hosts_ips = ($json.hosts).ip

Write-Output "Stage Names: $stgnames"
Write-Output "Days List: $days"
Write-Output "Crons List: $crons"

foreach ($stgarray in $PSObjectArray)
{
$stgname=$stgarray.stgname
$day=$stgarray.days
$cron=$stgarray.cron
Write-Output "---------------------------------"
Write-Output "stgname: $stgname"
Write-Output "Days: $day"
Write-Output "Cron: $cron"
# Проверка крона, если делится на $cron без остатка
$ostatok=$daysCount % $cron
if ($ostatok -eq 0)
{
  Write-Output "Starting cronBackup - Stage Name:$stgname Days:$day Cron:$cron Ostatok:$ostatok"
  foreach ($h in $hosts_ips)
  {
  $pw = convertto-securestring -AsPlainText -Force -String "$ps_pass"
  $cred = new-object -typename System.Management.Automation.PSCredential -argumentlist "$ps_user",$pw

  # Проверяем путь до директории стенда
  if ((Invoke-Command -ComputerName $h -Credential $cred  -ScriptBlock {$(Get-WebFilePath -PSPath "IIS:\Sites\$using:stgname")} -erroraction 'silentlycontinue'))
  {
    # Создаем папку для бэкапа
    $webcatalog=$(Invoke-Command -ComputerName $h -Credential $cred -ScriptBlock {$(Get-WebFilePath -PSPath "IIS:\Sites\$using:stgname")})
    if (!(Test-Path -Path $pathBackup\$stgName)) 
    { 
        Write-Output "Create dir if it need $pathBackup\$stgName"
        New-Item -Type Directory $pathBackup\$stgName
    }

    $connstring="$webcatalog\ConnectionStrings.config"

    Write-Output "Web Directory: $h - $webcatalog"
    Write-Output "Connection String: $h - $connstring"

    # Берем нужные значения из ConnectionStrings
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

    # Бэкапим БД если Postgresql
    if ( $PGHOST.Value )
    {
    $env:PGPASSWORD = $PASSWORD.Value
    pg_dump -h $PGHOST.Value -d $PGDATABASE.Value -p $PGPORT.Value -U $USER.Value -F c -Z 9 --file="$pathBackup\$stgname\$stgname-$date.backup"
    }

    # Бэкапим БД если MS SQL Server
    elseif ( $msdatasource.Value )
    {
    $secPassword = ConvertTo-SecureString $PASSWORD.Value -AsPlainText -Force
    $credential = New-Object System.Management.Automation.PSCredential -ArgumentList $USER.Value,$secPassword
    Invoke-Command -ComputerName $h -Credential $cred  -ScriptBlock {Backup-SqlDatabase -ServerInstance $using:msdatasource.Value -Credential $using:credential -Database $using:msdbname.Value -CompressionOption "On" -BackupFile "$using:pathBackup\$using:stgname\$using:stgname-$using:date.bak"}
    }

    # Бэкапим web-директорию
    Invoke-Command -ComputerName $h -Credential $cred -ScriptBlock {
    Get-PSDrive V -erroraction 'silentlycontinue' | Remove-PSDrive -erroraction 'silentlycontinue'
    New-PSDrive -Name 'V' -PSProvider 'FileSystem' -Root "$using:pathBackup\$using:stgname" -Persist -Scope 'Global' -Credential $using:cred
    & "C:\Program Files\7-Zip\7z.exe" "a" "V:\$using:stgname-$using:date.zip" $using:webcatalog
    Get-ChildItem "V:\$stgname\" -Recurse -File | Where CreationTime -lt  (Get-Date).AddDays($using:day)  | Remove-Item -Force
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
