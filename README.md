﻿
# smfc
[![Tests](https://github.com/petersulyok/smfc/actions/workflows/test.yml/badge.svg)
](https://github.com/petersulyok/smfc/actions/workflows/tests.yml) [![Codecov](https://codecov.io/gh/petersulyok/smfc/branch/main/graph/badge.svg)
](https://app.codecov.io/gh/petersulyok/smfc) [![Issues](https://img.shields.io/github/issues/petersulyok/smfc)
](https://github.com/petersulyok/smfc/issues)

Super Micro fan control for Linux (home) servers.

## TL;DR

This is a `systemd service` running on Linux and is able to control fans in CPU and HD zones with the help of IPMI on Super Micro X10/X11 (and some X9) motherboards.

### 1. Prerequisites
 - a Super Micro motherboard with a BMC chip (i.e. ASPEED AST2400/2500)
 - Python 3.7+
 - Linux OS with:
   - `systemd` package
   - `coretemp` kernel module for Intel(R) CPUs
   - `k10temp` kernel module for AMD(R) CPUs
   - `drivetemp` kernel module (kernel version 5.6+ required) modules for SATA hard disks
 - `bash`
 - `ipmitool`
 - optional: `smartmontools` for the *standby guard* feature
 - optional: `hddtemp` for the SAS/SCSI disks

### 2. Installation and configuration
 1. Set up the IPMI threshold values for your fans (see script `ipmi/set_ipmi_threshold.sh`). 
 2. Optional: enable advanced power management features for your CPU and SATA hard disks for lower power consumption, heat generation and fan noise. 
 3. Load kernel modules (`coretemp/k10temp` and `drivetemp`).
 4. Install the service with running the script `install.sh`.
 5. Edit the configuration file `/opt/smfc/smfc.conf` and command line options in `/etc/default/smfc`.
 6. Start the `systemd` service
 7. Check results in system log
 8. Leave a feedback in [issue #19](https://github.com/petersulyok/smfc/issues/19)

## Details
### 1. How does it work?
This service was planned for Super Micro motherboards installed in computer chassis with two independent cooling systems employing separate fans. In IPMI terms these are called:
 - CPU zone (FAN1, FAN2, etc.)
 - HD or peripheral zone (FANA, FANB, etc.) 

Please note: the fan assignment is defined by IPMI and it cannot be changed! On the other hand `smfc` implements a feature, called *Swapped zones*, in order to make the use of the fans more suitable.

In this service a fan control logic is implemented for both zones which can:

 1. read the zone's temperature from Linux kernel
 2. calculate a new fan level based on the user-defined control function and the current temperature value of the zone 
 3. set up the new fan level through IPMI in the zone

<img src="https://github.com/petersulyok/smfc/raw/main/doc/smfc_overview.jpg" align="center" width="600">

The fan control logic can be enabled and disabled independently per zone. In the zone all fans will have the same rotation speed. The user can configure different temperature calculation method (e.g. minimum, average, maximum temperatures) in case of multiple heat sources in a zone.

#### 2. User-defined control function
The user-defined parameters (see configuration file below for more details) create a function where a temperature interval is being mapped to a fan level interval.

 <img src="https://github.com/petersulyok/smfc/raw/main/doc/userdefined_control_function.jpg" align="center" width="500">

The following five parameters will define the function in both zones:

     min_temp=
     max_temp=
     min_level=
     max_level=
     steps=

With the help of this function `smfc` can map any new temperature measurement value to a fan level. Changing the fan rotation speed is a very slow process (i.e. it could take seconds depending on fan type and the requested amount of change), so we try to minimize these kinds of actions. Instead of setting fan rotation speed continuously we define discrete fan levels based on `steps=` parameter.

 <img src="https://github.com/petersulyok/smfc/raw/main/doc/fan_output_levels.jpg" align="center" width="500">

In order to avoid/minimize the unnecessary change of fan levels the service employs the following steps:

 1. When the service adjusts the fan rotation speed then it always applies a delay time defined in configuration parameter `[IPMI] fan_level_delay=` in order to let the fan implement the physical change.
 2. There is a sensitivity threshold parameter (`sensitivity=`) for the fan control logic. If the temperature change is below this value then the service will not react at all. 
 3. There configuration parameter `polling=` can also impact the frequency of change of the fan levels. The bigger polling time in a zone the lower frequency of changing of the fan speed.

#### 3. Swapped zones
In some cases it is useful to swap IPMI zones. In this way the fans `FAN1, FAN2, ...` will cool the HD zone and the fans `FANA, FANB, ...` will cool the CPU zone. This feature could be useful if you need more fans for the HD zone since Super Micro motherboards have more fan connectors in the CPU zone usually. This feature can be enabled with `[IPMI] swapped_zones=True` configuration parameter, in default it is disabled. 

#### 4. Standby guard
For HD zone an additional optional feature was implemented, called *Standby guard*, with the following assumptions:
	
 - SATA hard disks are organized into a RAID array
 - the RAID array will go to standby mode recurrently

This feature is monitoring the power state of SATA hard disks (with the help of the `smartctl`) and will put the whole array to standby mode if a few members are already stepped into that. With this feature we can avoid a situation where the array is partially in standby mode while other members are still active.

#### 5. Hard disk compatibility
The `smfc` service was originally designed for `SATA` hard drives, but from `3.0` version it is also compatible with `NVME` and `SAS/SCSI` disks. The following table summarizes how the temperature is read for different disk types: 

| Disk type  | Temperature source   | Kernel module | Command   |
|------------|----------------------|---------------|-----------|
| `SATA`       | Linux kernel (HWMON) | `drivetemp`   | -         |
| `NVME`       | Linux kernel (HWMON) | -             | -         |
| `SAS/SCSI`   | `hddtemp`            | -             | `hddtemp` |

Some additional notes:

- For `NVME` SSDs no kernel driver will be loaded the kernel itself can handle this disk type
- For `SATA` disks the `drivetemp` kernel module should be loaded (this is the fastest way to read disk temperature and the kernel module can report the temperature during sleep mode!)
- For `SAS/SCSI` disks the `hddtemp` command will be used to read disk temperature (NO daemon mode is required for `hddtemp`!)
- Different disks types can be mixed in `hd_names=` configuration parameter but the power management (standy mode) and *Standby guard* feature will not be supported in this case.
- Although `smfc` can handle NVME SSDs, it is NOT RECOMMENDED to include NVME disks in `hd_names=` parameters, because the hard disks and NVME SSDs are operating in quite different temperature zones (e.g. 40 C vs 70 C).
- The service can identify the disk types automatically based on the tags (`ata-`/`-SATA`, `nvme-` and `scsi-`)

### 6. Super Micro compatibility
Originally this software was designed to work with Super Micro X10 and X11 motherboards with a BMC chip (i.e. ASPEED AST2400/2500) and IPMI functionality. 

In case of X9 motherboards the compatibility is not guaranteed, it depends on the hardware components of the motherboard (i.e. not all X9 motherboards employ BMC chip). 

The earlier X8 motherboards are NOT compatible with this software. They do not implement `IPMI_FULL` mode and they cannot control fan levels how it is implemented in `smfc`.

Feel free to create a short feedback in [issue #19](https://github.com/petersulyok/smfc/issues/19) on your compatibility experience.

TODO: Feedback would be needed about the compatibility with Super Micro X12/X13 motherboards and AST2600 BMC chip.

### 7. IPMI fan control and thresholds
Many utilities and scripts (created by NAS and home server community) are using `IPMI FULL MODE`. In this mode the IPMI system set fan rotation speed initially to 100% but after then it can be changed freely while it is not reaching the lower and the upper threshold values. If it happens then IPMI will set all fans back to full rotation speed (100%) in the zone. In order to avoid this situation, you should redefine IPMI sensor thresholds based on your fan specification. On Linux you can display and change several IPMI parameters (like fan mode, fan level, sensor data and thresholds etc.) with the help of `ipmitool`.

 IPMI defines six sensor thresholds for fans:
 1. Lower Non-Recoverable  
 2. Lower Critical  
 3. Lower Non-Critical
 4. Upper Non-Critical  
 5. Upper Critical  
 6. Upper Non-Recoverable

You can redefine the proper thresholds in following way:
1. Check the specification of your fans and find the minimum and maximum rotation speeds. In case of [Noctua NF-12 PWM](https://noctua.at/en/products/fan/nf-f12-pwm) these are 300 and 1500 rpm.
2. Configure the lower thresholds below the minimum fan rotation speed and upper thresholds above the maximum fan rotation speed (e.g., in case of the previous Noctua fan the thresholds are 0, 100, 200, 1600, 1700, 1800).  Edit and run `ipmi/set_ipmi_treshold.sh` to redefine IPMI thresholds. If you install a new BMC firmware on your Super Micro motherboard you have to repeat this step!
3. Check the configured IPMI thresholds:

		root@home:~# ipmitool sensor
		...
		FAN1             | 700.000    | RPM        | ok    | 0.000     | 100.000   | 200.000   | 1600.000  | 1700.000  | 1800.000
		FAN2             | 700.000    | RPM        | ok    | 0.000     | 100.000   | 200.000   | 1600.000  | 1700.000  | 1800.000
		FAN3             | na         |            | na    | na        | na        | na        | na        | na        | na
		FAN4             | 600.000    | RPM        | ok    | 0.000     | 100.000   | 200.000   | 1600.000  | 1700.000  | 1800.000
		FANA             | 500.000    | RPM        | ok    | 0.000     | 100.000   | 200.000   | 1600.000  | 1700.000  | 1800.000
		FANB             | 500.000    | RPM        | ok    | 0.000     | 100.000   | 200.000   | 1600.000  | 1700.000  | 1800.000
		...

**Important**: if you do not see any fans when executing `ipmitool sensors`, you may want to reset the BMC to factory default using the Web UI or using `ipmitool mc reset cold`.

You can read more about:

 - IPMI fan control: [STH Forums](https://forums.servethehome.com/index.php?resources/supermicro-x9-x10-x11-fan-speed-control.20/) and [TrueNAS Forums](https://www.truenas.com/community/threads/pid-fan-controller-perl-script.50908/)
 - Change IPMI sensors thresholds: [TrueNAS Forums](https://www.truenas.com/community/resources/how-to-change-ipmi-sensor-thresholds-using-ipmitool.35/)

### 8. Power management
If low noise and low heat generation are important attributes of your Linux box, then you may consider the following chapters.

#### 8.1 CPU
Most of the modern CPUs has multiple energy saving features. You can check your BIOS and enable them in order to minimize the heat generation.

Intel(R) CPUs:
 - Intel(R) Speed Shift Technology
 - Intel(R) SpeedStep
 - C-states
 - Boot performance mode

AMD(R) CPUs:
 - PowerNow!
 - Cool\`n\`quiet
 - Turbo Core

With this setup the CPU will change its base frequency and power consumption dynamically based on the load.

#### 8.2 SATA hard disks
In case of SATA hard disks, you may enable:

 - advanced power management
 - spin down timer

With the help of command `hdparm` you can enable advanced power management and specify a spin down timer (read more [here](https://en.wikipedia.org/wiki/Hdparm)):

	hdparm -B 127 /dev/sda
	hdparm -S 240 /dev/sda
	
In file `/etc/hdparm.conf` you can specify all parameters in a persistent way:

	quiet

	/dev/sda {
        apm = 127
        spindown_time = 240
	}
	/dev/sdb {
        apm = 127
        spindown_time = 240
	}
	...

Important notes: 
 1. If you plan to spin down your hard disks or RAID array (i.e. put them to standby mode) you have to set up the configuration parameter `[HD zone] polling=` minimum twice bigger as the `spindown_time` specified here.
 2. In file `/etc/hdparm.conf` you must define HD names in `/dev/disk/by-id/...` form to avoid inconsistency.

### 9. Kernel modules
We need to load the following important Linux kernel modules:

 - [`coretemp`](https://www.kernel.org/doc/html/latest/hwmon/coretemp.html): temperature report for Intel(R) CPUs
 - [`k10temp`](https://docs.kernel.org/hwmon/k10temp.html): temperature report for AMD(R) CPUs
 - [`drivetemp`](https://www.kernel.org/doc/html/latest/hwmon/drivetemp.html): temperature report for SATA hard disks (available from kernel 5.6+ version)

Use `/etc/modules` file for persistent loading of these modules. 
Here are some sample HWMON file locations for these kernel modules:

 - `coretemp`: `/sys/devices/platform/coretemp.0/hwmon/hwmon*/temp1_input`
 - `k10temp`: `/sys/bus/pci/drivers/k10temp/0000*/hwmon/hwmon*/temp1_input`
 - `drivetemp`: `/sys/class/scsi_disk/0:0:0:0/device/hwmon/hwmon*/temp1_input`

Notes:
- `smfc` is able to find the proper HWMON file automatically for Intel(R) CPUs and SATA hard drives, but users of the AMD(R) CPU should specify manually (see `hwmon_path=` parameter in the config file)
- Reading `drivetemp` module is the fastest way to get the temperature of the hard disks, and it can read temperature of the SATA hard disks even in standby mode, too. 

### 10. Installation
For the installation you need a root user. The default installation script `install.sh` will use the following folders:

| File           | Installation folder   | Description                     |
|----------------|-----------------------|---------------------------------|
| `smsc.service` | `/etc/systemd/system` | systemd service definition file |
| `smsc`         | `/etc/default`        | service command line options    |
| `smsc.py`      | `/opt/smfc`           | service (python program)        |
| `smsc.conf`    | `/opt/smfc`           | service configuration file      |

but you can use freely any other folders too. The service has the following command line options:

	root@home:~/opt/smfc# ./smfc.py --help
	usage: smfc.py [-h] [-c CONFIG_FILE] [-v] [-l {0,1,2,3,4}] [-o {0,1,2}]
	
	optional arguments:
  		-h, --help      show this help message and exit
  		-c CONFIG_FILE  configuration file
  		-v              show program's version number and exit
  		-l {0,1,2,3,4}  log level: 0-NONE, 1-ERROR(default), 2-CONFIG, 3-INFO, 4-DEBUG
  		-o {0,1,2}      log output: 0-stdout, 1-stderr, 2-syslog(default)

You may configure logging output and logging level here and these options can be specified in `/etc/default/smfc`in a persistent way.

### 11. Configuration file
Edit `/opt/smfc/smfc.conf` and specify your configuration parameters here:

	#  
	#   smfc.conf  
	#   smfc service configuration parameters  
	#  
	  
	  
	[Ipmi]  
	# Path for ipmitool (str, default=/usr/bin/ipmitool)  
	command=/usr/bin/ipmitool   
	# Delay time after changing IPMI fan mode (int, seconds, default=10)  
	fan_mode_delay=10  
	# Delay time after changing IPMI fan level (int, seconds, default=2)  
	fan_level_delay=2  
	# CPU and HD zones are swapped (bool, default=0).  
	swapped_zones=0  
	  
	  
	[CPU zone]  
	# Fan controller enabled (bool, default=0)  
	enabled=1  
	# Number of CPUs (int, default=1)  
	count=1  
	# Calculation method for CPU temperatures (int, [0-minimum, 1-average, 2-maximum], default=1)  
	temp_calc=1  
	# Discrete steps in mapping of temperatures to fan level (int, default=6)  
	steps=6  
	# Threshold in temperature change before the fan controller reacts (float, C, default=3.0)  
	sensitivity=3.0  
	# Polling time interval for reading temperature (int, sec, default=2)  
	polling=2  
	# Minimum CPU temperature (float, C, default=30.0)  
	min_temp=30.0  
	# Maximum CPU temperature (float, C, default=60.0)  
	max_temp=60.0  
	# Minimum CPU fan level (int, %, default=35)  
	min_level=35  
	# Maximum CPU fan level (int, %, default=100)  
	max_level=100  
	# Optional parameter, it will be generated automatically for Intel CPUs and must be specified manually for AMD CPUs.  
	# Path for CPU sys/hwmon file(s) (str multi-line list, default=/sys/devices/platform/coretemp.0/hwmon/hwmon*/temp1_input)  
	# hwmon_path=/sys/devices/platform/coretemp.0/hwmon/hwmon*/temp1_input  
	#            /sys/devices/platform/coretemp.1/hwmon/hwmon*/temp1_input  
	# or  
	# hwmon_path=/sys/bus/pci/drivers/k10temp/0000*/hwmon/hwmon*/temp1_input  
	  
	  
	[HD zone]  
	# Fan controller enabled (bool, default=0)  
	enabled=1  
	# Number of HDs (int, default=1)  
	count=1  
	# Calculation of HD temperatures (int, [0-minimum, 1-average, 2-maximum], default=1)  
	temp_calc=1  
	# Discrete steps in mapping of temperatures to fan level (int, default=4)  
	steps=4  
	# Threshold in temperature change before the fan controller reacts (float, C, default=2.0)  
	sensitivity=2.0  
	# Polling interval for reading temperature (int, sec, default=10)  
	polling=10  
	# Minimum HD temperature (float, C, default=32.0)  
	min_temp=32.0  
	# Maximum HD temperature (float, C, default=46.0)  
	max_temp=46.0  
	# Minimum HD fan level (int, %, default=35)  
	min_level=35  
	# Maximum HD fan level (int, %, default=100)  
	max_level=100  
	# Names of the HDs (str multi-line list, default=)  
	# These names MUST BE specified in '/dev/disk/by-id/...' form!  
	hd_names=  
	# Optional parameter, it will be generated automatically based on the disk names.  
	# List of files in /sys/hwmon file system or 'hddtemp' (str multi-line list, default=)  
	# hwmon_path=/sys/class/scsi_disk/0:0:0:0/device/hwmon/hwmon*/temp1_input  
	#            /sys/class/scsi_disk/1:0:0:0/device/hwmon/hwmon*/temp1_input  
	#            hddtemp  
	# Standby guard feature for RAID arrays (bool, default=0)  
	standby_guard_enabled=0  
	# Number of HDs already in STANDBY state before the full RAID array will be forced to it (int, default=1)  
	standby_hd_limit=1  
	# Path for 'smartctl' command (str, default=/usr/sbin/smartctl).  
	# Required for 'standby guard' feature only  
	smartctl_path=/usr/sbin/smartctl  
	# Path for 'hddtemp' command (str, default=/usr/sbin/hddtemp).  
	# Required for reading of the temperature of SAS/SCSI disks.  
	hddtemp_path=/usr/sbin/hddtemp
Important notes:
 1. `[HD zone} hd_names=`: This is a compulsory parameter, its value must be specified in `/dev/disk/by-id/...` form (the `/dev/sda` form is not persistent could be changed after a reboot).
 2. `[CPU zone] / [HD zone] min_level= / max_level=`: Check the stability of your fans and adjust the fan levels based on your measurement. As it was stated earlier, IPMI can switch back to full rotation speed if fans reach specific thresholds. You can collect real data about the behavior of your fans if you edit and run script `ipmi/fan_measurement.sh`. The script will set fan levels from 100% to 20% in 5% steps and results will be saved in the file `fan_result.csv`:

		root:~# cat fan_result.csv
		Level,FAN1,FAN2,FAN4,FANA,FANB
		100,1300,1300,1200,1300,1300
		95,1300,1300,1100,1200,1300
		90,1200,1200,1100,1200,1200
		85,1100,1100,1000,1100,1100
		80,1100,1100,1000,1100,1100
		75,1000,1000,900,1000,1000
		70,900,900,800,1000,900
		65,900,900,800,900,900
		60,800,800,700,900,800
		55,700,700,700,800,700
		50,700,700,600,700,700
		45,600,600,500,700,600
		40,500,500,500,600,500
		35,500,500,400,500,500
		30,400,400,300,400,400
		25,300,300,300,400,300
		20,1300,1300,1200,1300,1300

	My experience is that Noctua fans in my box are running stable in the 35-100% fan level interval. An additional user experience is (see [issue #12](https://github.com/petersulyok/smfc/issues/12)) when Noctua fans are paired with Ultra Low Noise Adapter the minimum stable fan level could go up to 45% (i.e. 35% is not stable).  

 3. `[CPU zone] / [HD zone] hwmon_path=`: This parameter is optional for Intel(R) CPUs and SATA drives (i.e. `smfc` can identify automatically the proper file locations), but must be specified manually for AMD(R) CPUs. In case of SAS/SCSI hard disks (where `drivetemp` cannot be loaded) you can specify `hddtemp` value. You can use wild characters (`?,*`) in this parameter and `smfc` will do the path resolution automatically.
 4. Several sample configuration files are provided for different scenarios in folder `./src/samples`. Please take a look on them, it could be a good starting point in the creation of your own configuration.

### 12. Automatic execution of the service
This `systemd` service can be started and stopped in the standard way. Do not forget to reload `systemd` configuration after a new installation or if you changed the service definition file:

	systemctl daemon-reload
	systemctl start smfc.service
	systemctl stop smfc.service
	systemctl restart smfc.service
	systemctl status smfc.service
	● smfc.service - Super Micro Fan Control
	     Loaded: loaded (/etc/systemd/system/smfc.service; enabled; vendor preset: enabled)
	     Active: active (running) since Fri 2021-09-17 23:28:10 CEST; 1 day 19h ago
	   Main PID: 1064180 (smfc.py)
	      Tasks: 1 (limit: 38371)
	     Memory: 7.4M
	        CPU: 41.917s
	     CGroup: /system.slice/smfc.service
	             └─1064180 /usr/bin/python3 /opt/smfc/smfc.py -c /opt/smfc/smfc.conf -l 2

	Sep 19 17:12:39 home smfc.service[1064180]: CPU zone: new level > 39.0C > [T:40.0C/L:61%]
	Sep 19 17:12:42 home smfc.service[1064180]: CPU zone: new level > 33.0C > [T:35.0C/L:48%]
	Sep 19 17:48:14 home smfc.service[1064180]: CPU zone: new level > 38.0C > [T:40.0C/L:61%]

If you are testing your configuration, you can start `smfc.py` directly in a terminal. Logging to the standard output and debug log level are useful in this case:

	cd /opt
	sudo smfc.py -o 0 -l 3

### 13. Checking result and monitoring logs
All messages will be logged to the specific output and the specific level.
With the help of command `journalctl` you can check logs easily. For examples:

1. listing service logs of the last two hours:

		journalctl -u smfc --since "2 hours ago"

2. listing service logs from the last boot:

		journalctl -b -u smfc

## 14. FAQ

### Q: My fans are spinning up and loud. What is wrong?
Most probably the rotation speed of the fans went above or below of a threshold value
You can check the current fan rotation speeds:

	ipmitool sdr

and you can also check event log on Super Micro remote web interface (Server Health > Health Event log). If you see Assertions log messages for fans:

	Fan(FAN1)	Lower Critical - going low - Assertion
	Fan(FAN1)	Lower Non-recoverable - going low - Assertion
	Fan(FAN1)	Lower Non-recoverable - going low - Deassertion
	Fan(FAN1)	Lower Critical - going low - Deassertion
	Fan(FAN4)	Lower Critical - going low - Assertion
	Fan(FAN4)	Lower Non-recoverable - going low - Assertion

then you must adjust your configuration (i.e. threshold values) because IPMI switched back to full rotation speed.

### Q: I would like to use constant fan rotation speed in one or both zones. How can I configure that?
You should configure the temperatures and levels with the same value. 

	min_temp=40
	max_temp=40
	min_level=60
	max_level=60

With this setup there will be a constant 60% fan level in the specific zone. The temperature value is ignored, `steps` parameter is also ignored.

### Q: I receive an error message "Cannot read hwmon*/temp1_input file". What is the problem?
The problem is that the specific file cannot be found in HWMON system. The potential reasons behind this issue could be:
 - `drivetemp` driver cannot support your disks (it support only SATA hard disks). In case of SAS/SCSI hard disks you can use `hddtemp` instead of `drivetemp`. See more details in [issue #21](https://github.com/petersulyok/smfc/issues/21).
 - Maybe you specified the `hwmon_path=` parameter manually and it contains an invalid path. You can correct it.

### Q: How does the author test/use this service?
The configuration is the following:

 - [Super Micro X11SCH-F motherboard](https://www.supermicro.com/en/products/motherboard/X11SCH-F)
 - [Intel Core i3-9300T CPU](https://ark.intel.com/content/www/us/en/ark/products/134875/intel-core-i39300t-processor-8m-cache-up-to-3-80-ghz.html)
 - 64 GB ECC DDR4 RAM
 - [Fractal Design Node 804 case](https://www.fractal-design.com/products/cases/node/node-804/black/), with separate chambers for the motherboard and the hard disks:
 
	<img src="https://www.legitreviews.com/wp-content/uploads/2014/05/fractal-design-node-804-vendor-fans.jpg" align="center" width="500">

 - Debian Linux LTS (actually bullseye with backport Linux kernel 6.0)
 - 8 x [WD Red 12TB (WD120EFAX)](https://shop.westerndigital.com/en-ie/products/outlet/internal-drives/wd-red-plus-sata-3-5-hdd#WD120EFAX) hard disks in ZFS RAID
 - 3 x [Noctua NF-12 PWM](https://noctua.at/en/products/fan/nf-f12-pwm)  fans (FAN1, FAN2, FAN4) in CPU zone 
 - 2 x [Noctua NF-12 PWM](https://noctua.at/en/products/fan/nf-f12-pwm) fans (FANA, FANB) in HD zone

## 15. References
Further readings:

 - [\[STH forums\] Reference Material: Supermicro X9/X10/X11 Fan Speed Control](https://forums.servethehome.com/index.php?resources/supermicro-x9-x10-x11-fan-speed-control.20/)
 - [\[TrueNAS forums\] How To: Change IPMI Sensor Thresholds using ipmitool](https://www.truenas.com/community/resources/how-to-change-ipmi-sensor-thresholds-using-ipmitool.35/)
 - [\[TrueNAS forums\] Script to control fan speed in response to hard drive temperatures](https://www.truenas.com/community/threads/script-to-control-fan-speed-in-response-to-hard-drive-temperatures.41294/)
 - [\[Pcfe's blog\] Set fan thresholds on my Super Micro H11DSi-NT](https://blog.pcfe.net/hugo/posts/2018-08-14-epyc-ipmi-fans/)
 - [\[Super Micro\] IPMI Utilities](https://www.supermicro.com/en/solutions/management-software/ipmi-utilities)
 - Documentation of [`coretemp`](https://www.kernel.org/doc/html/latest/hwmon/coretemp.html) kernel module
 - Documentation of [`drivetemp`](https://www.kernel.org/doc/html/latest/hwmon/drivetemp.html) kernel module and its [GitHub project](https://github.com/groeck/drivetemp)

Similar projects:
 - [\[GitHub\] Kevin Horton's nas_fan_control](https://github.com/khorton/nas_fan_control)
 - [\[GitHub\] Rob Urban's fork nas_fan control](https://github.com/roburban/nas_fan_control)
 - [\[GitHub\] sretalla's fork nas_fan control](https://github.com/sretalla/nas_fan_control)
 - [\[GitHub\] Andrew Gunnerson's ipmi-fan-control](https://github.com/chenxiaolong/ipmi-fan-control)

> Written with [StackEdit](https://stackedit.io/).
