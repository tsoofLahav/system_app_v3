"""Optimistic concurrency on document_json PATCH."""

from __future__ import annotations

from areas.files.services.document_v3 import empty_document_json
from areas.files.services.file_ops import bump_content_revision, check_base_revision
from models import File


def test_check_base_revision_ok():
    file = File(content_revision=3, document_json=empty_document_json())
    ok, err = check_base_revision(file, {"base_revision": 3})
    assert ok and err is None


def test_check_base_revision_conflict():
    file = File(content_revision=3, document_json=empty_document_json())
    ok, err = check_base_revision(file, {"base_revision": 2})
    assert not ok and err == "revision conflict"


def test_check_base_revision_required():
    file = File(content_revision=1, document_json=empty_document_json())
    ok, err = check_base_revision(file, {})
    assert not ok and "base_revision" in (err or "")


def test_bump_content_revision():
    file = File(content_revision=1, document_json=empty_document_json())
    bump_content_revision(file)
    assert file.content_revision == 2


def test_to_dict_includes_content_revision():
    file = File(
        id=1,
        topic_id=1,
        name="Notes",
        document_json=empty_document_json(),
        content_revision=7,
    )
    data = file.to_dict(include_document=False)
    assert data["content_revision"] == 7
