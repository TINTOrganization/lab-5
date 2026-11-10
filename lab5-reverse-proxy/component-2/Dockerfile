FROM python:3.11-slim
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY app ./app
ENV SERVICE_NAME=orders
ENV PORT=5000
CMD ["python", "app/app.py"]
