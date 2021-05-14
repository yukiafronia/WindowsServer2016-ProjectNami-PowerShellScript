# Windows Server IIS+SQLServer+WordPress.ps1
#ファイアウォール無効化
Get-NetFirewallProfile | Set-NetFirewallProfile -Enabled false
#IISのインストール
Install-WindowsFeature -Name @("Web-Server","Web-CGI") -IncludeManagementTools
#PHP7.1(x64 Non Thread Safe)
Start-BitsTransfer -Source "http://windows.php.net/downloads/releases/php-7.4.19-nts-Win32-vc15-x64.zip" -Destination C:\php-7.4.19-nts-Win32-vc15-x64.zip
New-Item 'C:\PHP' -itemType Directory
Move-Item C:\php-7.4.19-nts-Win32-vc15-x64.zip C:\PHP
cd C:\PHP
#ダウンロードした.zipを解凍
Expand-Archive .\php-7.4.19-nts-Win32-vc15-x64.zip -DestinationPath C:\PHP
Remove-Item C:\PHP\*.zip -Force
# PATH の展開
[Environment]::SetEnvironmentVariable("Path", ($env:Path += "C:\PHP"), [System.EnvironmentVariableTarget]::Machine )
Start-BitsTransfer -Source "https://downloads.sourceforge.net/project/wincache/development/wincache-2.0.0.8-dev-7.4-nts-vc15-x64.exe" -Destination C:\wincache-2.0.0.8-dev-7.4-nts-vc15-x64.exe
cd C:\
Move-Item C:\wincache-2.0.0.8-dev-7.4-nts-vc15-x64.exe C:\PHP
# C:\PHP\ext に展開
.\PHP\wincache-2.0.0.8-dev-7.4-nts-vc15-x64.exe /Q /T:C:\PHP\ext

# IIS の設定
# ハンドラーマッピングの設定
New-WebHandler -Name "PHP" -Path "*.php" -Verb "*" -Modules FastCgiModule -ScriptProcessor C:\PHP\php-cgi.exe -ResourceType File
Add-WebConfiguration "system.webServer/fastCgi" -Value @{fullPath="C:\PHP\php-cgi.exe"}

# 既定のドキュメントの設定
Add-WebConfiguration -Filter "//defaultDocument/files" -AtIndex 0 -Value @{value="index.php"}

# PHP のテスト
"<?php phpinfo(); ?>" | Out-File C:\inetpub\wwwroot\phpinfo.php -Encoding UTF8
(Invoke-WebRequest -Uri "http://localhost/phpinfo.php").Content

#PHP ドライバーのインストール
Invoke-WebRequest -Uri "https://github.com/microsoft/msphpsql/releases/download/v5.9.0/Windows-7.4.zip" -OutFile C:\Windows-7.4.zip
cd C:\
Expand-Archive .\Windows-7.4.zip -DestinationPath ./
cd C:\Windows-7.4
cd C:\Windows-7.4\x64
Move-Item C:\Windows-7.4\x64\php_sqlsrv_74_nts.dll C:\PHP\Ext
cd C:\
Remove-Item C:\*.zip -Force
cd C:\
Remove-Item C:\Windows-7.4 -Force -Recurse
# PHP.ini の作成
Copy-Item "C:\PHP\php.ini-production" "C:\PHP\php.ini"
#指定した行の前に文字列を挿入する。
Get-Content C:\PHP\php.ini
$data= Get-Content C:\PHP\php.ini
$data[915]="extension=php_sqlsrv_74_nts.dll`n" + $data[915]
$data | Out-File C:\PHP\php.ini -Encoding UTF8
#error_logの保管場所を変更
$data=Get-Content C:\PHP\php.ini | % { $_ -replace ";error_log = php_errors.log","error_log = c:\translate.log" }
$data | Out-File C:\PHP\php.ini -Encoding UTF8
#max_execution_timeを変更
$data=Get-Content C:\PHP\php.ini | % { $_ -replace "max_execution_time = 30","max_execution_time = 120" }
$data | Out-File C:\PHP\php.ini -Encoding UTF8

# ファイルのアクセス権
Out-File c:\translate.log -Encoding ascii
$ACL = Get-ACL c:\translate.log
$permission = @("IIS AppPool\DefaultAppPool", "Fullcontrol", "Allow")
$accessRule = New-Object System.Security.AccessControl.FileSystemAccessRule $permission
$ACL.SetAccessRule($accessRule)
Set-Acl c:\translate.log -AclObject $ACL

#ProjectNamiのファイルをダウンロード
Start-Sleep -s 10
Start-BitsTransfer -Source "https://github.com/ProjectNami/projectnami/archive/2.7.2.zip" -Destination C:\projectnami-2.7.2.zip
New-Item C:\Nami -itemType Directory
Move-Item C:\projectnami-2.7.2.zip C:\Nami
cd C:\

# Nami のファイルを C:\Inetput\wwwroot に展開
Expand-Archive .\Nami\projectnami-2.7.2.zip -DestinationPath C:\temp
Move-Item C:\temp\projectnami-2.7.2\* C:\inetpub\wwwroot

# wp-config.php の作成
Copy-Item "C:\inetpub\wwwroot\wp-config-sample.php" "C:\inetpub\wwwroot\wp-config.php"

#SQL Server接続のPowerShellModule
Install-Module -Name "SqlServer" -AllowClobber

#SQLServer2016 Enterpriseのサイレントインストール
cd E:\
Move-Item C:\Users\Administrator\Desktop\WindowsServer2016-ProjectNami-PowerShellScript\ConfigurationFile.ini C:\ConfigurationFile.ini
.\Setup /ConfigurationFile="C:\ConfigurationFile.ini" /IACCEPTSQLSERVERLICENSETERMS="True" /IACCEPTROPENLICENSETERMS="True" /SAPWD="Password"

#インストール中待機
Start-Sleep -s 300

# DB 周りの設定
# WP 用ログインと DB の作成
$sql = @"
USE [master]
GO
EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'LoginMode', REG_DWORD, 2
GO
"@
Invoke-Sqlcmd -ServerInstance localhost -Query $sql
Restart-Service -Name "MSSQLSERVER"

#SQL Server DB設定
#WordPressUser , WordPressPassword , WordPressDatabase"
$sql =@"
CREATE DATABASE WordPressDatabase COLLATE SQL_Latin1_General_CP1_CI_AS
GO
USE [master]
GO
CREATE LOGIN [WordPressUser] WITH PASSWORD=N'<WordPressPassword>', DEFAULT_DATABASE=[master], CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF
GO
USE [WordPressDatabase]
GO
CREATE USER [WordPressUser] FOR LOGIN [WordPressUser]
GO
ALTER ROLE [db_datareader] ADD MEMBER [WordPressUser]
GO
ALTER ROLE [db_datawriter] ADD MEMBER [WordPressUser]
GO
ALTER ROLE [db_ddladmin] ADD MEMBER [WordPressUser]
GO
"@
Invoke-Sqlcmd -ServerInstance localhost -Query $sql