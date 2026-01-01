"""
Triggers Module

Operations for managing mission triggers, trigger zones, and trigger rules.

DCS missions have THREE trigger-related sections:
- ["triggers"]["zones"] - Trigger zones (circular map areas)
- ["trig"] - Compiled Lua code (actions, conditions, func arrays)
- ["trigrules"] - Human-readable trigger definitions

This module provides functions to read, add, modify, and remove triggers.
"""

from .list import (
    # Zone functions
    list_trigger_zones,
    list_trigger_zones_file,
    find_zone_by_name,
    find_zone_by_id,

    # Trigger rule functions
    list_trigger_rules,
    list_trigger_rules_file,
    find_trigger_by_comment,

    # Compiled trigger functions
    list_compiled_triggers,

    # Summary functions
    get_trigger_summary,
    get_trigger_summary_file,
)

from .add import (
    # Zone add functions
    add_trigger_zone,
    add_trigger_zone_file,

    # DO SCRIPT trigger functions
    add_do_script_trigger,
    add_do_script_trigger_file,

    # Flag trigger functions
    add_set_flag_trigger,

    # Message trigger functions
    add_message_trigger,
    add_message_trigger_file,
)

__all__ = [
    # Zone list functions
    'list_trigger_zones',
    'list_trigger_zones_file',
    'find_zone_by_name',
    'find_zone_by_id',

    # Zone add functions
    'add_trigger_zone',
    'add_trigger_zone_file',

    # Trigger rule list functions
    'list_trigger_rules',
    'list_trigger_rules_file',
    'find_trigger_by_comment',

    # Compiled trigger functions
    'list_compiled_triggers',

    # Summary functions
    'get_trigger_summary',
    'get_trigger_summary_file',

    # DO SCRIPT trigger functions
    'add_do_script_trigger',
    'add_do_script_trigger_file',

    # Flag trigger functions
    'add_set_flag_trigger',

    # Message trigger functions
    'add_message_trigger',
    'add_message_trigger_file',
]
