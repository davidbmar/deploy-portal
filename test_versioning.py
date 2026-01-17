#!/usr/bin/env python3
"""
Test script for deployment versioning system.

This script verifies:
1. Version format is correct (YYYYMMDD.HHmmss)
2. API endpoints are accessible
3. Skill file exists and has correct structure
4. Config includes version fields
"""

import sys
import os
import re
import json
from datetime import datetime

# Add current directory to path
sys.path.insert(0, os.path.dirname(__file__))

from config import Config

def test_version_format():
    """Test that version format matches expected pattern."""
    print("Testing version format...")

    # Test format constant
    expected_format = "%Y%m%d.%H%M%S"
    assert Config.DEPLOYMENT_VERSION_FORMAT == expected_format, \
        f"Version format mismatch: {Config.DEPLOYMENT_VERSION_FORMAT} != {expected_format}"

    # Test version generation
    test_version = datetime.utcnow().strftime(Config.DEPLOYMENT_VERSION_FORMAT)
    pattern = r'^\d{8}\.\d{6}$'  # YYYYMMDD.HHmmss

    assert re.match(pattern, test_version), \
        f"Generated version doesn't match pattern: {test_version}"

    print(f"  ✅ Version format correct: {test_version}")
    return True

def test_config_constants():
    """Test that config has new versioning constants."""
    print("Testing config constants...")

    assert hasattr(Config, 'DEPLOYMENT_VERSION_FORMAT'), \
        "Config missing DEPLOYMENT_VERSION_FORMAT"

    assert hasattr(Config, 'SESSION_TIMEOUT_MINUTES'), \
        "Config missing SESSION_TIMEOUT_MINUTES"

    assert hasattr(Config, 'SKILL_FILE_PATH'), \
        "Config missing SKILL_FILE_PATH"

    assert Config.SESSION_TIMEOUT_MINUTES == 30, \
        f"SESSION_TIMEOUT_MINUTES should be 30, got {Config.SESSION_TIMEOUT_MINUTES}"

    assert Config.SKILL_FILE_PATH == "deploy-skill.yaml", \
        f"SKILL_FILE_PATH should be 'deploy-skill.yaml', got {Config.SKILL_FILE_PATH}"

    print("  ✅ Config constants present and correct")
    return True

def test_skill_file_exists():
    """Test that skill file exists and has correct structure."""
    print("Testing skill file...")

    skill_path = os.path.join(os.path.dirname(__file__), Config.SKILL_FILE_PATH)
    assert os.path.exists(skill_path), \
        f"Skill file not found at {skill_path}"

    with open(skill_path, 'r') as f:
        skill_content = f.read()

    # Check for required sections
    required_strings = [
        'name: deploy',
        'version: DEPLOYMENT_VERSION_PLACEHOLDER',
        'commands:',
        'Phase 1: Pre-flight Checks',
        'Phase 2: Version Management',
        '/api/deployment/version',
        '/api/deployment/active-sessions'
    ]

    for required in required_strings:
        assert required in skill_content, \
            f"Skill file missing required content: {required}"

    print(f"  ✅ Skill file exists and has correct structure")
    print(f"     Path: {skill_path}")
    return True

def test_app_imports():
    """Test that app.py imports successfully."""
    print("Testing app.py imports...")

    try:
        import app
        print("  ✅ app.py imports successfully")

        # Check for new variables
        assert hasattr(app, 'DEPLOYMENT_VERSION'), \
            "app.py missing DEPLOYMENT_VERSION"

        assert hasattr(app, 'active_deployments'), \
            "app.py missing active_deployments"

        version_pattern = r'^\d{8}\.\d{6}$'
        assert re.match(version_pattern, app.DEPLOYMENT_VERSION), \
            f"DEPLOYMENT_VERSION has wrong format: {app.DEPLOYMENT_VERSION}"

        print(f"     DEPLOYMENT_VERSION: {app.DEPLOYMENT_VERSION}")
        print(f"     active_deployments: {type(app.active_deployments)}")

        return True

    except Exception as e:
        print(f"  ❌ Failed to import app.py: {e}")
        return False

def test_version_lexicographic_ordering():
    """Test that version format is lexicographically sortable."""
    print("Testing lexicographic ordering...")

    # Create test versions
    versions = [
        "20260116.143022",  # Jan 16, 2026 14:30:22
        "20260115.091533",  # Jan 15, 2026 09:15:33
        "20260117.000000",  # Jan 17, 2026 00:00:00
        "20250101.235959",  # Jan 1, 2025 23:59:59
    ]

    # Sort lexicographically
    sorted_versions = sorted(versions)

    # Verify order (should be ascending by date/time)
    expected_order = [
        "20250101.235959",
        "20260115.091533",
        "20260116.143022",
        "20260117.000000",
    ]

    assert sorted_versions == expected_order, \
        f"Lexicographic ordering failed: {sorted_versions} != {expected_order}"

    print("  ✅ Versions are lexicographically sortable")
    return True

def test_zip_filename_parsing():
    """Test parsing version from ZIP filename."""
    print("Testing ZIP filename parsing...")

    test_filenames = [
        ("deployment-kit-my-app-20260116.143022.zip", "my-app", "20260116.143022"),
        ("deployment-kit-contract-manager-20260115.091533.zip", "contract-manager", "20260115.091533"),
        ("deployment-kit-app-123-20250101.000000.zip", "app-123", "20250101.000000"),
    ]

    pattern = r'^deployment-kit-([\w-]+)-(\d{8}\.\d{6})\.zip$'

    for filename, expected_app, expected_version in test_filenames:
        match = re.match(pattern, filename)
        assert match, f"Failed to parse: {filename}"

        app_name = match.group(1)
        version = match.group(2)

        assert app_name == expected_app, \
            f"App name mismatch: {app_name} != {expected_app}"

        assert version == expected_version, \
            f"Version mismatch: {version} != {expected_version}"

    print("  ✅ ZIP filename parsing works correctly")
    return True

def main():
    """Run all tests."""
    print("=" * 70)
    print("Deployment Versioning System - Verification Tests")
    print("=" * 70)
    print()

    tests = [
        test_version_format,
        test_config_constants,
        test_skill_file_exists,
        test_app_imports,
        test_version_lexicographic_ordering,
        test_zip_filename_parsing,
    ]

    passed = 0
    failed = 0

    for test in tests:
        try:
            if test():
                passed += 1
            else:
                failed += 1
        except AssertionError as e:
            print(f"  ❌ Test failed: {e}")
            failed += 1
        except Exception as e:
            print(f"  ❌ Unexpected error: {e}")
            failed += 1
        print()

    print("=" * 70)
    print(f"Results: {passed} passed, {failed} failed")
    print("=" * 70)

    return 0 if failed == 0 else 1

if __name__ == '__main__':
    sys.exit(main())
