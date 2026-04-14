FROM node:24-alpine

# Install nginx and supervisord
RUN apk add --no-cache nginx supervisor && mkdir -p /run/nginx

# ── Auth service ──
WORKDIR /app/auth-service
COPY services/auth-service/package.json ./
RUN npm install --omit=dev
COPY services/auth-service/server.js ./

# ── Event service ──
WORKDIR /app/event-service
COPY services/event-service/package.json ./
RUN npm install --omit=dev
COPY services/event-service/server.js ./

# ── RSVP service ──
WORKDIR /app/rsvp-service
COPY services/rsvp-service/package.json ./
RUN npm install --omit=dev
COPY services/rsvp-service/server.js ./

# ── Frontend (nginx static files) ──
COPY frontend/index.html \
     frontend/login.html \
     frontend/signup.html \
     frontend/styles.css \
     frontend/app.js \
     /usr/share/nginx/html/

# nginx config — proxies /api/* to localhost ports
COPY nginx-local.conf /etc/nginx/nginx.conf

# supervisord config — starts nginx + 3 Node services
COPY supervisord.conf /etc/supervisord.conf

EXPOSE 80

CMD ["/usr/bin/supervisord", "-c", "/etc/supervisord.conf"]
