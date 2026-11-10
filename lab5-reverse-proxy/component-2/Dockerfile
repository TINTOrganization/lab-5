FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app ./app
ENV SERVICE_NAME=orders
ENV PORT=5000
# gunicorn instead of Flask's dev server. `exec` makes it PID 1, so it handles
# SIGTERM and `docker stop` is immediate. gthread workers keep the
# connection open, so nginx's keep-alive to the backend is actually reused.
CMD exec gunicorn --chdir app -b 0.0.0.0:${PORT} -w 2 -k gthread --threads 4 app:app
