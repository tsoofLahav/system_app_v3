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


def test_concurrent_orm_writers_cannot_overwrite_same_revision():
    from sqlalchemy import create_engine
    from sqlalchemy.orm import Session
    from sqlalchemy.orm.exc import StaleDataError
    import pytest

    # No production connection: exercise the real File mapper against an
    # isolated table. DDL is explicit because its metadata uses PostgreSQL JSONB.
    engine = create_engine("sqlite://")
    with engine.begin() as connection:
        connection.exec_driver_sql("""CREATE TABLE files (
            id INTEGER PRIMARY KEY, topic_id INTEGER NOT NULL,
            name TEXT NOT NULL, document_json TEXT NOT NULL,
            content_revision INTEGER NOT NULL, order_index INTEGER NOT NULL,
            meta JSON NOT NULL, archived_at DATETIME, created_at DATETIME
        )""")
    with Session(engine) as seed:
        seed.add(File(id=1, topic_id=1, name="Notes", document_json="base"))
        seed.commit()
    with Session(engine) as first, Session(engine) as second:
        left = first.get(File, 1)
        right = second.get(File, 1)
        assert left.content_revision == right.content_revision == 1
        left.document_json = "computer"
        first.commit()
        right.document_json = "phone"
        with pytest.raises(StaleDataError):
            second.commit()
        second.rollback()
        assert second.get(File, 1).document_json == "computer"
    engine.dispose()
