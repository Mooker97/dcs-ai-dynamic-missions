"""
MIZ File Modification Library

A MizParser-based library for modifying DCS World .miz mission files.

Architecture:
- Extract .miz → Modify string → Repackage .miz
- Pure Python, no DCS installation required
- Heavy emphasis on utility function reuse (DRY principle)

Usage:
    from miz_file_modification.parsing.miz_parser import MizParser
    from miz_file_modification.groups.remove import remove_groups_by_type

    parser = MizParser("mission.miz")
    parser.extract()
    content = parser.get_mission_content()
    modified = remove_groups_by_type(content, ["ship"])
    parser.write_mission_content(modified)
    parser.repackage("modified.miz")
"""

__version__ = "0.1.0"

# Export commonly used items
from . import core
from . import utils
from . import loadouts
from . import groups

__all__ = ['core', 'utils', 'loadouts', 'groups']
