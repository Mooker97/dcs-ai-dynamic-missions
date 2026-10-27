"""
Utils Module

Shared utilities for mission file manipulation:
- id_manager.py - Find and generate unique IDs
- patterns.py - Common regex patterns
- validation.py - Validation functions
- players.py - Player/Client/AI detection

IMPORTANT: Always use these utilities instead of duplicating logic!
"""

# Import commonly used items for convenience
from . import patterns
from . import validation
from . import id_manager
from . import players

__all__ = ['patterns', 'validation', 'id_manager', 'players']
