# Proxy settings

We'll automatically use the `HTTP_X_FORWARDED_FOR` header to determine the client's IP address when behind a trusted proxy.

If you need to use a different header to determine the client's IP address, you can set the `AIKIDO_CLIENT_IP_HEADER` environment variable to the name of that header. This will override the default `HTTP_X_FORWARDED_FOR` header.

```bash
# For Fly.io Platform
AIKIDO_CLIENT_IP_HEADER=HTTP_FLY_CLIENT_IP bin/rails server
```
