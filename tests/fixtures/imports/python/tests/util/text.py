"""Test-only text helpers.

Same basename as ``app/util/text.py`` on purpose: with two ``text.py`` in
the tree, a basename or path-suffix resolver has to pick one, and whichever
it picks it is wrong half the time.
"""


def fake_slug(value: str) -> str:
    return value.lower().replace(" ", "-")
