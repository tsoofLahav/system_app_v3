from models import TaskView, db

IMPORTANT_SECTION_FLAG = "important"


def section_flag_for(view_type, section_name):
    if not section_name:
        return None
    placeholder = (
        TaskView.query.filter_by(view_type=view_type, section_name=section_name)
        .filter(TaskView.task_id.is_(None))
        .first()
    )
    return placeholder.section_flag if placeholder else None


def propagate_section_flag(view_type, section_name, flag_value):
    if not section_name:
        return
    (
        TaskView.query.filter_by(view_type=view_type, section_name=section_name)
        .filter(TaskView.task_id.isnot(None))
        .update({TaskView.section_flag: flag_value}, synchronize_session=False)
    )


def apply_section_flag_to_membership(view):
    if view.task_id is None:
        return
    view.section_flag = section_flag_for(view.view_type, view.section_name)
