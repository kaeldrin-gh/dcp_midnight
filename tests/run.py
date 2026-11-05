"""Run without a WoW client: pip install lupa; python tests/run.py.

These API stubs exercise addon logic; they cannot reproduce WoW's security VM.
"""
from pathlib import Path
from lupa.lua51 import LuaRuntime

root = Path(__file__).resolve().parents[1]
lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(
    (root / 'tests/stubs.lua').read_text(encoding='utf-8')
    + '\n' + (root / 'Doom_CooldownPulse_Midnight.lua').read_text(encoding='utf-8')
    + '\n' + (root / 'tests/cooldowns.lua').read_text(encoding='utf-8')
)
