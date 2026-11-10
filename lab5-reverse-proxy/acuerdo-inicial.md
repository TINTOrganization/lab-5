# Acuerdo iniciales

## 1. Integrantes y roles

| Rol | Nombre completo | Se encarga de |
|---|---|---|
| **A: Nginx (seguridad)** | Daniel | `component-1/` |
| **B: Orders + balanceo** | Camilo Londoño | `component-2/` |
| **C: Catalog + aceleración** | Pablo | `component-3/` y archivos estáticos |
| **D: Docker, pruebas y documento** | Camilo Herrera | compose, `tests/`, `img/`, `l5_2a.md`, PDF |

---

## 2. Qué vamos a construir (en una frase)

Un nginx que recibe todas las peticiones por HTTPS y las reenvía a servicios que **no se pueden alcanzar desde afuera**. Además reparte la carga entre 3 réplicas y acelera las respuestas con caché y gzip.

```
cliente --> nginx (8443 HTTPS / 8080 redirige) --> orders (x3)
                                               \-> catalog (x1)
                                    (red interna, sin puertos publicados)
```

---

## 3. Contrato técnico

### 3.1 Servicios

| Qué | Valor |
|---|---|
| Contenedor nginx | `component-1` |
| Orders (Flask, 3 réplicas) | servicio `component-2`, puerto interno `5000` |
| Catalog (FastAPI, 1 instancia) | servicio `component-3`, puerto interno `8000` |
| Red interna | `internal` (con `internal: true`) |
| Puertos publicados | **solo nginx**: `8443` y `8080` |

### 3.2 Rutas en el proxy

| Ruta | Destino | Quién escribe la config |
|---|---|---|
| `/orders/` | orders (balanceado entre 3) | B escribe el `upstream`, A lo integra |
| `/catalog/` | catalog (con caché) | C escribe el `location`, A lo integra |
| `/static/` | archivos servidos por nginx | C |
| `/health` y rutas desconocidas | 404 | A |

### 3.3 Respuesta JSON de cada servicio

```json
{"service": "orders", "instance": "<hostname del contenedor>", "data": []}
```

El campo `instance` cambia entre réplicas, así se ve el balanceo.

### 3.4 Variables de entorno

| Variable | Ejemplo |
|---|---|
| `SERVICE_NAME` | `orders` |
| `PORT` | `5000` |

### 3.5 Estructura de carpetas

```
lab5-reverse-proxy/
  docker-compose.yml            # seguro: solo nginx publica puertos
  docker-compose.insecure.yml   # "antes": backends publicados
  component-1/                  # nginx
  component-2/                  # orders
  component-3/                  # catalog
  tests/before-after.sh
  img/
  l5_2a.md
```

### 3.6 Reglas de estilo

- Python + Docker, nombres en minúscula.
- `docker-compose.yml` **sin** la clave `version:`.
- Pruebas manuales con `curl`.
- Prohibido: rate limiting, límite de conexiones, código propio para el proxy.
- No editar la carpeta `example/`.

---

## 4. Reglas de trabajo en Git

1. Una rama por persona: `a-nginx`, `b-orders`, `c-catalog`, `d-docs`.
2. Cada uno edita **solo sus archivos**.
3. Archivos compartidos con un solo dueño:
   - `component-1/nginx.conf` → **A**
   - `docker-compose.yml` y `docker-compose.insecure.yml` → **D**
   - `l5_2a.md` → **D** (los demás le envían su parte)
4. B y C envían sus fragmentos de nginx (`upstream`, `location`) a A.
5. Antes de tocar un archivo compartido, avisar en el chat del grupo.
6. Subir a `main` en cuanto algo funcione, aunque sea básico.

---

## 5. Qué entrega cada uno

| Rol | Entregables | Checklist |
|---|---|---|
| **A** | HTTPS, redirección 301, cabeceras de seguridad, sin versión de nginx, 404 en `/health`, `X-Forwarded-For` sobrescrito, `nginx -t` OK | 3, 4, 5, 8 |
| **B** | App Flask con hostname, 3 réplicas, rotación y failover | 6, 7 |
| **C** | App FastAPI, `proxy_cache` con `X-Cache-Status`, gzip, estáticos, keep-alive | 9, 10, 11 |
| **D** | Ambos compose, `before-after.sh`, diagramas, guía y PDF | 1, 2 |

---

## 6. Horario

| Hora | Hito | Listo |
|---|---|---|
| ____ | Acuerdo inicial y ramas creadas | [ ] |
| ____ | Cada parte básica funcionando y en `main` | [ ] |
| ____ | Integración: `docker compose up --build` y checklist completo | [ ] |
| 20:00 | Diagramas y resultados listos | [ ] |
| 22:00 | PDF exportado y entregado | [ ] |

---

## 7. Cómo probar que todo funciona (checklist de la guía)

1. `docker compose up --build`; `docker ps` muestra que solo nginx publica puertos.
2. Los backends no se alcanzan directo (en el compose inseguro sí).
3. HTTPS funciona; HTTP devuelve 301; `curl -I` muestra cabeceras de seguridad y no muestra versión.
4. `/health` y rutas desconocidas dan 404.
5. Un `X-Forwarded-For` falso es sobrescrito.
6. 20 peticiones a orders rotan entre los 3 hostnames.
7. Al detener una réplica no hay errores para el cliente.
8. `docker exec component-1 nginx -t` pasa.
9. El segundo GET igual da `X-Cache-Status: HIT` y es más rápido que el primero (`MISS`).
10. Con `Accept-Encoding: gzip` la respuesta es más pequeña.
11. Un archivo estático lo sirve nginx sin que el backend reciba la petición.

---

## 8. El PDF final debe tener

- [ ] Nombres completos de los cuatro integrantes
- [ ] Vista arquitectónica (componentes y conectores + despliegue) en PNG
- [ ] Descripción y propósito del patrón
- [ ] Escenario de calidad
- [ ] Pasos de implementación
- [ ] Fragmentos de configuración y código (iguales a los archivos del repo)
- [ ] Resultados (salida de los comandos del checklist)
- [ ] Recomendaciones

---

## 9. Confirmación

Cada integrante dice en una frase qué archivos va a crear y qué le entrega a los demás. Si alguien no puede decirlo, se aclara antes de empezar.

| Integrante | Confirmo |
|---|---|
| A | [ ] |
| B | [ ] |
| C | [ ] |
| D | [ ] |
