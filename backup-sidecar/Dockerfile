FROM rclone/rclone:1.73.1

RUN apk add --no-cache curl=8.17.0-r1 jq=1.8.1-r0

COPY backup.sh /backup.sh
RUN chmod +x /backup.sh

ENTRYPOINT ["/backup.sh"]
