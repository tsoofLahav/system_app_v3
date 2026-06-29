from app import create_app
from services.automation_runner import enqueue_due_scheduled_rules, process_automation_queue


def main():
    app = create_app()
    with app.app_context():
        enqueued = enqueue_due_scheduled_rules()
        processed = process_automation_queue()
        print({"enqueued": enqueued, "processed": processed})


if __name__ == "__main__":
    main()
