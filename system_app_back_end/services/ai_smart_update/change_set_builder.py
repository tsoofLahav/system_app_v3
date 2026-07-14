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
) -> tuple[list[dict], list[dict]]:
    """Build anchor-only units and approval-gated add_after proposals for a new part."""
    units = [{"id": anchor_unit_id, "kind": kind, "text": ""}]
    changes = []
    anchor_id = anchor_unit_id

    for index, raw_text in enumerate(items):
        text = str(raw_text).strip()
        if not text:
            continue
        change_id = f"{key}:c{len(changes) + 1}"
        new_unit_id = f"new:{change_id}"
        changes.append(
            {
                "id": change_id,
                "action": "add_after",
                "unit_id": anchor_id,
                "old_text": "",
                "new_text": text,
                "new_unit": {"id": new_unit_id, "kind": kind, "text": text},
            }
        )
        anchor_id = new_unit_id

    return units, changes
