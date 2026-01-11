#!/usr/bin/env python3
"""Test ChromaDB directly with Python to verify it's working"""

import requests
import json
import time

CHROMA_URL = "http://localhost:8000"
TENANT = "default_tenant"
DATABASE = "default_database"

def test_heartbeat():
    """Test ChromaDB connection"""
    print("Test 1: ChromaDB heartbeat...")
    try:
        response = requests.get(f"{CHROMA_URL}/api/v2/heartbeat")
        if response.status_code == 200:
            print("✓ ChromaDB is running")
            return True
        else:
            print(f"✗ Failed: {response.status_code}")
            return False
    except Exception as e:
        print(f"✗ Connection failed: {e}")
        return False

def test_create_collection():
    """Create a test collection"""
    print("\nTest 2: Create collection...")
    collection_name = "test_python_collection"
    
    # Delete if exists
    try:
        requests.delete(f"{CHROMA_URL}/api/v2/tenants/{TENANT}/databases/{DATABASE}/collections/{collection_name}")
    except:
        pass
    
    try:
        response = requests.post(
            f"{CHROMA_URL}/api/v2/tenants/{TENANT}/databases/{DATABASE}/collections",
            json={"name": collection_name, "metadata": {"test": "true"}}
        )
        
        if response.status_code in [200, 201]:
            print(f"✓ Collection created: {collection_name}")
            return collection_name
        else:
            print(f"✗ Failed: {response.status_code} - {response.text}")
            return None
    except Exception as e:
        print(f"✗ Error: {e}")
        return None

def test_add_memories(collection_name):
    """Add test memories"""
    print("\nTest 3: Add memories...")
    
    try:
        response = requests.post(
            f"{CHROMA_URL}/api/v2/tenants/{TENANT}/databases/{DATABASE}/collections/{collection_name}/add",
            json={
                "ids": ["mem1", "mem2", "mem3"],
                "documents": [
                    "The player helped me with the sword quest. I'm grateful.",
                    "The player asked about my daughter. I told them she's a healer.",
                    "I saw the player steal from the merchant. I don't trust thieves."
                ],
                "metadatas": [
                    {"importance": 8, "emotion": "grateful"},
                    {"importance": 6, "emotion": "proud"},
                    {"importance": 9, "emotion": "disapproval"}
                ]
            }
        )
        
        if response.status_code in [200, 201]:
            print("✓ Added 3 memories")
            return True
        else:
            print(f"✗ Failed: {response.status_code} - {response.text}")
            return False
    except Exception as e:
        print(f"✗ Error: {e}")
        return False

def test_query_memories(collection_name):
    """Query memories"""
    print("\nTest 4: Query memories...")
    
    try:
        response = requests.post(
            f"{CHROMA_URL}/api/v2/tenants/{TENANT}/databases/{DATABASE}/collections/{collection_name}/query",
            json={
                "query_texts": ["What does the NPC think about trustworthiness?"],
                "n_results": 2
            }
        )
        
        if response.status_code == 200:
            data = response.json()
            documents = data.get("documents", [[]])[0]
            print(f"✓ Retrieved {len(documents)} memories:")
            for i, doc in enumerate(documents, 1):
                print(f"  {i}. {doc[:60]}...")
            return True
        else:
            print(f"✗ Failed: {response.status_code} - {response.text}")
            return False
    except Exception as e:
        print(f"✗ Error: {e}")
        return False

if __name__ == "__main__":
    print("=== ChromaDB Python Test ===\n")
    
    if not test_heartbeat():
        print("\n❌ ChromaDB not running. Start with: chroma run --host localhost --port 8000")
        exit(1)
    
    collection = test_create_collection()
    if not collection:
        print("\n❌ Failed to create collection")
        exit(1)
    
    if not test_add_memories(collection):
        print("\n❌ Failed to add memories")
        exit(1)
    
    if not test_query_memories(collection):
        print("\n❌ Failed to query memories")
        exit(1)
    
    print("\n=== ✅ All Tests Passed ===")
    print("ChromaDB is working correctly!")
