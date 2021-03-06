# Данный скрипт является частью ПО "Инвентаризация"
# Автор: Похресник Д.А. (19.04.2013)
# Версия: 0.01

# ГЛОБАЛЬНЫЕ НАСТРОЙКИ
# ===========================================================================================================
# поиск в разделе реестра HKEY_LOCAL_MACHINE
$HKLM = 2147483650;
# ключи реестра, в которых будем искать установленные программы (для 64-битных систем есть еще другой ключ)
$KeysUninstall = "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\","SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\";
# узнаем имя локального компьютера
$ComputerName = $Env:COMPUTERNAME;
# строка инициализации подключения к СУБД
$connStr = 'Server=INTRANET\SQLEXPRESS;Database=Inventory;User Id=sa;Password=secretpassword;';
# SQL значение NULL для типа date (применительно к string)
$SQL_NULL = Get-Date("01.01.1900 0:00:00");
# -----------------------------------------------------------------------------------------------------------

# шаблон объектов пользовательского типа - класс
# ===========================================================================================================
Add-Type @'
public class Application
{
    public string DisplayName;
    public string DisplayVersion;
    public string ParentKeyName;
    public string ParentDisplayName;
    public string Publisher;
    public string InstallDate;
    public string InstallSource;
    public string InstallLocation;
	
	public Application()
    {
		DisplayName = "";
		DisplayVersion = "";
		ParentKeyName = "";
		ParentDisplayName = "";
		Publisher = "";
		InstallDate = "";
		InstallSource = "";
		InstallLocation = "";
    }
	
	public Application(string name, string vers, string p_kname, string p_name, string pub, string date, string inst_s, string inst_d)
    {
		DisplayName = name;
		DisplayVersion = vers;
		ParentKeyName = p_kname;
		ParentDisplayName = p_name;
		Publisher = pub;
		InstallDate = date;
		InstallSource = inst_s;
		InstallLocation = inst_d;
    }
}
'@  
# -----------------------------------------------------------------------------------------------------------

# Возвращает DataTable, которая представляет собой коллекцию объектов, 
# каждый из которых является строкой результатов запроса. 
# Свойства каждого объекта соответствуют столбцам результата запроса.
# ===========================================================================================================
function Get-DatabaseData {
	[CmdletBinding()]
	param (
		[string]$connectionString,
		[string]$query,
		[switch]$isOleDB
	)
	if ($isOleDB) {
		Write-Verbose 'in OleDB mode';
		$connection = New-Object System.Data.OleDb.OleDbConnection;	
	} else {
		Write-Verbose 'in SQL Server mode';
		$connection = New-Object System.Data.SqlClient.SqlConnection;
	}
	$connection.ConnectionString = $connectionString;
	$command = $connection.CreateCommand();
	$command.CommandText = $query;
	if ($isOleDB) {
        $adapter = New-Object System.Data.OleDb.OleDbDataAdapter $command;
	} else {		
		$adapter = New-Object System.Data.SqlClient.SqlDataAdapter $command;
	}
	$dataset = New-Object System.Data.DataSet;
	$count = $adapter.Fill($dataset);
	$RowsFromTable = $dataset.Tables[0].Rows;
    return $RowsFromTable;    
}
# -----------------------------------------------------------------------------------------------------------

# Команда Invoke-DatabaseQuery не возвращает никакой информации
# ===========================================================================================================
function Invoke-DatabaseQuery {
	[CmdletBinding()]
	param (
		[string]$connectionString,
		[string]$query,
		[switch]$isOleDB
	)
	if ($isOleDB) {
		Write-Verbose 'in OleDB mode';
		$connection = New-Object System.Data.OleDb.OleDbConnection;	
	} else {
		Write-Verbose 'in SQL Server mode';
		$connection = New-Object System.Data.SqlClient.SqlConnection;
	}
	$connection.ConnectionString = $connectionString;
	$command = $connection.CreateCommand();
	$command.CommandText = $query;
	$connection.Open();
	$result = $command.ExecuteNonQuery();
	$connection.close();
}
# -----------------------------------------------------------------------------------------------------------

write-host "Извлечение информации об установленном ПО из реестра" -foregroundcolor "red";
# ===========================================================================================================
(Measure-Command {

# получаем экземпляр объекта класса StdRegProv
$srp = [wmiclass]"\\$ComputerName\root\default:StdRegProv";
# инициализация динамического массива для записей о ПО
$ALL_RECORDS = @();

foreach ($key in $KeysUninstall) # перебираем ключи реестра, в которых производится поиск
{
    $Items = $srp.EnumKey($HKLM,$key).sNames;
    foreach ($item in $Items) # перебираем все найденные ключи
    {
        # пропускаем пустые записи для DisplayName
        if (!($srp.GetStringValue($HKLM,$key+$item,"DisplayName").sValue)) {continue;}
		
		# считываем информацию о приложении
		$displayName = [string]$srp.GetStringValue($HKLM,$key+$item,"DisplayName").sValue;
		$displayVersion = [string]$srp.GetStringValue($HKLM,$key+$item,"DisplayVersion").sValue;
		$parentKeyName = [string]$srp.GetStringValue($HKLM,$key+$item,"ParentKeyName").sValue;
		$parentDisplayName = [string]$srp.GetStringValue($HKLM,$key+$item,"ParentDisplayName").sValue;
		$publisher = [string]$srp.GetStringValue($HKLM,$key+$item,"Publisher").sValue;
        if ($val=$srp.GetStringValue($HKLM,$key+$item,"InstallDate").sValue)
            { $installDate = Get-Date ([datetime]::ParseExact($val,'yyyyMMdd', $null)) -f 'yyyy-MM-dd'; }
        else 
            { $installDate = ""; }
		$installSource = [string]$srp.GetStringValue($HKLM,$key+$item,"InstallSource").sValue;        
		$installLocation = [string]$srp.GetStringValue($HKLM,$key+$item,"InstallLocation").sValue;
		               
		# создаем новый экземпляр класса Application и вносим значения в динамический массив
        $ALL_RECORDS += New-Object Application ($displayName, $displayVersion, $parentKeyName, $parentDisplayName, $publisher, $installDate, $installSource, $installLocation);
    }
}

# избавляемся от одинаковых объектов 
$UNIQUE_SORTED_RECORDS = $ALL_RECORDS | Sort-Object -Property DisplayName,InstallSource | Select-Object * | Get-Unique -AsString;

}).TotalSeconds 
# -----------------------------------------------------------------------------------------------------------

write-host "Сравнение существующих записей в БД с текущими записями из реестра" -foregroundcolor "red";
# ===========================================================================================================
(Measure-Command {

# инициализируем строку для будущего SQL запроса
$EXCLUDE_STRING = '';

foreach ($record in $UNIQUE_SORTED_RECORDS)
{
    $SQL_SelectSoftwareForCurrentComputer = "
    SELECT 
        [dbo].[SoftwareNames].displayname AS DisplayName,
		[dbo].[Software].SoftwareNames_id AS SoftwareNameID,
		[dbo].[Software].Computers_id AS ComputerID,
		[dbo].[Software].Licenses_id AS LicenseID,
        [dbo].[Software].displayversion AS DisplayVersion,
        [dbo].[Software].parentkeyname AS ParentKeyName,
        [dbo].[Software].parentdisplayname AS ParentDisplayName,
        [dbo].[Software].publisher AS Publisher,
        [dbo].[Software].date_install AS InstallDate,
        [dbo].[Software].install_source AS InstallSource,
        [dbo].[Software].install_location AS InstallLocation
    FROM 
        [dbo].[Software],[dbo].[SoftwareNames] 
    WHERE 
    (
        [dbo].[Software].[Computers_id] = (SELECT id FROM [dbo].[Computers] WHERE [dbo].[Computers].[name] = '"+$ComputerName+"') 
        AND
        [dbo].[SoftwareNames].[id] = [dbo].[Software].[SoftwareNames_id]
        AND
        [dbo].[SoftwareNames].[displayname] = '"+$record.DisplayName+"'
    )
    ";
    $DATA_SQL_SelectSoftwareForCurrentComputer = Get-DatabaseData -connectionString $connStr -query $SQL_SelectSoftwareForCurrentComputer;    
    
    if ($DATA_SQL_SelectSoftwareForCurrentComputer) # если найдено: проверяем на изменения + добавляем в массив проверенных значений
    {
		if ($DATA_SQL_SelectSoftwareForCurrentComputer.Table.Rows.Count -ne 1) 
		{
			write-host "найдено более 1 записи" -foregroundcolor "red";
			$IsEqual = $false;
			foreach ($data_sql_record in $DATA_SQL_SelectSoftwareForCurrentComputer)
			{
				if ($data_sql_record.DisplayName -eq $record.DisplayName -AND
	            $data_sql_record.DisplayVersion -eq $record.DisplayVersion -AND
	            $data_sql_record.ParentKeyName -eq $record.ParentKeyName -AND
	            $data_sql_record.ParentDisplayName -eq $record.ParentDisplayName -AND
	            $data_sql_record.Publisher -eq $record.Publisher -AND
	            (
					$data_sql_record.InstallDate -eq $record.InstallDate -OR 
					($data_sql_record.InstallDate -eq $SQL_NULL -AND $record.InstallDate -eq "")
				) -AND
	            $data_sql_record.InstallSource -eq $record.InstallSource -AND
	            $data_sql_record.InstallLocation -eq $record.InstallLocation)
		        {
					$IsEqual = $true;
				} 				
			}
			
			if ($IsEqual)
			{
				write-host "эквивалентно" -foregroundcolor "green";
			}
			# иначе (если записи отличаются) учесть в изменениях
			else
	        {
	            write-host "различно" -foregroundcolor "magenta";
	        }
	        $EXCLUDE_STRING += ("[dbo].[SoftwareNames].[displayname] != '"+$record.DisplayName+"' AND ");  
		}
		else
		{ 
			# если записи совпадают, ничего не делаем
	        if ($DATA_SQL_SelectSoftwareForCurrentComputer.DisplayName -eq $record.DisplayName -AND
	            $DATA_SQL_SelectSoftwareForCurrentComputer.DisplayVersion -eq $record.DisplayVersion -AND
	            $DATA_SQL_SelectSoftwareForCurrentComputer.ParentKeyName -eq $record.ParentKeyName -AND
	            $DATA_SQL_SelectSoftwareForCurrentComputer.ParentDisplayName -eq $record.ParentDisplayName -AND
	            $DATA_SQL_SelectSoftwareForCurrentComputer.Publisher -eq $record.Publisher -AND
	            (
					$DATA_SQL_SelectSoftwareForCurrentComputer.InstallDate -eq $record.InstallDate -OR 
					($DATA_SQL_SelectSoftwareForCurrentComputer.InstallDate -eq $SQL_NULL -AND $record.InstallDate -eq "")
				) -AND
	            $DATA_SQL_SelectSoftwareForCurrentComputer.InstallSource -eq $record.InstallSource -AND
	            $DATA_SQL_SelectSoftwareForCurrentComputer.InstallLocation -eq $record.InstallLocation)
	        {
				write-host "эквивалентно" -foregroundcolor "green";
			}
	        # иначе (если записи отличаются) учесть в изменениях
			else
	        {
	            write-host "различно" -foregroundcolor "magenta";
	            write-host "DisplayName";
				write-host $DATA_SQL_SelectSoftwareForCurrentComputer.DisplayName; 
				write-host $record.DisplayName;
	            write-host "DisplayVersion"; 
				write-host $DATA_SQL_SelectSoftwareForCurrentComputer.DisplayVersion; 
				write-host $record.DisplayVersion;
	            write-host "ParentKeyName"; 
				write-host $DATA_SQL_SelectSoftwareForCurrentComputer.ParentKeyName; 
				write-host $record.ParentKeyName;
	            write-host "ParentDisplayName"; 
				write-host $DATA_SQL_SelectSoftwareForCurrentComputer.ParentDisplayName; 
				write-host $record.ParentDisplayName;
	            write-host "Publisher";
				write-host $DATA_SQL_SelectSoftwareForCurrentComputer.Publisher; 
				write-host $record.Publisher;
	            write-host "InstallDate"; 
				write-host $DATA_SQL_SelectSoftwareForCurrentComputer.InstallDate.ToString('yyyy-MM-dd'); 
				write-host $record.InstallDate;
	            write-host "InstallSource"; 
				write-host $DATA_SQL_SelectSoftwareForCurrentComputer.InstallSource; 
				write-host $record.InstallSource;
	            write-host "InstallLocation"; 
				write-host $DATA_SQL_SelectSoftwareForCurrentComputer.InstallLocation; 
				write-host $record.InstallLocation;   
				$SQL_InsertSoftwareChangesDiff = "
				INSERT INTO [dbo].[SoftwareChanges]
			           ([datetime_change]
			           ,[SoftwareNames_id]
			           ,[Computers_id]
			           ,[Licenses_id]
			           ,[old_displayversion]
			           ,[old_publisher]
			           ,[old_date_install]
			           ,[old_install_location]
			           ,[new_displayversion]
			           ,[new_publisher]
			           ,[new_date_install]
			           ,[new_install_location])
			     VALUES
			           ('"+(Get-Date -Format "dd.MM.yyyy HH:mm:ss")+"'
			           ,"+($DATA_SQL_SelectSoftwareForCurrentComputer.SoftwareNameID)+"
			           ,"+($DATA_SQL_SelectSoftwareForCurrentComputer.ComputerID)+"
			           ,"+($DATA_SQL_SelectSoftwareForCurrentComputer.LicenseID)+"
			           ,'"+($DATA_SQL_SelectSoftwareForCurrentComputer.DisplayVersion)+"'
			           ,'"+($DATA_SQL_SelectSoftwareForCurrentComputer.Publisher)+"'
			           ,'"+($DATA_SQL_SelectSoftwareForCurrentComputer.InstallDate.ToString('yyyy-MM-dd'))+"'
			           ,'"+($DATA_SQL_SelectSoftwareForCurrentComputer.InstallLocation)+"'
			           ,'"+($record.DisplayVersion)+"'
			           ,'"+($record.Publisher)+"'
			           ,'"+($record.InstallDate)+"'
			           ,'"+($record.InstallLocation)+"')
				";
				Invoke-DatabaseQuery -connectionString $connStr -query $SQL_InsertSoftwareChangesDiff;
	        }
	        $EXCLUDE_STRING += ("[dbo].[SoftwareNames].[displayname] != '"+$record.DisplayName+"' AND ");   
		} # end foreach
    }
    else	# если НЕ найдено: программу недавно установили (учесть в изменениях)
    {
		write-host "новое ПО" -foregroundcolor "blue";
		$SQL_InsertSoftwareChangesNew = "
		INSERT INTO [dbo].[SoftwareChanges]
	           ([datetime_change]
	           ,[SoftwareNames_id]
	           ,[Computers_id]
	           ,[Licenses_id]
	           ,[new_displayversion]
	           ,[new_publisher]
	           ,[new_date_install]
	           ,[new_install_location])
	     VALUES
	           ('"+(Get-Date -Format "dd.MM.yyyy HH:mm:ss")+"'
	           ,1
	           ,1
	           ,1
	           ,'"+($record.DisplayVersion)+"'
	           ,'"+($record.Publisher)+"'
	           ,'"+($record.InstallDate)+"'
	           ,'"+($record.InstallLocation)+"')
		";
		Invoke-DatabaseQuery -connectionString $connStr -query $SQL_InsertSoftwareChangesNew;
	}
} # конец сравнения записей

# делаем запрос: проверяем все данные, которые не равны значениям в массиве. Это будут недавно удаленные программы (учесть в изменениях)
# ++++++++++ для теста
#$EXCLUDE_STRING = "[dbo].[SoftwareNames].[displayname] != ' Tools for .Net 3.5' AND 
#	[dbo].[SoftwareNames].[displayname] != ' Tools for .Net 3.5 - RUS Lang Pack' AND 
#	[dbo].[SoftwareNames].[displayname] != 'µTorrent' AND 
#	[dbo].[SoftwareNames].[displayname] != '2ГИС 3.13.2.3' AND 
#	[dbo].[SoftwareNames].[displayname] != 'Acronis Disk Director Home' AND
#	 [dbo].[SoftwareNames].[displayname] != 'Adobe Flash Player 10 Plugin' AND 
#	 [dbo].[SoftwareNames].[displayname] != 'Adobe Flash Player 11 ActiveX' AND 
#	 [dbo].[SoftwareNames].[displayname] != 'Adobe Reader X (10.1.6) - Russian' AND 
#	 [dbo].[SoftwareNames].[displayname] != 'AIMP3' AND 
#	 [dbo].[SoftwareNames].[displayname] != 'ArtMoney SE v7.40.2' AND 
#	 [dbo].[SoftwareNames].[displayname] != 'ASRock App Charger v1.0.4' AND 
#	 [dbo].[SoftwareNames].[displayname] != 'ASRock eXtreme Tuner v0.1.207.1' AND 
#	 [dbo].[SoftwareNames].[displayname] != 'ASRock XFast RAM v2.0.28' AND 
#	 [dbo].[SoftwareNames].[displayname] != 'ASUS Xonar D1 Audio Driver' AND 
#	 [dbo].[SoftwareNames].[displayname] != 'Attribute Changer 7.10c' AND 
#	 [dbo].[SoftwareNames].[displayname] != 'AusLogics BoostSpeed' AND 
#	 [dbo].[SoftwareNames].[displayname] != 'Blend for Visual Studio 2012' AND 
#	 [dbo].[SoftwareNames].[displayname] != 'Blend for Visual Studio 2012 RUS resources' AND 
#	 [dbo].[SoftwareNames].[displayname] != 'CGS15_IPM_T2' AND ";
# ++++++++++ 
$SQL_SelectDeletedSoftwareForCurrentComputer = "
SELECT 
    [dbo].[SoftwareNames].displayname AS DisplayName,
	[dbo].[Software].SoftwareNames_id AS SoftwareNameID,
	[dbo].[Software].Computers_id AS ComputerID,
	[dbo].[Software].Licenses_id AS LicenseID,
    [dbo].[Software].displayversion AS DisplayVersion,
    [dbo].[Software].parentkeyname AS ParentKeyName,
    [dbo].[Software].parentdisplayname AS ParentDisplayName,
    [dbo].[Software].publisher AS Publisher,
    [dbo].[Software].date_install AS InstallDate,
    [dbo].[Software].install_source AS InstallSource,
    [dbo].[Software].install_location AS InstallLocation
FROM 
    [dbo].[Software],[dbo].[SoftwareNames] 
WHERE 
(
    [dbo].[Software].[Computers_id] = (SELECT id FROM [dbo].[Computers] WHERE [dbo].[Computers].[name] = '"+$ComputerName+"') 
    AND
    [dbo].[SoftwareNames].[id] = [dbo].[Software].[SoftwareNames_id]
    AND
    ("+$EXCLUDE_STRING+"[dbo].[SoftwareNames].[displayname] != '')
)
";
$DATA_SQL_SelectDeletedSoftwareForCurrentComputer = Get-DatabaseData -connectionString $connStr -query $SQL_SelectDeletedSoftwareForCurrentComputer;

if ($DATA_SQL_SelectDeletedSoftwareForCurrentComputer -AND $DATA_SQL_SelectDeletedSoftwareForCurrentComputer.Count -ne 0)
{
	foreach ($data_sql_record in $DATA_SQL_SelectDeletedSoftwareForCurrentComputer)
	{
		write-host ("Удаленное ПО: "+$data_sql_record.DisplayName) -foregroundcolor "DarkCyan";  		
		$SQL_InsertSoftwareChangesDel = "
		INSERT INTO [dbo].[SoftwareChanges]
		       ([datetime_change]
		       ,[SoftwareNames_id]
		       ,[Computers_id]
		       ,[Licenses_id]
		       ,[old_displayversion]
		       ,[old_publisher]
		       ,[old_date_install]
		       ,[old_install_location])
		 VALUES
		       ('"+(Get-Date -Format "dd.MM.yyyy HH:mm:ss")+"'
		       ,"+($data_sql_record.SoftwareNameID)+"
		       ,"+($data_sql_record.ComputerID)+"
		       ,"+($data_sql_record.LicenseID)+"
		       ,'"+($data_sql_record.DisplayVersion)+"'
		       ,'"+($data_sql_record.Publisher)+"'
		       ,'"+($data_sql_record.InstallDate.ToString('yyyy-MM-dd'))+"'
		       ,'"+($data_sql_record.InstallLocation)+"')
		";
		Invoke-DatabaseQuery -connectionString $connStr -query $SQL_InsertSoftwareChangesDel;
	}
}

}).TotalSeconds 
# -----------------------------------------------------------------------------------------------------------

write-host "Очищаем данные в БД для текущего компьютера" -foregroundcolor "red";
# ===========================================================================================================
(Measure-Command {

# Удаляем все записи
$SQL_DeleteAllSoftwareWithComputerID = "DELETE FROM [dbo].[Software] WHERE [dbo].[Software].[Computers_id] = (SELECT id FROM [dbo].[Computers] WHERE [dbo].[Computers].[name] = '"+$ComputerName+"')";
Invoke-DatabaseQuery -connectionString $connStr -query $SQL_DeleteAllSoftwareWithComputerID;

}).TotalSeconds 
# -----------------------------------------------------------------------------------------------------------

write-host "Вносим данные в БД для текущего компьютера" -foregroundcolor "red";
# ===========================================================================================================
(Measure-Command {

foreach ($record in $UNIQUE_SORTED_RECORDS) 
{
    $SQL_SelectIdFromSoftwareNames = "SELECT id,displayname FROM [dbo].[SoftwareNames] WHERE [dbo].[SoftwareNames].[displayname] = '"+$record.DisplayName+"'";
    $DATA_SQL_SelectIdFromSoftwareNames = Get-DatabaseData -connectionString $connStr -query $SQL_SelectIdFromSoftwareNames;
    $SoftwareNames_id = [int]$DATA_SQL_SelectIdFromSoftwareNames.id;
    
    # если такое имя не существует, добавим его
    if ($SoftwareNames_id -eq 0)
    {        
        $SQL_InsertNewSoftwareName = "INSERT INTO SoftwareNames (SoftwareCategories_id, displayname) VALUES (1,'"+$record.DisplayName+"')";
        Invoke-DatabaseQuery -connectionString $connStr -query $SQL_InsertNewSoftwareName;
        $DATA_SQL_SelectIdFromSoftwareNames = Get-DatabaseData -connectionString $connStr -query $SQL_SelectIdFromSoftwareNames;
        $SoftwareNames_id = [int]$DATA_SQL_SelectIdFromSoftwareNames.id;
    }    
    if ($SoftwareNames_id -eq 0) {write-host "Критическая ошибка" -foregroundcolor "red";}
    
    $SQL_InsertIntoSoftware = "INSERT INTO Software (SoftwareNames_id, Computers_id, Licenses_id, displayversion, parentkeyname, parentdisplayname, publisher, date_install, install_source, install_location) 
            VALUES ("+$SoftwareNames_id+",1,1,'"+$record.DisplayVersion+"','"+$record.ParentKeyName+"','"+$record.ParentDisplayName+"','"+$record.Publisher+"','"+$record.InstallDate+"','"+$record.InstallSource+"','"+$record.InstallLocation+"')";
    Invoke-DatabaseQuery -connectionString $connStr -query $SQL_InsertIntoSoftware;
}

}).TotalSeconds 
# -----------------------------------------------------------------------------------------------------------