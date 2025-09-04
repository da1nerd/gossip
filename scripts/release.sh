#!/bin/bash

# Gossip Monorepo Release Script
# This script helps with versioning and releasing packages

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Print colored output
print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_header() {
    echo ""
    print_color $BLUE "=================================================="
    print_color $BLUE "$1"
    print_color $BLUE "=================================================="
    echo ""
}

print_success() {
    print_color $GREEN "✅ $1"
}

print_warning() {
    print_color $YELLOW "⚠️ $1"
}

print_error() {
    print_color $RED "❌ $1"
}

# Check if melos is installed
check_melos() {
    if ! command -v melos &> /dev/null; then
        print_error "Melos is not installed. Please run: dart pub global activate melos"
        exit 1
    fi
}

# Show usage information
show_usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  check       - Run all pre-release checks"
    echo "  version     - Interactive version bump for all packages"
    echo "  publish     - Publish packages to pub.dev (dry-run first)"
    echo "  app-version - Bump app version"
    echo "  full        - Complete release process (check -> version -> publish)"
    echo ""
    echo "Options:"
    echo "  --dry-run   - Show what would be published without actually publishing"
    echo "  --force     - Skip confirmation prompts"
    echo "  --help      - Show this help message"
    echo ""
    echo "Examples:"
    echo "  $0 check"
    echo "  $0 version"
    echo "  $0 publish --dry-run"
    echo "  $0 full"
}

# Run pre-release checks
run_checks() {
    print_header "Running Pre-Release Checks"

    print_color $BLUE "🔍 Running code analysis..."
    melos run analyze

    print_color $BLUE "🧪 Running tests..."
    melos run test

    print_color $BLUE "✨ Checking code formatting..."
    melos run format

    print_color $BLUE "📦 Checking publish readiness..."
    melos run publish-dry-run

    print_success "All checks passed!"
}

# Interactive version bumping
bump_version() {
    print_header "Version Management"

    echo "Current package versions:"
    melos list --parsable | while read package_path; do
        if [ -f "$package_path/pubspec.yaml" ]; then
            package_name=$(basename "$package_path")
            version=$(cd "$package_path" && grep "version:" pubspec.yaml | sed 's/version: //' | xargs)
            if [[ "$version" != "null" ]] && [[ "$package_path" == *"packages/"* ]]; then
                echo "  📦 $package_name: $version"
            fi
        fi
    done

    echo ""
    read -p "Do you want to version all packages together? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_color $BLUE "🔢 Running Melos version..."
        melos version --all --no-private
        print_success "Version bump completed!"
    else
        print_warning "Skipping version bump. You can run 'melos version' manually."
    fi
}

# Publish packages
publish_packages() {
    local dry_run=$1
    local force=$2

    if [ "$dry_run" = "true" ]; then
        print_header "Dry Run - Package Publishing"
        print_color $BLUE "🔍 Showing what would be published..."
        melos run publish-dry-run
        return 0
    fi

    print_header "Publishing Packages to pub.dev"

    # First, run dry-run to show what will be published
    print_color $BLUE "🔍 Checking what will be published..."
    melos run publish-dry-run

    echo ""
    if [ "$force" != "true" ]; then
        read -p "Do you want to proceed with publishing? (y/N): " -n 1 -r
        echo

        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            print_warning "Publishing cancelled."
            return 0
        fi
    fi

    print_color $BLUE "🚀 Publishing packages..."
    melos run publish-packages

    print_success "Packages published successfully!"
}

# Bump app version
bump_app_version() {
    print_header "App Version Management"

    local app_pubspec="apps/gossip_chat/pubspec.yaml"

    if [ ! -f "$app_pubspec" ]; then
        print_error "App pubspec.yaml not found at $app_pubspec"
        return 1
    fi

    local current_version=$(grep "version:" "$app_pubspec" | sed 's/version: //' | xargs)
    print_color $BLUE "Current app version: $current_version"

    echo ""
    echo "Version format: MAJOR.MINOR.PATCH+BUILD"
    echo "Example: 1.2.3+45"
    echo ""
    read -p "Enter new version (or press Enter to skip): " new_version

    if [ -n "$new_version" ]; then
        # Validate version format
        if [[ $new_version =~ ^[0-9]+\.[0-9]+\.[0-9]+\+[0-9]+$ ]]; then
            sed -i.bak "s/version: .*/version: $new_version/" "$app_pubspec"
            rm "$app_pubspec.bak" 2>/dev/null || true
            print_success "App version updated to $new_version"
        else
            print_error "Invalid version format. Expected: MAJOR.MINOR.PATCH+BUILD"
            return 1
        fi
    else
        print_warning "Skipping app version update."
    fi
}

# Full release process
full_release() {
    local force=$1

    print_header "Full Release Process"

    print_color $BLUE "Starting complete release workflow..."

    # Step 1: Run checks
    run_checks

    # Step 2: Version bump
    echo ""
    if [ "$force" != "true" ]; then
        read -p "Proceed with version management? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            bump_version
        fi
    else
        bump_version
    fi

    # Step 3: App version
    echo ""
    if [ "$force" != "true" ]; then
        read -p "Update app version? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            bump_app_version
        fi
    fi

    # Step 4: Final checks
    echo ""
    print_color $BLUE "🔍 Running final checks before publishing..."
    melos run pre-publish-check

    # Step 5: Publish
    echo ""
    if [ "$force" != "true" ]; then
        read -p "Proceed with publishing to pub.dev? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            publish_packages false $force
        fi
    else
        publish_packages false $force
    fi

    print_success "Full release process completed!"
    echo ""
    print_color $BLUE "Next steps:"
    echo "1. Review and commit your changes"
    echo "2. Push to main branch to trigger deployments"
    echo "3. Monitor Codemagic for app deployment"
    echo "4. Check pub.dev for package availability"
}

# Parse command line arguments
DRY_RUN=false
FORCE=false
COMMAND=""

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --force)
            FORCE=true
            shift
            ;;
        --help|-h)
            show_usage
            exit 0
            ;;
        check|version|publish|app-version|full)
            COMMAND="$1"
            shift
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Main script execution
main() {
    # Check prerequisites
    check_melos

    # Show header
    print_header "Gossip Monorepo Release Manager"

    # Execute command
    case $COMMAND in
        check)
            run_checks
            ;;
        version)
            bump_version
            ;;
        publish)
            publish_packages $DRY_RUN $FORCE
            ;;
        app-version)
            bump_app_version
            ;;
        full)
            full_release $FORCE
            ;;
        "")
            print_error "No command specified."
            show_usage
            exit 1
            ;;
        *)
            print_error "Unknown command: $COMMAND"
            show_usage
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
