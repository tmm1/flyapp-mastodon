FROM tootsuite/mastodon:v4.1.5

USER root
RUN mkdir -p /var/cache/apt/archives/partial && \
  apt-get clean && \
  apt-get update && \
  apt-get install -y --no-install-recommends tmux

RUN wget "https://github.com/caddyserver/caddy/releases/download/v2.6.4/caddy_2.6.4_linux_amd64.deb" -O caddy.deb && \
  dpkg -i caddy.deb

USER mastodon
RUN wget "https://github.com/DarthSim/overmind/releases/download/v2.4.0/overmind-v2.4.0-linux-amd64.gz" -O overmind.gz && \
  gunzip overmind.gz && \
  chmod +x overmind

ADD Procfile Caddyfile /opt/mastodon/

ENTRYPOINT []
CMD ["./overmind", "start"]
