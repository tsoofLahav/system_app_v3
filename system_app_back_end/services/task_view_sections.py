from models import TaskView


def first_section_name_for_view(view_type: str) -> str | None:
    row = (
        TaskView.query.filter_by(view_type=view_type)
        .filter(TaskView.task_id.is_(None))
        .filter(TaskView.section_name.isnot(None))
        .filter(TaskView.section_name != "")
        .order_by(TaskView.order_index, TaskView.id)
        .first()
    )
    return row.section_name if row else None


def resolve_task_section_name(view_type: str, section_name: str | None) -> str | None:
    if section_name:
        return section_name
    return first_section_name_for_view(view_type)
