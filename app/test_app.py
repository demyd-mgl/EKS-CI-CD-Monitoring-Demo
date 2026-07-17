from app import app


def client():
    app.config["TESTING"] = True
    return app.test_client()


def test_index_returns_200_and_payload():
    resp = client().get("/")
    assert resp.status_code == 200
    body = resp.get_json()
    assert body["message"] == "Hello from the sample app!"
    assert "version" in body


def test_health_returns_ok():
    resp = client().get("/health")
    assert resp.status_code == 200
    assert resp.get_json()["status"] == "ok"


def test_metrics_endpoint_exposes_prometheus_format():
    resp = client().get("/metrics")
    assert resp.status_code == 200
    assert b"app_requests_total" in resp.data


def test_metrics_increment_after_requests():
    c = client()
    c.get("/")
    c.get("/")
    resp = c.get("/metrics")
    text = resp.data.decode()
    assert 'app_requests_total{endpoint="/",http_status="200"}' in text
