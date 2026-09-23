FROM python:3.12.10-slim-bookworm

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    WANSIM_V2_DATA_DIR=/data \
    WANSIM_V2_EXECUTION_MODE=dry-run

WORKDIR /app
COPY requirements.txt ./
RUN pip install --no-cache-dir -r requirements.txt \
    && useradd --create-home --uid 10001 wansim \
    && mkdir /data \
    && chown wansim:wansim /data
COPY wansim_v2 ./wansim_v2
USER wansim
EXPOSE 8080
CMD ["uvicorn", "wansim_v2.api:app", "--host", "0.0.0.0", "--port", "8080"]
