CHANGE_SET_VERSION = 1


def build_change_set(documents):
    return {"version": CHANGE_SET_VERSION, "documents": documents}


def build_document_change_set(key, title, units, ops, id_prefix=None):
    unit_by_id = {unit["id"]: unit for unit in units}
    valid_unit_ids = set(unit_by_id)
    changes = []
    change_index = 0
    change_prefix = (id_prefix or key).strip() or key

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
            change_id = f"{change_prefix}:c{change_index}"
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
            change_id = f"{change_prefix}:c{change_index}"
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
            change_id = f"{change_prefix}:c{change_index}"
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


def build_doc_row_change_set(key, title, units, doc_ops):
    changes = []
    change_index = 0
    anchor_id = units[-1]["id"] if units else f"{key}:table:anchor"
    display_units = list(units)
    if not display_units:
        display_units = [
            {
                "id": anchor_id,
                "kind": "table_row",
                "text": "",
            }
        ]

    for op in doc_ops or []:
        date = (op.get("date") or "").strip()
        text = (op.get("text") or "").strip()
        reason = (op.get("reason") or "").strip()
        if not date or not text:
            continue
        change_index += 1
        change_id = f"{key}:c{change_index}"
        changes.append(
            {
                "id": change_id,
                "action": "add_row",
                "unit_id": anchor_id,
                "old_text": "",
                "new_text": f"{date} | {text}",
                "reason": reason,
                "row_date": date,
                "row_text": text,
            }
        )

    return {"key": key, "title": title, "units": display_units, "changes": changes}


def merge_document(units, changes, decisions):
    replace = {}
    remove = set()
    add_after = {}

    for change in changes or []:
        if not _decision(decisions, change.get("id")):
            continue
        action = change.get("action")
        unit_id = change.get("unit_id")
        if action == "replace":
            replace[unit_id] = change.get("new_text", "")
        elif action == "remove":
            remove.add(unit_id)
        elif action == "add_after":
            new_unit = change.get("new_unit") or {
                "id": change.get("id"),
                "kind": "list_item",
                "text": change.get("new_text", ""),
            }
            add_after.setdefault(unit_id, []).append(new_unit)

    merged = []
    for unit in units:
        unit_id = unit["id"]
        if unit_id in remove:
            continue
        next_unit = dict(unit)
        if unit_id in replace:
            next_unit["text"] = replace[unit_id]
        merged.append(next_unit)
        merged.extend(add_after.get(unit_id, []))
    return merged


def _decision(decisions, change_id):
    if not decisions or change_id is None:
        return False
    if str(change_id) in decisions:
        return bool(decisions[str(change_id)])
    return bool(decisions.get(change_id))
