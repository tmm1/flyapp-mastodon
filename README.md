## Mastodon on fly.io

[Mastodon](https://github.com/mastodon/mastodon) is a free, open-source social network server based on ActivityPub.

The Mastodon server is implemented a rails app, which relies on postgres and redis. It uses sidekiq for background jobs, along with a separate nodejs http streaming server.

#### Reference:

Docker images: https://hub.docker.com/r/tootsuite/mastodon/

Dockerfile: https://github.com/mastodon/mastodon/blob/main/Dockerfile

docker-compose.yml: https://github.com/mastodon/mastodon/blob/main/docker-compose.yml

### Setup

*Important notes*: 

* Ensure your [fly.toml](fly.toml) `[env]` section is fully populated before running any deploys of the application. mastodon will happily deploy with incorrect or invalid environment variables, which can break things later on [[1](https://github.com/mastodon/mastodon/issues/20820)]. 
* `fly` can automatically place your application in the optimal region for you, you can drop the `--region` flag and args if desired.
* You'll likely want to run this from a custom domain with SSL certificates, familiarize yourself with this guide: https://fly.io/docs/app-guides/custom-domains-with-fly/
* You'll want SMTP services enabled, sendgrid has a nice free tier, we'll use them in the `[env]` section of our [fly.toml](fly.toml)

#### App

```
$ fly apps create --region iad --name mastodon
$ fly scale memory 512 # rails needs more than 256mb
```

#### Secrets

```
$ SECRET_KEY_BASE=$(docker run --rm -it tootsuite/mastodon:latest bin/rake secret)
$ OTP_SECRET=$(docker run --rm -it tootsuite/mastodon:latest bin/rake secret)
$ fly secrets set OTP_SECRET=$OTP_SECRET SECRET_KEY_BASE=$SECRET_KEY_BASE   
```

The VAPID Keys are requisite for the [mastodon streaming API](https://docs.joinmastodon.org/methods/timelines/streaming/), they are generated in a way that doesn't play nicely with stdout, so you should surround them with quotations when setting as `fly` secrets.
```
$ docker run --rm -it tootsuite/mastodon:latest bin/rake mastodon:webpush:generate_vapid_key
```
The output of the previous command will look similar to this:
```
$ VAPID_PRIVATE_KEY=UWDTCtxJ-9QEXAMPLEz8TmKEYIVpYfhHOuOFI7ELvn0=
$ VAPID_PUBLIC_KEY=EXAMPLE_gzKiuO27vtpNVU3VgymkeyIKp5kbIiDmfkeyyhbkvYSxsu5s4eMeX-EXAMPLE=
```
Quote those values and set them as `fly` secrets:
```
$ fly secrets set VAPID_PRIVATE_KEY="UWDTCtxJ-9QEXAMPLEz8TmKEYIVpYfhHOuOFI7ELvn0=" VAPID_PUBLIC_KEY="EXAMPLE_gzKiuO27vtpNVU3VgymkeyIKp5kbIiDmfkeyyhbkvYSxsu5s4eMeX-EXAMPLE="
```

#### Redis server

Redis is used to store the home/list feeds, along with the sidekiq queue information. The feeds can be regenerated using `tootctl`, so persistence is [not strictly necessary](https://docs.joinmastodon.org/admin/backups/#failure).

```
$ fly apps create --region iad --name mastodon-redis
$ fly volumes create -c fly.redis.toml --region iad mastodon_redis
$ fly deploy --config fly.redis.toml --build-target redis-server
```

#### Storage (user uploaded photos and videos)

The [fly.toml](fly.toml) uses a `[mounts]` section to connect the `/opt/mastodon/public/system` folder to a persistent volume.

Create that volume below, or remove the `[mounts]` section and uncomment `[env] > S3_ENABLED` for S3 storage.

##### Option 1: Local volume

```
$ fly volumes create --region iad mastodon_uploads
```

##### Option 2: S3, R2, Min.io, Wasabi etc

*Note: You will need an object storage bucket already made and S3 compatible API keys that can access it. (for this example we will use Cloudflare's R2 bucket)*

###### Setup R2

1. [Create an S3 Auth Token](https://developers.cloudflare.com/r2/data-access/s3-api/tokens/)
2. Create Bucket 
3. Configure Bucket to enable [Domain Access](https://developers.cloudflare.com/r2/data-access/public-buckets/#connect-your-bucket-to-a-custom-domain) 
4. Optional: enable other cloudflare services as desired.


```
$ fly secrets set AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=yyy
```

See [lib/tasks/mastodon.rake](https://github.com/mastodon/mastodon/blob/5ba46952af87e42a64962a34f7ec43bc710bdcaf/lib/tasks/mastodon.rake#L137) for how to change your `[env]` section for Wasabi, Minio or Google Cloud Storage.

#### Postgres database

```
$ fly pg create --region iad --name mastodon-pg
$ fly pg attach --postgres-app mastodon-pg
```

### Deploy

You may run `fly deploy` as many times as desired in the future. But ensure that it is ran the very first time with the proper `[deploy]` section in the [fly.toml](fly.toml) file commented out. (note the different `release_commands` and their descriptions.)

Run the initial database setup on first deploy, uncomment:
```
# [deploy]
#   release_command = "bundle exec rails db:setup"
```
Save the file, then run:
```
$ fly deploy
```

Validate your instance, create a user, confirm the email, setup MFA. Then proceed with the following if desired:

Comment previous section back out, then uncomment the admin creation commands.
```
# [deploy]
#   release_command = "tootctl accounts modify yourusernamehere --role admin"
```
Save the file again, then run:
```
$ fly deploy
```

You should now be finished, and have a newly created mastodon instance to administer as desired.