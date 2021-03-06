# Сбор информации о важных событиях на серверах
# средствами PowerShell (08.05.2013)
# Данные выводятся в формате html
# Автор: Похресник Д.А.

##################################################################################  НАСТРОЙКИ
# список серверов
$SERVERS = "dc1", "dc2", "database", "appsrv", "1c", "pbx", "intranet";
# Формат даты/времени: dd - день (2 цифры), MM - месяц (2 цифры), yyyy - год (4 цифры),
# HH - час (24 часовой формат), mm - минуты (2 цифры), ss - секунды (2 цифры)
$DT_FORMAT = "dd.MM.yyyy HH:mm:ss";
$ReportDate = Get-Date -UFormat "%d-%m-%y";
# за какое количество дней считывать логи
$COUNT_DAYS = 1;
#--------------------------------------------------------------------------------------------
$USE_LOG_FILE = $false;
$ReportFolder = 'C:\_REPORTS_\';
$PATH_TO_LOG_FILE = $ReportFolder+'SRVerrors-'+$ReportDate+'.html';
#--------------------------------------------------------------------------------------------
$USE_MAIL = $true;
$MAIL_SERVER = "mail.example.com";
$MAIL_TO = "it@example.com";
$MAIL_FROM = "service-info@example.com";
$MAIL_SUBJECT = "Важные события на серверах";
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
		$ping = Get-WmiObject Win32_PingStatus -Filter $AddrIP_Name -ErrorAction SilentlyContinue;
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
		$wmi = Get-WmiObject -Class Win32_OperatingSystem -ComputerName $server -ErrorAction SilentlyContinue;
		$LastBootUpTime = $wmi.ConvertToDateTime($wmi.LastBootUpTime);
		$LastUptime = $wmi.ConvertToDateTime($wmi.LocalDateTime) – $LastBootUpTime;
		return [string](	$LastUptime.Days.ToString() + ' дней ' + 
							$LastUptime.Hours.ToString() + ' часов ' +  
							$LastUptime.Minutes.ToString() + ' минут (c ' + $LastBootUpTime.ToString($DT_FORMAT) + ')'
						);
	}catch{
		return "Ошибка получения данных";
	}
}
#============================================================================================

################################################################################## ВЫПОЛНЕНИЕ
# установка дат
$StartTime = (Get-Date).AddDays(-($COUNT_DAYS));
$today = Get-Date;
#--------------------------------------------------------------------------------------------
# Создаем HTML
$outHTML = "";
$outHTML += '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">'+$CrLf;
$outHTML += '<html>'+$CrLf;
$outHTML += '<head>'+$CrLf;
$outHTML += '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">'+$CrLf;
$outHTML += '<title>Отчет. LOG-Статистика за дней: '+$COUNT_DAYS+'</title>'+$CrLf;
$outHTML += '<style type="text/css">'+$CrLf;
$outHTML += 'BODY{font-size:62.5%;}'+$CrLf;
$outHTML += 'TABLE{width:100%; border-width:1px; border-style:solid; border-color:black; border-collapse:collapse; margin:0 auto;}'+$CrLf;
$outHTML += 'TH{border-width:1px; padding:2px 4px; border-style:solid; border-color:black; background-color:#4D81BE; color:WhiteSmoke}'+$CrLf;
$outHTML += 'TD{border-width:1px; padding:2px 4px; border-style:solid; border-color:black;}'+$CrLf;
$outHTML += '.ok{background:greenyellow;}'+$CrLf;
$outHTML += '.warning{background:yellow;}'+$CrLf;
$outHTML += '.error{background:lightpink;}'+$CrLf;
$outHTML += '.critical{background:red;}'+$CrLf;
$outHTML += '.greystring{background:lightgrey;}'+$CrLf;
$outHTML += '</style>'+$CrLf;
$outHTML += '</head>'+$CrLf;
$outHTML += '<body>'+$CrLf;
$outHTML += '<H2>Состояние серверов за дней: '+$COUNT_DAYS+'<br>(всего серверов: '+($SERVERS.Length)+')</H2>'+$CrLf;
$outHTML += '<H3>Отчет создан: '+(Get-Date -Format $DT_FORMAT)+'</H3>'+$CrLf;
$outHTML += '<hr>'+$CrLf;
#--------------------------------------------------------------------------------------------
foreach ($Server in $SERVERS){
	# Write-Host $Server -ForegroundColor DarkGreen;
	# Удаляем/очищаем переменную для каждой итерации
	Remove-Variable -Name Events -Force -ErrorAction SilentlyContinue;	
	# Заглавные буквы для серверов
	$Server = $Server.ToUpper();
	# Проверка на доступность сервера (должны быть разрешены пинги)
	if (IsNotAvailable $Server) {
		$outHTML += '<H4>'+$Server+' (всего важных событий: ?)</H4>'+$CrLf;
		$outHTML += '<table>'+$CrLf;
		$outHTML += '<tr><th width="100px">Тип события</th><th width="130px">Дата/время</th><th width="62px">Код события</th><th>Событие</th><th width="100px">Источник</th></tr>'+$CrLf;
		$outHTML += '<tr align="left"><td colspan="5" class="critical"><b>Сервер "'+$Server+'" недоступен!</b></td></tr>'+$CrLf;
		$outHTML += '</table>'+$CrLf;
		$outHTML += '<hr>'+$CrLf;
		continue;
	}	
	# Пробуем получить логи
	try{
		$Events = Get-WinEvent -Computername $Server -FilterHashTable @{LogName='System'; StartTime=$StartTime;} | Select-Object –Property MachineName,TimeCreated,Id,Message,ProviderName,Level,LevelDisplayName |  Where-Object {$_.Level -ne 4} | Sort-Object -Property TimeCreated,Opcode -Descending;
	}catch{
		$outHTML += '<H4>'+$Server+' (всего важных событий: ?)</H4>'+$CrLf;
		$outHTML += '<H4>Время безотказной работы сервера: <span class="greystring">'+(UpTimeMachine ($Server))+'</span></H4>'+$CrLf;
		$outHTML += '<table>'+$CrLf;
		$outHTML += '<tr><th width="100px">Тип события</th><th width="130px">Дата/время</th><th width="62px">Код события</th><th>Событие</th><th width="100px">Источник</th></tr>'+$CrLf;
		$outHTML += '<tr align="left"><td colspan="5" class="critical"><b>Ошибка доступа к хранилищу событий. Причина: '+$error[0]+'</b></td></tr>'+$CrLf;
		$outHTML += '</table>'+$CrLf;
		$outHTML += '<hr>'+$CrLf;
		continue;
	}
	# Если имеются записи, то учтем их
	if ($Events.Count -ge 0 -AND $Events){
		$outHTML += '<H4>'+($Events.SyncRoot[0].MachineName.ToUpper())+' (всего важных событий: '+([string]$Events.Count)+')</H4>'+$CrLf;		
		$outHTML += '<H4>Время безотказной работы сервера: <span class="greystring">'+(UpTimeMachine ($Server))+'</span></H4>'+$CrLf;
		$outHTML += '<table>'+$CrLf;
		$outHTML += '<tr><th width="100px">Тип события</th><th width="130px">Дата/время</th><th width="62px">Код события</th><th>Событие</th><th width="100px">Источник</th></tr>'+$CrLf;
		foreach ($event in $Events)
		{	
			switch ($event.Level)
			{
				1{$tdClass = ' class="critical"'}	#win:Critical
				2{$tdClass = ' class="error"'}		#win:Error
				3{$tdClass = ' class="warning"'}	#win:Warning
				4{$tdClass = ' class="ok"'}			#win:Informational
				default {$tdClass = ' class="greystring"'} #win:5 - Verbose
			}
			$outHTML += '<tr><td'+$tdClass+'>'+($event.LevelDisplayName)+'</td><td>'+($event.TimeCreated.ToString($DT_FORMAT))+'</td><td align="center">'+($event.Id)+'</td><td>'+($event.Message)+'</td><td>'+($event.ProviderName)+'</td></tr>'+$CrLf;
		}
		$outHTML += '</table>'+$CrLf;
		$outHTML += '<hr>'+$CrLf;
	}
	else {
		$outHTML += '<H4>'+$Server+' (всего важных событий: <span class="ok">0</span>)</H4>'+$CrLf;
		$outHTML += '<H4>Время безотказной работы сервера: <span class="greystring">'+(UpTimeMachine ($Server))+'</span></H4>'+$CrLf;
		$outHTML += '<table>'+$CrLf;
		$outHTML += '<tr><th width="100px">Тип события</th><th width="130px">Дата/время</th><th width="62px">Код события</th><th>Событие</th><th width="100px">Источник</th></tr>'+$CrLf;
		$outHTML += '<tr align="left"><td colspan="5" class="ok"><b>Сервер "'+$Server+'" не имеет записей!</b></td></tr>'+$CrLf;
		$outHTML += '</table>'+$CrLf;
		$outHTML += '<hr>'+$CrLf;
	}	
}
#--------------------------------------------------------------------------------------------
$outHTML += '</body>'+$CrLf+'</html>'+$CrLf;
# сохраняем в файл, если нужно
if ($USE_LOG_FILE) { $outHTML | Out-File -FilePath $PATH_TO_LOG_FILE -Force; }
# отправляем письмо, если нужно
if ($USE_MAIL) { 
	$CRED = New-Object System.Management.Automation.PSCredential($MAIL_LOGIN, (ConvertTo-SecureString $MAIL_PASSWORD -AsPlainText -Force));
	Send-MailMessage -SmtpServer $MAIL_SERVER -To $MAIL_TO -From $MAIL_FROM -Subject $MAIL_SUBJECT -BodyAsHTML -body $outHTML -Encoding ([System.Text.Encoding]::UTF8) -useSSL -Credential $CRED -Priority High; 
}