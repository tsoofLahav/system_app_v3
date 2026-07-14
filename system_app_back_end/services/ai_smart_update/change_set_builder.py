"""Build change set payloads for process and project updates."""

from __future__ import annotations

from services.diff_engine import CHANGE_SET_VERSION, build_change_set, build_document_change_set

CHANGE_SET_VERSION_PART = 2


def build_process_change_set(documents: list[dict]) -> dict:
    return build_change_set(documents)


def build_part_change_set(
    *,
    log_file: dict,
    parts: list[dict],
    doc_append: dict | None = None,
) -> dict:
    payload = {
        "version": CHANGE_SET_VERSION_PART,
        "log_file": log_file,
        "parts": parts,
    }
    if doc_append:
        payload["doc_append"] = doc_append
    return payload


def build_part_documents(
    part_name: str,
    document_specs: list[tuple[str, str, list, list]],
) -> list[dict]:
    documents = []
    for key, title, units, ops in document_specs:
        documents.append(build_document_change_set(key, title, units, ops))
    return documents


def build_chained_add_after_changes(
    *,
    key: str,
    anchor_unit_id: str,
    items: list[str],
    kind: str,
    item_kinds: list[str] | None = None,
) -> tuple[list[dict], list[dict]]:
    """Build anchor-only units and approval-gated add_after proposals for a new part."""
    anchor_kind = item_kinds[0] if item_kinds else kind
    units = [{"id": anchor_unit_id, "kind": anchor_kind, "text": ""}]
    changes = []
    anchor_id = anchor_unit_id

    for index, raw_text in enumerate(items):
        text = str(raw_text).strip()
        if not text:
            continue
        item_kind = item_kinds[index] if item_kinds and index < len(item_kinds) else kind
        change_id = f"{key}:c{len(changes) + 1}"
        new_unit_id = f"new:{change_id}"
        changes.append(
            {
                "id": change_id,
                "action": "add_after",
                "unit_id": anchor_id,
                "old_text": "",
                "new_text": text,
                "new_unit": {"id": new_unit_id, "kind": item_kind, "text": text},
            }
        )
        anchor_id = new_unit_id

    return units, changes


def build_segment_change_set(*, key: str, title: str, segments: list[dict]) -> dict:
    """Build a change document from ordered text/list/task segments."""
    all_items = []
    all_kinds = []
    all_segment_ids = []

    for segment in segments or []:
        segment_id = segment.get("segment_id")
        items = segment.get("items") or []
        item_kinds = segment.get("item_kinds") or []
        block_kind = segment.get("block_kind") or "list"
        default_kind = _default_kind(block_kind)
        for index, raw_text in enumerate(items):
            text = str(raw_text).strip()
            if not text:
                continue
            all_items.append(text)
            all_kinds.append(
                item_kinds[index] if index < len(item_kinds) else default_kind
            )
            all_segment_ids.append(segment_id)

    if not all_items:
        return {"key": key, "title": title, "units": [], "changes": []}

    default_kind = all_kinds[0]
    units, changes = build_chained_add_after_changes(
        key=key,
        anchor_unit_id=f"anchor:{key}",
        items=all_items,
        kind=default_kind,
        item_kinds=all_kinds,
    )

    item_index = 0
    for change in changes:
        if item_index < len(all_segment_ids) and all_segment_ids[item_index]:
            segment_id = all_segment_ids[item_index]
            change["new_unit"]["segment_id"] = segment_id
            new_unit_id = change["new_unit"]["id"]
            for unit in units:
                if unit.get("id") == new_unit_id:
                    unit["segment_id"] = segment_id
        item_index += 1

    return {"key": key, "title": title, "units": units, "changes": changes}


def _default_kind(block_kind: str) -> str:
    if block_kind == "text":
        return "paragraph"
    if block_kind == "task":
        return "task"
    return "list_item"
