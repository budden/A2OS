# Сборка нативных образов

(This document in Russian describes bare metal image builds)

[Источник на oberoncore.ru](https://forum.oberoncore.ru/viewtopic.php?f=22&t=6386#p107603)

Если хочется попробовать запустить A2 на голом железе, это можно сделать.

Тут на форуме одна рекомендация была уже. Kemet писал:
```
В этом файле есть пункт:
# Step 3e: Create image for bootable USB (A2USB.img)
Создание других образов ещё не поправлено
```

Т.е. надо:

1) создать папку `Test` (на уровень выше рабочей папки Work. Если А2.exe запустить с настройками по-умолчанию, папку Test надо создать в той же папке, где лежит А2.exe);

2) открыть `Build.Tool`;

3) выполнить шаг 1 из `Build.Tool` (всё скомпилировать в папку `Test`):
```
# Step 1: Compile modules and generate ZIP packages
Release.Build --path="../Test/" --build --zip --xml Bios32 ~
```
4) выполнить шаг 3e из `Build.Tool`.

В итоге у нас в папке `Test` появится образ, пригодный для записи на флешку (записать можно, например, с помощью `win32diskimager`). И всё. Заставить его загружаться хоть в какой-нибудь виртуалке не получилось. QEMU, вроде, поддерживает эмуляцию загрузочных USB в [трёх различных вариантах эмуляции](https://git.qemu.org/?p=qemu.git;a=blob_plain;f=docs/usb-storage.txt), но тоже результата я не добился.

Тем не менее, флешка нормально загрузилась на моём старом ноутбуке Samsung R518.

Гораздо полезнее, как оказалось, сделать загрузочный образ HDD. С него удалось загрузиться в QEMU и BOCHS.
Слегка модифицировав команды из шага 3e из `Build.Tool` получил генератор образов HDD:

```
# Create image for bootable HDD (A2IDE.img)

System.DoCommands

Compiler.Compile -p=Bios32 --destPath=../Test/ BIOS.PCI.Mod UsbEhci.Mod BIOS.UsbEhciPCI.Mod  ~

PCAAMD64.Assemble OBLUnreal.Asm ~
PartitionsLib.SetBootLoaderFile OBLUnreal.Bin ~
PCAAMD64.Assemble BootManager.Asm ~
BootManager.Split BootManager.Bin ~
System.Timer start ~

FSTools.DeleteFiles -i ../Test/A2IDE.img ~

VirtualDisks.Create ../Test/A2IDE.img 320000 512 ~
VirtualDisks.Install -b=512 VDISK0 ../Test/A2IDE.img ~

Partitions.WriteMBR VDISK0#0 OBEMBR.BIN ~
Partitions.InstallBootManager VDISK0#0 BootManagerMBR.Bin BootManagerTail.Bin ~
Partitions.Create VDISK0#1 76 150 ~

Linker.Link --path=../Test/ --displacement=100000H --fileName=../Test/IDE.Bin Kernel Traps
	ATADisks DiskVolumes DiskFS Loader BootConsole ~

Partitions.Format VDISK0#1 AosFS -1 ../Test/IDE.Bin ~ (* -1 makes sure that actual boot file size is taken as offset for AosFS *)
FSTools.Mount TEMP AosFS VDISK0#1 ~

ZipTool.ExtractAll --prefix=TEMP: --sourcePath=../Test/ --overwrite --silent
	Kernel.zip System.zip Drivers.zip ApplicationsMini.zip Applications.zip Compiler.zip CompilerSrc.zip
	GuiApplicationsMini.zip GuiApplications.zip Fun.zip Contributions.zip Build.zip EFI.zip
	Oberon.zip OberonGadgets.zip OberonApplications.zip OberonDocumentation.zip
	KernelSrc.zip SystemSrc.zip DriversSrc.zip ApplicationsMiniSrc.zip ApplicationsSrc.zip GuiApplicationsMiniSrc.zip GuiApplicationsSrc.zip FunSrc.zip BuildSrc.zip
	ScreenFonts.zip CjkFonts.zip TrueTypeFonts.zip ~

FSTools.Watch TEMP ~
FSTools.Unmount TEMP ~

Partitions.SetConfig VDISK0#1
	TraceMode="4" 
	TracePort="1" 
	TraceBPS="115200"
	BootVol1="AOS AosFS IDE0#1"
	AosFS="DiskVolumes.New DiskFS.NewFS"
	CacheSize="1000"
	ExtMemSize="512"
	MaxProcs="-1"
	ATADetect="legacy"
	Init="117"
	Boot="DisplayLinear.Install"
	Boot1="Keyboard.Install;MousePS2.Install"
	Boot2="DriverDatabase.Enable;UsbHubDriver.Install;UsbEhciPCI.Install;UsbUhci.Install;UsbOhci.Install"
	Boot3="WindowManager.Install"
	Boot4="Autostart.Run"
	~
VirtualDisks.Uninstall VDISK0 ~

System.Show HDD image build time:  ~ System.Timer elapsed ~

FSTools.CloseFiles ../Test/A2IDE.img ~

```

Для загрузки в BOCHS надо скачать последние версии: [BOCHS](http://bochs.sourceforge.net/), [BIOS-bochs-latest](https://raw.githubusercontent.com/lubomyr/bochs/master/bios/BIOS-bochs-latest), [VGABIOS-lgpl-latest.bin](http://cvs.savannah.gnu.org/viewvc/*checkout*/vgabios/vgabios/VGABIOS-lgpl-latest.bin?revision=HEAD). Положить всё в одну папку, а также положить такой текстовый файл конфигурации машины (назвать `bochsrc.bxrc`):

```
megs: 1024
romimage: file=BIOS-bochs-latest
vgaromimage: file=VGABIOS-lgpl-latest.bin
vga: extension=vbe, update_freq=60
ata0-master: type=disk, path=A2IDE.img, cylinders=203, heads=16, spt=63
boot: disk
log: bochsout.txt
mouse: enabled=1
cpu: ips=15000000
```

QEMU - виртуальная машинка поинтереснее. В ней можно настроить вывод отладочной информации через COM-порт в отдельное окно (этот образ HDD, созданный по приведённой инструкции,  как-раз будет её выводить на COM1 со скоростью 115200).

Батник для запуска QEMU прилагается (a2ide qemu.bat) :
``` 
"c:\Program Files\qemu\qemu-system-x86_64.exe" -drive file=A2IDE.img,format=raw -m 1024 -machine pc -chardev serial,id=com1,path=com1
```

Когда при запуске появится диалог настроек COM-порта, там как-раз надо выбрать скорость 115200.
