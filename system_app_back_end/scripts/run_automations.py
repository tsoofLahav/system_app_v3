import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app import create_app
from services.automation_change_triggers import process_due_change_triggers
from services.automation_runner import enqueue_due_scheduled_rules, process_automation_queue


def main():
    app = create_app()
    with app.app_context():
        enqueued = enqueue_due_scheduled_rules()
        processed = process_automation_queue()
        change_triggers = process_due_change_triggers(app=app)
        print(
            {
                "enqueued": enqueued,
                "processed": processed,
                "change_triggers": change_triggers,
            }
        )


if __name__ == "__main__":
    main()
