"""Automations: a scope, a trigger, and an ordered series of steps.

Saved AI actions are a different thing and live at `/ai-actions`. They only
ever shared this table because both stored a prompt.
"""

from flask import Blueprint, jsonify, request

from models import Automation, db
from shared.bootstrap import default_workspace_id
from shared.helpers import apply_updates, get_or_404
from areas.objects.services.delete_cascade import delete_automation_cascade
from areas.automations.services.automation_schedule import (
    DEFAULT_AUTOMATION_TIMEZONE,
)
from areas.automations.services.run_automation import run_automation
from areas.automations.services.steps import StepError, validate_steps
from areas.automations.services.section_windows import (
    KIND_SECTION_WINDOW,
    KIND_STANDARD,
    apply_leftover_clear,
    clear_section_window_state,
    close_expired_section_windows,
    complete_review_if_clear,
    enrich_automation,
    ensure_complimentary_tasks,
    ensure_section_windows,
    input_topics,
    needs_complimentary_placement,
    pending_clears,
    review_status,
    store_user_input,
    sync_linked_schedules,
)

automations_bp = Blueprint("automations", __name__)


def _workspace_id_from_request(data=None):
    data = data or {}
    return (
        data.get("workspace_id")
        or request.args.get("workspace_id", type=int)
        or default_workspace_id()
    )


def _kind_of(data, existing=None):
    raw = data.get("kind") if "kind" in data else (existing.kind if existing else None)
    return raw or KIND_STANDARD


def _apply_window_fields(row: Automation, data: dict) -> None:
    apply_updates(
        row,
        data,
        {
            "kind",
            "view_id",
            "section_key",
            "window_duration_minutes",
            "window_opened_at",
            "window_closes_at",
            "pending_clear",
            "pending_user_input",
        },
        datetime_fields={"window_opened_at", "window_closes_at"},
    )


@automations_bp.route("/automations", methods=["GET"])
def list_automations():
    workspace_id = _workspace_id_from_request()
    if workspace_id:
        ensure_section_windows(workspace_id)
        close_expired_section_windows(workspace_id)
        db.session.commit()
    query = Automation.query
    if workspace_id:
        query = query.filter_by(workspace_id=workspace_id)
    rows = query.order_by(Automation.id).all()
    return jsonify([enrich_automation(r) for r in rows])


@automations_bp.route("/automations/pending-clears", methods=["GET"])
def list_pending_clears():
    workspace_id = _workspace_id_from_request()
    if not workspace_id:
        return jsonify([])
    close_expired_section_windows(workspace_id)
    db.session.commit()
    return jsonify(pending_clears(workspace_id))


@automations_bp.route("/automations", methods=["POST"])
def create_automation():
    data = request.get_json(silent=True) or {}
    kind = _kind_of(data)
    name = str(data.get("name") or "").strip()
    name_he = str(data.get("name_he") or "").strip()
    if not name or not name_he:
        return jsonify({"error": "name and name_he are required"}), 400
    workspace_id = data.get("workspace_id") or default_workspace_id()
    if not workspace_id:
        return jsonify({"error": "workspace_id is required"}), 400
    try:
        steps = validate_steps(data.get("steps") or [])
    except StepError as error:
        return jsonify({"error": str(error)}), 400

    row = Automation(
        workspace_id=workspace_id,
        name=name,
        name_he=name_he,
        trigger=data.get("trigger") or {},
        scope=data.get("scope") or {},
        steps=steps,
        schedule=data.get("schedule"),
        timezone=data.get("timezone") or DEFAULT_AUTOMATION_TIMEZONE,
        enabled=bool(data.get("enabled", True)),
        kind=kind,
        view_id=data.get("view_id"),
        section_key=data.get("section_key"),
        window_duration_minutes=data.get("window_duration_minutes"),
    )
    db.session.add(row)
    db.session.flush()
    try:
        if kind == KIND_STANDARD and needs_complimentary_placement(row):
            ensure_complimentary_tasks(row)
        if kind == KIND_SECTION_WINDOW:
            sync_linked_schedules(row)
    except ValueError as error:
        db.session.rollback()
        return jsonify({"error": str(error)}), 400
    db.session.commit()
    return jsonify(enrich_automation(row)), 201


@automations_bp.route("/automations/<int:automation_id>", methods=["PATCH"])
def update_automation(automation_id):
    row = get_or_404(Automation, automation_id)
    data = request.get_json(silent=True) or {}
    if "steps" in data:
        try:
            data = {**data, "steps": validate_steps(data.get("steps") or [])}
        except StepError as error:
            return jsonify({"error": str(error)}), 400
    if "schedule" in data or "timezone" in data:
        data = {**data, "next_run_at": None}

    clock_changed = False
    if (row.kind or KIND_STANDARD) == KIND_SECTION_WINDOW:
        if "schedule" in data and data.get("schedule") != row.schedule:
            clock_changed = True
        if "timezone" in data and data.get("timezone") != row.timezone:
            clock_changed = True
        if "window_duration_minutes" in data:
            incoming = data.get("window_duration_minutes")
            if incoming != row.window_duration_minutes:
                clock_changed = True

    apply_updates(
        row,
        data,
        {
            "name",
            "name_he",
            "trigger",
            "scope",
            "steps",
            "schedule",
            "timezone",
            "enabled",
            "last_run_at",
            "next_run_at",
        },
        datetime_fields={"last_run_at", "next_run_at"},
    )
    _apply_window_fields(row, data)
    if "name" in data or "name_he" in data:
        name = (row.name or "").strip()
        name_he = (row.name_he or "").strip()
        if not name or not name_he:
            return jsonify({"error": "name and name_he are required"}), 400
        row.name = name
        row.name_he = name_he
    if (row.kind or KIND_STANDARD) == KIND_SECTION_WINDOW and row.enabled:
        if not (row.schedule or "").strip() or not row.window_duration_minutes:
            return jsonify(
                {"error": "a section window needs a start time and a duration"}
            ), 400
    try:
        if (row.kind or KIND_STANDARD) == KIND_STANDARD:
            ensure_complimentary_tasks(row)
        if (row.kind or KIND_STANDARD) == KIND_SECTION_WINDOW:
            if clock_changed:
                clear_section_window_state(row)
            sync_linked_schedules(row)
    except ValueError as error:
        db.session.rollback()
        return jsonify({"error": str(error)}), 400
    db.session.commit()
    return jsonify(enrich_automation(row))


@automations_bp.route("/automations/<int:automation_id>", methods=["DELETE"])
def delete_automation(automation_id):
    get_or_404(Automation, automation_id)
    delete_automation_cascade(automation_id)
    db.session.commit()
    return "", 204


@automations_bp.route("/automations/<int:automation_id>/run", methods=["POST"])
def run_automation_now(automation_id):
    """Run it this second, on its own stored scope — the same thing the clock
    would do, so testing an automation shows what it will really do."""
    automation = get_or_404(Automation, automation_id)
    data = request.get_json(silent=True) or {}
    user_input = data.get("user_input") or automation.pending_user_input
    run = run_automation(
        automation, trigger_source="manual", user_input=user_input
    )
    db.session.commit()
    return jsonify({"run": run.to_dict()})


@automations_bp.route("/automations/<int:automation_id>/submit-input", methods=["POST"])
def submit_automation_input(automation_id):
    automation = get_or_404(Automation, automation_id)
    data = request.get_json(silent=True) or {}
    try:
        stored = store_user_input(automation, data)
    except ValueError as error:
        return jsonify({"error": str(error)}), 400
    run = run_automation(automation, trigger_source="user_input", user_input=stored)
    db.session.commit()
    return jsonify({"run": run.to_dict(), "user_input": stored})


@automations_bp.route("/automations/<int:automation_id>/clear-leftovers", methods=["POST"])
def clear_automation_leftovers(automation_id):
    automation = get_or_404(Automation, automation_id)
    if not automation.pending_clear:
        return jsonify({"error": "nothing to clear"}), 400
    data = request.get_json(silent=True) or {}
    disposition = str(data.get("disposition") or "report").strip()
    if disposition not in ("report", "dismiss"):
        return jsonify({"error": "disposition must be report or dismiss"}), 400
    result = apply_leftover_clear(automation, disposition=disposition)
    db.session.commit()
    return jsonify({"ok": True, **result})


@automations_bp.route("/automations/<int:automation_id>/review-status", methods=["GET"])
def automation_review_status(automation_id):
    automation = get_or_404(Automation, automation_id)
    return jsonify(review_status(automation))


@automations_bp.route("/automations/<int:automation_id>/complete-review", methods=["POST"])
def automation_complete_review(automation_id):
    automation = get_or_404(Automation, automation_id)
    done = complete_review_if_clear(automation)
    db.session.commit()
    return jsonify({"completed": done, **review_status(automation)})


@automations_bp.route("/automations/<int:automation_id>/input-topics", methods=["GET"])
def automation_input_topics(automation_id):
    automation = get_or_404(Automation, automation_id)
    return jsonify(input_topics(automation))
