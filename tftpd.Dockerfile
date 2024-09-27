FROM alpine:latest
RUN apk add --no-cache tftp-hpa
RUN mkdir -p /var/tftp_files
WORKDIR /var/tftp_files
EXPOSE 69/udp
CMD ["in.tftpd", "--foreground", "--address", "0.0.0.0:69", "--secure", "/var/tftp_files"]