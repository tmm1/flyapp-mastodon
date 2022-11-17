## Mastodon on fly.io

[Mastodon](https://github.com/mastodon/mastodon) is a free, open-source social network server based on ActivityPub.

The Mastodon server is implemented a rails app, which relies on postgres and redis. It uses sidekiq for background jobs, along with a separate nodejs http streaming server.

Docker images: https://hub.docker.com/r/tootsuite/mastodon/

Dockerfile: https://github.com/mastodon/mastodon/blob/main/Dockerfile

docker-compose.yml: https://github.com/mastodon/mastodon/blob/main/docker-compose.yml

### Setup

#### App

Fork this repo and clone a copy of it. Choose a name for your app that isn't already taken on Fly, and run the script `bin/name YOURNAME`. Follow this readme from inside your repo, after you have run the script, so that all of the steps will be updated for the name of your Fly app.

```
$ fly apps create mastodon-example
$ fly scale memory 1024 # Rails + Sidekiq needs more than 512
```

#### Secrets

```
$ SECRET_KEY_BASE=$(docker run --rm -it tootsuite/mastodon:latest bin/rake secret)
$ OTP_SECRET=$(docker run --rm -it tootsuite/mastodon:latest bin/rake secret)
$ fly secrets set OTP_SECRET=$OTP_SECRET SECRET_KEY_BASE=$SECRET_KEY_BASE
$ docker run --rm -e OTP_SECRET=$OTP_SECRET -e SECRET_KEY_BASE=$SECRET_KEY_BASE -it tootsuite/mastodon:latest bin/rake mastodon:webpush:generate_vapid_key | fly secrets import
```

#### Redis server

Redis is used to store the home/list feeds, along with the sidekiq queue information. The feeds can be regenerated using `tootctl`, so persistence is [not strictly necessary](https://docs.joinmastodon.org/admin/backups/#failure).

```
$ fly apps create mastodon-example-redis
$ bin/fly-redis volumes create --region sjc --size 1 mastodon_redis
$ bin/fly-redis deploy
```

#### Storage (user uploaded photos and videos)

The `fly.toml` uses a `[mounts]` section to connect the `/opt/mastodon/public/system` folder to a persistent volume.

Create that volume below, or remove the `[mounts]` section and uncomment `[env] > S3_ENABLED` for S3 storage.

##### Option 1: Local volume

```
$ fly volumes create --region sjc mastodon_uploads
```

##### Option 2: S3, etc

```
$ fly secrets set AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=yyy
```

See [lib/tasks/mastodon.rake](https://github.com/mastodon/mastodon/blob/5ba46952af87e42a64962a34f7ec43bc710bdcaf/lib/tasks/mastodon.rake#L137) for how to change your `[env]` section for Wasabi, Minio or Google Cloud Storage.

#### Postgres database

```
$ fly pg create --region sjc --name mastodon-example-db
$ fly pg attach mastodon-example-db
$ fly deploy -c fly.setup.toml # run `rails db:schema:load`, may take 2-3 minutes
```

### Deploy

```
$ fly deploy
```

### Custom domain (optional)

1. Edit `fly.toml` and set `LOCAL_DOMAIN` to your custom domain.
2. Run `fly ips list`, and if the list is empty, run `fly ips allocate-v4`. 
3. Then, create DNS records for your custom domain.

    If your DNS host supports ALIAS records:

    ```
    @   ALIAS mastodon-example.fly.dev
    www CNAME mastodon-example.fly.dev
    ```

    If your DNS host only allows A records, use the IP. For example, if your IP was `3.3.3.3`:

    ```
    @   A     3.3.3.3
    www CNAME @
    ```

4. Finally, generate SSL certificates from Let's Encrypt:

    ```
    $ fly certs add MYDOMAIN.COM
    $ fly certs add WWW.MYDOMAIN.COM
    ```
