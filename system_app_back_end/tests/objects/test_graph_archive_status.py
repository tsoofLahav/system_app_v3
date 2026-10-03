from datetime import datetime
import pytest
from tests.objects.test_clone_embed import client
from models import db, File, Topic, InformationPiece
from areas.objects.services.create_embed import create_embed_in_file
from areas.objects.services.object_graph import build_workspace_graph


@pytest.mark.parametrize('archived_model', [File, Topic, InformationPiece])
def test_graph_reports_archive_status_for_picker(client, archived_model):
    source = create_embed_in_file(db.session.get(File, 1), type_='info', title='Source')
    create_embed_in_file(db.session.get(File, 2), type_='info', title='Live')
    row_id = source.information_id if archived_model is InformationPiece else 1
    db.session.get(archived_model, row_id).archived_at = datetime(2026, 10, 1)
    db.session.flush()
    nodes = {node['title']: node for node in build_workspace_graph(1)['nodes']}
    assert nodes['Source']['is_archived'] is True
    assert nodes['Live']['is_archived'] is False
