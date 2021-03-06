# Данный скрипт является частью ПО "Инвентаризация"
# Автор: Похресник Д.А. (09.02.2015)
# Версия: 0.01

############################################################################ НАСТРОЙКИ
# SQL сервер
$SERVER = 'INTRANET\SQLEXPRESS'	# Адрес сервера
$USER = 'sa'					# Пользователь
$PWD = 'secretpassword'			# Пароль
$DATABASE = 'SCRIPTCOLLECTORS'	# Имя базы данных
#--------------------------------------------------------------------------------------
# Формат даты/времени: dd - день (2 цифры), MM - месяц (2 цифры), yyyy - год (4 цифры),
# HH - час (24 часовой формат), mm - минуты (2 цифры), ss - секунды (2 цифры)
$DATETIME_FORMAT = "dd.MM.yyyy HH:mm:ss";
#-------------------------------------------------------------------------------------
# 
#-------------------------------------------------------------------------------------
$CrLf = [char]13+[char]10;	# перевод каретки
######################################################################################

#=====================================================================================
#Подключение к серверу баз данных
function SQLconnect ($connectionString){
	$connection = New-Object System.Data.SqlClient.SqlConnection
	$connection.ConnectionString = $connectionString
	$connection.Open()
	return $connection
}
#-------------------------------------------------------------------------------------
#Отключение от сервера баз данных
function SQLdisconnect ($connection){
	$connection.Close()
}
#-------------------------------------------------------------------------------------
# узнать версию (билд) WMI-сервера
# вернуть целое число
function BuildVersion(){
	$wmiSetting = [System.Environment]::OSVersion.Version.Build;
	return [int]$wmiSetting;
	#$wmiSetting = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue;
	#return [int]$wmiSetting.BuildNumber;
}
#-------------------------------------------------------------------------------------
# специальная функция - нужна для определения даты создания ключа в реестре
function Add-RegKeyMember {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true, ParameterSetName="ByKey", Position=0, ValueFromPipeline=$true)]
        [ValidateScript({ $_ -is [Microsoft.Win32.RegistryKey] })]
        $RegistryKey,
        [Parameter(Mandatory=$true, ParameterSetName="ByPath", Position=0)]
        [string] $Path
    )
    begin {
        $Namespace = "CustomNamespace", "SubNamespace"
        Add-Type @"
            using System; 
            using System.Text;
            using System.Runtime.InteropServices; 
            $($Namespace | ForEach-Object {
                "namespace $_ {"
            })
                public class advapi32 {
                    [DllImport("advapi32.dll", CharSet = CharSet.Auto)]
                    public static extern Int32 RegQueryInfoKey(
                        IntPtr hKey,
                        StringBuilder lpClass,
                        [In, Out] ref UInt32 lpcbClass,
                        UInt32 lpReserved,
                        out UInt32 lpcSubKeys,
                        out UInt32 lpcbMaxSubKeyLen,
                        out UInt32 lpcbMaxClassLen,
                        out UInt32 lpcValues,
                        out UInt32 lpcbMaxValueNameLen,
                        out UInt32 lpcbMaxValueLen,
                        out UInt32 lpcbSecurityDescriptor,
                        out Int64 lpftLastWriteTime
                    );
                    [DllImport("advapi32.dll", CharSet = CharSet.Auto)]
                    public static extern Int32 RegOpenKeyEx(
                        IntPtr hKey,
                        string lpSubKey,
                        Int32 ulOptions,
                        Int32 samDesired,
                        out IntPtr phkResult
                    );
                    [DllImport("advapi32.dll", CharSet = CharSet.Auto)]
                    public static extern Int32 RegCloseKey(
                        IntPtr hKey
                    );
                }
            $($Namespace | ForEach-Object { "}" })
"@
        $RegTools = ("{0}.advapi32" -f ($Namespace -join ".")) -as [type]
    }
    process {
        switch ($PSCmdlet.ParameterSetName) {
            "ByKey" {
                # Already have the key, no more work to be done :)
            }
            "ByPath" {
                $Item = Get-Item -Path $Path -ErrorAction Stop
                if ($Item -isnot [Microsoft.Win32.RegistryKey]) {
                    throw "'$Path' is not a path to a registry key!"
                }
                $RegistryKey = $Item
            }
        }
        # Initialize variables that will be populated:
        $ClassLength = 255 # Buffer size (class name is rarely used, and when it is, I've never seen 
                            # it more than 8 characters. Buffer can be increased here, though. 
        $ClassName = New-Object System.Text.StringBuilder $ClassLength  # Will hold the class name
        $LastWriteTime = $null
        # Get a handle to our key via RegOpenKeyEx (PSv3 and higher could use the .Handle property off of registry key):
        $KeyHandle = New-Object IntPtr
        if ($RegistryKey.Name -notmatch "^(?<hive>[^\\]+)\\(?<subkey>.+)$") {
            Write-Error ("'{0}' not a valid registry path!")
            return
        }
        $HiveName = $matches.hive -replace "(^HKEY_|_|:$)", ""  # Get hive in a format that [RegistryHive] enum can handle
        $SubKey = $matches.subkey
        try {
            $Hive = [Microsoft.Win32.RegistryHive] $HiveName
        }
        catch {
            #Write-Error ("Unknown hive: {0} (Registry path: {1})" -f $HiveName, $RegistryKey.Name)
            return  # Exit function or we'll get an error in RegOpenKeyEx call
        }
        #Write-Verbose ("Attempting to get handle to '{0}' using RegOpenKeyEx" -f $RegistryKey.Name)
        switch ($RegTools::RegOpenKeyEx(
            $Hive.value__,
            $SubKey,
            0,  # Reserved; should always be 0
            [System.Security.AccessControl.RegistryRights]::ReadKey,
            [ref] $KeyHandle
        )) {
            0 { # Success
                # Nothing required for now
                #Write-Verbose "  -> Success!"
            }
            default {
                # Unknown error!
                #Write-Error ("Error opening handle to key '{0}': {1}" -f $RegistryKey.Name, $_)
            }
        }            
        switch ($RegTools::RegQueryInfoKey(
            $KeyHandle,
            $ClassName, 
            [ref] $ClassLength, 
            $null,  # Reserved
            [ref] $null, # SubKeyCount
            [ref] $null, # MaxSubKeyNameLength
            [ref] $null, # MaxClassLength
            [ref] $null, # ValueCount
            [ref] $null, # MaxValueNameLength 
            [ref] $null, # MaxValueValueLength 
            [ref] $null, # SecurityDescriptorSize
            [ref] $LastWriteTime
        )) {
            0 { # Success
                $LastWriteTime = [datetime]::FromFileTime($LastWriteTime)
                # Add properties to object and output them to pipeline
                $RegistryKey | 
                    Add-Member -MemberType NoteProperty -Name LastWriteTime -Value $LastWriteTime -Force -PassThru |
                    Add-Member -MemberType NoteProperty -Name ClassName -Value $ClassName.ToString() -Force -PassThru
            }
            122  { # ERROR_INSUFFICIENT_BUFFER (0x7a)
                throw "Class name buffer too small"
                # function could be recalled with a larger buffer, but for
                # now, just exit
            }
            default {
                throw "Unknown error encountered (error code $_)"
            }
        }
        # Closing key:
        Write-Verbose ("Closing handle to '{0}' using RegCloseKey" -f $RegistryKey.Name)
        switch ($RegTools::RegCloseKey($KeyHandle)) {
            0 {
                # Success, no action required
                Write-Verbose "  -> Success!"
            }
            default {
                Write-Error ("Error closing handle to key '{0}': {1}" -f $RegistryKey.Name, $_)
            }
        }
    }
}
#-------------------------------------------------------------------------------------

$RunTimeGetWMI = (Measure-Command {	# замеряем время выполнения
########################################################################### ВЫПОЛНЕНИЕ
# генерируем метку времени
$strDateTime = [string](Get-Date -f $DATETIME_FORMAT);
$Today = Get-Date -Format d;
# узнаем имя локального компьютера
$HOSTNAME = $env:computername;
#-------------------------------------------------------------------------------------	
$cmd = New-Object System.Data.SqlClient.SqlCommand;
# строка подлючения к SQL серверу
$connectionString = "Server=$SERVER;Database=$DATABASE;User id=$USER;Password=$PWD;";
$connection = SQLconnect ($connectionString);
$cmd.connection = $connection;

# узнаем версию WMI-сервера
$build = BuildVersion;
#-------------------------------------------------------------------------------------	
if ($build -le 2600) {	# для старых версий Windows
	$RegPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR\*\*"; 
} 
else { # для новых версий Windows
	$RegPath = "HKLM:\SYSTEM\CurrentControlSet\Enum\USBSTOR\*\*"; 
}

# поиск записей в реестре
#-------------------------------------------------------------------------------------	
$USBDEV = Get-ItemProperty $RegPath | Select-Object `
	@{
		Name="DeviceDesc";	
		Expression={ 
			$_.DeviceDesc -split ";" | select -last 1 
		}
	},
	@{
		Name="Mfg";			
		Expression={ 
			$_.Mfg -split ";" | select -last 1 
		}
	},
	@{
		Name="Service";	
		Expression={ 
			if([string]::IsNullOrEmpty($_.Service)) {"unknown"} 
			else {$_.Service} 
		}
	},
	@{
		Name="SerialNumber";	
		Expression={ $_.PsChildName }
	},
	@{
		Name="FriendlyName";	
		Expression={ 
			if([string]::IsNullOrEmpty($_.FriendlyName)) {
				$_.DeviceDesc -split ";" | select -last 1
			} 
			else {
				$_.FriendlyName
			} 
		}
	},
	@{
		Name="LastModified";	
		Expression={ 
			(Get-Item $_.PsPath | Add-RegKeyMember | select LastWriteTime).LastWriteTime 
		}
	}
#-------------------------------------------------------------------------------------
# определяем глобальный массив, в который будем добавлять 
# SQL запросы для дальнейшего использования
$SQL_cmd = @();
#-------------------------------------------------------------------------------------
if ($USBDEV.Count -ge 0)
{
	foreach ($instance in $USBDEV){
		$SQL_cmd += "
			IF EXISTS (SELECT serial FROM dbo.UsbDev 
					WHERE [hostID]='{0}' AND [name]='{2}' AND [description]='{3}' AND [mfg]='{4}' AND [service]='{5}' AND [serial]='{6}')
				UPDATE dbo.UsbDev SET [upd_datetime]='{1}' WHERE [hostID]='{0}' AND [name]='{2}' AND [description]='{3}' AND [mfg]='{4}' AND [service]='{5}' AND [serial]='{6}'
			ELSE 
				INSERT INTO  dbo.UsbDev ([hostID], [upd_datetime], [name], [description], [mfg], [service], [serial], [last_modified]) 
				VALUES ('{0}','{1}','{2}','{3}','{4}','{5}','{6}','{7}')
				" -f $HOSTNAME,$strDateTime,$instance.FriendlyName,$instance.DeviceDesc,$instance.Mfg,$instance.Service,$instance.SerialNumber,$instance.LastModified;		     
	}				
}
					
# внесение информации в БД
#-------------------------------------------------------------------------------------	
$cmd = New-Object System.Data.SqlClient.SqlCommand;
# строка подлючения к SQL серверу
#$connectionString = "Server=$SERVER;Database=$DATABASE;User id=$USER;Password=$PWD;Trusted_Connection=True;";
$connectionString = "Server=$SERVER;Database=$DATABASE;User id=$USER;Password=$PWD;";
$connection = SQLconnect ($connectionString);
$cmd.connection = $connection;
$cmd.CommandText = $SQL_cmd;
[void]$cmd.ExecuteNonQuery();
}).TotalSeconds;	# конец времени выполнения

# внесение информации в БД о времени выполнения
#-------------------------------------------------------------------------------------
# получение информации о разделителе в числах с плавающей точкой
$nfi = (new-object System.Globalization.CultureInfo "en-US", $false ).NumberFormat;
$RunTime = $RunTimeGetWMI.ToString("G", $nfi);
# работа с БД
$cmd.CommandText = "INSERT INTO dbo.RunTime (hostID, upd_datetime, category, runtime) VALUES ('{0}','{1}','{2}','{3}')" -f $HOSTNAME, $strDateTime, "usbdev", $RunTime;
[void]$cmd.ExecuteNonQuery();
# отключаемся от БД
SQLdisconnect ($connection);