"""Gunicorn settings for the Render web service.

Two workers so an agent run can occupy one while the app still serves pages.
post_fork drops Postgres sockets inherited from the parent — sharing one SSL
session across workers is the `bad record mac` / `unexpected eof` crash.
"""

timeout = 180
workers = 2


def post_fork(server, worker):
    from app import after_worker_fork

    after_worker_fork()
