"""Appending a saved snippet onto an existing file body."""

from areas.files.services.document_marker_text import wrap_editor_text
from areas.files.services.file_snapshot import append_editor_text


def test_append_joins_two_bodies():
    dest = wrap_editor_text("Hello")
    snippet = wrap_editor_text("World")
    out = append_editor_text(dest, snippet)
    assert "Hello" in out
    assert "World" in out
    assert out.index("Hello") < out.index("World")


def test_append_onto_empty_uses_the_snippet():
    snippet = wrap_editor_text("Only")
    out = append_editor_text("", snippet)
    assert "Only" in out


def test_append_of_empty_snippet_keeps_the_dest():
    dest = wrap_editor_text("Keep")
    out = append_editor_text(dest, wrap_editor_text(""))
    assert "Keep" in out
