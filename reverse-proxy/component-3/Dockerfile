FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app ./app
ENV SERVICE_NAME=catalog
ENV PORT=8000
CMD ["python", "app/app.py"]
