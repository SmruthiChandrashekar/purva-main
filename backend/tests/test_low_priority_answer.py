"""
test_low_priority_answer.py: the low-priority "File it anyway" flow.

- A low-priority concern is not filed straight away: the response carries the policy
  answer so the form can show it. "File it anyway" (file_anyway=True) files the same
  text at L1 without retyping or logging in.

Supabase and the AI are replaced with fakes, so these run offline.
"""
import os
import sys
from types import SimpleNamespace
from unittest.mock import MagicMock

import pytest

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..")))
os.environ.setdefault("SUPABASE_URL", "https://example.supabase.co")
os.environ.setdefault("SUPABASE_KEY", "test-anon-key")
os.environ.setdefault("SUPABASE_SERVICE_ROLE_KEY", "test-service-key")

from fastapi.testclient import TestClient  # noqa: E402
import backend.main as main  # noqa: E402
from backend.middleware.auth import require_verified_phone  # noqa: E402


class _Query:
    def __init__(self, db, table):
        self.db, self.table, self.ops = db, table, []

    def __getattr__(self, name):
        def op(*a, **k):
            self.ops.append((name, a, k))
            return self
        return op

    def execute(self):
        self.db.calls.append((self.table, self.ops))
        if self.table == "grievances" and any(o[0] == "insert" for o in self.ops):
            return SimpleNamespace(data=[{"grievance_id": "g-guest-1"}])
        return SimpleNamespace(data=[])


class _FakeSupabase:
    def __init__(self):
        self.calls = []
        self.auth = SimpleNamespace(admin=MagicMock())
        self.storage = MagicMock()

    def table(self, name):
        return _Query(self, name)

    def inserted(self):
        return [o[1][0] for t, ops in self.calls if t == "grievances" for o in ops if o[0] == "insert"]


async def _noop(*a, **k):
    return None


@pytest.fixture
def app(monkeypatch):
    fake = _FakeSupabase()
    monkeypatch.setattr(main, "supabase", fake)
    monkeypatch.setattr(main, "translate_to_english", lambda t: t)
    monkeypatch.setattr(main, "classify_department_node", lambda s: {"department": "HR"})
    monkeypatch.setattr(main, "escalation_agent", SimpleNamespace(process_async=_noop), raising=False)
    monkeypatch.setattr(main, "get_rag_response", lambda q: {
        "answer": "Per the Visitor Policy, visitor parking is available at Gate 2.",
        "sources": [{"source": "Visitor Policy"}],
    })
    notifier = MagicMock()
    notifier.email_configured = True
    monkeypatch.setattr(main, "notifier", notifier, raising=False)
    main.app.dependency_overrides[require_verified_phone] = lambda: {"user_id": "u1", "role": "user"}
    yield TestClient(main.app), fake, monkeypatch
    main.app.dependency_overrides.clear()


def _severity(monkeypatch, sev):
    monkeypatch.setattr(main, "classify_severity_node",
                        lambda s: {"severity": sev, "classification_failed": False})




# ── Low-priority concerns: answer first, then "File it anyway" ──────────────

def test_low_priority_returns_policy_answer_and_files_nothing(app):
    c, fake, mp = app
    _severity(mp, "LOW")
    r = c.post("/submit-complaint", json={"description": "Where can visitors park their cars?"})
    body = r.json()
    assert r.status_code == 200 and body["redirect"] == "assistant"
    assert "Gate 2" in body["answer"] and body["sources"] == ["Visitor Policy"]
    assert not fake.inserted()


def test_file_it_anyway_files_low_concern_at_l1(app):
    c, fake, mp = app
    _severity(mp, "LOW")
    r = c.post("/submit-complaint", json={"description": "Where can visitors park their cars?",
                                          "file_anyway": True})
    assert r.status_code == 200, r.text
    rows = fake.inserted()
    assert len(rows) == 1
    assert rows[0]["severity"] == "Low" and rows[0]["assigned_tier"] == "L1"
    assert rows[0]["status"] == "HUMAN_HANDLING"
