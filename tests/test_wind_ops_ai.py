"""Tests for wind_ops_ai."""

from wind_ops_ai import __version__, hello


def test_version() -> None:
    assert __version__ == "0.1.0"


def test_hello_default() -> None:
    assert hello() == "Hello, world!"


def test_hello_name() -> None:
    assert hello("Niraj") == "Hello, Niraj!"
