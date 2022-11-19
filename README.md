## Mastodon on fly.io

[Mastodon](https://github.com/mastodon/mastodon) is a free, open-source social network server based on ActivityPub.

The Mastodon server is implemented a rails app, which relies on postgres and redis. It uses sidekiq for background jobs, along with a separate nodejs http streaming server.

While following this guide, you may find it helpful to also view the [Mastodon docker image list](https://hub.docker.com/r/tootsuite/mastodon/), the [Mastodon Dockerfile](https://github.com/mastodon/mastodon/blob/main/Dockerfile), or the [Mastodon docker-compose.yml](https://github.com/mastodon/mastodon/blob/main/docker-compose.yml).

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
$ docker run --rm -e OTP_SECRET=$OTP_SECRET -e SECRET_KEY_BASE=$SECRET_KEY_BASE -it tootsuite/mastodon:latest bin/rake mastodon:webpush:generate_vapid_key | sed 's/\r//' | fly secrets import
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
<a id="cloud-storage"></a>

```
$ fly secrets set AWS_ACCESS_KEY_ID=xxx AWS_SECRET_ACCESS_KEY=yyy
```

Uncomment the section in `fly.io` to configure S3 or Wasabi.  See [mastodon.rake](https://github.com/mastodon/mastodon/blob/5ba46952af87e42a64962a34f7ec43bc710bdcaf/lib/tasks/mastodon.rake#L137) for the env vars needed for Minio or Google Cloud Storage.

To serve cloud-stored images directly from your domain, set `S3_ALIAS_HOST` in `fly.toml` and then uncomment the section at the top of `Caddyfile`.

#### Postgres database

```
$ fly pg create --region sjc --name mastodon-example-db
$ fly pg attach mastodon-example-db
$ fly deploy -c fly.setup.toml # run `rails db:schema:load`, may take 2-3 minutes
```

#### Sending email

Mastodon sends emails on signup, to confirm email addresses. It also uses emails for password resets, notifications to the server admins, and various other tasks. To have a fully-functioning Mastodon server, you'll need to create an account with an email service like [Postmark](https://postmarkapp.com), get credentials, and provide those credentials to Mastodon as env vars or secrets. See `fly.toml` for an example of the env vars you would set, and then provide your credentials as Fly secrets:

```
$ fly secrets set SMTP_LOGIN=<public token> SMTP_PASSWORD=<secret token>
```

#### Custom domain (optional)

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

### Deploy

```
$ fly deploy
```

#### Make yourself an instance admin

After you've deployed, sign up. You will hopefully get an email, but if you don't, we'll manually confirm your account regardless as part of making you an owner on the instance. Substitute your own username in this command:

```
$ fly ssh console -C 'tootctl accounts modify <username> --confirm --role Owner'
```

## You're done!

Enjoy your server.


### Operating your instance

If you still haven't gotten enough, here are some notes on how to operate your instance after it's running.

Useful resources for operating and debugging a running instance include `fly logs`, `fly scale show`, `fly ssh console`, the Metrics section of `fly dashboard`, and the Sidekiq dashboard at https://mastodon-example.fly.dev/sidekiq (you have to be logged in to Mastodon as an admin user to see it).

If your instance is getting slow or falling over, you may find [Scaling Mastodon in the Face of an Exodus](https://nora.codes/post/scaling-mastodon-in-the-face-of-an-exodus/) helpful.

#### Upgrading Mastodon

To upgrade to a new version of Mastodon, change the version number on the first line of `Dockerfile`, and then check the release notes for upgrade instructions.

If there are migrations that need to be run, make sure that the release command in `fly.toml` is uncommented.

If there are migrations that must be run before deploying to avoid downtime, you can run the pre-deploy migrations using a second app. By scaling this app to a VM count of zero, it won't add to our bill, but it will let us run the pre-deploy migrations as a release command before the web processes get the new code.

```
$ fly apps create mastodon-example-predeploy
$ bin/fly-predeploy secrets set OTP_SECRET=placeholder SECRET_KEY_BASE=placeholder
$ bin/fly-predeploy secrets set $(fly ssh console -C env | grep DATABASE_URL)
$ bin/fly-predeploy scale memory 1024
$ bin/fly-predeploy scale count 0
$ bin/fly-predeploy deploy
```

After that, just deploy the updated container as usual, and the post-deploy migrations will run in the regular release command:

```
$ fly deploy
```

#### Scaling your instance

If your instance attracts many users (or maybe a few users who follow a huge number of other accounts), you may notice things start to slow down, and you may run out of database, redis, or storage space.

##### A bigger VM
<a id="bigger-vm"></a>

If you need more web processes, or more sidekiq workers, the easiest option is to choose a larger Fly VM size via `fly scale vm`. With a larger VM, you can run more Puma processes by setting `WEB_CONCURRENCY`, and you can run more sidekiq processes by setting `OVERMIND_FORMATION`. Try to aim for about as many Puma+Sidekiq processes as you have cores, and review the CPU usage of your VM to know whether to adjust up or down.

For example, if you upgrade to `dedicated-cpu-4x`, you might set `WEB_CONCURRENCY=2` and `OVERMIND_FORMATION=sidekiq=2` in `fly.toml`.

At that point, you'll have two Puma processes and two Sidekiq processes, running 5 threads each. If your CPUs aren't fully utilized yet, you can increase the threads on each CPU by setting `MAX_THREADS=25` and editing the Sidekiq line in the procfile to change `-c 5` to `-c 25` instead. Adjust up or down until your CPUs are as utilized as you'd like them to be.

##### Adding many VMs

If you need to scale beyond the largest Fly VM (8 CPU cores and 16GB, at the time of writing), or you just want to run a bigger number of smaller VMs, you can do that.

**Caveat: to have more than one VM, you _must_ be using [cloud storage](#cloud-storage) instead of Fly volumes.**

1. Create a separate app to scale Sidekiq VMs:
    ```
    $ fly apps create mastodon-example-sidekiq
    ```
1. Make sure to copy any config env vars for e.g. S3 and SMTP from `fly.toml` to `fly.sidekiq.toml`.
1. Make sure to copy any secrets for e.g. S3 and SMTP from `fly secrets` to `bin/fly-sidekiq secrets`.
    ```
    $ bin/fly-sidekiq secrets set OTP_SECRET=placeholder SECRET_KEY_BASE=placeholder
    $ bin/fly-sidekiq secrets set $(fly ssh console -C env | grep DATABASE_URL)
    $ bin/fly-sidekiq secrets set $(fly ssh console -C env | grep YOUR_SECRET_HERE)
    ```
1. Deploy the Sidekiq app
    ```
    $ bin/fly-sidekiq scale memory 512 # a single sidekiq with 5 threads uses about 400MB
    $ bin/fly-sidekiq scale count 3 # or your desired number of Sidekiq VMs
    $ bin/fly-sidekiq deploy
    ```
1. Remove Sidekiq from your main VMs by setting `OVERMIND_FORMATION = "sidekiq=0"` in `fly.toml`.
    ```
    $ fly scale memory 512 # a single puma process + node uses about 430MB
    $ fly scale count 3 # or your desired number of web VMs
    $ fly deploy
    ```

Don't forget to adjust the number of Puma and Sidekiq threads, as described in [A bigger VM](#bigger-vm) above, to match your CPU and memory settings!

Finally, make sure that your Postgres is big enough to successfully handle one connection for every thread in Pumo or Sidekiq across all VMs. If your postgres is unable to accept more connections, you might need to increase the CPU or memory on your Postgres VM(s), or you might need to add pg_bouncer to act as a connection proxy and reduce the number of open connections directly to the database.
