#!/usr/bin/env python3
"""
Patch pydcs to support unknown options gracefully and fix liveries scanner.

This creates monkey patches that:
1. Handle missing option IDs by creating generic Option objects
2. Fix the liveries scanner country_list KeyError
"""

import os

# Disable DCS installation detection to avoid liveries scanner issues
os.environ['DCS_INSTALLATION'] = ''
os.environ['DCS_SAVED_GAMES'] = ''

import dcs.task as task_module


# Store original function
_original_create_from_dict = task_module._create_from_dict


def patched_create_from_dict(d):
    """Patched version that handles unknown option IDs."""
    _id = d["id"]
    if _id == "WrappedAction":
        actionid = d["params"]["action"]["id"]
        if actionid == "Option":
            option_name = d["params"]["action"]["params"]["name"]

            # Check if option exists in pydcs
            if option_name in task_module.options:
                t = task_module.options[option_name].create_from_dict(d)
            else:
                # Unknown option - create generic one
                print(f"Warning: Unknown option ID {option_name}, creating generic option")
                t = task_module.Option(option_name, d["params"]["action"]["params"].get("value"))
                # Still set the basic task properties
                t.auto = d.get("auto", False)
                t.enabled = d.get("enabled", True)
                t.number = d.get("number", 1)
                t.params = d.get("params", {})
                return t
        else:
            t = task_module.wrappedactions[actionid].create_from_dict(d)
    elif _id == "EngageTargets":
        t = task_module.engagetargets_tasks[d.get("key")].create_from_dict(d)
    else:
        t = task_module.tasks_map[_id].create_from_dict(d)

    t.auto = d["auto"]
    t.enabled = d["enabled"]
    t.number = d["number"]
    t.params = d["params"]
    return t


def apply_patch():
    """Apply the monkey patch to pydcs."""
    task_module._create_from_dict = patched_create_from_dict
    print("✓ pydcs patch applied - unknown options will be handled gracefully")


def remove_patch():
    """Remove the monkey patch."""
    task_module._create_from_dict = _original_create_from_dict
    print("✓ pydcs patch removed")


if __name__ == "__main__":
    print("This is a library module to patch pydcs.")
    print("\nUsage in your scripts:")
    print("  from pydcs_patch import apply_patch")
    print("  apply_patch()")
    print("  # Now use pydcs normally")
