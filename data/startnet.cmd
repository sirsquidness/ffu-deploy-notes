wpeinit

REM DO: update the IP address here to point to either IP or hostname of your Docker SMB server created previous step
net use g: \\10.0.2.216\share

REM DO: uncomment first line to enable capture mode. Uncomment second line to enable deploy mode.
REM dism /capture-ffu /imagefile=g:\test.ffu /capturedrive=\\.\PhysicalDrive0 /name:disk0 /description:"Capture lol"
REM DISM /apply-ffu /ImageFile=g:\test.ffu /ApplyDrive:\\.\PhysicalDrive0

echo "Process finished."
REM DO: Consider adding a reboot at this step. Without a shutdown -r -t 0 here, after finishing the dism command it will sit at command prompt forever. `exit` might also work.