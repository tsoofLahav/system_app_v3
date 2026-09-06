"""Built-in topics the user cannot create, edit, or open as a live canvas.

Reports lives only under Archive. Section-window leftover reports and
one-time section archives write there.
"""

from __future__ import annotations

from models import File, Topic, db

SYSTEM_REPORTS_TOPIC_NAME = "Reports"
SYSTEM_REPORTS_ICON = "📋"
SYSTEM_REPORTS_COLOR = "#6B7280"
MISSED_REPORT_KIND = "missed_section_report"
ONE_TIME_ARCHIVE_KIND = "one_time_section_archive"
REPORT_FILE_KINDS = frozenset({MISSED_REPORT_KIND, ONE_TIME_ARCHIVE_KIND})


def is_system_topic(topic: Topic | None) -> bool:
    return topic is not None and bool(getattr(topic, "is_system", False))


def ensure_system_reports_topic(workspace_id: int) -> Topic:
    row = (
        Topic.query.filter_by(workspace_id=workspace_id, is_system=True)
        .filter(Topic.name == SYSTEM_REPORTS_TOPIC_NAME)
        .first()
    )
    if row is not None:
        _adopt_stray_report_files(workspace_id, row)
        return row
    row = Topic(
        workspace_id=workspace_id,
        name=SYSTEM_REPORTS_TOPIC_NAME,
        icon=SYSTEM_REPORTS_ICON,
        color=SYSTEM_REPORTS_COLOR,
        order_index=10_000,
        file_layout="auto",
        is_system=True,
        is_template=False,
    )
    db.session.add(row)
    db.session.flush()
    _adopt_stray_report_files(workspace_id, row)
    return row


def _adopt_stray_report_files(workspace_id: int, reports: Topic) -> None:
    """Move leftover live Reports files off Home into Archive."""
    from areas.files.services import file_ops

    stray = (
        File.query.join(Topic, File.topic_id == Topic.id)
        .filter(
            Topic.workspace_id == workspace_id,
            File.topic_id != reports.id,
        )
        .all()
    )
    for file in stray:
        meta = file.meta or {}
        if meta.get("system_kind") not in REPORT_FILE_KINDS:
            continue
        file.topic_id = reports.id
        if file.archived_at is None:
            file_ops.archive_file(file)


def files_in_system_topic(topic: Topic) -> list[File]:
    return File.query.filter_by(topic_id=topic.id).all()
