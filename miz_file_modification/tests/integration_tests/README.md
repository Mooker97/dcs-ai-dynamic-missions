# Integration Tests

Practical tests demonstrating real-world usage of the miz-file-modification library.

## Available Tests

### position_of_group.py

Find and extract group positions from mission files.

**Usage:**
```bash
# Find F-16 groups
python position_of_group.py f16 "../../miz-files/input/f16 A-G.miz"

# Find specific group by name
python position_of_group.py group "Aerial-1" "../../miz-files/input/f16 A-G.miz"

# Find all aircraft in mission
python position_of_group.py all "../../miz-files/input/f16 A-G.miz"
```

**What it tests:**
- GROUP_PATTERN for finding groups
- POSITION_PATTERN for extracting coordinates
- UNIT_TYPE_PATTERN for identifying aircraft type
- Context detection for coalition/category
- Real-world extraction workflow

**Example output:**
```
[1] Aerial-1
    Unit Type:  F-16C_50
    Coalition:  BLUE
    Category:   plane
    Position:
      X:      -43,124.01
      Y:      -35,050.74
      Distance from origin: 55,571.88 meters
```

## Test Data

Integration tests use real .miz files from `miz-files/input/`:
- `f16 A-G.miz` - F-16 air-to-ground mission

## Running Tests

```bash
# From integration_tests directory
cd miz-file-modification/tests/integration_tests

# Run specific test
python position_of_group.py f16

# With custom miz file
python position_of_group.py all "/path/to/mission.miz"
```

## Creating New Integration Tests

Integration tests should:
1. Use real .miz files
2. Demonstrate practical usage patterns
3. Validate against expected results
4. Provide human-readable output
5. Return exit code 0 on success, 1 on failure

**Template:**
```python
#!/usr/bin/env python3
"""
Integration test: [Description]
"""

import sys
from pathlib import Path

# Add parent directories to path
sys.path.insert(0, str(Path(__file__).parent.parent.parent))

from parsing.miz_parser import MizParser
from utils import patterns

def test_something(miz_path: str):
    """Test description."""
    print("Testing...")

    # Extract mission
    parser = MizParser(miz_path)
    try:
        parser.extract()
        content = parser.get_mission_content()
    finally:
        parser.cleanup()

    # Perform test
    # ...

    return success

if __name__ == "__main__":
    # CLI handling
    # ...
    success = test_something(miz_path)
    sys.exit(0 if success else 1)
```
