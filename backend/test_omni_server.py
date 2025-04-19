from openai import OpenAI
from fastapi.testclient import TestClient

# Use TestClient to interact directly with the application

# Configure client to use local server
client = OpenAI(
    base_url="http://localhost:10240/v1",  # Point to local server
    api_key="not-needed"  # API key is not required for local server
)

# Initialize conversation history
messages = []

print("Chat started. Type 'exit' or 'quit' to end.")

while True:
    # Get user input
    user_input = input("You: ")
    if user_input.lower() in ["exit", "quit"]:
        print("Exiting chat.")
        break

    # Add user message to history
    messages.append({"role": "user", "content": user_input})

    # Image Generation Example (Now inside the loop)
    try:
        chat_completion = client.chat.completions.create(
            model="mlx-community/QwQ-32B-4bit",
            messages=messages,  # Send the whole history
            max_tokens=9000,
            stream=True,
        )

        print("Assistant: ", end="", flush=True)
        full_response = ""
        for chunk in chat_completion:
            content = chunk.choices[0].delta.content
            if content:
                print(content, end="", flush=True)
                full_response += content
        print() # Newline after the stream finishes

        # Add assistant response to history
        messages.append({"role": "assistant", "content": full_response})

    except Exception as e:
        print(f"An error occurred: {e}")
        # Optionally remove the last user message if the request failed
        if messages and messages[-1]["role"] == "user":
            messages.pop()