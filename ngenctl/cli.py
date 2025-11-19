#!/usr/bin/env python3
"""CLI dispatcher for ngenctl command wrapper."""

import sys
import os
import subprocess
from pathlib import Path


def find_script(command: str) -> Path:
    """
    Find the script wrapper for the given command.
    
    Priority:
    1. /usr/local/bin/ngenctl-{command}
    2. Scripts bundled in the package
    
    Args:
        command: The subcommand (e.g., "rancher", "git")
        
    Returns:
        Path to the script, or None if not found
    """
    # Check in /usr/local/bin first
    system_script = Path(f"/usr/local/bin/ngenctl-{command}")
    if system_script.exists() and system_script.is_file():
        return system_script
    
    # Check in bundled scripts
    package_dir = Path(__file__).parent
    bundled_script = package_dir / "scripts" / f"ngenctl-{command}"
    if bundled_script.exists() and bundled_script.is_file():
        return bundled_script
    
    return None


def execute_script(script_path: Path, args: list) -> int:
    """
    Execute the script with the given arguments.
    
    Args:
        script_path: Path to the script to execute
        args: List of arguments to pass to the script
        
    Returns:
        Exit code from the script execution
    """
    try:
        # Make script executable if it's not already
        if not os.access(script_path, os.X_OK):
            os.chmod(script_path, 0o755)
        
        # Execute the script with arguments
        result = subprocess.run([str(script_path)] + args)
        return result.returncode
    except Exception as e:
        print(f"Error executing {script_path}: {e}", file=sys.stderr)
        return 1


def main():
    """Main entry point for ngenctl command."""
    if len(sys.argv) < 2:
        print("Usage: ngenctl <command> [args...]", file=sys.stderr)
        print("\nAvailable commands:")
        # List available commands
        commands_found = set()
        # Check /usr/local/bin
        system_bin = Path("/usr/local/bin")
        if system_bin.exists():
            for script in system_bin.glob("ngenctl-*"):
                if script.is_file():
                    command = script.name.replace("ngenctl-", "", 1)
                    commands_found.add(command)
        # Check bundled scripts
        package_dir = Path(__file__).parent
        bundled_dir = package_dir / "scripts"
        if bundled_dir.exists():
            for script in bundled_dir.glob("ngenctl-*"):
                if script.is_file():
                    command = script.name.replace("ngenctl-", "", 1)
                    commands_found.add(command)
        # Print commands
        for cmd in sorted(commands_found):
            print(f"  {cmd}")
        if not commands_found:
            print("  (no commands found)")
        sys.exit(1)
    
    command = sys.argv[1]
    
    # Handle help flags
    if command in ("-h", "--help", "help"):
        print("Usage: ngenctl <command> [args...]", file=sys.stderr)
        print("\nngenctl is a universal command wrapper that dispatches to scripts at /usr/local/bin/ngenctl-*")
        print("\nExamples:")
        print("  ngenctl rancher --help")
        print("  ngenctl git clone <repo>")
        sys.exit(0)
    
    args = sys.argv[2:]
    
    script_path = find_script(command)
    
    if script_path is None:
        print(f"Error: command '{command}' not found", file=sys.stderr)
        print(f"Expected script at: /usr/local/bin/ngenctl-{command}", file=sys.stderr)
        sys.exit(1)
    
    exit_code = execute_script(script_path, args)
    sys.exit(exit_code)


if __name__ == "__main__":
    main()

