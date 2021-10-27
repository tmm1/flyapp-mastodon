## Mastodon on fly.io

[Mastodon](https://github.com/mastodon/mastodon) is a free, open-source social network server based on ActivityPub.

The Mastodon server is implemented a rails app, which relies on postgres and redis. It uses sidekiq for background jobs, along with a separate nodejs http streaming server.

Docker images: https://hub.docker.com/r/tootsuite/mastodon/

Dockerfile: https://github.com/mastodon/mastodon/blob/main/Dockerfile

docker-compose.yml: https://github.com/mastodon/mastodon/blob/main/docker-compose.yml

### Setup

#### App

```
$ fly apps create --name mastodon
```

#### Postgres database

```
$ fly pg create --region iad --name mastodon-db
$ fly secrets set DB_PASS=xxxx # password from output above
```

#### Redis server

Redis is used to store the home/list feeds, along with the sidekiq queue information. The feeds can be regenerated using `tootctl`, so persistence is [not strictly necessary](https://docs.joinmastodon.org/admin/backups/#failure).

```
$ fly apps create --name mastodon-redis
$ fly volumes create -c fly.redis.toml --region iad mastodon_redis
$ fly deploy --config fly.redis.toml --build-target redis-server
```

#### Secrets

```
$ SECRET_KEY_BASE=$(docker run --rm -it tootsuite/mastodon:latest bin/rake secret)
$ OTP_SECRET=$(docker run --rm -it tootsuite/mastodon:latest bin/rake secret)
$ fly secrets set OTP_SECRET=$OTP_SECRET SECRET_KEY_BASE=$SECRET_KEY_BASE
$ docker run --rm -e OTP_SECRET=$OTP_SECRET -e SECRET_KEY_BASE=$SECRET_KEY_BASE -it tootsuite/mastodon:latest bin/rake mastodon:webpush:generate_vapid_key | fly secrets import
```

#### Storage (user uploaded photos and videos)

The `fly.toml` uses a `[mounts]` section to connect the `/opt/mastodon/public/system` folder to a persistent volume.

Create that volume below, or remove the `[mounts]` section and uncomment `[env] > S3_ENABLED` for S3 storage.

##### Option 1: Volume

```
$ fly volumes create --region iad mastodon_uploads
```

##### Option 2: S3

```
$ fly secrets set AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=yyy
```

### Deploy

```
$ fly deploy
```
