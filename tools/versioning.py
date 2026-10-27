"""Pure MIR source-to-edition distribution version codec."""

import re


_SOURCE = re.compile(r"^(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<patch>0|[1-9]\d*)$")
_DISTRIBUTION = re.compile(r"^(?P<major>0|[1-9]\d*)\.(?P<minor>0|[1-9]\d*)\.(?P<component>\d+)$")
MAX_COMPONENT = 65535
MAX_SOURCE_PATCH = 99

# Portal digits are stable public edition identities, not an ordering derived
# from the target record.  Earlier F001--F012 and selected F018 use the
# extended form because no one-digit portal slot is assigned to them.
PORTAL_DIGITS = {
    "f013": 1,
    "f014": 2,
    "f015": 3,
    "f016": 4,
    "f017": 5,
    "f100": 6,
    "f110": 7,
    "f200": 8,
    "f210": 9,
}
EXTENDED_TARGETS = frozenset({*(f"f{number:03d}" for number in range(1, 13)), "f018"})


def _components(version, pattern, label):
    if not isinstance(version, str):
        raise ValueError(label + " must be a string")
    match = pattern.fullmatch(version)
    if match is None:
        raise ValueError("Invalid " + label)
    values = tuple(int(match[group]) for group in match.groupdict())
    if any(value > MAX_COMPONENT for value in values[:-1]):
        raise ValueError(label + " component exceeds Factorio's numeric range")
    return values


def parse_source_version(version):
    """Validate and return a canonical source (major, minor, patch) tuple."""
    major, minor, patch = _components(version, _SOURCE, "source version")
    if patch > MAX_SOURCE_PATCH:
        raise ValueError("Source patch must be in 0..99 for edition distributions")
    return major, minor, patch


def edition_form(target):
    """Return the fixed form and integer identity assigned to one target."""
    if not isinstance(target, str):
        raise ValueError("Edition target must be a string")
    if target in PORTAL_DIGITS:
        return "portal", PORTAL_DIGITS[target]
    if target in EXTENDED_TARGETS:
        return "extended", int(target[1:])
    raise ValueError("Edition target has no declared distribution codec: " + target)


def _distribution_component(target, patch):
    form, identity = edition_form(target)
    component = 10 * patch + identity if form == "portal" else 100 * identity + patch
    if component > MAX_COMPONENT:
        raise ValueError("Distribution component exceeds Factorio's numeric range")
    return form, component


def distribution_version(source_version, target):
    """Encode an exact source version for one declared edition."""
    major, minor, patch = parse_source_version(source_version)
    form, component = _distribution_component(target, patch)
    width = 2 if form == "portal" else 5
    return f"{major}.{minor}.{component:0{width}d}"


def source_version_from_distribution(distribution, target):
    """Decode only a canonical distribution for the explicitly named edition."""
    major, minor, component = _components(distribution, _DISTRIBUTION, "distribution version")
    if component > MAX_COMPONENT:
        raise ValueError("Distribution component exceeds Factorio's numeric range")
    form, identity = edition_form(target)
    if form == "portal":
        patch, digit = divmod(component, 10)
        if digit != identity:
            raise ValueError("Distribution version selects a different MIR edition")
    else:
        edition, patch = divmod(component, 100)
        if edition != identity:
            raise ValueError("Distribution version selects a different MIR edition")
    if patch > MAX_SOURCE_PATCH:
        raise ValueError("Distribution version has an invalid source patch")
    source = f"{major}.{minor}.{patch}"
    if distribution_version(source, target) != distribution:
        raise ValueError("Distribution version is not canonical for its edition")
    return source


def validate_targets(targets):
    """Reject unknown, repeated, or colliding edition mappings before output."""
    if not isinstance(targets, (list, tuple, set, frozenset)):
        raise ValueError("Edition target set must be a finite collection")
    rows = tuple(targets)
    if len(rows) != len(set(rows)):
        raise ValueError("Edition target set repeats a target")
    encoded = set()
    for target in rows:
        form, identity = edition_form(target)
        marker = (form, identity)
        if marker in encoded:
            raise ValueError("Edition target set has a colliding codec identity")
        encoded.add(marker)
    return rows


def distribution_versions(source_version, targets):
    """Encode a finite declared set and reject a collision before writing output."""
    rows = validate_targets(targets)
    versions = {target: distribution_version(source_version, target) for target in rows}
    if len(set(versions.values())) != len(versions):
        raise ValueError("Edition target set has colliding distribution versions")
    return versions
