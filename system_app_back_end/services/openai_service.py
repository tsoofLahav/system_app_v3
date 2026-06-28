import base64
import json

from config import OPENAI_API_KEY, OPENAI_IMAGE_MODEL, OPENAI_MODEL
from openai import OpenAI
from urllib.request import urlopen


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
