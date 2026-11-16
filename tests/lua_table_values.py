"""Narrow test-owned conversion for JSON-like values crossing a pinned Lua runtime."""


def to_lua(lua, value):
    """Preserve existing dict/list conversion, including Lua nil holes; reject cycles."""
    return _to_lua(lua, value, set())


def _to_lua(lua, value, active):
    if not isinstance(value, (dict, list)):
        return value
    identity = id(value)
    if identity in active:
        raise ValueError("cyclic Python container")
    active.add(identity)
    try:
        table = lua.table()
        items = value.items() if isinstance(value, dict) else enumerate(value, start=1)
        for key, nested in items:
            table[key] = _to_lua(lua, nested, active)
        return table
    finally:
        active.remove(identity)


def from_lua(lua, value):
    """Decode Lua tables: only nonempty 1..N keys become lists; sparse keys stay dict keys."""
    return _from_lua(value, lua.eval("type"), lua.eval("rawequal"), [])


def _from_lua(value, lua_type, raw_equal, active):
    if lua_type(value) != "table":
        return value
    if any(raw_equal(value, ancestor) for ancestor in active):
        raise ValueError("cyclic Lua table")
    active.append(value)
    try:
        items = list(value.items())
        keys = [key for key, _ in items]
        if _is_dense_array(keys):
            by_index = dict(items)
            return [_from_lua(by_index[index], lua_type, raw_equal, active) for index in range(1, len(items) + 1)]
        output = {}
        for key, nested in items:
            if key in output:
                raise ValueError("Lua mapping keys collide in Python")
            output[key] = _from_lua(nested, lua_type, raw_equal, active)
        return output
    finally:
        active.pop()


def _is_dense_array(keys):
    return bool(keys) and all(type(key) is int for key in keys) and set(keys) == set(range(1, len(keys) + 1))
