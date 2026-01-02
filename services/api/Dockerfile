# Minimal Node 22.21.1 API image
FROM node:22.21.1-alpine
WORKDIR /app
COPY package.json package-lock.json* ./
RUN npm ci --no-audit --no-fund || npm install --no-audit --no-fund
COPY src ./src
USER node
EXPOSE 9000
CMD ["npm","start"]
