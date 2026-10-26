"""Run the Lua tests with lupa when no lua54/texlua CLI is installed.

Usage (from this folder):  python run_lua.py tests/upgrade.lua src/upgrade.lua
argv[2:] reach the script as arg[1..], exactly like a Lua interpreter.
"""
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)),
                                '..', '..', 'analysis', 'luaenv'))
import lupa


def main():
    if len(sys.argv) < 2:
        sys.exit(__doc__)
    lua = lupa.LuaRuntime(unpack_returned_tuples=True)
    g = lua.globals()
    g.arg = lua.eval('{}')
    g.arg[0] = sys.argv[1]
    for i, a in enumerate(sys.argv[2:], 1):
        g.arg[i] = a
    try:
        lua.execute('assert(loadfile(arg[0]))()')
    except lupa.LuaError as e:
        print("LUA ERROR:", e)
        sys.exit(1)


if __name__ == '__main__':
    main()
