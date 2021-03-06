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
# События за последние $MAX_DAYS_HISTORY дней
$MAX_DAYS_HISTORY = 14;
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

$RunTimeGetWMI = (Measure-Command {	# замеряем время выполнения
########################################################################### ВЫПОЛНЕНИЕ
# генерируем метку времени
$strDateTime = [string](Get-Date -f $DATETIME_FORMAT);
$Today = Get-Date -Format d;
$startDate = (Get-Date).AddDays((-1*$MAX_DAYS_HISTORY));
# узнаем имя локального компьютера
$HOSTNAME = $env:computername;
#-------------------------------------------------------------------------------------	
$cmd = New-Object System.Data.SqlClient.SqlCommand;
# строка подлючения к SQL серверу
$connectionString = "Server=$SERVER;Database=$DATABASE;User id=$USER;Password=$PWD;";
$connection = SQLconnect ($connectionString);
$cmd.connection = $connection;

# определяем глобальный массив, в который будем добавлять 
# SQL запросы для дальнейшего использования
$SQL_cmd = @();

# Удаляем старые (больше недели) записи
#

# узнаем версию WMI-сервера
$build = BuildVersion;
#-------------------------------------------------------------------------------------	
if ($build -le 2600) {	# для старых версий Windows
	# 
	#
}
#-------------------------------------------------------------------------------------	
else { # для новых версий Windows
	$LogFilter = @{
		LogName = 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'
		ID = 21, 23, 24, 25
		StartTime = $startDate
	}
	$AllEntries = Get-WinEvent -FilterHashtable $LogFilter -ComputerName $HOSTNAME `
		-ErrorAction SilentlyContinue  | Sort TimeCreated;;
	
	$Output = @{}
	$AllEntries | Foreach {
		$entry = [xml]$_.ToXml();
		$SQL_cmd += "
			IF EXISTS (SELECT [upd_datetime] FROM dbo.Sessions 
					WHERE [hostID]='{0}' AND [created_datetime]='{2}' AND [user]='{3}' AND 
						[ip]='{4}' AND [session_id]='{5}' AND [event_id]='{6}' AND [message]='{7}')
				UPDATE dbo.Sessions SET [upd_datetime]='{1}' 
					WHERE [hostID]='{0}' AND [created_datetime]='{2}' AND [user]='{3}' AND 
						[ip]='{4}' AND [session_id]='{5}' AND [event_id]='{6}' AND [message]='{7}'
			ELSE 
				INSERT INTO dbo.Sessions 
					([hostID],[upd_datetime],[created_datetime],[user],[ip],[session_id],[event_id],[message]) 
				VALUES ('{0}','{1}','{2}','{3}','{4}','{5}','{6}','{7}')
			" -f `
				$HOSTNAME,
				$strDateTime,
				$_.TimeCreated,
				$entry.Event.UserData.EventXML.User,
				$entry.Event.UserData.EventXML.Address,
				$entry.Event.UserData.EventXML.SessionID,
				$entry.Event.System.EventID,
				$_.Message; 
	}
	
	#if ($_.EventID -eq '21'){"Logon"}
	#if ($_.EventID -eq '22'){"Shell start"}
	#if ($_.EventID -eq '23'){"Logoff"}
	#if ($_.EventID -eq '24'){"RDS disconnected"}
	#if ($_.EventID -eq '25'){"RDS reconnection"}
}
#-------------------------------------------------------------------------------------
if ($SQL_cmd) {
	$cmd.CommandText = $SQL_cmd;
	[void]$cmd.ExecuteNonQuery();
}
}).TotalSeconds;	# конец времени выполнения

# получение информации о разделителе в числах с плавающей точкой
$nfi = (new-object System.Globalization.CultureInfo "en-US", $false ).NumberFormat;
$RunTime = $RunTimeGetWMI.ToString("G", $nfi);
# работа с БД
$cmd.CommandText = "INSERT INTO dbo.RunTime (hostID, upd_datetime, category, runtime) VALUES ('{0}','{1}','{2}','{3}')" -f $HOSTNAME,$strDateTime,"sessions",$RunTime;
[void]$cmd.ExecuteNonQuery();
# отключаемся от БД
SQLdisconnect ($connection);