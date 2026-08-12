"""File body membership must delete orphan object rows."""

from areas.files.services.document_marker_text import (
    embed_ids_in_text,
    pointer_line,
    wrap_editor_text,
)
import areas.objects.services.delete_cascade as cascade


def test_embed_ids_in_text_finds_pointers():
    body = wrap_editor_text(
        "\n\n".join(
            [
                "Hello",
                pointer_line(3, "info"),
                pointer_line(9, "task_list"),
            ]
        )
    )
    assert embed_ids_in_text(body) == {3, 9}


def test_purge_unreferenced_embeds_for_file(monkeypatch):
    class FakeEmbed:
        def __init__(self, id):
            self.id = id
            self.file_id = 1
            self.type = "info"
            self.task_list_id = None
            self.information_id = None

    class FakeFile:
        id = 1
        document_json = wrap_editor_text(pointer_line(2, "info"))

    class _Query:
        def filter_by(self, **kwargs):
            return self

        def all(self):
            return [FakeEmbed(2), FakeEmbed(7), FakeEmbed(11)]

    class FakeObjectEmbed:
        query = _Query()

    deleted = []

    def fake_delete(embed, *, remove_from_document):
        assert remove_from_document is False
        deleted.append(embed.id)

    monkeypatch.setattr(cascade, "ObjectEmbed", FakeObjectEmbed)
    monkeypatch.setattr(cascade, "delete_object_embed_cascade", fake_delete)

    removed = cascade.purge_unreferenced_embeds_for_file(FakeFile())
    assert set(removed) == {7, 11}
    assert set(deleted) == {7, 11}
    assert 2 not in deleted
