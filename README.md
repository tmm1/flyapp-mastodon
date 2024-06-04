# Mastodon on Fly.io

[Mastodon](https://github.com/mastodon/mastodon) is a free, open-source social network server based on the [ActivityPub](https://www.w3.org/TR/activitypub/) standard.

The Mastodon server is implemented a [Rails](https://github.com/rails/rails) app, which relies on [PostgresSQL](https://github.com/postgres/postgres) and [Redis](https://github.com/redis/redis). It uses [Sidekiq](https://github.com/mperham/sidekiq) for background jobs, along with a separate [Node.js](https://github.com/nodejs/node) http streaming server.

While following this guide, you may find it helpful to also view the [Mastodon docker image list](https://hub.docker.com/r/tootsuite/mastodon/), the [Mastodon Dockerfile](https://github.com/mastodon/mastodon/blob/main/Dockerfile), or the [Mastodon docker-compose.yml](https://github.com/mastodon/mastodon/blob/main/docker-compose.yml).

## Setup

You'll need a [Fly.io](https://fly.io/) account, and the [Flyctl CLI](https://fly.io/docs/flyctl/installing/).

### App

Fork this repo and clone a copy of it. Choose a name for your app that isn't already taken on https://fly.io/, and run the script `bin/name YOUR-APP-NAME`. Follow this readme from inside your repo, after you have run the script, so that all of the steps will be updated for the name of your Fly.io app.

```bash
fly apps create mastodon-example
```

### Secrets

```bash
export SECRET_KEY_BASE=$(docker run --rm -it tootsuite/mastodon:latest bin/rake secret)
export OTP_SECRET=$(docker run --rm -it tootsuite/mastodon:latest bin/rake secret)
fly secrets set OTP_SECRET=$OTP_SECRET SECRET_KEY_BASE=$SECRET_KEY_BASE
docker run --rm -e OTP_SECRET=$OTP_SECRET -e SECRET_KEY_BASE=$SECRET_KEY_BASE -it tootsuite/mastodon:latest bin/rake mastodon:webpush:generate_vapid_key | sed 's/\r//' | fly secrets import
```

### Redis server

Redis is used to store the home/list feeds, along with the Sidekiq queue information. The feeds can be regenerated using `tootctl`, so persistence is [not strictly necessary](https://docs.joinmastodon.org/admin/backups/#failure).

Choose a region that is close to your users. See [Fly regions](https://fly.io/docs/reference/regions/) for a list of regions or run `fly platform regions`. In this example, we'll use `sjc` (San Jose, CA).

```bash
fly apps create mastodon-example-redis
fly redis create --region sjc --name mastodon_redis
```

### Storage (user uploaded photos and videos)

The [`fly.toml`](./fly.toml) uses a `[mounts]` section to connect the `/opt/mastodon/public/system` folder to a persistent volume.

Create that volume below, or remove the `[mounts]` section and uncomment `[env] > S3_ENABLED` for S3 storage.

#### Option 1: Local volume

```bash
fly volumes create --region sjc mastodon_uploads
```

#### Option 2: Cloud storage

S3, Wasabi, etc

```bash
fly secrets set AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=yyy
```

Uncomment the section in [`fly.toml`](./fly.toml) to configure [AWS S3](https://aws.amazon.com/s3/) or [Wasabi](https://wasabi.com/).  See [mastodon.rake](https://github.com/mastodon/mastodon/blob/5ba46952af87e42a64962a34f7ec43bc710bdcaf/lib/tasks/mastodon.rake#L137) for the env vars needed for [MinIO](https://min.io/) or [Google Cloud Storage](https://cloud.google.com/storage/).

To serve cloud-stored images directly from your domain, set `S3_ALIAS_HOST` in [`fly.toml`](./fly.toml) and then uncomment the section at the top of `Caddyfile`.

### Postgres database

```bash
fly pg create --region sjc --name mastodon-example-db
fly pg attach mastodon-example-db
fly deploy -c fly.setup.toml # run `rails db:schema:load`, may take 2-3 minutes
```

### Sending email

Mastodon sends emails on sign-up, to confirm email addresses. It also uses emails for password resets, notifications to the server admins, and various other tasks. To have a fully-functioning Mastodon server, you'll need to create an account with an email service like [Postmark](https://postmarkapp.com/) or [Mailgun](https://www.mailgun.com/), get credentials, and provide those credentials to Mastodon as env vars or secrets. See [`fly.toml`](./fly.toml) for an example of the env vars you would set, and then provide your credentials as Fly secrets:

```bash
fly secrets set SMTP_LOGIN=<public token> SMTP_PASSWORD=<secret token>
```

### Custom domain (optional)

1. Edit [`fly.toml`](./fly.toml) and set `LOCAL_DOMAIN` to your custom domain.
2. Run `fly ips list`, and if the list is empty, run `fly ips allocate-v4`.
3. Then, create DNS records for your custom domain.

    If your DNS host supports ALIAS records:

    ```bash
    @   ALIAS mastodon-example.fly.dev
    www CNAME mastodon-example.fly.dev
    ```

    If your DNS host only allows A records, use the IP. For example, if your IP was `3.3.3.3`:

    ```bash
    @   A     3.3.3.3
    www CNAME @
    ```

4. Finally, generate SSL certificates from Let's Encrypt:

    ```bash
    fly certs add MYDOMAIN.COM
    fly certs add WWW.MYDOMAIN.COM
    ```

## Deploy

```bash
fly deploy
fly scale memory 1024 # Rails + Sidekiq needs more than 512
```

### Make yourself an instance admin

After you've deployed, sign up. You will hopefully get an email, but if you don't, we'll manually confirm your account regardless as part of making you an owner on the instance. Substitute your own username in this command:

```bash
fly ssh console -C 'tootctl accounts modify <username> --confirm --role Owner'
```

## You're done!

Enjoy your server.

### Operating your instance

If you still haven't gotten enough, here are some notes on how to operate your instance after it's running.

Useful resources for operating and debugging a running instance include `fly logs`, `fly scale show`, `fly ssh console`, the Metrics section of `fly dashboard`, and the Sidekiq dashboard at <https://mastodon-example.fly.dev/sidekiq> (you have to be logged in to Mastodon as an admin user to see it).

If your instance is getting slow or falling over, you may find [Scaling Mastodon in the Face of an Exodus](https://nora.codes/post/scaling-mastodon-in-the-face-of-an-exodus/) helpful.

### Upgrading Mastodon

To upgrade to a new version of Mastodon, change the version number on the first line of `Dockerfile`, and then check the [release notes](https://github.com/mastodon/mastodon/blob/main/CHANGELOG.md) for upgrade instructions.

If there are migrations that need to be run, make sure that the release command in [`fly.toml`](./fly.toml) is uncommented.

If there are migrations that must be run before deploying to avoid downtime, you can run the pre-deploy migrations using a second app. By scaling this app to a VM count of zero, it won't add to our bill, but it will let us run the pre-deploy migrations as a release command before the web processes get the new code.

```bash
fly apps create mastodon-example-predeploy
bin/fly-predeploy secrets set OTP_SECRET=placeholder SECRET_KEY_BASE=placeholder
bin/fly-predeploy secrets set $(fly ssh console -C env | grep DATABASE_URL)
bin/fly-predeploy scale memory 1024
bin/fly-predeploy scale count 0
bin/fly-predeploy deploy
```

After that, just deploy the updated container as usual, and the post-deploy migrations will run in the regular release command:

```bash
fly deploy
```

You should also regularly update the Postgres and Redis instances:

- `flyctl image update -a mastodon-example-db` to update Postgres
- `./bin/fly-redis deploy` to update Redis

### Scaling your instance

If your instance attracts many users (or maybe a few users who follow a huge number of other accounts), you may notice things start to slow down, and you may run out of database, redis, or storage space.

#### A bigger VM

If you need more web processes, or more sidekiq workers, the easiest option is to choose a larger Fly VM size via `fly scale vm`. With a larger VM, you can run more Puma processes by setting `WEB_CONCURRENCY`, and you can run more sidekiq processes by setting `OVERMIND_FORMATION`. Try to aim for about as many Puma+Sidekiq processes as you have cores, and review the CPU usage of your VM to know whether to adjust up or down.

For example, if you upgrade to `dedicated-cpu-4x`, you might set `WEB_CONCURRENCY=2` and `OVERMIND_FORMATION=sidekiq=2` in [`fly.toml`](./fly.toml).

At that point, you'll have two Puma processes and two Sidekiq processes, running 5 threads each. If your CPUs aren't fully utilized yet, you can increase the threads for each single-CPU process by setting `MAX_THREADS`. Adjust up or down until your CPUs are as utilized as you'd like them to be.

#### Adding more VMs

If you need to scale beyond the largest Fly VM (8 CPU cores and 16GB, at the time of writing), or you just want to run a bigger number of smaller VMs, you can also do that. We're going to split up responsibilities, creating one type of VM that runs the Sidekiq scheduler process, another type of VM that runs Sidekiq workers for all the other background jobs, and a third type of VM that runs the Rails, Node, and Caddy servers. You'll be able to tell Fly how many of each VM you want, separately.

**Caveats:**

1. **You _must_ already be using [cloud storage](#option-2-cloud-storage) instead of Fly volumes.**
1. **To undo this change you have to destroy your Fly app and recreate it.**

Ready? Okay, let's do it:

1. Convert your application to multiple-VM mode by uncommenting the `[processes]` section in [`fly.toml`](./fly.toml).
1. Scale memory so everything can run successfully.

    ```bash
    fly scale memory 512 --group sidekiq  # a single sidekiq with 5 threads uses about 400MB
    fly scale memory 512 --group schedule # a single sidekiq with 5 threads uses about 400MB
    fly scale memory 512 --group rails    # rails with 5 threads plus node uses about 430MB
    fly scale count schedule=1 rails=2 sidekiq=2 # or your desired number of VMs
    fly deploy
    ```

Increase the number of `rails` or `sidekiq` processes by running `fly scale count rails=N` or `fly scale count sidekiq=N` as needed. Don't forget to also adjust the number of Puma and Sidekiq threads, as described in [A bigger VM](#a-bigger-vm) above, to match your CPU and memory settings!

Finally, make sure that your Postgres is big enough to successfully handle one connection for every thread in Pumo or Sidekiq across all VMs. If your postgres is unable to accept more connections, you might need to increase the CPU or memory on your Postgres VM(s), or you might need to add pg_bouncer to act as a connection proxy and reduce the number of open connections directly to the database.
