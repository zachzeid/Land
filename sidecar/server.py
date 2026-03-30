"""
Land JRPG Sidecar Server
FastAPI server handling AWS Bedrock inference and ChromaDB memory operations.
Replaces the subprocess-based CLI pattern with HTTP endpoints.
"""

import json
import logging
import os
from typing import Optional

import chromadb
import uvicorn
from dotenv import load_dotenv
from fastapi import FastAPI, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from pydantic import BaseModel

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

load_dotenv(dotenv_path=os.path.join(os.path.dirname(__file__), "..", ".env"))

logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(message)s")
logger = logging.getLogger("sidecar")

MODEL_IDS = {
    "sonnet": "us.anthropic.claude-sonnet-4-5-v2-20250514",
    "haiku": "us.anthropic.claude-haiku-4-5-20251001",
}

# ---------------------------------------------------------------------------
# App setup
# ---------------------------------------------------------------------------

app = FastAPI(title="Land Sidecar", version="1.0.0")

app.add_middleware(
    CORSMiddleware,
    allow_origins=["http://localhost:*", "http://127.0.0.1:*"],
    allow_origin_regex=r"^https?://(localhost|127\.0\.0\.1)(:\d+)?$",
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

# ---------------------------------------------------------------------------
# ChromaDB client (persistent, same path as chroma_cli.py)
# ---------------------------------------------------------------------------

chroma_path = os.path.join(os.path.dirname(__file__), "..", "chroma")
chroma_client = chromadb.PersistentClient(path=chroma_path)
logger.info("ChromaDB persistent client initialised at %s", chroma_path)

# ---------------------------------------------------------------------------
# Bedrock / Anthropic inference helpers
# ---------------------------------------------------------------------------

_bedrock_client = None
_anthropic_client = None


def _get_bedrock_client():
    """Return a boto3 bedrock-runtime client, or None if unavailable."""
    global _bedrock_client
    if _bedrock_client is not None:
        return _bedrock_client
    try:
        import boto3
        session = boto3.Session()
        creds = session.get_credentials()
        if creds is None:
            logger.warning("No AWS credentials found; Bedrock unavailable.")
            return None
        region = os.environ.get("AWS_REGION", "us-east-1")
        _bedrock_client = session.client("bedrock-runtime", region_name=region)
        logger.info("Bedrock client ready (region=%s)", region)
        return _bedrock_client
    except Exception as exc:
        logger.warning("Bedrock init failed: %s", exc)
        return None


def _get_anthropic_client():
    """Return an Anthropic API client using CLAUDE_API_KEY, or None."""
    global _anthropic_client
    if _anthropic_client is not None:
        return _anthropic_client
    api_key = os.environ.get("CLAUDE_API_KEY")
    if not api_key:
        return None
    try:
        import anthropic
        _anthropic_client = anthropic.Anthropic(api_key=api_key)
        logger.info("Anthropic direct client ready.")
        return _anthropic_client
    except Exception as exc:
        logger.warning("Anthropic client init failed: %s", exc)
        return None


def _invoke_bedrock(model_alias: str, system_prompt: str, messages: list, max_tokens: int) -> dict:
    """Call Bedrock invoke_model and return parsed response."""
    client = _get_bedrock_client()
    if client is None:
        raise RuntimeError("Bedrock client not available")

    model_id = MODEL_IDS.get(model_alias)
    if not model_id:
        raise ValueError(f"Unknown model alias: {model_alias}")

    body = {
        "anthropic_version": "bedrock-2023-05-31",
        "max_tokens": max_tokens,
        "system": system_prompt,
        "messages": messages,
    }

    response = client.invoke_model(
        modelId=model_id,
        contentType="application/json",
        accept="application/json",
        body=json.dumps(body),
    )

    result = json.loads(response["body"].read())
    text = ""
    for block in result.get("content", []):
        if block.get("type") == "text":
            text += block["text"]

    usage = result.get("usage", {})
    return {
        "response": text,
        "input_tokens": usage.get("input_tokens", 0),
        "output_tokens": usage.get("output_tokens", 0),
    }


def _invoke_anthropic(model_alias: str, system_prompt: str, messages: list, max_tokens: int) -> dict:
    """Fallback: call Anthropic API directly."""
    client = _get_anthropic_client()
    if client is None:
        raise RuntimeError("Anthropic client not available (no CLAUDE_API_KEY)")

    # Map aliases to Anthropic model names (same IDs work for direct API)
    model_id = MODEL_IDS.get(model_alias)
    if not model_id:
        raise ValueError(f"Unknown model alias: {model_alias}")

    response = client.messages.create(
        model=model_id,
        max_tokens=max_tokens,
        system=system_prompt,
        messages=messages,
    )

    text = ""
    for block in response.content:
        if block.type == "text":
            text += block.text

    return {
        "response": text,
        "input_tokens": response.usage.input_tokens,
        "output_tokens": response.usage.output_tokens,
    }


# ---------------------------------------------------------------------------
# Request / response models
# ---------------------------------------------------------------------------

class ThinkRequest(BaseModel):
    model: str = "sonnet"
    system_prompt: str = ""
    messages: list = []
    max_tokens: int = 4096


class MemoryCreateRequest(BaseModel):
    collection_name: str


class MemoryAddRequest(BaseModel):
    collection: str
    id: str
    document: str
    metadata: dict = {}


class MemoryQueryRequest(BaseModel):
    collection: str
    query_text: str
    n_results: int = 5
    where: Optional[dict] = None


class MemoryGetRequest(BaseModel):
    collection: str
    id: str


class MemoryDeleteCollectionRequest(BaseModel):
    collection_name: str


# ---------------------------------------------------------------------------
# Endpoints — Inference
# ---------------------------------------------------------------------------

@app.post("/think")
async def think(req: ThinkRequest):
    """Run Claude inference via Bedrock, falling back to direct Anthropic API."""
    try:
        return _invoke_bedrock(req.model, req.system_prompt, req.messages, req.max_tokens)
    except Exception as bedrock_err:
        logger.info("Bedrock unavailable (%s), falling back to Anthropic API.", bedrock_err)
        try:
            return _invoke_anthropic(req.model, req.system_prompt, req.messages, req.max_tokens)
        except Exception as api_err:
            logger.error("Both Bedrock and Anthropic API failed: %s", api_err)
            raise HTTPException(status_code=502, detail=f"Inference failed: {api_err}")


# ---------------------------------------------------------------------------
# Endpoints — Memory (ChromaDB)
# ---------------------------------------------------------------------------

@app.post("/memory/create")
async def memory_create(req: MemoryCreateRequest):
    try:
        collection = chroma_client.get_or_create_collection(name=req.collection_name)
        return {"name": collection.name}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/memory/add")
async def memory_add(req: MemoryAddRequest):
    try:
        collection = chroma_client.get_collection(name=req.collection)
        collection.upsert(
            ids=[req.id],
            documents=[req.document],
            metadatas=[req.metadata],
        )
        return {"success": True}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/memory/query")
async def memory_query(req: MemoryQueryRequest):
    try:
        collection = chroma_client.get_collection(name=req.collection)
        results = collection.query(
            query_texts=[req.query_text],
            n_results=req.n_results,
            where=req.where,
        )

        ids = results.get("ids", [[]])[0]
        documents = results.get("documents", [[]])[0]
        metadatas = results.get("metadatas", [[]])[0]
        distances = results.get("distances", [[]])[0]

        return {
            "ids": ids,
            "documents": documents,
            "metadatas": metadatas,
            "distances": distances,
        }
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/memory/get")
async def memory_get(req: MemoryGetRequest):
    try:
        collection = chroma_client.get_collection(name=req.collection)
        results = collection.get(ids=[req.id])

        if results["documents"] and len(results["documents"]) > 0:
            return {
                "id": results["ids"][0],
                "document": results["documents"][0],
                "metadata": results["metadatas"][0] if results["metadatas"] else {},
            }
        else:
            raise HTTPException(status_code=404, detail=f"Memory '{req.id}' not found")
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.post("/memory/delete_collection")
async def memory_delete_collection(req: MemoryDeleteCollectionRequest):
    try:
        chroma_client.delete_collection(name=req.collection_name)
        return {"success": True}
    except Exception:
        # Collection may not exist — treat as success (matches chroma_cli.py behaviour)
        return {"success": True}


@app.get("/memory/count/{collection}")
async def memory_count(collection: str):
    try:
        col = chroma_client.get_collection(name=collection)
        return {"count": col.count()}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


@app.get("/memory/list")
async def memory_list():
    try:
        collections = chroma_client.list_collections()
        names = [c.name for c in collections]
        return {"collections": names}
    except Exception as exc:
        raise HTTPException(status_code=500, detail=str(exc))


# ---------------------------------------------------------------------------
# Health check
# ---------------------------------------------------------------------------

@app.get("/health")
async def health():
    return {
        "status": "ok",
        "bedrock": _get_bedrock_client() is not None,
        "anthropic": _get_anthropic_client() is not None,
        "chroma": True,
    }


# ---------------------------------------------------------------------------
# Startup
# ---------------------------------------------------------------------------

@app.on_event("startup")
async def on_startup():
    logger.info("Sidecar ready on http://localhost:8080")


if __name__ == "__main__":
    uvicorn.run("sidecar.server:app", host="127.0.0.1", port=8080, log_level="info")
