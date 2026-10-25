FROM alpine:3.22

RUN apk add --no-cache python3 ca-certificates

ADD --chmod=755 https://github.com/aptible/supercronic/releases/download/v0.2.33/supercronic-linux-amd64 /usr/local/bin/supercronic

RUN adduser -D app
RUN mkdir /textfile
RUN chown app:app /textfile

WORKDIR /app
COPY url-probe/probe.py /app/probe.py
COPY crontab /app/crontab

USER app
CMD ["/usr/local/bin/supercronic", "/app/crontab"]
