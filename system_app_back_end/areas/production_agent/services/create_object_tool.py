"""Agent create_object tool — allocate embed id + insert pointer."""

from __future__ import annotations

from typing import Any

from models import File, ObjectEmbed, db
from areas.files.services.document_agent_text import load_objects_by_id
from areas.objects.services.create_embed import (
    create_embed_in_file,
    normalize_create_type,
)
from areas.production_agent.services.browse_tools import (
    block_index_after_agent_line,
    file_allowed,
)
from areas.production_agent.services.openai_service import generate_image
from areas.production_agent.services.write_tools import WriteMode, resolve_write_mode
from shared.routes.upload import store_image_bytes


def _empty_image_embed(file_id: int) -> ObjectEmbed | None:
    """An image object in this file that still has no uploaded url."""
    embeds = ObjectEmbed.query.filter_by(file_id=file_id, type="image").all()
    for embed in embeds:
        payload = embed.payload or {}
        if not str(payload.get("url") or payload.get("path") or "").strip():
            return embed
    return None


def _create_result(
    *,
    file_id: int,
    object_id: int,
    type_: str,
    write_mode: WriteMode,
    payload: dict[str, Any] | None = None,
    filled_existing: bool = False,
) -> dict[str, Any]:
    result: dict[str, Any] = {
        "tool": "create_object",
        "file_id": file_id,
        "object_id": object_id,
        "type": type_ if type_ != "graph" else "graph",
        "write_mode": write_mode,
    }
    if payload and payload.get("url"):
        result["url"] = payload["url"]
        if payload.get("caption"):
            result["caption"] = payload["caption"]
    if filled_existing:
        result["filled_existing"] = True
    if write_mode == "notify_only":
        return {**result, "applied": False}
    if write_mode == "review":
        # Still flushed in-session so later open_file/patch see the id; run may roll back.
        return {**result, "applied": False}
    return {**result, "applied": True}


def create_object(
    *,
    file_id: int,
    type_: str,
    scope: dict,
    write_mode: WriteMode,
    title: str = "",
    body: str = "",
    after_line: int | None = None,
) -> dict[str, Any]:
    file = db.session.get(File, file_id)
    if file is None:
        return {"error": "file not found", "tool": "create_object"}
    if not file_allowed(file, scope):
        return {"error": "file out of scope", "tool": "create_object"}
    if file.archived_at is not None:
        return {"error": "archived files are read-only", "tool": "create_object"}

    block_index: int | None = None
    if after_line is not None:
        objects_by_id = load_objects_by_id(file.id)
        block_index = block_index_after_agent_line(
            file.document_json or "",
            objects_by_id,
            int(after_line),
        )

    api_type, _is_chart = normalize_create_type(type_)
    payload: dict[str, Any] | None = None
    if api_type == "image":
        picture = (body or title or "").strip()
        if not picture:
            return {
                "error": "image needs a description in body (the picture to generate)",
                "tool": "create_object",
            }
        try:
            png = generate_image(picture)
            url = store_image_bytes(png, original_name="generated.png")
        except Exception as err:
            return {
                "error": f"could not generate image: {err}",
                "tool": "create_object",
            }
        payload = {"url": url, "caption": (title or "").strip()}
        existing = _empty_image_embed(file.id)
        if existing is not None:
            existing.payload = payload
            db.session.flush()
            return _create_result(
                file_id=file.id,
                object_id=existing.id,
                type_="image",
                write_mode=write_mode,
                payload=payload,
                filled_existing=True,
            )

    try:
        embed = create_embed_in_file(
            file,
            type_=type_,
            title=title or "",
            body=body or "",
            payload=payload,
            block_index=block_index,
        )
    except ValueError as err:
        return {"error": str(err), "tool": "create_object"}

    return _create_result(
        file_id=file.id,
        object_id=embed.id,
        type_=type_,
        write_mode=write_mode,
        payload=payload,
    )


def create_object_write_mode(run_apply_mode: str) -> WriteMode:
    return resolve_write_mode("create_object", run_apply_mode)
