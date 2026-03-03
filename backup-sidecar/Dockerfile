FROM rclone/rclone:1.73.1

RUN apk add --no-cache curl jq

COPY backup.sh /backup.sh
RUN chmod +x /backup.sh

ENTRYPOINT ["/backup.sh"]
