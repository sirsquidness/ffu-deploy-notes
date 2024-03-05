# Windows FFU image deploy notes

These notes describe how to capture then deploy a Windows PC image using FFU images, using the least Windows possible.

tl;dr - we will use iPXE to boot a PXE environment, including iPXE's wimboot that allows injecting overlay files to a `.wim` image file. We will inject small scripts to trigger capture and deploying.

Requirements:
* A host with Docker
* An ISO or similar of Windows 10 or 11 installation media
* A DHCP server
* A TFTP server

## A Linux SMB server

On a Linux box with Docker and adequate storage space:

```

cat <<EOF >Dockerfile
FROM ubuntu:focal
RUN apt-get update && apt-get install -y samba && apt-get clean
ADD smb.conf /etc/samba/smb.conf
ENTRYPOINT ["smbd", "--interactive", "--log-stdout"]
EOF

cat <<EOF >smb.conf
[global]
   workgroup = WORKGROUP
   server string = %h server (Samba, Ubuntu)
   dns proxy = no
   log file = /var/log/samba/log.%m
   max log size = 1000
   syslog = 0
   panic action = /usr/share/samba/panic-action %d

   server role = standalone server
   passdb backend = tdbsam
   obey pam restrictions = yes
   map to guest = bad user

   server services = -dns, -nbt
   server signing = default
   server multi channel support = yes
   disable spoolss = yes
   disable netbios = yes

   security = user
   guest account = nobody
   create mask = 0664
   force create mode = 0664
   directory mask = 0775
   force directory mode = 0775
[share]
    comment = All ur data r belong 2 us
    path = /srv/share
    browsable = yes
    guest ok = yes
    read only = no
    create mask = 0755
    acl allow execute always = yes
EOF
```

mkdir -p share
chmod 777 share/
docker build -t samba .

docker run -d --restart=unless-stopped -v /data/temp/share:/srv/share samba

## Preparing the WIM boot file

On a PC with a web server, mount a Windows 10 or 11 ISO file. From this, extract:
* `boot/bcd`
* `bood/bcd.sdi`
* `sources/boot.wim`

Put these files in a folder on your webserver.

In the same directory, create a new file called `boot.ipxe` with contents:

```
#!ipxe
kernel wimboot 
initrd bcd         BCD
initrd boot.sdi    boot.sdi
initrd --name boot.wim winpe_amd64.wim boot.wim
initrd startnet.cmd startnet.cmd
# DO: customise desktop background by putting a jpg in this same folder called winpe.jpg then uncommenting this line
# initrd winpe.jpg winpe.jpg
# You can add extra initrd lines here to overlay extra files in to the x:\windows\system32\ directory of the WinPE environment, including adding full blown scripts, exe files, etc.
imgstat
boot
```

In the same directory, create a new file called `startnet.cmd` with contents:

```
wpeinit

REM DO: update the IP address here to point to either IP or hostname of your Docker SMB server created previous step
net use g: \\10.0.243.0\share

REM DO: uncomment first line to enable capture mode. Uncomment second line to enable deploy mode.
REM dism /capture-ffu /imagefile=g:\test.ffu /capturedrive=\\.\PhysicalDrive0 /name:disk0 /description:"Capture lol"
REM DISM /apply-ffu /ImageFile=g:\test.ffu /ApplyDrive:\\.\PhysicalDrive0

echo "Process finished."
REM DO: Consider adding a reboot at this step. Without a shutdown -r -t 0 here, after finishing the dism command it will sit at command prompt forever. `exit` might also work.
```

Important: if your target PCs need special drivers injected, you will need to inject drivers separately to the boot.wim file manually (eg using MDT or dism.exe or similar)

## Preparing iPXE

On a linux box (take note of the `DO:` things as you need to do manual steps):
```
git clone https://github.com/ipxe/ipxe.git
cd ipxe/src

cat <<EOF >boot.ipxe
#!ipxe

echo "Doing DHCP!"
dhcp
echo "DHCP done! About to chain load"

# DO: Replace the IP address here with a relevant IP or hostname and path for the webserver created in previous step
chain http://10.0.1.9/boot.ipxe
EOF

# undionly.kpxe is for old style BIOS netbooting. ipxe.efi is for (U)EFI netbooting.
make bin/undionly.kpxe EMBED=boot.ipxe
make bin-x86_64-efi/ipxe.efi EMBED=boot.ipxe

# DO: put either undionly.kpxe or ipxe.efi on your TFTP server.
# DO: set your DHCP server to provide the TFTP server address and bootfilename to point to one of the above files
```

