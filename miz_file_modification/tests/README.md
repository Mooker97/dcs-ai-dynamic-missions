# Test Suite for miz-file-modification

This directory contains all tests for the miz-file-modification library.

## Running Tests

### Run All Tests (Recommended)

```bash
python run_tests.py
```

This will automatically discover and run all `test_*.py` files in the tests folder.

### Run Individual Test File

You can also run individual test files for debugging:

```bash
python test_patterns.py
python test_groups_list.py
```

## Test Files

- **`test.miz`** - Standard test mission file used by all tests
- **`test_patterns.py`** - Tests for `utils/patterns.py` regex patterns
- **`test_groups_list.py`** - Tests for `groups/list.py` (future)
- **`test_groups_remove.py`** - Tests for `groups/remove.py` (future)
- **`run_tests.py`** - Master test runner that runs all tests

## Test Structure

All tests follow this pattern:

```python
from pathlib import Path
from parsing.miz_parser import MizParser

TEST_MIZ = Path(__file__).parent / "test.miz"

def test_something():
    """Test description."""
    # Load test mission
    parser = MizParser(str(TEST_MIZ))
    parser.extract()
    content = parser.get_mission_content()

    # Run test
    # ... assertions ...

    # Cleanup
    parser.cleanup()
```

## test.miz Contents

The standard test mission file (`test.miz`) contains:

```
TODO: Document the expected contents of test.miz
- Groups (blue, red, neutral)
- Unit types
- Coordinates
- Waypoints
- Expected values for validation
```

This will be filled in as the test mission is created and validated.

## Adding New Tests

1. Create a new file: `test_<module_name>.py`
2. Define test functions: `def test_<feature>():`
3. Use `test.miz` as the standard test data
4. Run `python run_tests.py` to verify all tests pass

The master test runner will automatically discover and run your new test file.
