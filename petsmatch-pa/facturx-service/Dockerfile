# Micro-service d'assemblage Factur-X.
# ⚠️ Partie fiscale → à déployer sur une infra UE (objectif SecNumCloud).
FROM python:3.12-slim

WORKDIR /app

# libs système utiles à fpdf2 / pikepdf (dépendance de factur-x)
RUN apt-get update && apt-get install -y --no-install-recommends \
      libqpdf-dev \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app.py .

EXPOSE 8081
CMD ["gunicorn", "--bind", "0.0.0.0:8081", "--workers", "2", "--timeout", "60", "app:app"]
