"""Generated package-excluded MIR 4 API V1 preview types."""
from dataclasses import dataclass
from typing import Any, Generic, Optional, TypeVar
T = TypeVar("T")
CANONICALIZATION = "mir-canonical-json/1"
@dataclass(frozen=True)
class Availability:
    status: str
    reason: str
    evidence: tuple[str, ...]
@dataclass(frozen=True)
class Page(Generic[T]):
    items: tuple[T, ...]
    offset: int
    limit: int
    total: Optional[int]
    next_cursor: Optional[str]
def require_explicit_availability(value: dict[str, Any]) -> None:
    status = value.get("availability", {}).get("status")
    if status not in ("available", "unavailable"):
        raise ValueError("mir4-api-v1-availability")
    if status == "unavailable" and value.get("page", {}).get("total") is not None:
        raise ValueError("mir4-api-v1-unavailable-is-not-zero")