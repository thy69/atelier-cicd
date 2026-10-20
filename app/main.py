"""Mini API de l'atelier CI/CD.

L'application est volontairement minuscule : le sujet de l'atelier est le
pipeline, pas le code.
"""

import os

from flask import Flask, jsonify

from app.greeting import greet

app = Flask(__name__)


@app.get("/")
def index():
    return jsonify(message=greet("usine logicielle"), env=os.getenv("APP_ENV", "local"))


@app.get("/hello/<name>")
def hello(name: str):
    return jsonify(message=greet(name))


@app.get("/health")
def health():
    return jsonify(status="ok")


@app.get("/version")
def version():
    return jsonify(
        version=os.getenv("APP_VERSION", "0.0.0-dev"),
        commit=os.getenv("GIT_SHA", "unknown"),
    )
