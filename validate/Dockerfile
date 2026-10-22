# Debian 9 "stretch" toolchain (gcc 6, autoconf 2.69, bison 3.0.4, re2c 0.16):
# contemporary with PHP 5.6 - 7.4, so their configure checks behave.
FROM debian:stretch
RUN printf 'deb http://archive.debian.org/debian stretch main\n' > /etc/apt/sources.list \
 && apt-get -o Acquire::Check-Valid-Until=false update \
 && apt-get install -y --no-install-recommends \
      build-essential autoconf automake libtool bison re2c pkg-config file libxml2-dev ca-certificates \
 && rm -rf /var/lib/apt/lists/*
COPY ci.sh run-targeted.sh /usr/local/bin/
RUN chmod +x /usr/local/bin/ci.sh /usr/local/bin/run-targeted.sh
