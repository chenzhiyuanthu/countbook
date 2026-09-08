# syntax=docker/dockerfile:1
FROM node:24-alpine

ENV NODE_ENV=production \
    PORT=8080 \
    DATA_DIR=/data

WORKDIR /app

# No npm dependencies: the server runs on the Node standard library alone
# (node:http + node:sqlite + node:crypto), so there is nothing to install and
# nothing in the supply chain to audit.
COPY package.json ./
COPY server.js ./

RUN mkdir -p /data && chown -R node:node /data /app
USER node

VOLUME ["/data"]
EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=4s --start-period=5s --retries=3 \
  CMD node -e "fetch('http://127.0.0.1:8080/healthz').then(r=>process.exit(r.ok?0:1)).catch(()=>process.exit(1))"

CMD ["node", "server.js"]
