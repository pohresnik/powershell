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
$DATE_FORMAT = "dd.MM.yyyy";
#-------------------------------------------------------------------------------------
# какие параметры программного обеспечения нам важны: 
# DisplayName - название, ParentKeyName - родительская программа, 
# InstallDate - дата установки, Publisher - производитель
$PARAMETERS = "Publisher","DisplayName","DisplayVersion","ParentKeyName","InstallDate";
# поиск в разделе реестра HKEY_LOCAL_MACHINE
$HKLM = [UInt32]"0x80000002"; # dec = 2147483650
# ключи реестра, в которых будем искать установленные программы 
# (для 64-битных систем есть еще другой ключ)
$UNINSTALL_KEY = "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\";
$UNINSTALL_KEY_WOW = "SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Uninstall\";
#-------------------------------------------------------------------------------------
$CrLf = [char]13+[char]10;	# перевод каретки
######################################################################################

#=====================================================================================
#Подключение к серверу баз данных
function SQLconnect ($connectionString){
	$connection = New-Object System.Data.SqlClient.SqlConnection;
	$connection.ConnectionString = $connectionString;
	$connection.Open();
	return $connection;
}
#-------------------------------------------------------------------------------------
#Отключение от сервера баз данных
function SQLdisconnect ($connection){
	$connection.Close();
}
#-------------------------------------------------------------------------------------
# преобразование даты формата DMTF в читаемый вид (ДД.ММ.ГГГГ) => dd.MM.yyyy
# http://msdn.microsoft.com/en-us/library/aa389802.aspx
# yyyymmddHHMMSS.mmmmmmsUUU 
function ReadableDate($str){
	# объект недоступен в Windows 2000, поэтому см. далее
	return $str.SubString(6,2)+"."+$str.SubString(4,2)+"."+$str.SubString(0,4)
}
#-------------------------------------------------------------------------------------

$RunTimeGetWMI = (Measure-Command {	# замеряем время выполнения
########################################################################### ВЫПОЛНЕНИЕ
# узнаем имя локального компьютера
$HOSTNAME = $env:computername;
# генерируем метку времени
$DateTime = [string](Get-Date -f $DATETIME_FORMAT);
# определяем глобальный массив, в который будем добавлять 
# SQL запросы для дальнейшего использования
$SQL_cmd = @();

$srp = [wmiclass]"\\$HOSTNAME\root\default:StdRegProv";
# создаем динамический массив, для всех записей
$RECORDS = @();
foreach ($key in @($UNINSTALL_KEY,$UNINSTALL_KEY_WOW)) # перебираем ключи реестра, в которых производится поиск
{
	$Items = $srp.EnumKey($HKLM,$key).sNames;
	foreach ($item in $Items) # перебираем все найденные ключи
	{
		# пропускаем пустые записи для DisplayName
		if (!($srp.GetStringValue($HKLM,$key+$item,"DisplayName").sValue)) {continue;}
		$TEMP = @{};
		foreach ($parameter in $PARAMETERS) # поиск производим по необходимым параметрам
		{            
			$val = $srp.GetStringValue($HKLM,$key+$item,$parameter).sValue;
			if ($val -match "\d{8}") {$val = ReadableDate($val);}
			if ($val) 
				{ $TEMP[$parameter] = $val; }
			else
				{ $TEMP[$parameter] = ""; }
		}
		# вносим значения в динамический массив
		$RECORDS += $TEMP;
	}
}
# обязательно сортируем: на этом основан дальнейший алгоритм
$SORTED_RECORDS = $RECORDS | Sort-Object;
$arrUnqRecords = @();	# массив с уникальными значениями
$matchFound = $false;	# флаг - найдено совпадение
for ($i = 0; $i -lt $SORTED_RECORDS.Count-1; $i++) 
{
	# если перед этим было совпадение, пропускаем шаг
	if($matchFound -eq $true){$matchFound = $false; continue;}
	# сравниваем текущее значение с последующим.
	# при наличии совпадения - объединяем "по-максимуму" значения
	$t = $i+1;
	if ($SORTED_RECORDS[$i]['DisplayName'] -eq $SORTED_RECORDS[$t]['DisplayName'])
	{
		$matchFound = $true;
		$softName = $SORTED_RECORDS[$t]['DisplayName'];
		if ($SORTED_RECORDS[$t]['ParentKeyName'].Length -ge $SORTED_RECORDS[$i]['ParentKeyName'].Length) {$softParent = $SORTED_RECORDS[$t]['ParentKeyName']}
		else {$softParent = $SORTED_RECORDS[$i]['ParentKeyName']}
		if ($SORTED_RECORDS[$t]['InstallDate'].Length -ge $SORTED_RECORDS[$i]['InstallDate'].Length) {$softInstallDate = $SORTED_RECORDS[$t]['InstallDate']}
		else {$softInstallDate = $SORTED_RECORDS[$i]['InstallDate']}
		if ($SORTED_RECORDS[$t]['Publisher'].Length -ge $SORTED_RECORDS[$i]['Publisher'].Length) {$softManufacturer = $SORTED_RECORDS[$t]['Publisher']}
		else {$softManufacturer = $SORTED_RECORDS[$i]['Publisher']}
		if ($SORTED_RECORDS[$t]['DisplayVersion'].Length -ge $SORTED_RECORDS[$i]['DisplayVersion'].Length) {$softVersion = $SORTED_RECORDS[$t]['DisplayVersion']}
		else {$softVersion = $SORTED_RECORDS[$i]['DisplayVersion']}
		# заполняем массив уникальными значениями
		$arrUnqRecords += @{'DisplayName'=$softName;'ParentKeyName'=$softParent;'InstallDate'=$softInstallDate;'Publisher'=$softManufacturer;'DisplayVersion'=$softVersion};
	} else {
		$arrUnqRecords += $SORTED_RECORDS[$i];
	}
}
# анализируем последний элемент массива
if($matchFound -ne $true){$arrUnqRecords += $SORTED_RECORDS[$i];}
	
# генерируем SQL запросы
foreach ($record in $arrUnqRecords )
{
	$install_date = $NULL;
	if ($record['InstallDate'].Length -eq 10) {		
		$install_date = Get-Date -Date $record['InstallDate'] -Format $DATE_FORMAT;
	}
	$SQL_cmd += "
		IF EXISTS (SELECT id FROM dbo.Software WHERE hostID='{0}' AND vendor='{2}' AND name='{3}' AND parent='{4}' AND version='{5}' AND install_date='{6}')
			UPDATE dbo.Software SET upd_datetime='{1}' WHERE hostID='{0}' AND vendor='{2}' AND name='{3}' AND parent='{4}' AND version='{5}' AND install_date='{6}'
		ELSE 
			INSERT INTO dbo.Software (hostID, upd_datetime, vendor, name, parent, version, install_date) 
			VALUES ('{0}','{1}','{2}','{3}','{4}','{5}','{6}')" -f $HOSTNAME, $DateTime, $record['Publisher'].Trim(), $record['DisplayName'].Trim(), $record['ParentKeyName'].Trim(), $record['DisplayVersion'].Trim(), $install_date;
}							

# внесение информации в БД
#-------------------------------------------------------------------------------------	
$cmd = New-Object System.Data.SqlClient.SqlCommand;
# строка подлючения к SQL серверу
$connectionString = "Server=$SERVER;Database=$DATABASE;User id=$USER;Password=$PWD;";
$connection = SQLconnect ($connectionString);
$cmd.connection = $connection;
$cmd.CommandText = $SQL_cmd;
[void]$cmd.ExecuteNonQuery();
#foreach ($sql in $SQL_cmd)
#{
#	$cmd.CommandText = $sql;
#	[void]$cmd.ExecuteNonQuery();
#}
}).TotalSeconds;	# конец времени выполнения

# внесение информации в БД о времени выполнения
#-------------------------------------------------------------------------------------
# получение информации о разделителе в числах с плавающей точкой
$nfi = (new-object System.Globalization.CultureInfo "en-US", $false).NumberFormat;
$RunTime = $RunTimeGetWMI.ToString("G", $nfi);
# работа с БД
$cmd.CommandText = "INSERT INTO dbo.RunTime (hostID, upd_datetime, category, runtime) VALUES ('{0}','{1}','{2}','{3}')" -f $HOSTNAME, $DateTime, "software", $RunTime;
[void]$cmd.ExecuteNonQuery();
# отключаемся от БД
SQLdisconnect ($connection);