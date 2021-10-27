## Mastodon on fly.io

### Setup

#### App & Database

```
$ fly apps create --name mastodon
$ fly pg create --region iad --name mastodon-db
$ fly secrets set DB_PASS=xxxx # password from output above
```

#### Secrets

```
$ SECRET_KEY_BASE=$(docker run --rm -it tootsuite/mastodon:latest bin/rake secret)
$ OTP_SECRET=$(docker run --rm -it tootsuite/mastodon:latest bin/rake secret)
$ fly secrets set OTP_SECRET=$OTP_SECRET SECRET_KEY_BASE=$SECRET_KEY_BASE
$ docker run --rm -e OTP_SECRET=$OTP_SECRET -e SECRET_KEY_BASE=$SECRET_KEY_BASE -it tootsuite/mastodon:latest bin/rake mastodon:webpush:generate_vapid_key | fly secrets import
```

#### Storage (user uploaded photos and videos)

Edit the `fly.toml` and enable either the `[mounts]` section for local storage, or `[env] > S3_ENABLED` for S3

##### Option 1: Volume

```
$ fly volumes create --region iad mastodon_data
```

##### Option 2: S3

```
$ fly secrets set AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=yyy
```