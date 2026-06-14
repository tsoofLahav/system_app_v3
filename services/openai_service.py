import json

from config import OPENAI_API_KEY, OPENAI_IMAGE_MODEL, OPENAI_MODEL
from openai import OpenAI


def _client():
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


def chat_json(system: str, user: str) -> dict:
    response = _client().chat.completions.create(
        model=OPENAI_MODEL,
        messages=[
            {"role": "system", "content": system},
            {"role": "user", "content": user},
        ],
        response_format={"type": "json_object"},
        temperature=0.2,
    )
    raw = response.choices[0].message.content or "{}"
    return json.loads(raw)


def generate_image(prompt: str) -> str:
    """Returns a temporary URL from OpenAI."""
    response = _client().images.generate(
        model=OPENAI_IMAGE_MODEL,
        prompt=prompt[:4000],
        size="1024x1024",
        n=1,
    )
    return response.data[0].url
