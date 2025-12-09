"""
Groups Module

Operations for managing DCS mission groups:
- list.py - List and find groups (read-only)
- add.py - Add new groups (not yet implemented)
- remove.py - Remove groups
- duplicate.py - Duplicate existing groups
- modify.py - Modify group properties (not yet implemented)
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
]
