import json
from openai import OpenAI

# Configure client to use local server
client = OpenAI(
    base_url="http://localhost:10240/v1",  # Point to local server
    api_key="not-needed"  # API key is not required for local server
)

# Define the conversation with the AI
messages = [
    {"role": "system", "content": "You are a helpful AI assistant."},
    {"role": "user", "content": "Create 1-3 fictional characters"}
]

# Define the expected response structure (JSON Schema)
character_schema = {
    "type": "json_schema",
    "json_schema": {
        "name": "characters",
        "description": "Schema for generating fictional characters",
        "schema": {
            "type": "object",
            "properties": {
                "characters": {
                    "type": "array",
                    "description": "A list of fictional characters",
                    "items": {
                        "type": "object",
                        "properties": {
                            "name": {"type": "string", "description": "Character's full name"},
                            "occupation": {"type": "string", "description": "Character's primary job or role"},
                            "personality": {"type": "string", "description": "Key personality traits"},
                            "background": {"type": "string", "description": "Brief background or history"}
                        },
                        "required": ["name", "occupation", "personality", "background"]
                    },
                    "minItems": 1,
                    "maxItems": 3 # Explicitly setting maxItems based on user request
                }
            },
            "required": ["characters"]
        },
    }
}

print("Requesting structured character data from the model...")

try:
    # Get response from AI, enforcing the schema
    response = client.chat.completions.create(
        model="mlx-community/QwQ-32B-4bit", # Make sure this model is served by your local engine
        messages=messages,
        response_format=character_schema,
        max_tokens=1024, # Allow enough tokens for the JSON response
    )

    # Parse and display the results
    content = response.choices[0].message.content
    print("Raw JSON response from model:")
    print(content)

    print("Parsed and formatted character data:")
    results = json.loads(content)
    print(json.dumps(results, indent=2))

except Exception as e:
    print(f"An error occurred: {e}")

print("Script finished.") 