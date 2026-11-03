#!/usr/bin/env python3
"""
ChromaDB CLI wrapper - Allows Godot to interact with ChromaDB via command-line calls
Usage: python3 chroma_cli.py <command> [args...]
       python3 chroma_cli.py serve   (one command per stdin line; used by ChromaClient)
"""

import os
import io
import sys
import json
import base64
import contextlib
import chromadb
from chromadb.config import Settings

# Use persistent client (local database, no server needed); tests point LAND_CHROMA_PATH at a temp dir
client = chromadb.PersistentClient(path=os.environ.get("LAND_CHROMA_PATH", "./chroma"))

def create_collection(collection_name):
    """Create or get collection"""
    collection = client.get_or_create_collection(name=collection_name)
    print(json.dumps({"success": True, "name": collection.name}))

def add_memory(collection_name, memory_id, document_b64, metadata_b64):
    """Add document to collection"""
    collection = client.get_collection(name=collection_name)
    
    # Decode base64 document and metadata to avoid shell escaping issues
    try:
        if document_b64:
            document = base64.b64decode(document_b64).decode('utf-8')
        else:
            print(json.dumps({"error": "Missing document"}))  
            return
            
        if metadata_b64:
            metadata_json = base64.b64decode(metadata_b64).decode('utf-8')
            metadata = json.loads(metadata_json)
        else:
            metadata = {}
    except (json.JSONDecodeError, base64.binascii.Error) as e:
        print(json.dumps({"error": f"Invalid base64 data: {str(e)}"}))  
        return
    
    # Use upsert instead of add to replace existing IDs
    collection.upsert(
        ids=[memory_id],
        documents=[document],
        metadatas=[metadata]
    )
    print(json.dumps({"success": True}))

def query_memories(collection_name, query_text, n_results=5, min_importance=None, memory_tier=None):
    """Query collection with optional filters"""
    collection = client.get_collection(name=collection_name)

    # Build where filter for metadata
    where_filter = None
    conditions = []

    if min_importance is not None:
        conditions.append({"importance": {"$gte": min_importance}})

    if memory_tier is not None:
        conditions.append({"memory_tier": memory_tier})

    if len(conditions) == 1:
        where_filter = conditions[0]
    elif len(conditions) > 1:
        where_filter = {"$and": conditions}

    results = collection.query(
        query_texts=[query_text],
        n_results=n_results,
        where=where_filter
    )
    
    # Format results
    memories = []
    if results['documents'] and len(results['documents']) > 0:
        docs = results['documents'][0]
        metas = results.get('metadatas', [[]])[0]
        ids = results.get('ids', [[]])[0]
        distances = results.get('distances', [[]])[0]
        
        for i in range(len(docs)):
            memories.append({
                "id": ids[i] if i < len(ids) else "",
                "document": docs[i],
                "metadata": metas[i] if i < len(metas) else {},
                "distance": distances[i] if i < len(distances) else 0.0
            })
    
    print(json.dumps({"success": True, "memories": memories}))

def delete_memory(collection_name, memory_id):
    """Delete one document by ID"""
    collection = client.get_collection(name=collection_name)
    collection.delete(ids=[memory_id])
    print(json.dumps({"success": True}))

def update_metadata(collection_name, memory_id, metadata_b64):
    """Replace one document's metadata (document and embedding unchanged)"""
    collection = client.get_collection(name=collection_name)
    try:
        metadata = json.loads(base64.b64decode(metadata_b64).decode('utf-8'))
    except (json.JSONDecodeError, base64.binascii.Error) as e:
        print(json.dumps({"error": f"Invalid base64 data: {str(e)}"}))
        return
    if not collection.get(ids=[memory_id])['ids']:
        print(json.dumps({"error": f"No memory with id {memory_id}"}))
        return
    collection.update(ids=[memory_id], metadatas=[metadata])
    print(json.dumps({"success": True}))

def get_by_id(collection_name, memory_id):
    """Get specific document by ID"""
    collection = client.get_collection(name=collection_name)

    try:
        results = collection.get(ids=[memory_id])

        if results['documents'] and len(results['documents']) > 0:
            memory = {
                "id": results['ids'][0],
                "document": results['documents'][0],
                "metadata": results['metadatas'][0] if results['metadatas'] else {}
            }
            print(json.dumps({"success": True, "memory": memory}))
        else:
            print(json.dumps({"success": True, "memory": None}))
    except Exception as e:
        print(json.dumps({"error": str(e)}))

def get_where(collection_name, where_b64, limit=10):
    """Exact metadata match (no embedding). where is base64 JSON {key: value, ...}"""
    try:
        where = json.loads(base64.b64decode(where_b64).decode('utf-8'))
        collection = client.get_collection(name=collection_name)
        conditions = [{key: value} for key, value in where.items()]
        where_filter = conditions[0] if len(conditions) == 1 else {"$and": conditions}
        results = collection.get(where=where_filter, limit=limit)
        memories = []
        for i, memory_id in enumerate(results.get('ids', [])):
            memories.append({
                "id": memory_id,
                "document": results['documents'][i] if results.get('documents') else "",
                "metadata": results['metadatas'][i] if results.get('metadatas') else {}
            })
        print(json.dumps({"success": True, "memories": memories}))
    except Exception as e:
        print(json.dumps({"error": str(e), "memories": []}))

def delete_collection(collection_name):
    """Delete a collection and all its data"""
    try:
        client.delete_collection(name=collection_name)
        print(json.dumps({"success": True, "deleted": collection_name}))
    except Exception as e:
        # Collection might not exist, that's OK
        print(json.dumps({"success": True, "deleted": collection_name, "note": str(e)}))

def list_collections():
    """List all collections"""
    try:
        collections = client.list_collections()
        names = [c.name for c in collections]
        print(json.dumps({"success": True, "collections": names}))
    except Exception as e:
        print(json.dumps({"error": str(e)}))

def get_count(collection_name):
    """Get count of documents in a collection"""
    try:
        collection = client.get_collection(name=collection_name)
        count = collection.count()
        print(json.dumps({"success": True, "count": count}))
    except Exception as e:
        print(json.dumps({"error": str(e), "count": 0}))

def dispatch(argv):
    """Run one command (argv = [command, args...]); prints one JSON line, returns the exit code"""
    if len(argv) < 1:
        print(json.dumps({"error": "No command specified"}))
        return 1
    command = argv[0]
    sys_argv = ["chroma_cli.py"] + list(argv)  # same indexes as the command line

    try:
        if command == "create_collection":
            create_collection(sys_argv[2])
        
        elif command == "add_memory":
            collection_name = sys_argv[2]
            memory_id = sys_argv[3]
            document_b64 = sys_argv[4]
            metadata_b64 = sys_argv[5] if len(sys_argv) > 5 else ""
            add_memory(collection_name, memory_id, document_b64, metadata_b64)
        
        elif command == "query":
            collection_name = sys_argv[2]
            query_text = sys_argv[3]
            if query_text.startswith("b64:"):  # ChromaClient encodes queries: they carry player speech
                query_text = base64.b64decode(query_text[4:]).decode('utf-8')
            n_results = int(sys_argv[4]) if len(sys_argv) > 4 else 5
            min_importance = int(sys_argv[5]) if len(sys_argv) > 5 and sys_argv[5] != "-1" else None
            memory_tier = int(sys_argv[6]) if len(sys_argv) > 6 else None
            query_memories(collection_name, query_text, n_results, min_importance, memory_tier)
        
        elif command == "get_by_id":
            collection_name = sys_argv[2]
            memory_id = sys_argv[3]
            get_by_id(collection_name, memory_id)

        elif command == "delete_memory":
            delete_memory(sys_argv[2], sys_argv[3])

        elif command == "update_metadata":
            update_metadata(sys_argv[2], sys_argv[3], sys_argv[4])

        elif command == "get_where":
            get_where(sys_argv[2], sys_argv[3], int(sys_argv[4]) if len(sys_argv) > 4 else 10)

        elif command == "delete_collection":
            collection_name = sys_argv[2]
            delete_collection(collection_name)

        elif command == "list_collections":
            list_collections()

        elif command == "get_count":
            collection_name = sys_argv[2]
            get_count(collection_name)

        else:
            print(json.dumps({"error": f"Unknown command: {command}"}))
            return 1
    
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        return 1
    return 0

def serve():
    """Long-lived mode for ChromaClient: one JSON array of argv per stdin line, one reply per line
    {"code": exit code, "out": the command's JSON line}. Pays the chromadb import and the embedding
    model load once per game instead of once per call. Exits when stdin closes (the game quit)."""
    reply_to = sys.stdout
    devnull = os.open(os.devnull, os.O_WRONLY)
    os.dup2(devnull, 2)  # nobody reads our stderr: a full pipe would block us
    sys.stdout = sys.stderr  # stray prints (library warnings) never corrupt a reply
    stdin = io.TextIOWrapper(sys.stdin.buffer, encoding="utf-8")
    while True:
        line = stdin.readline()
        if not line:
            return
        line = line.strip()
        if not line:
            continue
        buf = io.StringIO()
        try:
            argv = json.loads(line)
            if not isinstance(argv, list):
                raise ValueError("request must be a JSON array")
            with contextlib.redirect_stdout(buf):
                code = dispatch([str(a) for a in argv])
        except Exception as e:
            buf.write(json.dumps({"error": str(e)}) + "\n")
            code = 1
        lines = [l for l in buf.getvalue().splitlines() if l.strip()]
        reply_to.write(json.dumps({"code": code, "out": lines[-1] if lines else ""}) + "\n")
        reply_to.flush()

if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "serve":
        serve()
        sys.exit(0)
    sys.exit(dispatch(sys.argv[1:]))
