#!/usr/bin/env python3
"""
ChromaDB Bridge - Simple HTTP server that wraps ChromaDB Python client
This allows Godot to use ChromaDB's auto-embedding features via simple HTTP calls
"""

from flask import Flask, request, jsonify
import chromadb
from chromadb.config import Settings

app = Flask(__name__)

# Initialize ChromaDB client
client = chromadb.HttpClient(host="localhost", port=8000)

@app.route('/health', methods=['GET'])
def health():
    """Health check endpoint"""
    try:
        client.heartbeat()
        return jsonify({"status": "ok"}), 200
    except Exception as e:
        return jsonify({"status": "error", "message": str(e)}), 500

@app.route('/collection/<collection_name>', methods=['POST'])
def create_collection(collection_name):
    """Create or get collection"""
    try:
        collection = client.get_or_create_collection(name=collection_name)
        return jsonify({
            "name": collection.name,
            "id": collection.id
        }), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/collection/<collection_name>/add', methods=['POST'])
def add_to_collection(collection_name):
    """Add documents to collection (embeddings auto-generated)"""
    try:
        data = request.json
        collection = client.get_collection(name=collection_name)
        
        collection.add(
            ids=data.get('ids', []),
            documents=data.get('documents', []),
            metadatas=data.get('metadatas', [])
        )
        
        return jsonify({"success": True}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/collection/<collection_name>/query', methods=['POST'])
def query_collection(collection_name):
    """Query collection with semantic search"""
    try:
        data = request.json
        collection = client.get_collection(name=collection_name)
        
        results = collection.query(
            query_texts=data.get('query_texts', []),
            n_results=data.get('n_results', 5),
            where=data.get('where')
        )
        
        return jsonify(results), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

@app.route('/collection/<collection_name>', methods=['DELETE'])
def delete_collection(collection_name):
    """Delete collection"""
    try:
        client.delete_collection(name=collection_name)
        return jsonify({"success": True}), 200
    except Exception as e:
        return jsonify({"error": str(e)}), 500

if __name__ == '__main__':
    print("ChromaDB Bridge starting on http://localhost:8001")
    print("Make sure ChromaDB server is running on localhost:8000")
    app.run(host='0.0.0.0', port=8001, debug=False)
