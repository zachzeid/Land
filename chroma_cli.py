#!/usr/bin/env python3
"""
ChromaDB CLI wrapper - Allows Godot to interact with ChromaDB via command-line calls
Usage: python3 chroma_cli.py <command> [args...]
"""

import sys
import json
import base64
import chromadb
from chromadb.config import Settings

# Use persistent client (local database, no server needed)
client = chromadb.PersistentClient(path="./chroma")

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

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"error": "No command specified"}))
        sys.exit(1)
    
    command = sys.argv[1]
    
    try:
        if command == "create_collection":
            create_collection(sys.argv[2])
        
        elif command == "add_memory":
            collection_name = sys.argv[2]
            memory_id = sys.argv[3]
            document_b64 = sys.argv[4]
            metadata_b64 = sys.argv[5] if len(sys.argv) > 5 else ""
            add_memory(collection_name, memory_id, document_b64, metadata_b64)
        
        elif command == "query":
            collection_name = sys.argv[2]
            query_text = sys.argv[3]
            n_results = int(sys.argv[4]) if len(sys.argv) > 4 else 5
            min_importance = int(sys.argv[5]) if len(sys.argv) > 5 and sys.argv[5] != "-1" else None
            memory_tier = int(sys.argv[6]) if len(sys.argv) > 6 else None
            query_memories(collection_name, query_text, n_results, min_importance, memory_tier)
        
        elif command == "get_by_id":
            collection_name = sys.argv[2]
            memory_id = sys.argv[3]
            get_by_id(collection_name, memory_id)

        elif command == "delete_collection":
            collection_name = sys.argv[2]
            delete_collection(collection_name)

        elif command == "list_collections":
            list_collections()

        elif command == "get_count":
            collection_name = sys.argv[2]
            get_count(collection_name)

        else:
            print(json.dumps({"error": f"Unknown command: {command}"}))
            sys.exit(1)
    
    except Exception as e:
        print(json.dumps({"error": str(e)}))
        sys.exit(1)
