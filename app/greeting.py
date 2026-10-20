"""Logique métier (très) simple, testée unitairement."""


def greet(name: str) -> str:
    """Retourne un message de bienvenue.

    Un nom vide ou composé d'espaces donne un message générique.
    """
    cleaned = name.strip()
    if not cleaned:
        return "Bonjour !"
    return f"Bonjour {cleaned} !"
