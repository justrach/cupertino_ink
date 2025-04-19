# Copyright © 2025 Apple Inc.

import json

from mlx_lm import load, stream_generate

# Specify the checkpoint
checkpoint = "mlx-community/Qwen2.5-7B-Instruct-1M-4bit"

# Load the corresponding model and tokenizer
model, tokenizer = load(path_or_hf_repo=checkpoint)

# Specify the prompt and conversation history
prompt = "Write a story about Einstein"
messages = [{"role": "user", "content": prompt}]

prompt = tokenizer.apply_chat_template(
    messages, add_generation_prompt=True
)

# Generate the response using streaming:
print(f"User: {messages[0]['content']}\n")
print("Assistant: ", end="", flush=True)
for response in stream_generate(model, tokenizer, prompt, max_tokens=512):
    print(response.text, end="", flush=True)
print()