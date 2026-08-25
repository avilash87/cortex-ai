# BASE_IMAGE defaults to the public path for portability (this Dockerfile also
# has to build in GitHub Actions later, which has no VPN route to Nexus at
# 10.3.0.4). Building on the management VM: override with
#   --build-arg BASE_IMAGE=10.3.0.4:8082/library/python:3.12-slim
# to route through the Nexus chokepoint instead. Flagged CLAUDE.md deviation:
# Nexus as deployed only proxies builds happening inside the VNet — CI's
# base-image pulls are a gap this doesn't solve yet.
ARG BASE_IMAGE=python:3.12-slim

# ---- build stage: install deps into a user site-packages dir ----
FROM ${BASE_IMAGE} AS build
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir --user -r requirements.txt

# ---- final stage: only the installed packages + app code, non-root ----
FROM ${BASE_IMAGE}
RUN useradd --create-home --uid 1000 appuser
WORKDIR /app
COPY --from=build /root/.local /home/appuser/.local
COPY app/ ./app/
ENV PATH=/home/appuser/.local/bin:$PATH
USER 1000:1000
EXPOSE 8000
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
