FROM nginx:1.28-alpine

# The stock image ships a default site; this proxy only uses nginx.conf.
RUN rm -f /etc/nginx/conf.d/default.conf

COPY nginx.conf /etc/nginx/nginx.conf
COPY snippets/ /etc/nginx/snippets/

# Self-signed certificate: run ./gen-certs.sh once before building.
COPY certs/server.crt certs/server.key /etc/nginx/certs/

# Static files served by nginx itself (acceleration demo).
COPY static/ /usr/share/nginx/html/static/

EXPOSE 8080 8443
