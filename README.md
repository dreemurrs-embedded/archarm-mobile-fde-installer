# archarm-mobile-fde-installer
## Description
This script allows you to install [Arch Linux ARM for PinePhone / PineTab](https://github.com/dreemurrs-embedded/Pine64-Arch) with full disk encryption.
## How to install
If you want to install Arch on your eMMC, you have to boot from your SD card. If you want to install Arch to the SD card, you have to boot from the eMMC. Once you booted, you should execute the following steps:
```
sudo pacman -S wget squashfs-tools
# If you don't like URL shorteners, you can also type
# wget https://raw.githubusercontent.com/dreemurrs-embedded/archarm-mobile-fde-installer/master/installer.sh
wget tinyurl.com/archFDE
chmod +x archFDE
./archFDE
```

Now you just need to answer the questions from the script and after a little while you successfully installed FDE Arch :)
