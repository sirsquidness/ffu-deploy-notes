# Windows FFU image deploy notes

These notes describe how to capture then deploy a Windows PC image using FFU images, using the least Windows possible.

tl;dr - we will use iPXE to boot a PXE environment, including iPXE's wimboot that allows injecting overlay files to a `.wim` image file. We will inject small scripts to trigger capture and deploying.

Requirements:
* A host with Docker
* An ISO or similar of Windows 10 or 11 installation media
* A DHCP server
* A TFTP server

## Steps to Do

### A Linux SMB server

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

# do folder permission crimes to let smb inside docker write to this folder
mkdir -p share
chmod 777 share/
docker build -t samba .

docker run -d --restart=unless-stopped -v $(pwd)/share:/srv/share samba
```


### Preparing the WIM boot file

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

In the same directory, [download the latest version of `wimboot`](https://github.com/ipxe/wimboot/releases/latest/download/wimboot) and make sure it has a filename of `wimboot`.

Important: if your target PCs need special drivers injected, you will need to inject drivers separately to the boot.wim file manually (eg using MDT or dism.exe or similar)

### Preparing iPXE

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

## How to prepare the Windows PC for capture and/or deploy

1) Install Windows 10 or 11 on a PC
2) Do whatever you want - install stuff, change settings, etc etc
3) Shutdown cleanly and reboot in to the WinPE capture environment

No sysprep needed!

## Notes on how it works

In custom building iPXE, we are able to embed a config file in it. This saves a bunch of complexity in the DHCP server configuration. iPXE allows us to boot from HTTP servers, including from `.wim` files.

The `wimboot` package extends iPXE to support booting from `.wim` files. Instead of using MDT or ADK or other big fat silly Windows packages to inject a single file in to the `boot.wim`, we use the `wimboot` package to overlay the script file we want. This means (except for any drivers we need to inject) we can use an entirely vanilla `boot.wim` file.

Being that `startnet.cmd` is just a regular old batch file, you could customise it to your hearts content. eg, "Press F in the next 60 seconds to capture an image from this PC or else we'll start automatically imaging this PC". Or making it so that deploying an image pulls from a read only share, but capturing an image will ask for username/password to mount the share with so that you don't have to have a globally writable windows share to store the images. The only requirement is that the first line of this file is `wpeinit`.

Likewise, being that the `boot.ipxe` and the `startnet.cmd` files are served by a HTTP server, they could trivially both be dynamically generated. eg, press button to enter imaging mode and the next PC to network boot will auto-capture an image. Or having the script poll a backend to post success/failure results.

There are ways to customise the DHCP server so that it will serve `undionly.kpxe` to regular BIOS netboot clients and `ipxe.efi` to EFI based netboot clients. [Here is an example](https://docs.fogproject.org/en/latest/kb/how-tos/bios-and-uefi-co-existence/#using-linux-dhcp) that you'd need to adapt to this scenario. Without adding something like this you can only support EITHER BIOS _or_ EFI netbooting ... I think. And hence above, you have to pick setting the bootfilename to either `undionly.kpxe` or `ipxe.efi` according to what you're targetting.

FFU files advertise in the Microsoft docs that they can be "optimised". Be aware that this apparently only works if the FFU image is of a sysprep'd system. As we are NOT syspreping, do NOT optimise. When we tried it, it truncated almost the entire image.

Scaling out is easy. When deploying the FFU image, you can create multiple cloned SMB servers all containing the same configuration and FFU file. Put all of the servers behind a round-robin DNS record and use that DNS record in the `net use` statement. Or, have whatever generates the `startnet.cmd` file do the round robining for you. Last time we did this, we had 5 servers running and managed to get a large fraction of 100Gbps of imaging traffic. Be aware that round robin DNS records might get cached by your DNS resolvers somewhere in your LAN, and so it can be prudent to set a 1 second TTL on the record, and also have the `startnet.cmd` script include a random wait of, eg, up to a minute.

Security in this configuration is an afterthought. The Windows SMB share is globally writable by anonymous users. It is left as an exercise for the reader to lock it down a bit more.
