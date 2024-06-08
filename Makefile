#
# Example invocation:
#
# make ADMIN_USER=herb ADMIN_EMAIL=herb@gmail.com REGION=sea APPNAME=superfly-mastodon setup
#
# Or, if you're using your own domain:
#
# make LOCAL_DOMAIN=superfly.example.com ADMIN_USER=herb ADMIN_EMAIL=herb@gmail.com REGION=sea APPNAME=superfly-mastodon setup
# fly certs add -a superfly-mastodon superfly.example.com
#
# See the "New password" output for the admin user's randomly-generated
# password. As generated, the instance will not allow signups or send
# emails, so needs further work if signups are desired.
#

FILES = \
	.secrets/SECRET_KEY_BASE \
	.secrets/OTP_SECRET \
	.secrets/VAPID_PRIVATE_KEY \
	.secrets/VAPID_PUBLIC_KEY

APPNAME =	mastodon-example
REGION =	sjc
LOCAL_DOMAIN ?=	${APPNAME}.fly.dev
ADMIN_USER ?=	johndoe
ADMIN_EMAIL ?=	example@example.com

all: 	${FILES}

.check_openssl:
	if ! which openssl > /dev/null ; then \
		echo need openssl for secrets ; \
		exit 1 ; \
	else \
		touch $@ ; \
	fi

.secrets:
	mkdir .secrets

.secrets/SECRET_KEY_BASE: .check_openssl .secrets
	openssl rand -hex 64 > $@

.secrets/OTP_SECRET: .check_openssl .secrets
	openssl rand -hex 64 > $@

.secrets/vapid_private_key.pem: .check_openssl .secrets
	openssl ecparam -name prime256v1 -genkey -noout -out $@
.secrets/vapid_public_key.pem: .secrets/vapid_private_key.pem
	openssl ec -in $^ -pubout -out $@
.secrets/VAPID_PUBLIC_KEY: .secrets/vapid_public_key.pem
	(cat $^ | grep -v 'PUBLIC KEY-----$$' | tr -d '\n') > $@
.secrets/VAPID_PRIVATE_KEY: .secrets/vapid_private_key.pem
	(cat $^ | grep -v 'PRIVATE KEY-----$$' | tr -d '\n') > $@

.done_import: ${FILES} .done_create_app1
	fly secrets set -c fly.${APPNAME}.toml OTP_SECRET=$$(cat .secrets/OTP_SECRET)
	fly secrets set -c fly.${APPNAME}.toml SECRET_KEY_BASE=$$(cat .secrets/SECRET_KEY_BASE)
	fly secrets set -c fly.${APPNAME}.toml VAPID_PRIVATE_KEY=$$(cat .secrets/VAPID_PRIVATE_KEY)
	fly secrets set -c fly.${APPNAME}.toml VAPID_PUBLIC_KEY=$$(cat .secrets/VAPID_PUBLIC_KEY)
	touch $@

.done_create_app1: fly.${APPNAME}.toml
	fly apps create ${APPNAME}
	fly scale memory -c fly.${APPNAME}.toml 1024
	touch $@

fly.${APPNAME}-redis.toml: fly.redis.toml
	cat $^ | sed 's/^app.*/app = "${APPNAME}-redis"/' > $@

fly.${APPNAME}-setup.toml: fly.setup.toml
	cat $^ | sed 's/^app.*/app = "${APPNAME}"/' > $@

fly.${APPNAME}.toml: fly.toml
	cat $^ | sed 's/^app.*/app = "${APPNAME}"/' | \
		sed 's/LOCAL_DOMAIN = .*/LOCAL_DOMAIN = "${LOCAL_DOMAIN}"/' | \
		sed 's/REDIS_HOST = .*/REDIS_HOST = "${APPNAME}-redis.internal"/' \
	> $@

.done_create_redis: .done_create_app1 fly.${APPNAME}-redis.toml
	fly apps create ${APPNAME}-redis
	FLY_APP=${APPNAME}-redis fly -c fly.${APPNAME}-redis.toml volumes create --region ${REGION} --size 1 mastodon_redis
	FLY_APP=${APPNAME}-redis fly -c fly.${APPNAME}-redis.toml deploy
	touch $@

.done_create_app2: .done_import fly.${APPNAME}-setup.toml fly.${APPNAME}.toml .done_create_redis
	fly volumes create -c fly.${APPNAME}.toml --region ${REGION} mastodon_uploads
	fly pg create --region ${REGION} --name ${APPNAME}-db
	fly pg attach -a ${APPNAME} ${APPNAME}-db
	fly deploy -c fly.${APPNAME}-setup.toml || echo this deployment does its job then appears to fail, no problem
	touch $@

.done_create_app3: .done_create_app2
	fly deploy -c fly.${APPNAME}.toml
	fly ssh console -a ${APPNAME} -C 'tootctl settings registrations close'
	fly ssh console -a ${APPNAME} -C 'tootctl accounts create ${ADMIN_USER} --email=${ADMIN_EMAIL}'
	fly ssh console -a ${APPNAME} -C 'tootctl accounts modify ${ADMIN_USER} --confirm --role Owner'
	fly ssh console -a ${APPNAME} -C 'tootctl accounts approve ${ADMIN_USER}'
	fly ips -a ${APPNAME} allocate-v4
	while ! curl https://${APPNAME}.fly.dev ; do sleep 5 ; done
	echo congratulations, your instance is at https://${APPNAME}.fly.dev\!
	touch $@

setup: .done_create_app3

deploy: .done_create_app3
	fly deploy -c fly.${APPNAME}.toml

create: .done_create_app1 .done_import .done_create_app2

destroy:
	-fly apps destroy --yes ${APPNAME}
	-fly apps destroy --yes ${APPNAME}-db
	-fly apps destroy --yes ${APPNAME}-redis
	rm -fr .secrets
	rm -fr .done_create_app1 .done_create_app2 .done_import
	rm -fr .done_create_app3
	rm -fr .done_create_redis
	rm -fr fly.${APPNAME}.toml
	rm -fr fly.${APPNAME}-redis.toml
	rm -fr fly.${APPNAME}-setup.toml


