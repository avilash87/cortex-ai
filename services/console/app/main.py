from fastapi import FastAPI

app = FastAPI(title="Cortex AI Console")


@app.get("/health")
def health() -> dict[str, str]:
    return {"status": "ok"}


@app.get("/")
def root() -> dict[str, str]:
    return {"service": "cortex-ai-console", "status": "not yet implemented"}
