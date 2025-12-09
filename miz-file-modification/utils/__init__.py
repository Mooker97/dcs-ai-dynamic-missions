"""
Utils Module

Shared utilities for mission file manipulation:
- id_manager.py - Find and generate unique IDs
- patterns.py - Common regex patterns
- validation.py - Validation functions

IMPORTANT: Always use these utilities instead of duplicating logic!
"""

# Import commonly used items for convenience
from . import patterns

__all__ = ['patterns']
