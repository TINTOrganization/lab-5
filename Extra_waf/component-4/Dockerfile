# 1) Compilar la página con Astro (Node viene dentro de la imagen)
FROM node:22-alpine AS build
WORKDIR /app
RUN npm init -y && npm install astro@5.18.2
COPY index.astro src/pages/index.astro
ARG PUBLIC_API_URL
ARG PUBLIC_WS_URL
RUN npx astro build

# 2) Servir los archivos generados con nginx
FROM nginx:alpine
COPY --from=build /app/dist /usr/share/nginx/html
