# Сбор информации о производительности серверов
# средствами PowerShell (09.05.2013)
# Данные выводятся в формате html
# Автор: Похресник Д.А.

##################################################################################  НАСТРОЙКИ
# список серверов
$SERVERS = "dc1", "dc2", "database", "appsrv", "1c", "pbx", "intranet";
# Формат даты/времени: dd - день (2 цифры), MM - месяц (2 цифры), yyyy - год (4 цифры),
# HH - час (24 часовой формат), mm - минуты (2 цифры), ss - секунды (2 цифры)
$DT_FORMAT = "dd.MM.yyyy HH:mm:ss";
$ReportDate = Get-Date -UFormat "%d-%m-%y";
# всего выборок
$MAX_SAMPLES = 10;
# количество секунд между выборками
$SAMPLE_INTERVAL = 3;
#--------------------------------------------------------------------------------------------
$PERFORMANCE_COUNTER_SET_RU =
"\Сведения о процессоре(_total)\% загруженности процессора",	# общая загрузка процессора
"\Процессор(_total)\Процент времени бездействия",				# процент времени бездействия
"\Память\Байт выделенной виртуальной памяти",					# всего используется памяти
"\Память\Байт свободной памяти и обнуленных страниц памяти",	# свободно физической памяти
"\Память\Доступно байт",										# доступной памяти
"\Файл подкачки(_total)\% использования",						# процент использования файла подкачки
"\Физический диск(_total)\% активности диска";					# процент активности жесткого диска
#--------------------------------------------------------------------------------------------
$PERFORMANCE_COUNTER_SET_EN =
"\Processor(_Total)\% Processor Time",		# общая загрузка процессора
"\Processor(_Total)\% Idle Time",			# процент времени бездействия
"\Memory\Committed Bytes",					# всего используется памяти
"\Memory\Free & Zero Page List Bytes",		# свободно физической памяти
"\Memory\Available Bytes",					# доступной памяти
"\Paging File(_Total)\% Usage",				# процент использования файла подкачки
"\PhysicalDisk(_Total)\% Disk Time";		# процент активности жесткого диска
#--------------------------------------------------------------------------------------------
$PERFORMANCE_COUNTER_SET_NUMERICAL =
"\238(_Total)\6",							# общая загрузка процессора
"\Processor(_Total)\% Idle Time",			# процент времени бездействия
"\Memory\Committed Bytes",					# всего используется памяти
"\Memory\Free & Zero Page List Bytes",		# свободно физической памяти
"\Memory\Available Bytes",					# доступной памяти
"\Paging File(_Total)\% Usage",				# процент использования файла подкачки
"\PhysicalDisk(_Total)\% Disk Time";		# процент активности жесткого диска
#--------------------------------------------------------------------------------------------
$USE_LOG_FILE = $false;
$ReportFolder = 'C:\_REPORTS_\';
$PATH_TO_LOG_FILE = $ReportFolder+'SRVperform-'+$ReportDate+'.html';
#--------------------------------------------------------------------------------------------
$USE_MAIL = $true;
$MAIL_SERVER = "mail.example.com";
$MAIL_TO = "it@example.com";
$MAIL_FROM = "service-info@example.com";
$MAIL_SUBJECT = "Производительность серверов";
$MAIL_LOGIN = "service-info@example.com";
$MAIL_PASSWORD = "secretpassword";
#--------------------------------------------------------------------------------------------
$CrLf = [char]13+[char]10;	# перевод каретки
#############################################################################################

#============================================================================================
# Проверка доступности сервера в сети. Возвращает TRUE, если НЕ доступен.
function IsNotAvailable($server)
{
	$AddrIP_Name = "Address='$server'";
	try{
		$ping = Get-WmiObject Win32_PingStatus -Filter $AddrIP_Name;
		if ($ping.StatusCode -ne 0) {return $true;}
		else {return $false;}
	}catch{
		return $true;
	}		
}
#--------------------------------------------------------------------------------------------
# Время безотказной работы
# Формат: dd дней HH часов mm минут (c dd.MM.yyyy HH:mm)
function UpTimeMachine($server)
{
	try{
		$wmi = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $server;
		$LastBootUpTime = $wmi.ConvertToDateTime($wmi.LastBootUpTime);
		$LastUptime = $wmi.ConvertToDateTime($wmi.LocalDateTime) – $LastBootUpTime;
		return [string]($LastUptime.Days.ToString()+' дней '+$LastUptime.Hours.ToString()+' часов '+$LastUptime.Minutes.ToString()+' минут (c '+$LastBootUpTime.ToString($DT_FORMAT)+')');
	}catch{
		return '<span class="critical">Ошибка получения данных. Причина: '+$error[0]+'</span>';
	}
}
#============================================================================================

################################################################################## ВЫПОЛНЕНИЕ
#--------------------------------------------------------------------------------------------
# Создаем HTML
$outHTML = "";
$outHTML += '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">'+$CrLf;
$outHTML += '<html>'+$CrLf;
$outHTML += '<head>'+$CrLf;
$outHTML += '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">'+$CrLf;
$outHTML += '<title>Отчет. Производительность серверов</title>'+$CrLf;
$outHTML += '<style type="text/css">'+$CrLf;
$outHTML += 'TABLE{width:100%; border-width:1px; border-style:solid; border-color:black; border-collapse:collapse; margin:0 auto;}'+$CrLf;
$outHTML += 'TH{border-width:1px; padding:2px 4px; border-style:solid; border-color:black; background-color:#4D81BE; color:WhiteSmoke}'+$CrLf;
$outHTML += 'TD{border-width:1px; padding:2px 4px; border-style:solid; border-color:black;}'+$CrLf;
$outHTML += '.ok{background:greenyellow;}'+$CrLf;
$outHTML += '.warning{background:yellow;}'+$CrLf;
$outHTML += '.critical{background:lightpink;}'+$CrLf;
$outHTML += '.greystring{background:lightgrey;}'+$CrLf;
$outHTML += '</style>'+$CrLf;
$outHTML += '</head>'+$CrLf;
$outHTML += '<body>'+$CrLf;
$outHTML += '<H2>Состояние серверов (всего серверов: '+($SERVERS.Length)+')</H2>'+$CrLf;
$outHTML += '<H3>Отчет создан: '+(Get-Date -Format $DT_FORMAT)+'</H3>'+$CrLf;
$outHTML += '<H3>Количество выборок: '+$MAX_SAMPLES+' с интервалом '+$SAMPLE_INTERVAL+' сек.</H3>'+$CrLf;
$outHTML += '<hr>'+$CrLf;
#--------------------------------------------------------------------------------------------
foreach ($Server in $SERVERS){	
	#Write-Host $Server;
	$OSCaption = "undefined";
	$OSLanguage = "undefined";
	$OS = Get-WmiObject -ComputerName $Server -Class Win32_OperatingSystem -Property "Caption","OSLanguage";
	$OSCaption = $OS.Caption;
	switch ($OS.OSLanguage)
	{
		"1033"{$OSLanguage = "English – United States"; $PERFORMANCE_COUNTER_SET = $PERFORMANCE_COUNTER_SET_EN; break;}
		"2057"{$OSLanguage = "English – United Kingdom"; $PERFORMANCE_COUNTER_SET = $PERFORMANCE_COUNTER_SET_EN; break;}
		"1049"{$OSLanguage = "Russian"; $PERFORMANCE_COUNTER_SET = $PERFORMANCE_COUNTER_SET_RU; break;}
		default {$OSLanguage = "Other"; $PERFORMANCE_COUNTER_SET = $PERFORMANCE_COUNTER_SET_NUMERICAL;}
	}
	$outHTML += '<H3>Выбранный сервер: '+($Server.ToUpper())+' ('+$OSCaption+') ['+$OSLanguage+']</H3>'+$CrLf;
	# Проверка на доступность сервера (должны быть разрешены пинги)
	if (IsNotAvailable $Server) {
		$outHTML += '<H4 class="critical">Сервер недоступен</H4>'+$CrLf;
		$outHTML += '<hr>'+$CrLf;
		continue;
	}	
	$outHTML += '<H4>Время безотказной работы сервера: <span class="greystring">'+(UpTimeMachine ($Server))+'</span></H4>'+$CrLf;
	#----------------------------------------------------------------------------------------
	# Объем выделенной оперативной памяти
	try {
		$TotalPhysicalMemory = (Get-WmiObject -ComputerName $Server -Class Win32_ComputerSystem -Property TotalPhysicalMemory).TotalPhysicalMemory;
		$outHTML += '<H4>Объем выделенной оперативной памяти: <span class="ok">'+([int]($TotalPhysicalMemory/1Mb))+' Мб</span></H4>'+$CrLf;
	} catch {
		$outHTML += '<H4>Объем выделенной оперативной памяти: <span class="critical">Ошибка получения данных. Причина: '+$error[0]+'</span></H4>'+$CrLf;
	}
	#----------------------------------------------------------------------------------------
	# Объем используемого пространства хранения
	try {
		$LogicalDrives = Get-WmiObject -ComputerName $Server -Class Win32_LogicalDisk -filter "DriveType=3";
		$outHTML += '<H4>Объем используемого пространства хранения:</H4>'+$CrLf;
		if ($LogicalDrives)
		{
			$outHTML += '<table>'+$CrLf;
			$outHTML += '<tr align="center"><th>Диск</th><th>Всего, Гб</th><th>Свободно, Гб</th><th>Свободно, %</th><th>Занято, Гб</th><th>Занято, %</th></tr>'+$CrLf;
			foreach ($LogicalDisk in $LogicalDrives)
			{
				$freeSize = "{0:n1}" -f ($LogicalDisk.freespace/1gb);
				$fullSize = "{0:n1}" -f ($LogicalDisk.size/1gb);
				$percentFree =  ($LogicalDisk.freespace/$LogicalDisk.size)*100;
				$percentFull = (100 - $percentFree);
				$percentFull = "{0:n1}%" -f $percentFull;
				$percentFree = "{0:n1}%" -f $percentFree;	
				if ($percentFull -le 50) {$tdStyle = "ok"}
				elseif ($percentFull -gt 50 -and $percentFull -le 85) {$tdStyle = "warning"}
				else {$tdStyle = "critical"}
				
				$outHTML += '<tr align="right"><td align="left">'+$LogicalDisk.DeviceID+' ('+$LogicalDisk.VolumeName+')'+'</td><td>'+$fullSize+'</td><td>'+$freeSize+'</td><td>'+$percentFree+'</td><td>'+('{0:n1}' -f (($LogicalDisk.size-$LogicalDisk.freespace)/1gb))+'</td><td class="'+$tdStyle+'">'+$percentFull+'</td></tr>'+$CrLf;
			}
			$outHTML += '</table>'+$CrLf;
		}
		else { $outHTML += '<div>Неправильно указан диск</br></div>'+$CrLf;}
	} catch {
		$outHTML += '<H4>Объем используемого пространства хранения: <span class="critical">Ошибка получения данных. Причина: '+$error[0]+'</span></H4>'+$CrLf;
	}	
	$outHTML += '<br>'+$CrLf;
	#----------------------------------------------------------------------------------------
	# Таблица производительности
	$outHTML += '<table>'+$CrLf;
	$outHTML += '<tr><th>Счетчик</th><th>Значение</th></tr>'+$CrLf;	
	
	foreach ($counter in $PERFORMANCE_COUNTER_SET)
	{
		#Write-Host $counter;
		try {
			$Result = Get-Counter -ComputerName $Server -Counter $counter -SampleInterval $SAMPLE_INTERVAL –MaxSamples $MAX_SAMPLES;
			$values = @();	
			foreach ($record in $Result) {
				$values += ($record.CounterSamples | Select-Object -Property CookedValue);
			}
			$Avg = ($values | Measure-Object -Property CookedValue -Average);
			# округление для России: округлять до большего, отличного от нуля. 2 значащих цифры после запятой
			$AverageValue = [System.Math]::Round($Avg.Average, 2, [System.MidPointRounding]::AwayFromZero);		
			
			switch ($counter)
			{
				$PERFORMANCE_COUNTER_SET[0]{
					$outHTML += '<tr align="left"><td>Общая загруженность CPU</td><td>'+$AverageValue+'%</td></tr>'+$CrLf; 
					break;
				}
				$PERFORMANCE_COUNTER_SET[1]{
					$outHTML += '<tr align="left"><td>Бездействие CPU</td><td>'+$AverageValue+'%</td></tr>'+$CrLf; 
					break;
				}
				$PERFORMANCE_COUNTER_SET[2]{
					$outHTML += '<tr align="left"><td>Всего используется памяти</td><td>'+([int]($AverageValue/1Mb))+' Мб</td></tr>'+$CrLf; 
					break;
				}
				$PERFORMANCE_COUNTER_SET[3]{
					$outHTML += '<tr align="left"><td>Свободно физической памяти</td><td>'+([int]($AverageValue/1Mb))+' Мб</td></tr>'+$CrLf; 
					break;
				}
				$PERFORMANCE_COUNTER_SET[4]{
					$outHTML += '<tr align="left"><td>Доступно памяти</td><td>'+([int]($AverageValue/1Mb))+' Мб</td></tr>'+$CrLf;
					break;
				}
				$PERFORMANCE_COUNTER_SET[5]{
					$outHTML += '<tr align="left"><td>Использование файла подкачки</td><td>'+$AverageValue+'%</td></tr>'+$CrLf; 
					break;
				}
				$PERFORMANCE_COUNTER_SET[6]{
					$outHTML += '<tr align="left"><td>Активность HDD</td><td>'+$AverageValue+'%</td></tr>'+$CrLf;
					break;
				}
				default {$outHTML += '<tr align="left"><td>'+$counter+'</td><td>'+$AverageValue+'</td></tr>'+$CrLf;}
			}	
		} catch {
			$outHTML += '<tr align="left" class="critical"><td>'+$counter+'</td><td>Ошибка получения данных. Причина: '+$error[0]+'</td></tr>'+$CrLf;
			continue;
		}			
	}	
	$outHTML += '</table>'+$CrLf;
	#----------------------------------------------------------------------------------------
	# разделитель
	$outHTML += '<hr>'+$CrLf;
}
#--------------------------------------------------------------------------------------------
$outHTML += '</body>'+$CrLf+'</html>'+$CrLf;
# сохраняем в файл, если нужно
if ($USE_LOG_FILE) { 
	if(!(Test-Path $ReportFolder)){New-Item -ItemType Directory -Force -Path $ReportFolder | Out-Null}
	$outHTML | Out-File -FilePath $PATH_TO_LOG_FILE -Force; 
}
# отправляем письмо, если нужно
if ($USE_MAIL) { 
	$CRED = New-Object System.Management.Automation.PSCredential($MAIL_LOGIN, (ConvertTo-SecureString $MAIL_PASSWORD -AsPlainText -Force));
	Send-MailMessage -SmtpServer $MAIL_SERVER -To $MAIL_TO -From $MAIL_FROM -Subject $MAIL_SUBJECT -BodyAsHTML -body $outHTML -Encoding ([System.Text.Encoding]::UTF8) -useSSL -Credential $CRED -Priority High; 
}