# Harbor Setup

This folder adds a Harbor deployment scaffold next to the existing Gitea setup.
It is designed for this host, where:

- `nginx-proxy-manager` already owns ports `80/443`
- Harbor should be published on a separate domain such as `harbor.precia.site`
- Harbor should bind to a non-conflicting internal host port and sit behind the reverse proxy

## Design

- Harbor version is pinned in [`.env`](./.env) to `v2.15.0`
- Harbor frontend listens on internal port `8080`
- Harbor advertises `external_url=https://harbor.precia.site`
- TLS is expected to terminate at the reverse proxy, not inside Harbor itself
- The official Harbor `prepare` step is used to generate Harbor's upstream `docker-compose.yml`
- The day-to-day lifecycle is then managed with `docker compose`
- The Harbor frontend joins the external Docker network configured by `HARBOR_PROXY_NETWORK` and is exposed there with alias `HARBOR_PROXY_ALIAS`

## Files

- [`.env`](./.env): version pin, domain, passwords, storage paths
- [`harbor.yml.template`](./harbor.yml.template): templated Harbor config
- [`prepare-compose.sh`](./prepare-compose.sh): downloads the official release, renders config, and runs Harbor `prepare`
- [`compose-up.sh`](./compose-up.sh): starts Harbor with `docker compose up -d`
- [`compose-down.sh`](./compose-down.sh): stops Harbor
- [`compose-ps.sh`](./compose-ps.sh): shows Harbor service status
- [`compose-logs.sh`](./compose-logs.sh): tails Harbor logs

## Usage

1. Edit [`.env`](./.env) and change at least:
   - `HARBOR_HOSTNAME`
   - `HARBOR_EXTERNAL_URL`
   - `HARBOR_ADMIN_PASSWORD`
   - `HARBOR_DB_PASSWORD`
   - `HARBOR_PROXY_NETWORK` if your reverse proxy uses a different Docker network name
2. Create the persistent host paths configured in [`.env`](./.env). The defaults point to user-writable directories inside this folder, so `sudo` is usually not needed:

```bash
set -a
. ./.env
set +a
mkdir -p "$HARBOR_DATA_VOLUME" "$HARBOR_LOG_LOCATION"
```

3. From this directory, prepare the official Harbor Compose stack:

```bash
./prepare-compose.sh
```

4. Start Harbor:

```bash
./compose-up.sh
```

5. Inspect Harbor:

```bash
./compose-ps.sh
./compose-logs.sh
```

The generated upstream Compose file lives at:

- [`installer/harbor/docker-compose.yml`](./installer/harbor/docker-compose.yml)

You can also manage Harbor directly with Docker Compose after `prepare-compose.sh` has run:

```bash
docker compose -f ./installer/harbor/docker-compose.yml up -d
docker compose -f ./installer/harbor/docker-compose.yml ps
docker compose -f ./installer/harbor/docker-compose.yml logs --tail=200
docker compose -f ./installer/harbor/docker-compose.yml down
```

## Reverse Proxy

Because this host already runs Nginx Proxy Manager on `80/443`, Harbor is designed to be reached through a shared Docker network instead of a published host port.

Recommended NPM settings:

- Domain: `harbor.precia.site`
- Scheme: `http`
- Forward Hostname / IP: `harbor-proxy`
- Forward Port: `8080`
- Websockets: `on`
- Block Common Exploits: `off` if uploads are misbehaving

Requirements:

- The Nginx Proxy Manager container must be attached to the Docker network named by `HARBOR_PROXY_NETWORK`
- Harbor's generated `proxy` service will join that same network with alias `HARBOR_PROXY_ALIAS`

Recommended custom Nginx config in NPM:

```nginx
client_max_body_size 0;
proxy_request_buffering off;
proxy_buffering off;
```

## Docker Usage

Create a Harbor project first, for example `apps`, then:

```bash
docker login harbor.precia.site
docker pull alpine:3.20
docker tag alpine:3.20 harbor.precia.site/apps/alpine-test:3.20
docker push harbor.precia.site/apps/alpine-test:3.20
docker pull harbor.precia.site/apps/alpine-test:3.20
```

## Notes

- Harbor must not use `localhost` or `127.0.0.1` as its hostname.
- If you change the data or log paths back to something like `/srv/...`, you may need `sudo` to create or manage those directories.
- If you change `HARBOR_PROXY_NETWORK` or `HARBOR_PROXY_ALIAS`, run [`compose-down.sh`](./compose-down.sh) and then [`compose-up.sh`](./compose-up.sh) so the generated Compose file is rebuilt.
- This scaffold intentionally does not auto-run Harbor in this turn, because the official prepare step will generate and then start a large multi-container stack.
- If you want, the next step is to run [compose-up.sh](./compose-up.sh) and then wire `harbor.precia.site` into Nginx Proxy Manager.
