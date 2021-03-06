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
$MAX_DAYS_HISTORY = 90;
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
	
# поиск самой свежей даты создания
#$cmd.CommandText = "SELECT TOP 1 created_datetime FROM dbo.PrintService WHERE hostID = '{0}' ORDER BY id DESC" -f $HOSTNAME;
#$Reader = $cmd.ExecuteReader();
#while ($Reader.Read()) {
#	if ($Reader.GetValue(0)) { $startDate = $Reader.GetValue(0); }
#}
#$Reader.Close();

# определяем глобальный массив, в который будем добавлять 
# SQL запросы для дальнейшего использования
$SQL_cmd = @();

# Удаляем старые (больше недели) записи
$DelDate = ([datetime]::ParseExact($strDateTime, $DATETIME_FORMAT, $null)).AddDays((-1*$MAX_DAYS_HISTORY));
$SQL_cmd += "DELETE FROM dbo.PrintService WHERE created_datetime < '{0}' AND hostID = '{1}'" -f $DelDate, $HOSTNAME;

# узнаем версию WMI-сервера
$build = BuildVersion;
#-------------------------------------------------------------------------------------	
if ($build -le 2600) {	# для старых версий Windows
	# 
	#
} 
#-------------------------------------------------------------------------------------	
else { # для новых версий Windows
	$PrintEntries = Get-WinEvent -FilterHashTable @{LogName="Microsoft-Windows-PrintService/Operational"; ID=307; StartTime=$startDate;} `
		-Computername $HOSTNAME -ErrorAction SilentlyContinue | Sort TimeCreated;
	if ($PrintEntries.Count -ge 0)
	{
		foreach ($event in $PrintEntries){
			$queue_name = '';
		    $document_name = '';
		    $user = '';
		    $hostID = '';
		    $printer = '';
		    $port = '';
		    $document_size = '';
		    $document_pages = '';
		    $message = $event.Message;
			
			if ( (Get-WmiObject -ComputerName $HOSTNAME Win32_OperatingSystem).OSLanguage -eq 1049 ) {
				$isParse = $event.Message -match "^\s*(?<Queue>.*),\s*(?<Document>.*),\s*которым владеет\s*(?<User>.*)\s*на\s*\\*(?<Client>.*),\s*был распечатан на\s*(?<Printer>.*)\s*через порт\s*(?<Port>.*)\s*\.\s*Размер в байтах:\s*(?<Size>\d*)\s*\.\s*Страниц напечатано:\s*(?<Pages>\d*)\s*\.\s*(?<Notes>.*)\s*\.\s*$"; }
			else {
				$isParse = $event.Message -match "^\s*(?<Queue>.*),\s*(?<Document>.*)\s*owned by\s*(?<User>.*)\s*on\s*(?<Client>.*)\s*was printed on\s*(?<Printer>.*)\s*through port\s*(?<Port>.*)\s*\.\s*Size in bytes:\s*(?<Size>\d*)\s*\.\s*Pages printed:\s*(?<Pages>\d*)\s*\.\s*(?<Notes>.*)\s*\.\s*$";
			}
			if($isParse) {
				$queue_name = $Matches.Queue;
			    $document_name = $Matches.Document;
			    $user = $Matches.User;
			    $hostID = $Matches.Client;
			    $printer = $Matches.Printer;
				ForEach ($hkcuPrinter in (Get-ChildItem -Path 'HKCU:\Printers\Connections' -ErrorAction SilentlyContinue)) {
					$data = $hkcuPrinter | Get-ItemProperty -Name GuidPrinter -ErrorAction SilentlyContinue;
					if ($data.GuidPrinter -eq $printer) {$printer = $data.PSChildName.Replace(',','\');}
				}
			    $port = $Matches.Port;
			    $document_size = $Matches.Size;
			    $document_pages = $Matches.Pages;
			    $message = $Matches.Notes;
			}
	
			$created_datetime = Get-Date($event.TimeCreated) -f $DATETIME_FORMAT;
			$created_datetime = [datetime]::ParseExact($created_datetime, $DATETIME_FORMAT, $null);

	        if( $created_datetime -gt $startDate ) {
	            $SQL_cmd += "
					IF EXISTS (SELECT [upd_datetime] FROM dbo.PrintService 
							WHERE [hostID]='{0}' AND [created_datetime]='{2}' AND [queue_name]='{6}' AND [message]='{10}' AND 
								[document_name]='{7}' AND [document_pages]='{8}' AND [document_size]='{9}')
						UPDATE dbo.PrintService SET [upd_datetime]='{1}' 
							WHERE [hostID]='{0}' AND [created_datetime]='{2}' AND [queue_name]='{6}' AND [message]='{10}' AND 
								[document_name]='{7}' AND [document_pages]='{8}' AND [document_size]='{9}'
					ELSE 
						INSERT INTO dbo.PrintService 
							([hostID], [upd_datetime], [created_datetime], [user], [printer], [port], [queue_name], [document_name], [document_pages], [document_size], [message]) 
						VALUES ('{0}','{1}','{2}','{3}','{4}','{5}','{6}','{7}','{8}','{9}','{10}')
					" -f $HOSTNAME,$strDateTime,$created_datetime,$user,$printer,$port,$queue_name,$document_name,$document_pages,$document_size,$message;
			}        
		}
	}
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
$cmd.CommandText = "INSERT INTO dbo.RunTime (hostID, upd_datetime, category, runtime) VALUES ('{0}','{1}','{2}','{3}')" -f $HOSTNAME,$strDateTime,"printservice",$RunTime;
[void]$cmd.ExecuteNonQuery();
# отключаемся от БД
SQLdisconnect ($connection);