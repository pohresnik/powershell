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
	$wmiSetting = Get-WmiObject -Query "Select BuildVersion From Win32_WMISetting" -ErrorAction SilentlyContinue;
	return [int]$wmiSetting.BuildVersion.substring(0,4)
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
# поиск самой свежей даты создания
$startDate = $Today;
$cmd.CommandText = "SELECT TOP 1 created_datetime FROM dbo.Events WHERE hostID = '{0}' ORDER BY id DESC" -f $HOSTNAME;
$Reader = $cmd.ExecuteReader();
while ($Reader.Read()) {
	$startDate = $Reader.GetValue(0)
}
$Reader.Close();

# Удаляем старые (больше месяца) записи
$DelDate = ([datetime]::ParseExact($strDateTime, $DATETIME_FORMAT, $null)).AddMonths(-1);
$cmd.CommandText = "DELETE FROM dbo.Events WHERE created_datetime < '{0}' AND hostID = '{1}'" -f $DelDate, $HOSTNAME;
$cmd.ExecuteNonQuery();	
	
# узнаем версию WMI-сервера
$build = BuildVersion;
if ($build -le 2600) {	# для старых версий Windows
	$Events = Get-EventLog -LogName System -after $startDate -EntryType Error,FailureAudit,Warning -Computername $HOSTNAME -ErrorAction SilentlyContinue | Sort Time; 
} else { # для новых версий Windows
	$Events = Get-WinEvent -FilterHashTable @{LogName='System'; StartTime=$startDate;} -Computername $HOSTNAME -ErrorAction SilentlyContinue | Select-Object –Property MachineName,TimeCreated,Id,Message,ProviderName,Level,LevelDisplayName | Where {$_.Level -ne 4} | Sort TimeCreated;
}
#-------------------------------------------------------------------------------------	
if ($Events -AND $Events.Count -ge 0 -AND $build -gt 2600)
{
	foreach ($event in $Events){
		$created_datetime = Get-Date($event.TimeCreated) -f $DATETIME_FORMAT;
		$created_datetime = [datetime]::ParseExact($created_datetime, $DATETIME_FORMAT, $null);
        #++++++++++++++++++++
		# нам нужно значение $event.Level # 1 - win:Critical; 2 - win:Error; 3 - win:Warning; 4 - win:Informational; 0 - win:default-Verbose
        switch ($event.Level)
		{
			1 {$eventLevel = 'Critical'}
			2 {$eventLevel = 'Error'}
			3 {$eventLevel = 'Warning'}
			4 {$eventLevel = 'Informational'}
			default {$eventLevel = 'default-Verbose'} 
		}
        #++++++++++++++++++++
        if( $created_datetime -ne $startDate ) {
            $cmd.CommandText = "INSERT INTO  dbo.Events (hostID, upd_datetime, created_datetime, level, message, provider, code) 
										VALUES ('{0}','{1}','{2}','{3}','{4}','{5}','{6}')" -f $HOSTNAME,$strDateTime,$created_datetime,$eventLevel,$event.Message,$event.ProviderName,$event.Id;
		    $cmd.ExecuteNonQuery();
		}        
	}
}
elseif ($Events -AND $Events.Count -ge 0 -AND $build -le 2600)
{
	foreach ($event in $Events){
		$created_datetime = (Get-Date($event.TimeCreated) -f $DATETIME_FORMAT);
        $created_datetime = [datetime]::ParseExact($created_datetime, $DATETIME_FORMAT, $null);
		#++++++++++++++++++++
		switch ($event.EntryType)
		{
			"FailureAudit"{$eventLevel = 'Critical'}
			"Error"{$eventLevel = 'Error'}
			"Warning"{$eventLevel = 'Warning'}
			"Information"{$eventLevel = 'Informational'}
			"SuccessAudit"{$eventLevel = 'Informational'}
			default {$eventLevel = 'default-Verbose'} 
		}
        #++++++++++++++++++++
        if( $created_datetime -ne $startDate ) {
            $cmd.CommandText = "INSERT INTO  dbo.Events (hostID, upd_datetime, created_datetime, level, message, provider, code) 
										VALUES ('{0}','{1}','{2}','{3}','{4}','{5}','{6}')" -f $HOSTNAME,$strDateTime,$created_datetime,$eventLevel,$event.Message,$event.ProviderName,$event.Id;
		    $cmd.ExecuteNonQuery();
        }        
	}				
}
#-------------------------------------------------------------------------------------
}).TotalSeconds;	# конец времени выполнения

# получение информации о разделителе в числах с плавающей точкой
$nfi = (new-object System.Globalization.CultureInfo "en-US", $false ).NumberFormat;
$RunTime = $RunTimeGetWMI.ToString("G", $nfi);
# работа с БД
$cmd.CommandText = "INSERT INTO dbo.RunTime (hostID, upd_datetime, category, runtime) VALUES ('{0}','{1}','{2}','{3}')" -f $HOSTNAME,$strDateTime,"event",$RunTime;
[void]$cmd.ExecuteNonQuery();
# отключаемся от БД
SQLdisconnect ($connection);