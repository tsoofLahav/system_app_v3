from app import create_app
from services.automation_runner import run_due_automations


def main():
    app = create_app()
    with app.app_context():
        results = run_due_automations()
        print({"automation_runs": results})


if __name__ == "__main__":
    main()
