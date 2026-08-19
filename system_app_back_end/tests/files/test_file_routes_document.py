"""Guards that the app is actually sent the documents it renders.

The topic screen draws every file of a topic inline from one list response. When
that response omits ``document_json`` each editor opens empty, and the first
keystroke saves the emptiness over the stored document — so this is a data-loss
bug, not just a display one.

The app needs Postgres (JSONB columns), so these read the route source rather
than calling it.
"""

import ast
import inspect
import textwrap

from areas.files.routes import files as files_routes
from models import File


def _include_document_arg(func) -> ast.expr | None:
    """The `include_document=` value the route passes to `to_dict`, if any."""
    tree = ast.parse(textwrap.dedent(inspect.getsource(func)))
    for node in ast.walk(tree):
        if (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Attribute)
            and node.func.attr == "to_dict"
        ):
            for keyword in node.keywords:
                if keyword.arg == "include_document":
                    return keyword.value
            return None
    raise AssertionError(f"{func.__name__} no longer calls to_dict")


def _is_true(node: ast.expr | None) -> bool:
    return node is None or (isinstance(node, ast.Constant) and node.value is True)


def test_topic_file_list_includes_documents():
    """Regression: files opened empty because this list dropped document_json."""
    assert _is_true(_include_document_arg(files_routes.list_files_by_topic)), (
        "GET /topics/<id>/files must include document_json — the app renders "
        "each file's content straight from this response"
    )


def test_archived_file_list_omits_documents():
    source = inspect.getsource(files_routes.list_archived_files_by_topic)
    assert "list_archived_files_for_topic" in source
    assert "include_document=True" not in source


def test_agent_text_route_exists():
    source = inspect.getsource(files_routes)
    assert '"/files/<int:file_id>/agent-text"' in source


def test_single_file_includes_documents():
    assert _is_true(_include_document_arg(files_routes._file_response))


def test_to_dict_includes_the_document_by_default():
    """A caller that forgets the flag should get the document, not lose it."""
    default = inspect.signature(File.to_dict).parameters["include_document"].default
    assert default is True
