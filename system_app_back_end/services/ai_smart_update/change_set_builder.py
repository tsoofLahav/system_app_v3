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
