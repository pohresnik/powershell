# Сбор информации об учетных записях в AD
# средствами PowerShell (08.05.2013)
# Данные выводятся в формате html
# Автор: Похресник Д.А.

#################################################################
$Age = 10;
$SearchBase = "OU=Users,DC=domain,DC=tld";
$ReportFolder = 'C:\_REPORTS_\';
$ReportDate = Get-Date -UFormat "%d-%m-%y";
# Формат даты/времени: dd - день (2 цифры), MM - месяц (2 цифры), yyyy - год (4 цифры),
# HH - час (24 часовой формат), mm - минуты (2 цифры), ss - секунды (2 цифры)
$DT_FORMAT = "dd.MM.yyyy HH:mm:ss";
$NotSet = "not set";
#--------------------------------------------------------------------------------------------
$CrLf = [char]13+[char]10;	# перевод каретки
#--------------------------------------------------------------------------------------------
$USE_LOG_FILE = $false;
$PATH_TO_LOG_FILE = $ReportFolder+'PWDReport-'+$ReportDate+'.html';
#--------------------------------------------------------------------------------------------
$USE_MAIL = $true;
$MAIL_SERVER = "mail.example.com";
$MAIL_TO = "it@example.com";
$MAIL_FROM = "service-info@example.com";
$MAIL_SUBJECT = "Состояние password expiration’s";
#--------------------------------------------------------------------------------------------
#################################################################

#################################################################
#Importing External modules
Import-Module activedirectory
#################################################################

#################################################################
#Script Body

#----------------------------------------------------------------
#region Determine MaxPasswordAge;
$maxPasswordAgeTimeSpan = $null; 
$dfl = (get-addomain).DomainMode; 
$maxPasswordAgeTimeSpan = (Get-ADDefaultDomainPasswordPolicy).MaxPasswordAge; 
If ($maxPasswordAgeTimeSpan -eq $null -or $maxPasswordAgeTimeSpan.TotalMilliseconds -eq 0) 
{
	Write-Host "MaxPasswordAge is not set for the domain or is set to zero!";
	Write-Host "So no password expiration’s possible.";
    Exit;
}
#endregion
#----------------------------------------------------------------

$Users = Get-ADUser -Filter * -SearchBase $SearchBase -SearchScope Subtree -Properties GivenName,sn,PasswordExpired,PasswordLastSet,PasswordneverExpires,LastLogonDate,CannotChangePassword,Title,Department,Company;

$ResultExpired = @();
$ResultTotal = @();
#----------------------------------------------------------------
ForEach ($User in $Users) 
{
	If ($User.PasswordNeverExpires -or $User.PasswordLastSet -eq $null) 
	{   
		$ResultTotal += New-Object PSObject -Property @{ 
			FullName = $User.sn + ' ' + $User.GivenName
			Account = $User.SamAccountName 
			State = If ($User.Enabled) { $true } Else { $false } 
			Department = $User.Department 
			Company = $User.company 
			Title = $User.Title
			LastLogonDate = If ($User.LastLogonDate -ne $null) { $User.LastLogonDate.ToString($DT_FORMAT) } Else { $NotSet } 
			Expiration = $NotSet 
			CannotChangePassword = $User.CannotChangePassword			
			PasswordneverExpires = $User.PasswordneverExpires 
			PasswordExpired = $User.PasswordExpired 
			PasswordLastSet = If ($User.PasswordLastSet -ne $null) { $User.PasswordLastSet.ToString($DT_FORMAT) } Else { $NotSet } 
			DaysLeft = $NotSet
		}
		Continue;
	} 
	If ($dfl -ge 3) 
	{    ## Greater than Windows2008 domain functional level 
		$accountFGPP = $null 
		$accountFGPP = Get-ADUserResultantPasswordPolicy $User 
		If ($accountFGPP -ne $null) { $ResultPasswordAgeTimeSpan = $accountFGPP.MaxPasswordAge } 
		Else { $ResultPasswordAgeTimeSpan = $maxPasswordAgeTimeSpan } 
	} 
	Else 
	{    
		$ResultPasswordAgeTimeSpan = $maxPasswordAgeTimeSpan 
	} 
	$Expiration = $User.PasswordLastSet + $ResultPasswordAgeTimeSpan 
	#If ((New-TimeSpan -Start (Get-Date) -End $Expiration).Days -le $Age) 
	#{    
		$ResultTotal += New-Object PSObject -Property @{ 
			FullName = $User.sn + ' ' + $User.GivenName
			Account = $User.SamAccountName 
			State = If ($User.Enabled) { $true } Else { $false } 
			Department = $User.Department 
			Company = $User.company 
			Title = $User.Title
			LastLogonDate = If ($User.LastLogonDate -ne $null) { $User.LastLogonDate.ToString($DT_FORMAT) } Else { $NotSet } 
			Expiration = $Expiration.ToString($DT_FORMAT)
			CannotChangePassword = $User.CannotChangePassword			
			PasswordneverExpires = $User.PasswordneverExpires 
			PasswordExpired = $User.PasswordExpired 
			PasswordLastSet = $User.PasswordLastSet.ToString($DT_FORMAT)
			DaysLeft = (New-TimeSpan -Start (Get-Date) -End $Expiration).Days
		} 
	#} 
}
#----------------------------------------------------------------
$ResultTotal = $ResultTotal | Sort Expiration,Account,DaysLeft
#--------------------------------------------------------------------------------------------
# Создаем HTML
$outHTML = "";
$outHTML += '<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">'+$CrLf;
$outHTML += '<html>'+$CrLf;
$outHTML += '<head>'+$CrLf;
$outHTML += '<meta http-equiv="Content-Type" content="text/html; charset=utf-8">'+$CrLf;
$outHTML += '<title>Отчет. Дней действует пароль: '+$maxPasswordAgeTimeSpan+'</title>'+$CrLf;
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
$outHTML += '<H2>Статистика учетных записей (парольная защита)</H2>'+$CrLf;
$outHTML += '<H3>Отчет создан: '+(Get-Date -Format $DT_FORMAT)+'</H3>'+$CrLf;
$outHTML += '<H3>Всего записей: '+([string]$ResultTotal.Count)+'</H3>'+$CrLf;
$outHTML += '<H4>Период замены паролей: '+([string]$maxPasswordAgeTimeSpan.Days)+' дней</H4>'+$CrLf;
$outHTML += '<hr>'+$CrLf;
$outHTML += '<table>'+$CrLf;
$outHTML += '<tr><th>#</th><th>Аккаунт</th><th>Полное имя</th><th>Активен</th><th>Описание</th><th>Время последней установки пароля</th><th>Время истечения срока пароля</th><th>Осталось дней</th><th>Срок действия пароля истек</th><th>Последнее время входа</th><th>Запрещена смена пароля</th><th>Срок действия пароля не ограничен</th></tr>'+$CrLf;
$i = 1
ForEach ($user In $ResultTotal)
{
	If ($user.PasswordExpired) {$trClass = ' class="warning"'} else {$trClass = ''}
	If ($user.DaysLeft -lt $Age) {$trDlClass = ' class="critical"'} else {$trDlClass = ''}
	$outHTML += '<tr'+$trClass+'><td>'+($i++)+'</td><td>'+($user.Account)+'</td><td>'+($user.FullName)+'</td><td>'+($user.State)+'</td><td>'+($user.Title + ' | ' + $user.Department + ' | ' + $user.Company)+'</td><td>'+($user.PasswordLastSet)+'</td><td>'+($user.Expiration)+'</td><td'+$trDlClass+'>'+($user.DaysLeft)+'</td><td>'+($user.PasswordExpired)+'</td><td>'+($user.LastLogonDate)+'</td><td>'+($user.CannotChangePassword)+'</td><td>'+($user.PasswordneverExpires)+'</td></tr>'+$CrLf;  
}
$outHTML += '</table>'+$CrLf;
$outHTML += '</body>'+$CrLf+'</html>'+$CrLf;
# сохраняем в файл, если нужно
if ($USE_LOG_FILE) { $outHTML | Out-File -FilePath $PATH_TO_LOG_FILE -Force; }
# отправляем письмо, если нужно
if ($USE_MAIL) { Send-MailMessage -SmtpServer $MAIL_SERVER -To $MAIL_TO -From $MAIL_FROM -Subject $MAIL_SUBJECT -BodyAsHTML -body $outHTML -Encoding ([System.Text.Encoding]::UTF8); }