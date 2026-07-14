CHANGE_SET_VERSION = 1


def build_change_set(documents):
    return {"version": CHANGE_SET_VERSION, "documents": documents}


def build_document_change_set(key, title, units, ops):
    unit_by_id = {unit["id"]: unit for unit in units}
    valid_unit_ids = set(unit_by_id)
    changes = []
    change_index = 0

    for op in ops or []:
        op_type = (op.get("op") or "").strip().lower()
        unit_id = op.get("unit_id")
        text = (op.get("text") or "").strip()
        reason = (op.get("reason") or "").strip()

        if op_type == "replace":
            if unit_id not in valid_unit_ids or not text:
                continue
            old_text = (unit_by_id[unit_id].get("text") or "").strip()
            if old_text == text:
                continue
            change_index += 1
            change_id = f"{key}:c{change_index}"
            changes.append(
                {
                    "id": change_id,
                    "action": "replace",
                    "unit_id": unit_id,
                    "old_text": old_text,
                    "new_text": text,
                    "reason": reason,
                }
            )
        elif op_type == "remove":
            if unit_id not in valid_unit_ids:
                continue
            old_text = (unit_by_id[unit_id].get("text") or "").strip()
            change_index += 1
            change_id = f"{key}:c{change_index}"
            changes.append(
                {
                    "id": change_id,
                    "action": "remove",
                    "unit_id": unit_id,
                    "old_text": old_text,
                    "new_text": "",
                    "reason": reason,
                }
            )
        elif op_type == "add_after":
            if unit_id not in valid_unit_ids or not text:
                continue
            anchor = unit_by_id[unit_id]
            kind = op.get("kind") or anchor.get("kind") or "list_item"
            change_index += 1
            change_id = f"{key}:c{change_index}"
            changes.append(
                {
                    "id": change_id,
                    "action": "add_after",
                    "unit_id": unit_id,
                    "old_text": "",
                    "new_text": text,
                    "reason": reason,
                    "new_unit": {
                        "id": f"new:{change_id}",
                        "kind": kind,
                        "text": text,
                    },
                }
            )

    return {"key": key, "title": title, "units": units, "changes": changes}


def merge_document(units, changes, decisions):
    replace = {}
    remove = set()

    for change in changes or []:
        if not _decision(decisions, change.get("id")):
            continue
        action = change.get("action")
        unit_id = change.get("unit_id")
        if action == "replace":
            replace[unit_id] = change.get("new_text", "")
        elif action == "remove":
            remove.add(unit_id)

    merged = []
    for unit in units:
        unit_id = unit["id"]
        if unit_id in remove:
            continue
        next_unit = dict(unit)
        if unit_id in replace:
            next_unit["text"] = replace[unit_id]
        merged.append(next_unit)

    inserted_ids = set()
    for change in changes or []:
        if change.get("action") != "add_after":
            continue
        if not _decision(decisions, change.get("id")):
            continue
        new_unit = change.get("new_unit") or {
            "id": change.get("id"),
            "kind": "list_item",
            "text": change.get("new_text", ""),
        }
        new_unit = dict(new_unit)
        anchor_id = change.get("unit_id")
        idx = _index_of_unit_id(merged, anchor_id)
        if idx is None:
            merged.append(new_unit)
        else:
            insert_at = idx + 1
            while insert_at < len(merged) and merged[insert_at].get("id") in inserted_ids:
                insert_at += 1
            merged.insert(insert_at, new_unit)
        inserted_id = new_unit.get("id")
        if inserted_id:
            inserted_ids.add(inserted_id)
    return merged


def _index_of_unit_id(units, unit_id):
    if not unit_id:
        return None
    for index, unit in enumerate(units):
        if unit.get("id") == unit_id:
            return index
    return None


def _decision(decisions, change_id):
    if not decisions or change_id is None:
        return False
    raw = None
    if str(change_id) in decisions:
        raw = decisions[str(change_id)]
    else:
        raw = decisions.get(change_id)
    if raw is None:
        return False
    if isinstance(raw, bool):
        return raw
    if isinstance(raw, str):
        return raw.strip().lower() in {"1", "true", "yes"}
    return bool(raw)
