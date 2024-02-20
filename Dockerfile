# Releases: https://github.com/mastodon/mastodon/pkgs/container/mastodon
FROM ghcr.io/mastodon/mastodon:v4.2.7

USER root

# Releases: https://github.com/caddyserver/caddy/releases/
RUN wget "https://github.com/caddyserver/caddy/releases/download/v2.7.6/caddy_2.7.6_linux_amd64.deb" -O caddy.deb && \
  dpkg -i caddy.deb

USER mastodon

# Releases: https://github.com/DarthSim/overmind/releases
RUN wget "https://github.com/DarthSim/overmind/releases/download/v2.4.0/overmind-v2.4.0-linux-amd64.gz" -O overmind.gz && \
  gunzip overmind.gz && \
  chmod +x overmind

ADD Procfile Caddyfile /opt/mastodon/

ENTRYPOINT []
CMD ["./overmind", "start"]
