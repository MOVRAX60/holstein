Run This to create self signed certs for testing

```commandline
openssl req -x509 -nodes -newkey rsa:2048 \
  -keyout server.key -out server.crt -days 365 \
  -subj "/CN=rancher.local(HOSTNAME)" \
  -addext "subjectAltName=DNS:localhost,IP:(ADDRESS)"
```