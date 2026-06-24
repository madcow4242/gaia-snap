#!/bin/bash
# =====================================================================
# GAIA PACKAGING PROJECT - SMOKE TEST SUITE
# =====================================================================
# Validates: YAML syntax, file existence, version consistency, 
# snap store readiness, and basic deployment topology setup
# =====================================================================

set -e

TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# =====================================================================
# UTILITY FUNCTIONS
# =====================================================================

test_start() {
    echo -n "Testing: $1... "
}

test_pass() {
    echo -e "${GREEN}✓${NC}"
    ((++TESTS_PASSED))
}

test_fail() {
    echo -e "${RED}✗ FAILED${NC}"
    if [ -n "$1" ]; then
        echo "  Error: $1"
    fi
    ((++TESTS_FAILED))
}

test_skip() {
    echo -e "${YELLOW}⊘ SKIPPED${NC}"
    if [ -n "$1" ]; then
        echo "  Reason: $1"
    fi
    ((++TESTS_SKIPPED))
}

# =====================================================================
# TEST SUITE: Basic File & Permission Checks
# =====================================================================

echo ""
echo "========== FILE EXISTENCE & PERMISSION TESTS =========="

test_start "All required shell scripts exist"
required_scripts=("rebuild.sh" "install_gaia.sh" "gaia-launcher.sh" "cleanup.sh")
for script in "${required_scripts[@]}"; do
    if [ ! -f "$script" ]; then
        test_fail "Missing: $script"
        exit 1
    fi
done
test_pass

test_start "All shell scripts are executable"
for script in "${required_scripts[@]}"; do
    if [ ! -x "$script" ]; then
        test_fail "$script not executable"
        exit 1
    fi
done
test_pass

test_start "Python sandbox patch exists"
if [ ! -f "_gaia_sandbox_patch.py" ]; then
    test_fail "Missing: _gaia_sandbox_patch.py"
    exit 1
fi
test_pass

test_start "Snap configuration files exist"
snap_files=("snap/snapcraft.yaml" "snap/hooks/configure" "snap/gui/amd-gaia.png")
for file in "${snap_files[@]}"; do
    if [ ! -f "$file" ]; then
        test_fail "Missing: $file"
        exit 1
    fi
done
test_pass

test_start "OCI Rock configuration exists"
if [ ! -f "rockcraft.yaml" ]; then
    test_fail "Missing: rockcraft.yaml"
    exit 1
fi
test_pass

# =====================================================================
# TEST SUITE: YAML Syntax Validation
# =====================================================================

echo ""
echo "========== YAML SYNTAX VALIDATION =========="

test_start "snapcraft.yaml has valid YAML syntax"
if ! python3 -c "import yaml; yaml.safe_load(open('snap/snapcraft.yaml'))" 2>/dev/null; then
    if ! command -v yamllint &>/dev/null; then
        test_skip "yamllint not installed"
    else
        test_fail "snapcraft.yaml has invalid YAML"
        exit 1
    fi
else
    test_pass
fi

test_start "rockcraft.yaml has valid YAML syntax"
if ! python3 -c "import yaml; yaml.safe_load(open('rockcraft.yaml'))" 2>/dev/null; then
    if ! command -v yamllint &>/dev/null; then
        test_skip "yamllint not installed"
    else
        test_fail "rockcraft.yaml has invalid YAML"
        exit 1
    fi
else
    test_pass
fi

# =====================================================================
# TEST SUITE: Shell Script Syntax Validation
# =====================================================================

echo ""
echo "========== SHELL SCRIPT SYNTAX VALIDATION =========="

for script in "${required_scripts[@]}"; do
    test_start "Syntax check: $script"
    if ! bash -n "$script" 2>/dev/null; then
        test_fail "Syntax error in $script"
        exit 1
    fi
    test_pass
done

# =====================================================================
# TEST SUITE: Python Syntax Validation
# =====================================================================

echo ""
echo "========== PYTHON SYNTAX VALIDATION =========="

test_start "Python sandbox patch has valid syntax"
if ! python3 -m py_compile _gaia_sandbox_patch.py 2>/dev/null; then
    test_fail "Syntax error in _gaia_sandbox_patch.py"
    exit 1
fi
test_pass

# =====================================================================
# TEST SUITE: Version Consistency
# =====================================================================

echo ""
echo "========== VERSION CONSISTENCY CHECKS =========="

# Extract version from snapcraft.yaml
SNAP_VERSION=$(grep 'VERSION_TAG="' snap/snapcraft.yaml | head -1 | sed 's/.*VERSION_TAG="\([^"]*\)".*/\1/')

test_start "snapcraft.yaml has version set"
if [ -z "$SNAP_VERSION" ]; then
    test_fail "VERSION_TAG not found in snapcraft.yaml"
    exit 1
fi
test_pass
echo "  Version: $SNAP_VERSION"

# Extract version from rockcraft.yaml
ROCK_VERSION=$(grep 'version: &global_version "' rockcraft.yaml | head -1 | sed 's/.*version: &global_version "\([^"]*\)".*/\1/')

test_start "rockcraft.yaml version matches snapcraft.yaml"
if [ "$ROCK_VERSION" != "$SNAP_VERSION" ]; then
    test_fail "Version mismatch: snapcraft=$SNAP_VERSION, rockcraft=$ROCK_VERSION"
    exit 1
fi
test_pass

# Extract version from install_gaia.sh
INSTALL_VERSION=$(grep 'GAIA_VERSION="' install_gaia.sh | head -1 | sed 's/.*GAIA_VERSION="\([^"]*\)".*/\1/')

test_start "install_gaia.sh version matches snapcraft.yaml"
if [ "$INSTALL_VERSION" != "$SNAP_VERSION" ]; then
    test_fail "Version mismatch: snapcraft=$SNAP_VERSION, install_gaia=$INSTALL_VERSION"
    exit 1
fi
test_pass

# =====================================================================
# TEST SUITE: Snap Store Readiness
# =====================================================================

echo ""
echo "========== SNAP STORE READINESS CHECKS =========="

test_start "snapcraft.yaml has required store metadata: name"
if ! grep -q '^name:' snap/snapcraft.yaml; then
    test_fail "Missing 'name' field"
    exit 1
fi
test_pass

test_start "snapcraft.yaml has required store metadata: summary"
if ! grep -q '^summary:' snap/snapcraft.yaml; then
    test_fail "Missing 'summary' field"
    exit 1
fi
test_pass

test_start "snapcraft.yaml has required store metadata: description"
if ! grep -q '^description:' snap/snapcraft.yaml; then
    test_fail "Missing 'description' field"
    exit 1
fi
test_pass

test_start "snapcraft.yaml has required store metadata: license"
if ! grep -q '^license:' snap/snapcraft.yaml; then
    test_fail "Missing 'license' field"
    exit 1
fi
test_pass

test_start "snapcraft.yaml has required store metadata: icon"
if ! grep -q '^icon:' snap/snapcraft.yaml; then
    test_fail "Missing 'icon' field"
    exit 1
else
    ICON_PATH=$(grep '^icon:' snap/snapcraft.yaml | sed 's/^icon:[[:space:]]*//')
    if [ ! -f "$ICON_PATH" ]; then
        test_fail "Icon file not found: $ICON_PATH"
        exit 1
    fi
fi
test_pass

test_start "Version format is semantic versioning (X.Y.Z)"
if ! [[ "$SNAP_VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    test_fail "Version '$SNAP_VERSION' is not in semantic versioning format"
    exit 1
fi
test_pass

test_start "snapcraft.yaml has grade field set"
if ! grep -q '^grade:' snap/snapcraft.yaml; then
    test_fail "Missing 'grade' field (should be 'stable' or 'devel')"
    exit 1
fi
test_pass

test_start "snapcraft.yaml has confinement field set"
if ! grep -q '^confinement:' snap/snapcraft.yaml; then
    test_fail "Missing 'confinement' field (should be 'classic' or 'strict')"
    exit 1
fi
test_pass

# =====================================================================
# TEST SUITE: Critical Configuration Checks
# =====================================================================

echo ""
echo "========== CONFIGURATION VALIDATION =========="

test_start "gaia-launcher.sh has hardcoded default backend URL"
if ! grep -q 'http://127.0.0.1:13305' gaia-launcher.sh; then
    test_fail "Missing default backend URL"
    exit 1
fi
test_pass

test_start "gaia-launcher.sh has default max-steps setting"
if ! grep -q 'MAX_STEPS=20' gaia-launcher.sh; then
    test_fail "Missing MAX_STEPS default"
    exit 1
fi
test_pass

test_start "cleanup.sh uses TARGET_VERSION variable"
if grep -q 'gaia-desktop:0\.20\.0' cleanup.sh; then
    test_fail "Hardcoded version found in cleanup.sh instead of \$TARGET_VERSION"
    exit 1
fi
test_pass

test_start "rebuild.sh patches correct install_gaia.sh filename"
if grep -q 'install-gaia.sh' rebuild.sh; then
    test_fail "Found incorrect filename 'install-gaia.sh' in rebuild.sh (should be 'install_gaia.sh')"
    exit 1
fi
test_pass

test_start "Error handling in rebuild.sh (trap handlers present)"
if ! grep -q 'trap.*cleanup_on_exit.*EXIT' rebuild.sh; then
    test_fail "Missing trap handler for error cleanup"
    exit 1
fi
test_pass

# =====================================================================
# TEST SUITE: Tool Availability Checks
# =====================================================================

echo ""
echo "========== TOOL AVAILABILITY CHECKS =========="

test_start "Tool validation functions present in rebuild.sh"
if ! grep -q 'validate_required_tools()' rebuild.sh; then
    test_fail "Missing validate_required_tools function"
    exit 1
fi
test_pass

test_start "Pre-flight checks present in install_gaia.sh"
if ! grep -q 'validate_topology_tools()' install_gaia.sh; then
    test_fail "Missing validate_topology_tools function"
    exit 1
fi
test_pass

# =====================================================================
# TEST SUITE: Deployment Topology File Checks
# =====================================================================

echo ""
echo "========== DEPLOYMENT TOPOLOGY VALIDATION =========="

test_start "install_gaia.sh supports native Snap deployment"
if ! grep -q 'TOPOLOGY_CHOICE.*1' install_gaia.sh; then
    test_fail "Native snap deployment option missing"
    exit 1
fi
test_pass

test_start "install_gaia.sh supports LXD deployment"
if ! grep -q 'TOPOLOGY_CHOICE.*2' install_gaia.sh; then
    test_fail "LXD deployment option missing"
    exit 1
fi
test_pass

test_start "install_gaia.sh supports Docker deployment"
if ! grep -q 'TOPOLOGY_CHOICE.*3' install_gaia.sh; then
    test_fail "Docker deployment option missing"
    exit 1
fi
test_pass

test_start "install_gaia.sh supports Podman deployment"
if ! grep -q 'TOPOLOGY_CHOICE.*4' install_gaia.sh; then
    test_fail "Podman deployment option missing"
    exit 1
fi
test_pass

# =====================================================================
# TEST SUITE: Summary
# =====================================================================

echo ""
echo "========== TEST SUMMARY =========="
echo -e "${GREEN}Passed:${NC}  $TESTS_PASSED"
echo -e "${RED}Failed:${NC}  $TESTS_FAILED"
echo -e "${YELLOW}Skipped:${NC} $TESTS_SKIPPED"
echo ""

if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "${RED}❌ SMOKE TESTS FAILED${NC}"
    exit 1
else
    echo -e "${GREEN}✅ ALL SMOKE TESTS PASSED${NC}"
    exit 0
fi
