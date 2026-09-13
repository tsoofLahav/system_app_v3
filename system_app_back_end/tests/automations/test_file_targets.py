from datetime import datetime
from unittest.mock import patch
from tests.automations.test_review_lifecycle import database
from models import db, Topic, File, TopicType
from areas.automations.services.actions.files import archive_files, fill_file, bring_file, files_in_scope
from areas.automations.services.run_automation import run_steps
from areas.automations.services.scope import resolve_scope


def setup_topics():
    db.session.add(Topic(id=2, workspace_id=1, name='Second', topic_type_id=1))
    db.session.add(Topic(id=3, workspace_id=1, name='Template', is_template=True, topic_type_id=1))
    db.session.add(Topic(id=4, workspace_id=1, name='Missing', topic_type_id=1))
    db.session.add(TopicType(id=1, workspace_id=1, name='Process', template_topic_id=3))
    db.session.get(Topic,1).topic_type_id = 1
    db.session.get(File,10).name = 'Journal'
    replacement = db.session.get(File,20)
    replacement.topic_id = 2
    replacement.name = 'Daily Journal'
    replacement.meta = {}  # Replacement has no inherited slot metadata.
    db.session.add(File(id=40, topic_id=3, name='Journal', meta={'template_slot':'old-slot'}))
    db.session.flush()
    return {'workspace_id':1, 'topic_ids':[1,2,4]}


def test_archive_matches_independently_and_reports_missing(database):
    scope = setup_topics()
    result = archive_files(workspace_id=1, resolved_scope=scope, params={'file_name':'Journal'}, now=datetime.utcnow())
    assert result['file_ids'] == [10,20]
    assert result['missing_topics'][0]['topic_id'] == 4
    assert db.session.get(File,40).archived_at is None
    assert db.session.get(File,101).archived_at is None


def test_legacy_slot_resolves_name_and_replacement_without_slot(database):
    scope = setup_topics()
    with patch('areas.files.services.file_snapshot.apply_snippet_to_file') as apply:
        result = fill_file(workspace_id=1, resolved_scope=scope,
                           params={'template_slot':'old-slot', 'document_json':'note'}, now=datetime.utcnow())
    assert [call.args[0].id for call in apply.call_args_list] == [10,20]
    assert result['missing_topics'][0]['topic'] == 'Missing'


def test_saved_name_survives_template_replacement(database):
    scope = setup_topics()
    db.session.get(File,40).meta = {}
    result = archive_files(workspace_id=1, resolved_scope=scope, params={'file_name':'Journal'}, now=datetime.utcnow())
    assert result['file_ids'] == [10,20]


def test_bring_matches_each_topic(database):
    scope = setup_topics()
    with patch('areas.files.services.home_visits.add_home_visit', return_value=True) as add:
        result = bring_file(workspace_id=1, resolved_scope=scope, params={'file_name':'Journal'}, now=datetime.utcnow())
    assert result['file_ids'] == [10,20]
    assert add.call_count == 2


def test_empty_type_never_expands_to_workspace(database):
    setup_topics()
    db.session.add(TopicType(id=2, workspace_id=1, name='Empty'))
    db.session.add(Topic(id=5, workspace_id=1, name='Only template', is_template=True, topic_type_id=2))
    resolved = resolve_scope({'kind':'topic_type','topic_type_id':2}, workspace_id=1)
    assert resolved['topic_ids'] == []
    assert files_in_scope(resolved) == []
    with patch('areas.automations.services.run_automation.ACTIONS', {'archive_files': lambda **kw: (_ for _ in ()).throw(AssertionError('must not run'))}):
        result = run_steps(workspace_id=1, scope={'kind':'topic_type','topic_type_id':2}, steps=[{'kind':'archive_files'}])
    assert result['steps'] == []
    assert db.session.get(File,10).archived_at is None
