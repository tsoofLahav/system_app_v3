"""Guards for the bootstrap seed path, which only runs against an empty database."""

import ast
import inspect
import textwrap

from app import app
from models import File
from shared import bootstrap


def _file_kwargs_in_bootstrap() -> set[str]:
    """Kwargs bootstrap passes to File(...), read from the AST of the source."""
    tree = ast.parse(textwrap.dedent(inspect.getsource(bootstrap.bootstrap_if_empty)))
    for node in ast.walk(tree):
        if (
            isinstance(node, ast.Call)
            and isinstance(node.func, ast.Name)
            and node.func.id == "File"
        ):
            return {kw.arg for kw in node.keywords if kw.arg}
    raise AssertionError("bootstrap_if_empty no longer constructs a File")


def test_bootstrap_only_passes_real_file_columns():
    """Regression: File was seeded with the removed v1 `body` column."""
    kwargs = _file_kwargs_in_bootstrap()
    columns = {c.name for c in File.__table__.columns}
    assert kwargs, "expected File(...) to be called with keyword arguments"
    assert kwargs <= columns, f"not File columns: {sorted(kwargs - columns)}"


def test_bootstrap_file_kwargs_construct():
    with app.app_context():
        seeded = File(**{k: None for k in _file_kwargs_in_bootstrap()})
    assert seeded is not None
