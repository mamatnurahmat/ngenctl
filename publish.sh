#!/bin/bash
# Script untuk build dan publish package ngen ke PyPI

set -e  # Exit on error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Configuration
# Extract package name from pyproject.toml automatically
if [ -f "pyproject.toml" ]; then
    PACKAGE_NAME=$(python3 -c "
import re
try:
    with open('pyproject.toml', 'r') as f:
        content = f.read()
        # Try to find name = \"package-name\" or name = 'package-name'
        match = re.search(r'^name\s*=\s*\"([^\"]+)\"', content, re.MULTILINE)
        if not match:
            match = re.search(r\"^name\s*=\s*'([^']+)'\", content, re.MULTILINE)
        if match:
            print(match.group(1))
        else:
            print('ngenctl')
except:
    print('ngenctl')
" 2>/dev/null || echo "ngenctl")
else
    PACKAGE_NAME="ngenctl"
fi

PYPI_REPO="pypi"
TEST_PYPI_REPO="testpypi"

# Functions
print_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_requirements() {
    print_info "Checking requirements..."
    
    if ! command -v python3 &> /dev/null; then
        print_error "python3 not found. Please install Python 3.7+"
        exit 1
    fi
    
    if ! python3 -m pip show build &> /dev/null; then
        print_warn "build package not found. Installing..."
        python3 -m pip install --upgrade build
    fi
    
    if ! python3 -m pip show twine &> /dev/null; then
        print_warn "twine package not found. Installing..."
        python3 -m pip install --upgrade twine
    fi
    
    # Check for requests library (for API calls)
    if ! python3 -m pip show requests &> /dev/null; then
        print_warn "requests package not found. Installing..."
        python3 -m pip install --upgrade requests
    fi
    
    print_info "Requirements check completed"
}

check_pypirc() {
    print_info "Checking PyPI credentials..."
    
    PYPI_RC="$HOME/.pypirc"
    
    if [ ! -f "$PYPI_RC" ]; then
        print_error ".pypirc not found at $PYPI_RC"
        print_error "Please create ~/.pypirc with your PyPI credentials"
        print_error "See PUBLISH.md for configuration instructions"
        exit 1
    fi
    
    # Verify .pypirc has [pypi] or [testpypi] section
    if ! grep -q "\[pypi\]" "$PYPI_RC" && ! grep -q "\[testpypi\]" "$PYPI_RC"; then
        print_error ".pypirc found but missing [pypi] or [testpypi] section"
        print_error "Please add [pypi] section with username and password"
        exit 1
    fi
    
    # Check if username and password are set
    if grep -q "\[pypi\]" "$PYPI_RC"; then
        if ! grep -A 2 "\[pypi\]" "$PYPI_RC" | grep -q "username"; then
            print_error ".pypirc [pypi] section missing username"
            exit 1
        fi
        if ! grep -A 2 "\[pypi\]" "$PYPI_RC" | grep -q "password"; then
            print_error ".pypirc [pypi] section missing password"
            exit 1
        fi
    fi
    
    print_info "PyPI credentials found in ~/.pypirc"
    print_info "Twine will automatically use credentials from ~/.pypirc"
}

check_project_exists() {
    local repo=$1
    local project_url=""
    
    if [ "$repo" = "pypi" ]; then
        project_url="https://pypi.org/pypi/${PACKAGE_NAME}/json"
    elif [ "$repo" = "testpypi" ]; then
        project_url="https://test.pypi.org/pypi/${PACKAGE_NAME}/json"
    else
        return 1
    fi
    
    # Check if project exists using Python
    python3 -c "
import requests
import sys
try:
    r = requests.get('$project_url', timeout=5)
    if r.status_code == 200:
        sys.exit(0)  # Project exists
    else:
        sys.exit(1)  # Project doesn't exist
except Exception:
    sys.exit(1)
" >/dev/null 2>&1
    
    return $?
}

create_project_info() {
    local repo=$1
    
    print_info "Checking if project '${PACKAGE_NAME}' exists on ${repo}..."
    
    if ! check_project_exists "$repo"; then
        print_info "✅ Project '${PACKAGE_NAME}' does not exist on ${repo}"
        print_info "✅ PyPI will automatically create the project on first upload"
        print_info "✅ As a new project, you have full ownership"
        return 0
    else
        print_warn "⚠️  Project '${PACKAGE_NAME}' already exists on ${repo}"
        print_warn "   URL: https://${repo}.org/project/${PACKAGE_NAME}/"
        
        if [ "$repo" = "pypi" ]; then
            print_error "   This project may be owned by another user"
            print_error "   If you get 403 Forbidden, you need to:"
            print_error "   1. Change package name in pyproject.toml"
            print_error "   2. Or request access from current owner"
        fi
        return 1
    fi
}

clean_build() {
    print_info "Cleaning previous builds..."
    rm -rf dist/
    rm -rf build/
    rm -rf *.egg-info
    rm -rf ${PACKAGE_NAME}.egg-info
    print_info "Clean completed"
}

check_package() {
    print_info "Checking package files..."
    
    if [ ! -f "setup.py" ]; then
        print_error "setup.py not found!"
        exit 1
    fi
    
    if [ ! -f "pyproject.toml" ]; then
        print_error "pyproject.toml not found!"
        exit 1
    fi
    
    if [ ! -f "README.md" ]; then
        print_error "README.md not found!"
        exit 1
    fi
    
    if [ ! -d "ngenctl" ]; then
        print_error "ngenctl package directory not found!"
        exit 1
    fi
    
    print_info "Package files check completed"
}

build_package() {
    print_info "Building package..."
    python3 -m build
    
    if [ $? -eq 0 ]; then
        print_info "Build completed successfully"
        ls -lh dist/
    else
        print_error "Build failed!"
        exit 1
    fi
}

check_dist() {
    print_info "Checking distribution files..."
    python3 -m twine check dist/*
    
    if [ $? -eq 0 ]; then
        print_info "Distribution files check passed"
    else
        print_error "Distribution files check failed!"
        exit 1
    fi
}

test_package() {
    print_info "Running package tests..."
    local test_passed=0
    local test_failed=0
    
    # Test 1: Import package
    print_info "  Test 1: Import package..."
    if python3 -c "
import sys
sys.path.insert(0, '.')
# Test that ngenctl directory exists and can be imported
import ngenctl
print('✅ Package directory (ngenctl) imported successfully')
# After install, 'ngenctl' will be available via package_dir mapping
" 2>/dev/null; then
        ((test_passed++))
    else
        print_error "  ❌ Failed to import package"
        ((test_failed++))
    fi

    # Test 2: Check package version
    print_info "  Test 2: Check package version..."
    if python3 -c "
import sys
sys.path.insert(0, '.')
import ngenctl
print(f'✅ Version: {ngenctl.__version__}')
" 2>/dev/null; then
        ((test_passed++))
    else
        print_error "  ❌ Failed to get package version"
        ((test_failed++))
    fi

    # Test 3: Check CLI entry point
    print_info "  Test 3: Check CLI entry point..."
    if python3 -c "
import sys
sys.path.insert(0, '.')
from ngenctl.cli import main
print('✅ CLI entry point found')
" 2>/dev/null; then
        ((test_passed++))
    else
        print_error "  ❌ CLI entry point not found"
        ((test_failed++))
    fi
    
    # Test 4: Test CLI help command
    print_info "  Test 4: Test CLI help command..."
    # Try different ways to invoke help
    help_output=$(python3 -c "
import sys
sys.path.insert(0, '.')
try:
    from ngenctl.cli import main
    import sys
    sys.argv = ['ngenctl', '--help']
    main()
except SystemExit as e:
    if e.code == 0:
        sys.exit(0)
    else:
        sys.exit(1)
except Exception as e:
    print(f'Error: {e}', file=sys.stderr)
    sys.exit(1)
" 2>&1)

    if echo "$help_output" | grep -q "Usage:"; then
        print_info "    ✅ CLI help command works"
        ((test_passed++))
    else
        print_error "  ❌ CLI help command failed"
        print_error "    Debug output: $help_output"
        ((test_failed++))
    fi
    
    # Test 5: Check bundled scripts exist
    print_info "  Test 5: Check bundled scripts..."
    scripts_dir="ngenctl/scripts"
    if [ -d "$scripts_dir" ]; then
        script_count=$(find "$scripts_dir" -name "ngenctl-*" -type f | wc -l)
        if [ $script_count -gt 0 ]; then
            print_info "    ✅ Found $script_count bundled script(s)"
            find "$scripts_dir" -name "ngenctl-*" -type f -exec basename {} \; | while read script; do
                print_info "      - $script"
            done
            ((test_passed++))
        else
            print_warn "    ⚠️  No scripts found in $scripts_dir (this is OK if scripts are installed separately)"
            ((test_passed++))
        fi
    else
        print_warn "    ⚠️  Scripts directory not found (this is OK if scripts are installed separately)"
        ((test_passed++))
    fi
    
    # Test 6: Check wheel installation (if dist exists)
    if [ -d "dist" ] && ls dist/*.whl 1> /dev/null 2>&1; then
        print_info "  Test 6: Test wheel installation..."
        wheel_file=$(ls dist/*.whl | head -1)
        # Try to extract and check structure
        if python3 -c "
import zipfile
import sys
try:
    with zipfile.ZipFile('$wheel_file', 'r') as z:
        files = z.namelist()
        # Check for both possible structures (ngenctl or ngenctl in wheel)
        if any('ngenctl/__init__.py' in f or 'ngenctl/__init__.py' in f for f in files):
            print('✅ Wheel contains package files')
            sys.exit(0)
        else:
            print('❌ Wheel missing package files')
            sys.exit(1)
except Exception as e:
    print(f'❌ Error checking wheel: {e}')
    sys.exit(1)
" 2>/dev/null; then
            ((test_passed++))
        else
            print_error "  ❌ Wheel structure check failed"
            ((test_failed++))
        fi
    else
        print_info "  Test 6: Skipped (no wheel file found)"
    fi
    
    # Summary
    echo
    print_info "Test Summary:"
    print_info "  ✅ Passed: $test_passed"
    if [ $test_failed -gt 0 ]; then
        print_error "  ❌ Failed: $test_failed"
        print_error "Please fix the failing tests before publishing"
        return 1
    else
        print_info "  ✅ All tests passed!"
        return 0
    fi
}

publish_test() {
    print_info "Publishing to Test PyPI..."
    
    # Check if project exists
    create_project_info "testpypi"
    is_new_project=$?
    
    if [ $is_new_project -eq 0 ]; then
        print_info "✅ This is a new project - will be created automatically on first upload"
    fi
    
    print_info "Using credentials from ~/.pypirc"
    print_info "Package: ${PACKAGE_NAME}"
    
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warn "Publishing to Test PyPI cancelled"
        return
    fi
    
    # Upload using twine (automatically reads from ~/.pypirc)
    print_info "Uploading to Test PyPI..."
    python3 -m twine upload --repository ${TEST_PYPI_REPO} dist/*
    
    upload_status=$?
    
    if [ $upload_status -eq 0 ]; then
        print_info "✅ Published to Test PyPI successfully!"
        if [ $is_new_project -eq 0 ]; then
            print_info "✅ Project '${PACKAGE_NAME}' has been created on Test PyPI"
        fi
        print_info "Test installation: pip install -i https://test.pypi.org/simple/ ${PACKAGE_NAME}"
        print_info "Project URL: https://test.pypi.org/project/${PACKAGE_NAME}/"
    else
        print_error "❌ Publishing to Test PyPI failed!"
        print_error "Check your credentials in ~/.pypirc"
        print_error "Verify API token is valid and has correct permissions"
        exit 1
    fi
}

publish_prod() {
    print_info "Publishing to PyPI (production)..."
    print_warn "⚠️  This will publish to the public PyPI repository!"
    print_warn "⚠️  Make sure you have tested the package first."
    
    # Check if project exists
    create_project_info "pypi"
    is_new_project=$?
    
    if [ $is_new_project -eq 0 ]; then
        print_info "✅ This is a new project - will be created automatically on first upload"
        print_info "✅ As project owner, you'll have full control"
    else
        print_warn "⚠️  Project already exists - you may need permission to upload"
    fi
    
    print_info "Using credentials from ~/.pypirc"
    print_info "Package: ${PACKAGE_NAME}"
    print_info "Account: $(grep -A 2 "\[pypi\]" ~/.pypirc | grep username | cut -d'=' -f2 | tr -d ' ' || echo 'unknown')"
    
    read -p "Are you sure you want to publish to PyPI? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_warn "Publishing to PyPI cancelled"
        return
    fi
    
    # Upload using twine (automatically reads from ~/.pypirc)
    print_info "Uploading to PyPI..."
    python3 -m twine upload --repository ${PYPI_REPO} dist/*
    
    upload_status=$?
    
    if [ $upload_status -eq 0 ]; then
        print_info "✅ Published to PyPI successfully!"
        if [ $is_new_project -eq 0 ]; then
            print_info "✅ Project '${PACKAGE_NAME}' has been created on PyPI"
            print_info "✅ You are now the owner of this project"
        fi
        print_info ""
        print_info "Installation: pip install ${PACKAGE_NAME}"
        print_info "Project URL: https://pypi.org/project/${PACKAGE_NAME}/"
        print_info ""
        print_info "Next steps:"
        print_info "  - Verify your package at https://pypi.org/project/${PACKAGE_NAME}/"
        print_info "  - Test installation: pip install ${PACKAGE_NAME}"
    else
        print_error "❌ Publishing to PyPI failed!"
        print_error ""
        print_error "Possible issues:"
        print_error "  1. Check your credentials in ~/.pypirc"
        print_error "     - Verify API token is valid"
        print_error "     - Token should start with 'pypi-'"
        print_error "     - Check token has correct scope/permissions"
        print_error ""
        print_error "  2. Project name conflict (403 Forbidden):"
        print_error "     - Project '${PACKAGE_NAME}' exists but owned by another user"
        print_error "     - Check: https://pypi.org/project/${PACKAGE_NAME}/"
        print_error "     - Solutions:"
        print_error "       a) Change package name in pyproject.toml"
        print_error "       b) Request ownership/access from current owner"
        print_error ""
        print_error "  3. Version already exists:"
        print_error "     - Increment version number in pyproject.toml and ngenctl/__init__.py"
        print_error ""
        print_error "  4. Network/API issues:"
        print_error "     - Check internet connection"
        print_error "     - Try again later if PyPI is experiencing issues"
        exit 1
    fi
}

# Main script
main() {
    echo "======================================"
    echo "  ${PACKAGE_NAME} Package Publisher"
    echo "======================================"
    echo
    
    # Check if we're in the right directory
    if [ ! -f "setup.py" ] || [ ! -f "pyproject.toml" ]; then
        print_error "Please run this script from the package root directory"
        exit 1
    fi
    
    check_requirements
    check_pypirc
    check_package
    clean_build
    build_package
    check_dist
    test_package || exit 1
    
    echo
    echo "======================================"
    echo "  Build completed successfully!"
    echo "======================================"
    echo
    echo "Next steps:"
    echo "1. Test locally: pip install dist/${PACKAGE_NAME}-*.whl"
    echo "2. Publish to Test PyPI: ./publish.sh --test"
    echo "3. Publish to PyPI: ./publish.sh --publish"
    echo
}

# Handle command line arguments
case "${1:-}" in
    --test)
    check_requirements
    check_pypirc
    check_package
    if [ ! -d "dist" ]; then
        print_warn "No dist directory found. Building package first..."
        clean_build
        build_package
        check_dist
    fi
    test_package || exit 1
    publish_test
        ;;
    --publish)
    check_requirements
    check_pypirc
    check_package
    if [ ! -d "dist" ]; then
        print_warn "No dist directory found. Building package first..."
        clean_build
        build_package
        check_dist
    fi
    test_package || exit 1
    publish_prod
        ;;
    --build-only)
        check_requirements
        check_package
        clean_build
        build_package
        check_dist
        test_package || exit 1
        ;;
    --help|-h)
        echo "Usage: $0 [OPTION]"
        echo
        echo "Options:"
        echo "  (no option)    Build package and check distribution"
        echo "  --test         Build and publish to Test PyPI"
        echo "  --publish      Build and publish to PyPI (production)"
        echo "  --build-only   Only build package, don't publish"
        echo "  --help, -h     Show this help message"
        echo
        ;;
    "")
        main
        ;;
    *)
        print_error "Unknown option: $1"
        echo "Use --help for usage information"
        exit 1
        ;;
esac

