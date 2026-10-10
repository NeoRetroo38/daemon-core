#!/usr/bin/env python3
"""Comprueba el contrato del Cubo (por Cube Link en 127.0.0.1:8765) con sesiones desechables.

El token se lee de CHOISYS_LOCAL_API_TOKEN o de ~/.choisys.env.local; nunca se imprime.
Sale con 0 si todo cumple el contrato, 1 si algo falla.
"""
import json, os, sys, time, urllib.error, urllib.request, uuid

BASE = os.environ.get("CUBE_URL", "http://127.0.0.1:8765")


def token():
    value = os.environ.get("CHOISYS_LOCAL_API_TOKEN")
    if not value:
        path = os.path.expanduser(os.environ.get("CHOISYS_ENV_FILE", "~/.choisys.env.local"))
        for line in open(path):
            if line.startswith("CHOISYS_LOCAL_API_TOKEN="):
                value = line.split("=", 1)[1]
    if not value:
        sys.exit("Sin token del Cubo (CHOISYS_LOCAL_API_TOKEN o ~/.choisys.env.local).")
    return value.strip()


TOKEN = token()


def call(path, body=None, auth=True):
    request = urllib.request.Request(BASE + path, data=None if body is None else json.dumps(body).encode(),
                                     method="GET" if body is None else "POST")
    if body is not None:
        request.add_header("Content-Type", "application/json")
    if auth:
        request.add_header("Authorization", "Bearer " + TOKEN)
    started = time.time()
    try:
        response = urllib.request.urlopen(request, timeout=5)
        code, data = response.status, response.read()
    except urllib.error.HTTPError as error:
        code, data = error.code, error.read()
    return code, json.loads(data), round((time.time() - started) * 1000)


def decisions(selected):
    return [{"position": i, "selected": i == selected, "value": 1 if i == selected else 0} for i in range(1, 10)]


def evaluate(session, phase, selected, scenario="choice-grid"):
    return call("/evaluate", {"scenarioId": scenario, "sessionId": session, "phase": phase, "decisions": decisions(selected)})


failures = []


def check(name, condition, detail=""):
    print(("OK   " if condition else "FALLA"), name, detail)
    if not condition:
        failures.append(name)


check("sin token → 401", call("/health", auth=False)[0] == 401)
code, body, _ = call("/health")
check("health", code == 200 and body.get("ok") is True and body.get("service") == "neo-cube")

session, latencies = str(uuid.uuid4()), []
code, first, ms = evaluate(session, 1, 3); latencies.append(ms)
check("fase 1", code == 200 and first["result"]["status"] == "phase-complete" and first["result"]["nextPhase"] == 2)
check("reintento idéntico no avanza", evaluate(session, 1, 3)[1] == first)
code, body, ms = evaluate(session, 2, 5); latencies.append(ms)
check("fase 2", code == 200 and body["result"]["nextPhase"] == 3)
code, body, ms = evaluate(session, 3, 7); latencies.append(ms)
result = body.get("result", {})
check("fase 3 completa", code == 200 and result.get("status") == "completed" and result.get("nextPhase") is None)
check("DTO público: solo measurements", sorted(result) == ["measurements", "nextPhase", "phase", "sessionId", "status"]
      and all(sorted(m) == ["column", "phase", "row"] for m in result.get("measurements", [])))
check("alterar selección → 409", evaluate(session, 1, 4)[0] == 409)
check("saltar fase → 404", evaluate(str(uuid.uuid4()), 2, 1)[0] == 404)
check("petición inválida → 400", call("/evaluate", {"scenarioId": "x", "sessionId": session, "phase": 1, "decisions": []})[0] == 400)

print("latencia por fase (ms):", latencies)
sys.exit(1 if failures else 0)
