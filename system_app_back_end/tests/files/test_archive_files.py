"""Archive listing: pages of names, heading search, no document bodies."""

import inspect

from areas.files.routes import files as files_routes
from areas.files.services.archive_files import (
    archived_file_matches_query,
    heading_texts_from_body,
)
from areas.files.services import file_ops


def test_headings_come_from_hash_lines_not_pointers():
    body = (
        "%%system_app_document v4\n"
        "# Weekly\n"
        "\n"
        "Hello\n"
        "\n"
        "## Notes\n"
        "\n"
        '[INFO id="3"]\n'
    )
    assert heading_texts_from_body(body) == ["Weekly", "Notes"]


def test_heading_extractor_skips_empty_hashes():
    assert heading_texts_from_body("#   \nplain") == []


def test_archive_search_matches_name_or_heading_not_body():
    body = "%%system_app_document v4\n# Weekly review\n\nsecret body text\n"
    assert archived_file_matches_query(
        name="Q3 notes", document_json=body, q="q3"
    )
    assert archived_file_matches_query(
        name="Q3 notes", document_json=body, q="weekly"
    )
    assert not archived_file_matches_query(
        name="Q3 notes", document_json=body, q="secret"
    )


def test_archive_list_route_is_paged():
    source = inspect.getsource(files_routes.list_archived_files_by_topic)
    assert "limit" in source
    assert "offset" in source
    assert "q" in source


def test_unarchive_puts_the_file_first():
    source = inspect.getsource(file_ops.unarchive_file)
    assert "_place_file_first" in source
    assert "archived_at = None" in source
