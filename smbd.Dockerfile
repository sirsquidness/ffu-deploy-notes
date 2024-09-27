FROM ubuntu:noble
RUN apt-get update && apt-get install -y samba && apt-get clean
ADD smb.conf /etc/samba/smb.conf
ENTRYPOINT ["smbd", "--foreground", "--no-process-group"]