"""
Units Module

Operations for managing units within groups:
- add.py - Add units to groups
- remove.py - Remove units from groups
- modify.py - Modify unit properties (loadout, skill, position)
"""

# Add operations
from .add import (
    add_unit_to_group,
    add_multiple_units_to_group,
    add_unit_to_group_file,
    add_multiple_units_to_group_file,
)

# Remove operations
from .remove import (
    remove_unit_from_group,
    remove_unit_by_name,
    remove_units_by_type,
    remove_all_units_from_group,
    remove_unit_from_group_file,
    remove_unit_by_name_file,
    remove_units_by_type_file,
    remove_all_units_from_group_file,
)

# Modify operations
from .modify import (
    modify_unit_skill,
    modify_unit_position,
    modify_unit_heading,
    modify_unit_loadout,
    modify_unit_type,
    modify_unit_name,
    modify_unit_skill_file,
    modify_unit_position_file,
    modify_unit_heading_file,
    modify_unit_loadout_file,
    modify_unit_type_file,
    modify_unit_name_file,
)

__all__ = [
    # Add
    "add_unit_to_group",
    "add_multiple_units_to_group",
    "add_unit_to_group_file",
    "add_multiple_units_to_group_file",
    # Remove
    "remove_unit_from_group",
    "remove_unit_by_name",
    "remove_units_by_type",
    "remove_all_units_from_group",
    "remove_unit_from_group_file",
    "remove_unit_by_name_file",
    "remove_units_by_type_file",
    "remove_all_units_from_group_file",
    # Modify
    "modify_unit_skill",
    "modify_unit_position",
    "modify_unit_heading",
    "modify_unit_loadout",
    "modify_unit_type",
    "modify_unit_name",
    "modify_unit_skill_file",
    "modify_unit_position_file",
    "modify_unit_heading_file",
    "modify_unit_loadout_file",
    "modify_unit_type_file",
    "modify_unit_name_file",
]
