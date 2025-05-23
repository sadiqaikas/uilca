import os
import json
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
import openai
import firebase_admin
from firebase_admin import credentials, firestore

# === Initialize Firebase Admin SDK ===
# Replace "firebase_key.json" with the path to your Firebase service account key.
cred = credentials.Certificate("firebase_key.json")
firebase_admin.initialize_app(cred)
db = firestore.client()

# === Set OpenAI API key from environment variable ===
openai.api_key = os.getenv("OPENAI_API_KEY")

# === Initialize FastAPI app ===
app = FastAPI()

# === Define GPT Function Schema ===
# This schema tells GPT how to structure a function call for searching Firestore.
functions = [
    {
        "name": "search_firestore",
        "description": "Search Firestore for a process or dataset based on query keywords",
        "parameters": {
            "type": "object",
            "properties": {
                "query": {
                    "type": "string",
                    "description": "A search string containing keywords like 'Alaska', 'electricity', 'CO2', etc."
                }
            },
            "required": ["query"]
        }
    }
]

# === Define the Firestore search function ===
def search_firestore(query: str) -> dict:
    # Lowercase the query for case-insensitive matching.
    query_lower = query.lower()
    results = []
    # Query the Firestore collection "processes" (make sure your documents are stored there)
    docs = db.collection("processes").stream()
    for doc in docs:
        data = doc.to_dict()
        # Convert the entire record to a lowercase string for matching.
        record_str = json.dumps(data).lower()
        if query_lower in record_str:
            results.append({
                "name": data.get("name"),
                "location": data.get("location"),
                "code": data.get("code"),
                "reference": data.get("reference")
            })
    return {"found": bool(results), "matches": results}

# === Define Request Model for the /chat endpoint ===
class ChatRequest(BaseModel):
    prompt: str

# === Create the /chat endpoint ===
@app.post("/chat")
async def chat_endpoint(request: ChatRequest):
    user_prompt = request.prompt
    print(f"User prompt: {user_prompt}")

    # Call GPT with function calling enabled.
    response = openai.ChatCompletion.create(
        model="gpt-4-0613",
        messages=[{"role": "user", "content": user_prompt}],
        functions=functions,
        function_call="auto"  # GPT will decide whether to call the function
    )
    
    message = response["choices"][0]["message"]
    
    if "function_call" in message:
        fn_call = message["function_call"]
        fn_name = fn_call["name"]
        args = json.loads(fn_call["arguments"])
        print(f"GPT wants to call function: {fn_name} with arguments: {args}")

        # Call our Firestore search function with the parsed arguments.
        search_result = search_firestore(query=args["query"])
        print(f"Search result: {search_result}")

        # Pass the function call result back to GPT for a final natural response.
        followup = openai.ChatCompletion.create(
            model="gpt-4-0613",
            messages=[
                {"role": "user", "content": user_prompt},
                message,
                {"role": "function", "name": fn_name, "content": json.dumps(search_result)}
            ]
        )
        final_reply = followup["choices"][0]["message"]["content"]
        return {"answer": final_reply, "search_result": search_result}
    else:
        # If no function call was made, return GPT's plain answer.
        return {"answer": message["content"]}
