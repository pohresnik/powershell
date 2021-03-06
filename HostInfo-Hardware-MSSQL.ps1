# Данный скрипт является частью ПО "Инвентаризация"
# Автор: Похресник Д.А. (09.02.2015)
# Версия: 0.01

# Add-Type -Name win -MemberDefinition '[DllImport("user32.dll")] `
#	public static extern bool ShowWindow(int handle, int state);' -Namespace native
# [native.win]::ShowWindow(([System.Diagnostics.Process]::GetCurrentProcess() | `
#	Get-Process).MainWindowHandle,0)
############################################################################ НАСТРОЙКИ
# SQL сервер
$SERVER = 'INTRANET\SQLEXPRESS'	# Адрес сервера
$USER = 'sa'					# Пользователь
$PWD = 'secretpassword'			# Пароль
$DATABASE = 'SCRIPTCOLLECTORS'	# Имя базы данных
#--------------------------------------------------------------------------------------
# Список исключаемых хостов
$EXCLUDE_HOSTS = "1C","DC1","DC2";
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
# узнать версию (билд) WMI-сервера
# вернуть целое число
function BuildVersion(){
	$wmiSetting = [System.Environment]::OSVersion.Version.Build;
	return [int]$wmiSetting;
	#$wmiSetting = Get-CimInstance Win32_OperatingSystem -ErrorAction SilentlyContinue;
	#return [int]$wmiSetting.BuildNumber;
}
#-------------------------------------------------------------------------------------
# узнать разрядность операционной системы
# вернуть целое число
function OSArchitecture(){
	$OSArchitecture = 32;	# По умолчанию = 32, так как может не быть параиетра OSArchitecture
	$OSArchitecture = Get-WmiObject -Query "Select OSArchitecture From Win32_OperatingSystem" -ErrorAction SilentlyContinue;
	return [int]$OSArchitecture.OSArchitecture.substring(0,2)
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
# Получить информацию о лицензии ОС (тип и ключ)
# 
function WindowsLicenseInfo([string]$comp, [string]$datetime) {
    $hklm = 2147483650;
    $regPath = "Software\Microsoft\Windows NT\CurrentVersion";
    $regValue = "DigitalProductId";
	$ProductKey = $null;
	#$win32os = Get-WmiObject -ComputerName $comp Win32_OperatingSystem -ErrorAction SilentlyContinue ;
	#If ($win32os.OSArchitecture -eq '64-bit' -or $win32os.OSArchitecture -eq '64-разрядная') { $regValue = "DigitalProductId4" }
	$wmi = [WMIClass]"\\$comp\root\default:stdRegProv";
	$data = $wmi.GetBinaryValue($hklm,$regPath,$regValue);
	$binArray = ($data.uValue)[52..66];
	$charsArray = "B","C","D","F","G","H","J","K","M","P","Q","R","T","V","W","X","Y","2","3","4","6","7","8","9";
	## decrypt base24 encoded binary data
	For ($i = 24; $i -ge 0; $i--) {
		$k = 0;
		For ($j = 14; $j -ge 0; $j--) {
			$k = $k * 256 -bxor $binArray[$j];
			$binArray[$j] = [math]::truncate($k / 24);
			$k = $k % 24;
		}
		$ProductKey = $charsArray[$k] + $ProductKey;
		If (($i % 5 -eq 0) -and ($i -ne 0)) {
			$ProductKey = "-" + $ProductKey;
		}
	}
	# license type	
	$LicenseInfo = Get-WmiObject SoftwareLicensingProduct -ComputerName $comp `
		-Filter "ApplicationID = '55c92734-d682-4d71-983e-d6ec3f16059f' AND LicenseStatus = 1" `
		-Property Description,PartialProductKey -ErrorAction SilentlyContinue;
	$LicenseType = $null;	
	If ($LicenseInfo.ProductKeyChannel) { 
		$LicenseType = $LicenseInfo.ProductKeyChannel;
	} Else { 
		$LicenseType = $LicenseInfo.Description.Split(",")[1] -replace " channel", "" -replace "_", ":" -replace " ", "";
	} 
	#Если запись существует в базе данных, то обновляем дату, если нет, то добавляем
	$Global:SQL_cmd += "
		IF EXISTS (SELECT upd_datetime FROM dbo.Hardware WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}')
			UPDATE dbo.Hardware SET upd_datetime='{1}' WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}'
		ELSE 
			INSERT INTO dbo.Hardware (hostID, upd_datetime, section, instance, param_name, param_value) 
			VALUES ('{0}','{1}','{2}','{3}','{4}','{5}')" -f $comp,$datetime,"Операционная система",1,"Тип лицензии",$LicenseType;
	$Global:SQL_cmd += "
		IF EXISTS (SELECT upd_datetime FROM dbo.Hardware WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}')
			UPDATE dbo.Hardware SET upd_datetime='{1}' WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}'
		ELSE 
			INSERT INTO dbo.Hardware (hostID, upd_datetime, section, instance, param_name, param_value) 
			VALUES ('{0}','{1}','{2}','{3}','{4}','{5}')" -f $comp,$datetime,"Операционная система",1,"Ключ продукта",$ProductKey;
	$Global:SQL_cmd += "
		IF EXISTS (SELECT upd_datetime FROM dbo.Hardware WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}')
			UPDATE dbo.Hardware SET upd_datetime='{1}' WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}'
		ELSE 
			INSERT INTO dbo.Hardware (hostID, upd_datetime, section, instance, param_name, param_value) 
			VALUES ('{0}','{1}','{2}','{3}','{4}','{5}')" -f $comp,$datetime,"Операционная система",1,"Ключ продукта (частичный)",$LicenseInfo.PartialProductKey;
}
#-------------------------------------------------------------------------------------
# получить WMI, сгенерировать и записать в БД
# входные параметры:
# comp - о каком компьютере собираем информацию
# datetime - дата и время сбора информация, лучше использовать общую для всего скрипта
# wmiclass - хэштаблица с информацией о wmi классе (key - класс, value - секция в БД)
# params - хэштаблица с информацией о параметрах выборки (key - параметры, value - параметры в БД)
# condition - условие выборки, следующее после ключевого слова WHERE
function HardwareLog([string]$comp, [string]$datetime, [hashtable]$wmiclass, [hashtable]$params, [string]$condition){
	$from = [string]$wmiclass.Keys;
	$props = [array]$params.Keys;	 
	$query = "Select "+[string]::Join(",",$props)+" From "+$from;
	if ($condition.Length -gt 0) {$query += " Where "+$condition;}
	$wmi = Get-WmiObject -Namespace root/cimv2 -Query $query -ErrorAction SilentlyContinue;	
	# переменные для внесения в БД
	$Section = [string]$wmiclass.Values;
	$ParamNames = [array]$params.Values;
	$Instance = 1;
	foreach ($item in $wmi)
	{
		for ($i=0; $i -lt $props.Length; $i++)
		{
			$value = $item.($props[$i]);
			# без проверки на Null возможнен вылет с ошибкой
			if ($value -eq $NULL) {$value = "";}
			# если тип данных - массив, собрать в строку
			if ($value -is [array]) {$value = [string]::Join(",", $value);}
			# если тип данных - календарная дата, преобразовать в читаемый вид
			if ($value -match "\d{14}\.\d{6}[\+\-]\d{3}") {$value = ReadableDate($value);}
			# задать явно тип string
			$value = ([string]$value).Trim();
			#Если запись существует в базе данных, то обновляем дату, если нет, то добавляем
			$Global:SQL_cmd += "
				IF EXISTS (SELECT upd_datetime FROM dbo.Hardware WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}')
					UPDATE dbo.Hardware SET upd_datetime='{1}' WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}'
				ELSE 
					INSERT INTO dbo.Hardware (hostID, upd_datetime, section, instance, param_name, param_value) 
					VALUES ('{0}','{1}','{2}','{3}','{4}','{5}')" -f $comp,$datetime,$Section,$Instance,$ParamNames[$i],$value;
		}
		$Instance++;
	}
}
#-------------------------------------------------------------------------------------
# получить WMI данные о жестких дисках и разделах
# comp - о каком компьютере собираем информацию
# datetime - дата и время сбора информация, лучше использовать общую для всего скрипта
# condition - хэштаблица - условие выборки, следующее после ключевого слова WHERE
# 			(key: DiskDrive, LogicalDisk - условия для соответствующего класса)
function HDDLog([string]$comp, [string]$datetime, [hashtable]$condition){	
	$cond_DiskDrive = [string]$condition.DiskDrive;
	$cond_LogicalDisk = [string]$condition.LogicalDisk;
	# Какие параметры HDD нужно выбрать
	$queryDiskDrive = "SELECT Caption, DeviceID, Index, Model, SerialNumber, Size, InterfaceType FROM Win32_DiskDrive";
	if ($cond_DiskDrive.Length -gt 0) {$queryDiskDrive += " WHERE "+$cond_DiskDrive;}
	$wmiDiskDrive = Get-WmiObject -Namespace root/cimv2 -Query $queryDiskDrive -ErrorAction SilentlyContinue;	

	$arrDiskDrive = @();	# массив HDD
	$arrPartition = @();	# массив Партиций
	foreach ($disk in $wmiDiskDrive){
		# получаем информацию о HDD
		$htDiskDrive = @{};
		$htDiskDrive.Add("Индекс", $disk.Index);
		$htDiskDrive.Add("Общий объем", $disk.Size);
		$htDiskDrive.Add("Наименование", $disk.Model);
		$htDiskDrive.Add("Серийный номер", $disk.SerialNumber);
		$htDiskDrive.Add("Тип интерфейса", $disk.InterfaceType);
		$arrDiskDrive += $htDiskDrive;
		# получаем информацию о Партициях, связанных с данным Жестким диском
		$queryDiskDriveToDiskPartition = "ASSOCIATORS OF {Win32_DiskDrive.DeviceID='" + $disk.DeviceID + "'} WHERE AssocClass = Win32_DiskDriveToDiskPartition";
		$wmiDiskDriveToDiskPartition = Get-WmiObject -Namespace root/cimv2 -Query $queryDiskDriveToDiskPartition -ErrorAction SilentlyContinue;	
		foreach ($partition in $wmiDiskDriveToDiskPartition){
			$ht = @{};
			$ht.Add("Индекс диска", $disk.Index);
			$ht.Add("Наименование", $partition.Name);
			$ht.Add("Размер раздела", $partition.Size);
			$ht.Add("Тип раздела", $partition.Type);
			$ht.Add("Загрузочный раздел", $partition.BootPartition);
			$arrPartition += $ht;
		}
	}
	# какие параметры логических дисков нужно выбрать
	$queryLogicalDisk = "SELECT DeviceID, Name, FileSystem, Size, FreeSpace, VolumeName, VolumeSerialNumber FROM Win32_LogicalDisk";
	if ($cond_LogicalDisk.Length -gt 0) {$queryLogicalDisk += " WHERE "+$cond_LogicalDisk;}
	$wmiLogicalDisk = Get-WmiObject -Namespace root/cimv2 -Query $queryLogicalDisk;

	$arrLogicalDisk = @();	# массив логических дисков
	foreach ($ldisk in $wmiLogicalDisk){	
		# логические диски связаны с Партициями
		$queryLogicalDiskToPartition = "ASSOCIATORS OF {Win32_LogicalDisk.DeviceID='" + $ldisk.DeviceID + "'} WHERE AssocClass = Win32_LogicalDiskToPartition";
		$wmiLogicalDiskToPartition = Get-WmiObject -Namespace root/cimv2 -query $queryLogicalDiskToPartition -ErrorAction SilentlyContinue;	
		# для каждой логической партиции...
		foreach ($partition in $wmiLogicalDiskToPartition){
			foreach ($part in $arrPartition)
			{
				# ... ищем соответствие в названии
				if ($partition.Name -eq $part."Наименование")
				{
					# дополняем массив Партиций информации о логическом диске на ней
					$part.Add("Метка диска", $ldisk.Name);
					$part.Add("Файловая система", $ldisk.FileSystem);
					$part.Add("Размер логического раздела", $ldisk.Size);
					$part.Add("Свободно на логическом разделе", $ldisk.FreeSpace);
					$part.Add("Название логического раздела", $ldisk.VolumeName);
				}
			}
		}
	}
	# SQL запрос на внесение информации о жестких дисках
	$Instance = 1;
	foreach ($disk in $arrDiskDrive){
		foreach ($key in $disk.keys){
			$Global:SQL_cmd += "
				IF EXISTS (SELECT upd_datetime FROM dbo.Hardware WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}')
					UPDATE dbo.Hardware SET upd_datetime='{1}' WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}'
				ELSE 
					INSERT INTO dbo.Hardware (hostID, upd_datetime, section, instance, param_name, param_value) 
					VALUES ('{0}','{1}','{2}','{3}','{4}','{5}')" -f $comp,$datetime,"HDD",$Instance,$key,$disk."$key";
		}
		$Instance++;
	}
	# SQL запрос на внесение информации о разделах диска
	$Instance = 1;
	foreach ($part in $arrPartition){
		foreach ($key in $part.keys){
			$Global:SQL_cmd += "
				IF EXISTS (SELECT upd_datetime FROM dbo.Hardware WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}')
					UPDATE dbo.Hardware SET upd_datetime='{1}' WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}'
				ELSE 
					INSERT INTO dbo.Hardware (hostID, upd_datetime, section, instance, param_name, param_value) 
					VALUES ('{0}','{1}','{2}','{3}','{4}','{5}')" -f $comp,$datetime,"Раздел диска",$Instance,$key,$part."$key";
		}
		$Instance++;
	}	
}
#-------------------------------------------------------------------------------------

$RunTimeGetWMI = (Measure-Command {	# замеряем время выполнения
########################################################################### ВЫПОЛНЕНИЕ
# узнаем версию WMI-сервера
$build = BuildVersion;
# узнаем имя локального компьютера
$HOSTNAME = $env:computername;
# генерируем метку времени
$DateTime = [string](Get-Date -f $DATETIME_FORMAT);
# определяем глобальный массив, в который будем добавлять 
# SQL запросы для дальнейшего использования
$SQL_cmd = @();

# Прерываемся, если хост в списке исключенных
if ($EXCLUDE_HOSTS -contains $HOSTNAME) { exit;}

# Удаляем записи, которые не нужно архивировать
$Global:SQL_cmd += "DELETE FROM dbo.Hardware WHERE hostID='{0}' AND section='{1}'" -f $HOSTNAME, "Принтер";
$Global:SQL_cmd += "DELETE FROM dbo.Hardware WHERE hostID='{0}' AND section='{1}'" -f $HOSTNAME, "Порт принтера";
$Global:SQL_cmd += "DELETE FROM dbo.Hardware WHERE hostID='{0}' AND section='{1}'" -f $HOSTNAME, "Идентификатор принтера";

# данные об аппаратном обеспечении
#-------------------------------------------------------------------------------------
HardwareLog $HOSTNAME $DateTime @{"Win32_ComputerSystemProduct"="Компьютер"}`
	@{"UUID"="UUID"};
HardwareLog $HOSTNAME $DateTime @{"Win32_ComputerSystem"="Компьютер"}`
	@{"Name"="Сетевое имя";"Domain"="Домен";"PrimaryOwnerName"="Владелец";"UserName"="Текущий пользователь";"TotalPhysicalMemory"="Объем памяти"};
#только для Vista и выше появилась разрядность
if ($build -ge 6000){
HardwareLog $HOSTNAME $DateTime @{"Win32_OperatingSystem"="Операционная система"}`
	@{"Caption"="Наименование";"OSArchitecture"="Разрядность";"Version"="Версия";"CSDVersion"="Обновление";"Description"="Описание";"RegisteredUser"="Зарегистрированный пользователь";"SerialNumber"="Серийный номер";"Organization"="Организация";"InstallDate"="Дата установки"};
}else{
HardwareLog $HOSTNAME $DateTime @{"Win32_OperatingSystem"="Операционная система"}`
	@{"Caption"="Наименование";"Version"="Версия";"CSDVersion"="Обновление";"Description"="Описание";"RegisteredUser"="Зарегистрированный пользователь";"SerialNumber"="Серийный номер";"Organization"="Организация";"InstallDate"="Дата установки"};
# ВАЖНО! Дописываем информацию о разрядности системы (null)
$Global:SQL_cmd += "IF EXISTS (SELECT upd_datetime FROM dbo.Hardware WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}')
						UPDATE dbo.Hardware SET upd_datetime='{1}' WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}'
					ELSE 
						INSERT INTO dbo.Hardware (hostID, upd_datetime, section, instance, param_name, param_value) 
						VALUES ('{0}','{1}','{2}','{3}','{4}','{5}')" -f $HOSTNAME,$datetime,'Операционная система',1,'Разрядность','';
}
HardwareLog $HOSTNAME $DateTime @{"Win32_BaseBoard"="Материнская плата"}`
	@{"Manufacturer"="Производитель";"Product"="Наименование";"Version"="Версия";"SerialNumber"="Серийный номер"};	
HardwareLog $HOSTNAME $DateTime @{"Win32_BIOS"="BIOS"}`
	@{"Manufacturer"="Производитель";"Name"="Наименование";"SMBIOSBIOSVersion"="Версия";"SerialNumber"="Серийный номер";"ReleaseDate"="Дата выпуска"};
if ($build -ge 6000){
#не определяется Core 2 в XP SP2, см. http://support.microsoft.com/kb/953955
#xp не знает что такое L3-кэш
HardwareLog $HOSTNAME $DateTime @{"Win32_Processor"="Процессор"}`
	@{"Name"="Наименование";"Caption"="Описание";"NumberOfCores"="Количество ядер";"NumberOfLogicalProcessors"="Количество потоков";"CurrentClockSpeed"="Частота";"ExtClock"="Частота FSB";"L2CacheSize"="Размер L2-кеша";"L3CacheSize"="Размер L3-кеша";"SocketDesignation"="Разъем";"UpgradeMethod"="Тип разъема";"UniqueId"="UID"};
}else{
HardwareLog $HOSTNAME $DateTime @{"Win32_Processor"="Процессор"}`
	@{"Name"="Наименование";"Caption"="Описание";"NumberOfCores"="Количество ядер";"NumberOfLogicalProcessors"="Количество потоков";"CurrentClockSpeed"="Частота";"ExtClock"="Частота FSB";"L2CacheSize"="Размер L2-кеша";"SocketDesignation"="Разъем";"UpgradeMethod"="Тип разъема";"UniqueId"="UID"};
}	
HardwareLog $HOSTNAME $DateTime @{"Win32_PhysicalMemory"="Модуль памяти"}`
	@{"Capacity"="Размер";"Speed"="Частота";"DeviceLocator"="Размещение";"Manufacturer"="Производитель";"Model"="Модель";"PartNumber"="Партномер";"FormFactor"="Форм-фактор";"MemoryType"="Тип памяти"};
HardwareLog $HOSTNAME $DateTime @{"Win32_CDROMDrive"="CD-привод"}`
	@{"Name"="Наименование";"Drive"="Метка";"MediaType"="Тип";"Manufacturer"="Производитель";"SerialNumber"="Серийный номер"};
HardwareLog $HOSTNAME $DateTime @{"Win32_FloppyDrive"="Дисковод гибких дисков"}`
	@{"Name"="Наименование";"DeviceID"="Идентификатор";"Manufacturer"="Производитель";"Availability"="Доступность";"Status"="Статус"};
#только для XP/2003 и выше
#пропускаются "двойники", имеющие в названии слово "Secondary"
if ($build -ge 2600){
HardwareLog $HOSTNAME $DateTime @{"Win32_VideoController"="Видеоконтроллер"}`
	@{"Name"="Наименование";"AdapterRAM"="Объем памяти";"VideoProcessor"="Видеопроцессор";"DriverDate"="Дата драйвера";"DriverVersion"="Версия драйвера";"CurrentHorizontalResolution"="Разрешение по горизонтали";"CurrentVerticalResolution"="Разрешение по вертикали";"CurrentNumberOfColors"="Количество цветов";"CurrentBitsPerPixel"="Бит на пиксель";"CurrentRefreshRate"="Частота обновления"} "NOT (Name LIKE '%Secondary%' OR Name LIKE 'Radmin%' OR Name LIKE 'mv video hook driver%')";
}else{
HardwareLog $HOSTNAME $DateTime @{"Win32_VideoController"="Видеоконтроллер"}`
	@{"Name"="Наименование";"AdapterRAM"="Объем памяти";"VideoProcessor"="Видеопроцессор";"DriverDate"="Дата драйвера";"DriverVersion"="Версия драйвера";"CurrentHorizontalResolution"="Разрешение по горизонтали";"CurrentVerticalResolution"="Разрешение по вертикали";"CurrentNumberOfColors"="Количество цветов";"CurrentBitsPerPixel"="Бит на пиксель";"CurrentRefreshRate"="Частота обновления"};
}
HardwareLog $HOSTNAME $DateTime @{"Win32_DesktopMonitor"="Монитор"}`
	@{"MonitorManufacturer"="Производитель";"DeviceID"="Идентификатор";"PNPDeviceID"="PNP Идентификатор";"Caption"="Наименование";"ScreenWidth"="Ширина экрана";"ScreenHeight"="Высота экрана";"Availability"="Доступность";"MonitorType"="Тип монитора"};
#только для XP/2003 и выше
#пропускаются отключенные сетевые адаптеры, в том числе минипорты
#пропускаются виртуальные адаптеры VMware
if ($build -ge 2600){
HardwareLog $HOSTNAME $DateTime @{"Win32_NetworkAdapter"="Сетевой адаптер"}`
	@{"Index"="Индекс";"Name"="Наименование";"AdapterType"="Тип";"MACAddress"="MAC-адрес"} "NetConnectionStatus > 0 AND NOT (Name LIKE 'VMware%' OR Name LIKE 'VirtualBox%')";
}else{
HardwareLog $HOSTNAME $DateTime @{"Win32_NetworkAdapter"="Сетевой адаптер"}`
	@{"Index"="Индекс";"Name"="Наименование";"MACAddress"="MAC-адрес"};
}
#только для XP/2003 и выше
#пропускаются сетевые адаптеры, для которых не установлен IP адрес
if ($build -ge 2600){
HardwareLog $HOSTNAME $DateTime @{"Win32_NetworkAdapterConfiguration"="Конфигурация сетевого адаптера"}`
	@{"Index"="Индекс";"Description"="Наименование";"DHCPEnabled"="DHCP";"IPAddress"="IP-адрес";"IPSubnet"="IP-маска";"DefaultIPGateway"="Шлюз"} "IPEnabled = True AND NOT (Description LIKE 'VMware%' OR Description LIKE 'VirtualBox%')";
}else{
HardwareLog $HOSTNAME $DateTime @{"Win32_NetworkAdapterConfiguration"="Конфигурация сетевого адаптера"}`
	@{"Index"="Индекс";"Description"="Наименование";"DHCPEnabled"="DHCP";"IPAddress"="IP-адрес";"IPSubnet"="IP-маска";"DefaultIPGateway"="Шлюз"};
}
HardwareLog $HOSTNAME $DateTime @{"Win32_SoundDevice"="Звуковое устройство"}`
	@{"Name"="Наименование";"DeviceID"="Идентификатор";"Manufacturer"="Производитель"};
#только для XP/2003 и выше
#пропускаются сетевые принтеры
#условия "Local = True Or Network = False" недостаточно для принт-серверов, поэтому проверяется порт
if ($build -ge 2600){
#HardwareLog $HOSTNAME $DateTime @{"Win32_Printer"="Принтер"}`
#	@{"Name"="Наименование";"PortName"="Порт";"Local"="Локальный";"Network"="Сетевой";"ShareName"="Сетевое имя"} "(Local = True OR Network = False) AND (PortName LIKE '%USB%' OR PortName LIKE '%LPT%')";
HardwareLog $HOSTNAME $DateTime @{"Win32_Printer"="Принтер"}`
	@{"Name"="Наименование";"PortName"="Порт";"Local"="Локальный";"Network"="Сетевой";"ShareName"="Сетевое имя";"ServerName"="Имя сервера";`
	"Published"="Опубликован";"Shared"="Общедоступен";"Default"="По умолчанию";"WorkOffline"="Автономная работа";"DriverName"="Драйвер";"Location"="Расположение"};
HardwareLog $HOSTNAME $DateTime @{"Win32_TCPIPPrinterPort"="Порт принтера"}`
	@{"HostAddress"="IP-адрес";"Name"="Наименование";"PortNumber"="Номер порта";"SNMPEnabled"="SNMP"};
}else{
HardwareLog $HOSTNAME $DateTime @{"Win32_Printer"="Принтер"}`
	@{"Name"="Наименование";"PortName"="Порт";"Local"="Локальный";"Network"="Сетевой";"ShareName"="Сетевое имя";"ServerName"="Имя сервера";`
	"Published"="Опубликован";"Shared"="Общедоступен";"Default"="По умолчанию";"WorkOffline"="Автономная работа";"DriverName"="Драйвер";"Location"="Расположение"};
HardwareLog $HOSTNAME $DateTime @{"Win32_TCPIPPrinterPort"="Порт принтера"}`
	@{"HostAddress"="IP-адрес";"Name"="Наименование";"PortNumber"="Номер порта";"SNMPEnabled"="SNMP"};
}
HardwareLog $HOSTNAME $DateTime @{"Win32_PortConnector"="Разъем порта"}`
	@{"Tag"="Тег";"PortType"="Тип порта";"ExternalReferenceDesignator"="Внешнее обозначение";"InternalReferenceDesignator"="Внутреннее обозначение";"ConnectorType"="Тип разъема";"Status"="Состояние"};
HardwareLog $HOSTNAME $DateTime @{"Win32_SystemSlot"="Слоты материнской платы"}`
	@{"Tag"="Тег";"SlotDesignation"="Обозначение слота";"ConnectorType"="Тип слота";"CurrentUsage"="Статус использования";"Status"="Состояние"};
HardwareLog $HOSTNAME $DateTime @{"Win32_Keyboard"="Клавиатура"}`
	@{"Name"="Наименование";"Description"="Описание";"NumberOfFunctionKeys"="Количество функциональных клавиш";"DeviceID"="Идентификатор"};
HardwareLog $HOSTNAME $DateTime @{"Win32_PointingDevice"="Манипулятор"}`
	@{"Name"="Наименование";"Description"="Описание";"NumberOfButtons"="Количество кнопок";"DeviceID"="Идентификатор"};
HardwareLog $HOSTNAME $DateTime @{"Win32_UserAccount"="Пользователи"}`
	@{"AccountType"="Тип аккаунта";"Disabled"="Заблокирован";"PasswordRequired"="Запаролен";"LocalAccount"="Локальный";"SID"="SID";"Name"="Имя";"Domain"="Домен"} "LocalAccount = True";
HardwareLog $HOSTNAME $DateTime @{"Win32_Share"="Общий ресурс"}`
	@{"Name"="Наименование";"Path"="Путь";"Status"="Статус";"Type"="Тип";"Description"="Описание"};

# данные о жестких дисках
#-------------------------------------------------------------------------------------	
#пропускаются USB-диски, размер которых обычно NULL	
HDDLog $HOSTNAME $DateTime @{"DiskDrive"="InterfaceType <> 'USB'";"LogicalDisk"="DriveType = 3 AND Size IS NOT NULL"};

# данные о лицензии ОС
#-------------------------------------------------------------------------------------	
WindowsLicenseInfo $HOSTNAME $DateTime;

# данные о принтерах из реестра
#-------------------------------------------------------------------------------------	
$Instance = 1;
$RegPrinterEnum = Get-ChildItem -Path "Registry::HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Enum\PrinterBusEnumerator\UMB" | `
	Get-ItemProperty -Name LocationInformation,HardwareID;
foreach ($record in $RegPrinterEnum){
	$record.PSChildName -match "^.*(?<WSD_PORT>WSD-[\d\w]{8}-[\d\w]{4}-[\d\w]{4}-[\d\w]{4}-[\d\w]{12}\.[\d\w]{4})$" | Out-Null;
	if ( -not ([string]::IsNullOrEmpty($Matches['WSD_PORT'])) ) {
		$Global:SQL_cmd += "
			IF EXISTS (SELECT upd_datetime FROM dbo.Hardware 
					WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}')
				UPDATE dbo.Hardware SET upd_datetime='{1}' 
					WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}'
			ELSE 
				INSERT INTO dbo.Hardware (hostID, upd_datetime, section, instance, param_name, param_value) 
				VALUES ('{0}','{1}','{2}','{3}','{4}','{5}')" -f $HOSTNAME,$datetime,'Идентификатор принтера',$Instance,'GUID',$Matches['WSD_PORT'];
	}
	
	$record.LocationInformation -match "(?<IP4_ADDR>(?:(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?)\.){3}(?:25[0-5]|2[0-4][0-9]|[01]?[0-9][0-9]?))" | Out-Null;
	if ( -not ([string]::IsNullOrEmpty($Matches['IP4_ADDR'])) ) {
		$Global:SQL_cmd += "
			IF EXISTS (SELECT upd_datetime FROM dbo.Hardware 
					WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}')
				UPDATE dbo.Hardware SET upd_datetime='{1}' 
					WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}'
			ELSE 
				INSERT INTO dbo.Hardware (hostID, upd_datetime, section, instance, param_name, param_value) 
				VALUES ('{0}','{1}','{2}','{3}','{4}','{5}')" -f $HOSTNAME,$datetime,'Идентификатор принтера',$Instance,'IP-адрес',$Matches['IP4_ADDR'];
	}
	
	$HardwareID = [string]::join(";", $record.HardwareID);
	if ( -not ([string]::IsNullOrEmpty($HardwareID)) ) {
		$Global:SQL_cmd += "
			IF EXISTS (SELECT upd_datetime FROM dbo.Hardware 
					WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}')
				UPDATE dbo.Hardware SET upd_datetime='{1}' 
					WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}'
			ELSE 
				INSERT INTO dbo.Hardware (hostID, upd_datetime, section, instance, param_name, param_value) 
				VALUES ('{0}','{1}','{2}','{3}','{4}','{5}')" -f $HOSTNAME,$datetime,'Идентификатор принтера',$Instance,'Наименование',$HardwareID;
	}
	
	$Instance++;
}

$RegPrinterConnections = Get-ItemProperty "Registry::\HKCU\Printers\Connections\*" | Select-Object `
	@{Name="GuidPrinter";	Expression={$_.GuidPrinter}},
	@{Name="Server";		Expression={$_.Server}},
	@{Name="Name";			Expression={$_.PsChildName -replace ',','\'}}
foreach ($record in $RegPrinterConnections){
	$Global:SQL_cmd += "
		IF EXISTS (SELECT upd_datetime FROM dbo.Hardware 
				WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}')
			UPDATE dbo.Hardware SET upd_datetime='{1}' 
				WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}'
		ELSE 
			INSERT INTO dbo.Hardware (hostID, upd_datetime, section, instance, param_name, param_value) 
			VALUES ('{0}','{1}','{2}','{3}','{4}','{5}')" -f $HOSTNAME,$datetime,'Идентификатор принтера',$Instance,'GUID',$record.GuidPrinter;
	$Global:SQL_cmd += "
		IF EXISTS (SELECT upd_datetime FROM dbo.Hardware 
				WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}')
			UPDATE dbo.Hardware SET upd_datetime='{1}' 
				WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}'
		ELSE 
			INSERT INTO dbo.Hardware (hostID, upd_datetime, section, instance, param_name, param_value) 
			VALUES ('{0}','{1}','{2}','{3}','{4}','{5}')" -f $HOSTNAME,$datetime,'Идентификатор принтера',$Instance,'Имя сервера',$record.Server;
	$Global:SQL_cmd += "
		IF EXISTS (SELECT upd_datetime FROM dbo.Hardware 
				WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}')
			UPDATE dbo.Hardware SET upd_datetime='{1}' 
				WHERE hostID='{0}' AND section='{2}' AND instance='{3}' AND param_name='{4}' AND param_value='{5}'
		ELSE 
			INSERT INTO dbo.Hardware (hostID, upd_datetime, section, instance, param_name, param_value) 
			VALUES ('{0}','{1}','{2}','{3}','{4}','{5}')" -f $HOSTNAME,$datetime,'Идентификатор принтера',$Instance,'Наименование',$record.Name;
	
	$Instance++;
}
#-------------------------------------------------------------------------------------

# внесение информации в БД
#-------------------------------------------------------------------------------------	
$cmd = New-Object System.Data.SqlClient.SqlCommand;
# строка подлючения к SQL серверу
#$connectionString = "Server=$SERVER;Database=$DATABASE;User id=$USER;Password=$PWD;Trusted_Connection=True;";
$connectionString = "Server=$SERVER;Database=$DATABASE;User id=$USER;Password=$PWD;";
$connection = SQLconnect ($connectionString);
$cmd.connection = $connection;
#$cmd.CommandText = $Global:SQL_cmd;
#[void]$cmd.ExecuteNonQuery();
foreach ($sql in $Global:SQL_cmd)
{
	$cmd.CommandText = $sql;
	[void]$cmd.ExecuteNonQuery();
}
}).TotalSeconds;	# конец времени выполнения

# внесение информации в БД о времени выполнения
#-------------------------------------------------------------------------------------
# получение информации о разделителе в числах с плавающей точкой
$nfi = (new-object System.Globalization.CultureInfo "en-US", $false ).NumberFormat;
$RunTime = $RunTimeGetWMI.ToString("G", $nfi);
# работа с БД
$cmd.CommandText = "INSERT INTO dbo.RunTime (hostID, upd_datetime, category, runtime) VALUES ('{0}','{1}','{2}','{3}')" -f $HOSTNAME, $DateTime, "hardware", $RunTime;
[void]$cmd.ExecuteNonQuery();
# отключаемся от БД
SQLdisconnect ($connection);