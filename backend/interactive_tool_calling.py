import json
from datetime import datetime, timedelta # Added timedelta for future date
from openai import OpenAI

# --- Configuration ---
# --- Configuration ---
MODEL = "mlx-community/Qwen2.5-7B-Instruct-1M-4bit" # Make sure this model supports tool calling
BASE_URL = "http://localhost:10240/v1"
API_KEY = "not-needed"

# --- Tool Definition ---
tools = [
    {
        "type": "function",
        "function": {
            "name": "get_delivery_date",
            "description": "Get the estimated delivery date for a customer's order. Call this whenever you need to know the delivery date, for example when a customer asks 'Where is my package?' or 'When will my order arrive?'",
            "parameters": {
                "type": "object",
                "properties": {
                    "order_id": {
                        "type": "string",
                        "description": "The customer's unique order identifier.",
                    },
                },
                "required": ["order_id"],
            },
        }
    }
]

# --- Mock Tool Implementation ---
def get_delivery_date(order_id: str) -> dict:
    """Simulates fetching delivery date based on order ID."""
    print(f"--- Tool: Called get_delivery_date for order_id: {order_id} ---")
    # Simulate finding the order and estimating delivery
    # In a real scenario, this would involve database lookups, API calls, etc.
    estimated_delivery = datetime.now() + timedelta(days=3)
    return {
        "order_id": order_id,
        "estimated_delivery_date": estimated_delivery.strftime('%Y-%m-%d') # Just the date
    }

available_functions = {
    "get_delivery_date": get_delivery_date,
}

# --- Main Chat Loop ---
print("Starting interactive chat with tool calling enabled.")
print(f"Model: {MODEL}")
print("Type 'exit' or 'quit' to end.")

# Initialize OpenAI client
client = OpenAI(base_url=BASE_URL, api_key=API_KEY)

# Initialize conversation history with system message
messages = [
    {
        "role": "system",
        "content": "You are a helpful customer support assistant. Use the supplied tools to answer questions about order delivery dates. When asked for a delivery date, first ask for the order ID if it's not provided."
    }
]

while True:
    # Get user input
    user_input = input("You: ")
    if user_input.lower() in ["exit", "quit"]:
        print("Exiting chat.")
        break

    # Add user message to history
    messages.append({"role": "user", "content": user_input})

    try:
        # --- Unified API Call: Handles both direct response and tool call detection (STREAMING) ---
        print("Assistant:", end=" ", flush=True)
        stream = client.chat.completions.create(
            model=MODEL,
            messages=messages,
            tools=tools,
            stream=True, # Enable streaming for the initial response
        )

        # Variables to accumulate stream results
        accumulated_content = ""
        tool_calls_list = []
        current_tool_call_id = None
        current_tool_function_name = ""
        current_tool_function_args = ""
        assistant_role = "assistant" # Default role

        for chunk in stream:
            delta = chunk.choices[0].delta

            # Accumulate content and print delta
            if delta.content:
                print(delta.content, end="", flush=True)
                accumulated_content += delta.content

            # Detect role (usually only in the first chunk)
            if delta.role:
                assistant_role = delta.role

            # Accumulate tool calls
            if delta.tool_calls:
                for tool_call_chunk in delta.tool_calls:
                    # Start of a new tool call
                    if tool_call_chunk.id:
                        # If we were accumulating args for a previous call, store it first
                        if current_tool_call_id:
                             tool_calls_list.append({
                                "id": current_tool_call_id,
                                "type": "function",
                                "function": {"name": current_tool_function_name, "arguments": current_tool_function_args}
                             })
                        # Reset for the new tool call
                        current_tool_call_id = tool_call_chunk.id
                        current_tool_function_name = ""
                        current_tool_function_args = ""

                    # Accumulate name and arguments
                    if tool_call_chunk.function:
                        if tool_call_chunk.function.name:
                            current_tool_function_name += tool_call_chunk.function.name
                        if tool_call_chunk.function.arguments:
                            current_tool_function_args += tool_call_chunk.function.arguments

        print() # Newline after initial stream finishes

        # Store the last accumulated tool call after the loop
        if current_tool_call_id:
            tool_calls_list.append({
                "id": current_tool_call_id,
                "type": "function",
                "function": {"name": current_tool_function_name, "arguments": current_tool_function_args}
            })

        # Construct the full response message for history
        response_message = {
            "role": assistant_role,
            "content": accumulated_content or None, # Use None if content is empty (tool call only)
        }
        if tool_calls_list:
             response_message["tool_calls"] = tool_calls_list

        messages.append(response_message)

        # --- Check if tool calls were detected during the stream ---
        if tool_calls_list:
            print("--- Tool Call(s) Detected & Executing ---")
            # --- Tool Execution Phase (using accumulated tool_calls_list) ---
            for tool_call in tool_calls_list:
                function_name = tool_call["function"]["name"]
                tool_call_id = tool_call["id"]
                try:
                    # Arguments are already accumulated as a string
                    function_args = json.loads(tool_call["function"]["arguments"])
                    print(f"  - Function: {function_name}")
                    print(f"  - Arguments: {function_args}")
                except json.JSONDecodeError:
                     print(f"  - Error: Invalid JSON arguments received for {function_name}: {tool_call['function']['arguments']}")
                     # Append error message for this specific tool call
                     messages.append({
                        "role": "tool",
                        "tool_call_id": tool_call_id,
                        "name": function_name,
                        "content": json.dumps({"error": "Invalid JSON arguments received from model."}),
                     })
                     continue # Skip to next tool call if args are invalid

                if function_name in available_functions:
                    function_to_call = available_functions[function_name]
                    try:
                        # Call the actual function
                        function_response = function_to_call(**function_args)
                        response_content = json.dumps(function_response)
                        print(f"  - Result: {response_content}")
                    except Exception as func_e:
                        print(f"  - Error executing function {function_name}: {func_e}")
                        response_content = json.dumps({"error": f"Failed to execute tool: {str(func_e)}"})

                    # Append the tool's response to the conversation history
                    messages.append({
                        "role": "tool",
                        "tool_call_id": tool_call_id,
                        "name": function_name,
                        "content": response_content,
                    })
                else:
                    print(f"  - Error: Function '{function_name}' not found.")
                    # Append message indicating function not found
                    messages.append({
                       "role": "tool",
                       "tool_call_id": tool_call_id,
                       "name": function_name,
                       "content": json.dumps({"error": f"Function '{function_name}' is not available."}),
                    })

            print("--- Resuming conversation with tool results ---")

            # --- Second API Call: Get final response using tool results (STREAMING) ---
            final_completion_stream = client.chat.completions.create(
                model=MODEL,
                messages=messages,
                tools=tools,
                stream=True # Keep streaming for the final response
            )

            print("Assistant: ", end="", flush=True)
            full_final_response = ""
            final_assistant_role = "assistant"

            for chunk in final_completion_stream:
                delta = chunk.choices[0].delta
                if delta.content:
                    print(delta.content, end="", flush=True)
                    full_final_response += delta.content
                if delta.role:
                    final_assistant_role = delta.role

            print() # Newline after final stream finishes

            # Append final assistant response to history
            messages.append({"role": final_assistant_role, "content": full_final_response})

        # --- Handle case where no tool call was made (response already streamed) ---
        # No explicit 'else' needed here, as the initial response was already streamed and printed.

    except Exception as e:
        print(f"An API error occurred: {e}")
        # Optionally remove the last user message if the request failed
        if messages and messages[-1]["role"] == "user":
             messages.pop()

# Removed extraneous tag at the end 