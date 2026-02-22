FROM tzahi12345/youtubedl-material:latest

# Install deno for yt-dlp JavaScript runtime support
# See: https://github.com/yt-dlp/yt-dlp/wiki/EJS
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl unzip ca-certificates && \
    curl -fsSL https://deno.land/install.sh | DENO_INSTALL=/usr/local sh && \
    apt-get clean && \
    rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/*

# Verify deno is installed and accessible
RUN deno --version
