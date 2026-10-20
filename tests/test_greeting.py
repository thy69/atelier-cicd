from app.greeting import greet


def test_greet_avec_un_nom():
    assert greet("Alice") == "Bonjour Alice !"


def test_greet_supprime_les_espaces():
    assert greet("  Bob  ") == "Bonjour Bob !"


def test_greet_sans_nom():
    assert greet("   ") == "Bonjour !"
