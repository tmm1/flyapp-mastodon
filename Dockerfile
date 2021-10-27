FROM redis:alpine AS redis-server
ADD start-redis-server.sh /usr/bin/
RUN chmod +x /usr/bin/start-redis-server.sh
CMD ["start-redis-server.sh"]

FROM tootsuite/mastodon:v3.4.1
ENTRYPOINT []
