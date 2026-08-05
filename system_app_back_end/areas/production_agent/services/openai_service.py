"""OpenAI client helpers for the production agent.

The agent runner uses the **Responses API** with a per-flow Conversation.
`chat_text` / `chat_json` / `generate_image` remain for non-agent callers.
"""

from __future__ import annotations

import base64
import json
from typing import Any

from config import OPENAI_API_KEY, OPENAI_IMAGE_MODEL, OPENAI_MODEL
from openai import OpenAI
from urllib.request import urlopen


def _client() -> OpenAI:
    if not OPENAI_API_KEY:
        raise RuntimeError("OPENAI_API_KEY is not configured")
    return OpenAI(api_key=OPENAI_API_KEY)


def chat_text(system: str, user: str, *, max_tokens: int = 500) -> str:
    response = _client().chat.completions.create(
        model=OPENAI_MODEL,
        messages=[
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        max_tokens=max_tokens,
        temperature=0.4,
    )
    return (response.choices[0].message.content or "").strip()


def chat_json(system: str, user: str, *, temperature: float = 0.2) -> dict:
    response = _client().chat.completions.create(
        model=OPENAI_MODEL,
        messages=[
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        response_format={"type": "json_object"},
        temperature=temperature,
    )
    raw = response.choices[0].message.content or "{}"
    return json.loads(raw)


def generate_image(prompt: str) -> bytes:
    """Generate an image and return raw PNG bytes."""
    response = _client().images.generate(
        model=OPENAI_IMAGE_MODEL,
        prompt=prompt[:4000],
        size="1024x1024",
        n=1,
    )
    item = response.data[0]
    if item.b64_json:
        return base64.b64decode(item.b64_json)
    if item.url:
        with urlopen(item.url) as resp:
            return resp.read()
    raise RuntimeError("Image generation returned no image data")


def create_conversation(*, metadata: dict[str, str] | None = None) -> str:
    """Create a short-lived OpenAI Conversation; returns its id."""
    conversation = _client().conversations.create(metadata=metadata or {})
    return conversation.id


def delete_conversation(conversation_id: str) -> None:
    """Best-effort delete; ignores missing/already-deleted conversations."""
    try:
        _client().conversations.delete(conversation_id)
    except Exception:
        pass


def create_response(
    *,
    model: str,
    conversation_id: str,
    instructions: str,
    tools: list[dict[str, Any]],
    input: str | list[dict[str, Any]],
    temperature: float = 0.2,
) -> Any:
    """One Responses API turn attached to an existing conversation."""
    return _client().responses.create(
        model=model,
        conversation=conversation_id,
        instructions=instructions,
        tools=tools,
        input=input,
        temperature=temperature,
        store=True,
    )


def function_calls_from_response(response: Any) -> list[dict[str, Any]]:
    """Extract native function_call items from a Responses API payload."""
    calls: list[dict[str, Any]] = []
    for item in getattr(response, "output", None) or []:
        item_type = getattr(item, "type", None)
        if item_type != "function_call":
            continue
        raw_args = getattr(item, "arguments", None) or "{}"
        try:
            args = json.loads(raw_args) if isinstance(raw_args, str) else dict(raw_args)
        except json.JSONDecodeError:
            args = {"_raw": raw_args}
        calls.append(
            {
                "call_id": getattr(item, "call_id", None),
                "name": getattr(item, "name", None),
                "arguments": args if isinstance(args, dict) else {"value": args},
            }
        )
    return calls


def output_text_from_response(response: Any) -> str:
    text = getattr(response, "output_text", None)
    if isinstance(text, str) and text.strip():
        return text.strip()
    chunks: list[str] = []
    for item in getattr(response, "output", None) or []:
        if getattr(item, "type", None) != "message":
            continue
        for part in getattr(item, "content", None) or []:
            part_type = getattr(part, "type", None)
            if part_type in ("output_text", "text"):
                value = getattr(part, "text", None)
                if value:
                    chunks.append(str(value))
    return "\n".join(chunks).strip()
