from fastapi import FastAPI, Header, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pathlib import Path
import os
import psycopg2
import logging

# --- Config via env ---
ADMIN_TOKEN = os.getenv("ADMIN_TOKEN", "")  # si vide => pas d'auth requise
PGHOST = os.getenv("PGHOST", "rag-n8n-db-1")  # adapte si service DB a un autre nom
PGUSER = os.getenv("PGUSER", "n8nuser")
PGPASSWORD = os.getenv("PGPASSWORD", "")
PGDATABASE = os.getenv("PGDATABASE", "notes_frais")

CSV_PATH = Path("/data/docs/ndf.csv")
SQL_PATH = Path("/data/init/10_notes_frais.sql")

# --- App & middlewares ---
app = FastAPI(title="demo-admin", version="1.0.0")

# CORS pas nécessaire tant que non exposé; on laisse en place par défaut fermé
app.add_middleware(
    CORSMiddleware,
    allow_origins=[],  # vide = aucune origine autorisée (on ouvrira plus tard si besoin)
    allow_methods=["POST", "GET", "OPTIONS"],
    allow_headers=["*"],
)

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("demo-admin")

def _auth_or_401(x_admin_token: str | None):
    if ADMIN_TOKEN and x_admin_token != ADMIN_TOKEN:
        raise HTTPException(status_code=401, detail="Unauthorized")

@app.get("/admin/health")
def health():
    return {"status": "ok"}

@app.post("/admin/reset")
def reset(x_admin_token: str | None = Header(default=None)):
    _auth_or_401(x_admin_token)

    # 1) Suppression CSV (idempotent)
    try:
        if CSV_PATH.exists():
            CSV_PATH.unlink(missing_ok=True)
            logger.info("CSV deleted: %s", CSV_PATH)
        else:
            logger.info("CSV not present: %s", CSV_PATH)
    except Exception as e:
        logger.exception("CSV delete failed")
        raise HTTPException(status_code=500, detail=f"CSV delete failed: {e}")

    # 2) Lecture SQL
    if not SQL_PATH.exists():
        raise HTTPException(status_code=500, detail=f"SQL not found at {SQL_PATH}")
    sql = SQL_PATH.read_text(encoding="utf-8")

    # 3) Exec SQL sur Postgres
    try:
        with psycopg2.connect(
            host=PGHOST,
            user=PGUSER,
            password=PGPASSWORD,
            dbname=PGDATABASE,
        ) as conn:
            with conn.cursor() as cur:
                cur.execute(sql)
        logger.info("SQL executed successfully")
    except Exception as e:
        logger.exception("SQL exec failed")
        raise HTTPException(status_code=500, detail=f"SQL exec failed: {e}")

    return {"ok": True}
