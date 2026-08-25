"""Image object payload: one picture, or a row of panes."""

from __future__ import annotations

from typing import Any


def panes_of(payload: dict[str, Any] | None) -> list[dict[str, Any]]:
    raw = dict(payload or {})
    images = raw.get("images")
    if isinstance(images, list) and images:
        panes: list[dict[str, Any]] = []
        for item in images:
            if not isinstance(item, dict):
                continue
            url = str(item.get("url") or item.get("path") or "").strip()
            caption = str(item.get("caption") or "")
            panes.append({"url": url, "caption": caption})
        if panes:
            return panes
    return [
        {
            "url": str(raw.get("url") or raw.get("path") or "").strip(),
            "caption": str(raw.get("caption") or ""),
        }
    ]


def mirrored(
    panes: list[dict[str, Any]],
    *,
    width: Any = None,
    look: str | None = None,
) -> dict[str, Any]:
    """First pane on url/caption so older readers still see one picture."""
    cleaned = [
        {
            "url": str(p.get("url") or "").strip(),
            "caption": str(p.get("caption") or ""),
        }
        for p in panes
        if isinstance(p, dict)
    ]
    if not cleaned:
        cleaned = [{"url": "", "caption": ""}]
    first = cleaned[0]
    out: dict[str, Any] = {
        "url": first["url"],
        "caption": first["caption"],
    }
    if width is not None and width != "":
        out["width"] = width
    if look:
        out["look"] = look
    if len(cleaned) > 1:
        out["images"] = cleaned
    return out
