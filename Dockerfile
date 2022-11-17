FROM tootsuite/mastodon:v4.0.1

USER root
RUN mkdir -p /var/cache/apt/archives/partial && \
  apt-get clean && \
  apt-get update && \
  apt-get install -y --no-install-recommends tmux

USER mastodon
RUN wget "https://github.com/DarthSim/overmind/releases/download/v2.3.0/overmind-v2.3.0-linux-amd64.gz" -O overmind.gz && \
 gunzip overmind.gz && \
 chmod +x overmind

ADD Procfile /opt/mastodon/

ENTRYPOINT []
CMD ["./overmind", "start"]
