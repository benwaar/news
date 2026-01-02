# Build Angular app
FROM node:22.21.1-alpine AS builder
WORKDIR /app
COPY package.json angular.json tsconfig*.json ./
COPY src ./src
# Install dependencies and build
RUN npm install && npm run build

# Nginx to serve built artifacts with HTTPS and proxying
FROM nginx:1.25-alpine
COPY nginx/default.conf /etc/nginx/conf.d/default.conf
COPY --from=builder /app/dist/ui/browser /usr/share/nginx/html

EXPOSE 80 443
CMD ["nginx", "-g", "daemon off;"]
