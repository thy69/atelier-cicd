import pytest

from app.main import app


@pytest.fixture
def client():
    app.config["TESTING"] = True
    return app.test_client()


def test_health(client):
    response = client.get("/health")
    assert response.status_code == 200
    assert response.get_json() == {"status": "ok"}


def test_hello(client):
    response = client.get("/hello/Alice")
    assert response.get_json() == {"message": "Bonjour Alice !"}


def test_version_par_defaut(client, monkeypatch):
    monkeypatch.delenv("APP_VERSION", raising=False)
    monkeypatch.delenv("GIT_SHA", raising=False)
    response = client.get("/version")
    assert response.get_json() == {"version": "0.0.0-dev", "commit": "unknown"}


def test_version_injectee_par_le_pipeline(client, monkeypatch):
    monkeypatch.setenv("APP_VERSION", "1.2.3")
    monkeypatch.setenv("GIT_SHA", "abc1234")
    response = client.get("/version")
    assert response.get_json() == {"version": "1.2.3", "commit": "abc1234"}
