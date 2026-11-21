"""
Shared test settings. pytest loads this before any test file, so these are in place
before the first test imports backend.main (which reads FRONTEND_URL once, at import,
to build its CORS list). Without this, the CORS tests pass or fail depending on which
test file happens to import backend.main first.
"""
import os

os.environ["FRONTEND_URL"] = "https://grm.example.test/, https://second.example.test"
