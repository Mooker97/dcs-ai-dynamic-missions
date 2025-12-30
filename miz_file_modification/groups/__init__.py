"""
Groups Module

Operations for managing DCS mission groups:
- list.py - List and find groups (read-only)
- add.py - Add new groups
- remove.py - Remove groups
- duplicate.py - Duplicate existing groups
- modify.py - Modify group properties
"""

# ============================================================================
# LIST FUNCTIONS (Read-only)
# ============================================================================

from .list import (
    # Core inspection functions
    list_all_groups,
    find_group_by_name,
    count_groups,
    get_group_info,

    # Utility functions
    get_groups_by_coalition,
    get_groups_by_type,

    # Convenience wrappers
    list_all_groups_file,
    get_group_info_file,
)

# ============================================================================
# ADD FUNCTIONS
# ============================================================================

from .add import (
    # Core addition function
    add_group,

    # Convenience wrapper
    add_group_file,

    # Utility functions
    get_available_countries,
    get_country_id,

    # Constants
    COUNTRY_IDS,
    UNIT_TYPE_DEFAULTS,
)

# ============================================================================
# REMOVE FUNCTIONS
# ============================================================================

from .remove import (
    # Core removal functions
    remove_group,
    remove_groups_by_type,
    remove_groups_by_coalition,
    remove_empty_groups,
    remove_groups_by_names,

    # Convenience wrappers
    remove_group_file,
    remove_groups_by_type_file,
    remove_groups_by_coalition_file,
    remove_empty_groups_file,
    remove_groups_by_names_file,
)

# ============================================================================
# DUPLICATE FUNCTIONS
# ============================================================================

from .duplicate import (
    # Core duplication function
    duplicate_group,

    # Convenience wrapper
    duplicate_group_file,
)

# ============================================================================
# MODIFY FUNCTIONS
# ============================================================================

from .modify import (
    # Core modification functions
    rename_group,
    move_group,
    change_group_coalition,
    modify_group_skill,
    modify_group_heading,

    # Convenience wrappers
    rename_group_file,
    move_group_file,
    change_group_coalition_file,
    modify_group_skill_file,
    modify_group_heading_file,
)

# ============================================================================
# MODULE EXPORTS
# ============================================================================

__all__ = [
    # List functions
    "list_all_groups",
    "find_group_by_name",
    "count_groups",
    "get_group_info",
    "get_groups_by_coalition",
    "get_groups_by_type",
    "list_all_groups_file",
    "get_group_info_file",

    # Add functions
    "add_group",
    "add_group_file",
    "get_available_countries",
    "get_country_id",
    "COUNTRY_IDS",
    "UNIT_TYPE_DEFAULTS",

    # Remove functions
    "remove_group",
    "remove_groups_by_type",
    "remove_groups_by_coalition",
    "remove_empty_groups",
    "remove_groups_by_names",
    "remove_group_file",
    "remove_groups_by_type_file",
    "remove_groups_by_coalition_file",
    "remove_empty_groups_file",
    "remove_groups_by_names_file",

    # Duplicate functions
    "duplicate_group",
    "duplicate_group_file",

    # Modify functions
    "rename_group",
    "move_group",
    "change_group_coalition",
    "modify_group_skill",
    "modify_group_heading",
    "rename_group_file",
    "move_group_file",
    "change_group_coalition_file",
    "modify_group_skill_file",
    "modify_group_heading_file",
]
