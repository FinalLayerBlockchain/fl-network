# Final Layer node (post-quantum ML-DSA-87, BSC/Parlia based), chain id 20261012
FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates && rm -rf /var/lib/apt/lists/*
COPY geth /usr/local/bin/geth
COPY flpq /usr/local/bin/flpq
COPY genesis.json /finallayer/genesis.json
COPY entrypoint.sh /finallayer/entrypoint.sh
RUN chmod +x /usr/local/bin/geth /usr/local/bin/flpq /finallayer/entrypoint.sh
VOLUME /data
EXPOSE 8545 30311/tcp 30311/udp
ENTRYPOINT ["/finallayer/entrypoint.sh"]
