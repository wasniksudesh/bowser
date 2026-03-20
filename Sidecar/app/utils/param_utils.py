"""Parameter normalization utilities for agent/skill execution."""

from typing import Any


def normalize_param_value(value: Any) -> Any:
    """
    Strip extraneous quotes from string values.
    LLMs often output 'value' or "value" instead of value, causing skills to
    receive literal quotes (e.g. branch='test-commit' instead of branch=test-commit).
    """
    if not isinstance(value, str):
        return value
    s = value.strip()
    # Strip matching outer quotes (single or double), handling nested cases like "'value'"
    while len(s) >= 2 and s[0] == s[-1] and s[0] in ('"', "'"):
        s = s[1:-1].strip()
    return s
