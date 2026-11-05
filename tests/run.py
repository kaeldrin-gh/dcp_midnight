"""Run the Lua 5.1 behavior tests (requires: python -m pip install lupa)."""
from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime()
lua.globals().arg = lua.table_from([str(root / 'Doom_CooldownPulse_Forever.lua')])
lua.execute((root / 'tests/test_cooldowns.lua').read_text(encoding='utf-8'))
