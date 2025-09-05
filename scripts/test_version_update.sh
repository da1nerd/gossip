#!/bin/bash

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_info() {
    echo -e "${BLUE}ℹ️  $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

# Function to show current versions
show_versions() {
    local title=$1
    echo
    print_info "$title"
    echo "----------------------------------------"

    # Root version
    root_version=$(grep "^version:" pubspec.yaml | sed 's/version: //' | xargs)
    echo "Root pubspec.yaml: $root_version"

    # Package versions
    for package_dir in packages/*/; do
        if [ -f "$package_dir/pubspec.yaml" ]; then
            package_name=$(basename "$package_dir")
            version=$(cd "$package_dir" && grep "^version:" pubspec.yaml | sed 's/version: //' | xargs)
            echo "  $package_name: $version"
        fi
    done

    # App version
    if [ -f "apps/gossip_chat/pubspec.yaml" ]; then
        app_version=$(cd "apps/gossip_chat" && grep "^version:" pubspec.yaml | sed 's/version: //' | xargs)
        echo "App (gossip_chat): $app_version"
    fi
    echo "----------------------------------------"
}

# Function to create backup
create_backup() {
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local backup_dir="backups/version_test_$timestamp"

    print_info "Creating backup in $backup_dir..."
    mkdir -p "$backup_dir"

    # Backup root pubspec
    cp pubspec.yaml "$backup_dir/"

    # Backup package pubspecs
    mkdir -p "$backup_dir/packages"
    for package_dir in packages/*/; do
        if [ -f "$package_dir/pubspec.yaml" ]; then
            package_name=$(basename "$package_dir")
            mkdir -p "$backup_dir/packages/$package_name"
            cp "$package_dir/pubspec.yaml" "$backup_dir/packages/$package_name/"
        fi
    done

    # Backup app pubspec
    if [ -f "apps/gossip_chat/pubspec.yaml" ]; then
        mkdir -p "$backup_dir/apps/gossip_chat"
        cp "apps/gossip_chat/pubspec.yaml" "$backup_dir/apps/gossip_chat/"
    fi

    echo "BACKUP_DIR=$backup_dir" > .version_test_backup
    print_success "Backup created successfully"
}

# Function to restore backup
restore_backup() {
    if [ ! -f ".version_test_backup" ]; then
        print_error "No backup found to restore"
        return 1
    fi

    local backup_dir=$(cat .version_test_backup | cut -d'=' -f2)

    if [ ! -d "$backup_dir" ]; then
        print_error "Backup directory $backup_dir not found"
        return 1
    fi

    print_info "Restoring from backup: $backup_dir..."

    # Restore root pubspec
    cp "$backup_dir/pubspec.yaml" .

    # Restore package pubspecs
    for package_dir in packages/*/; do
        if [ -f "$package_dir/pubspec.yaml" ]; then
            package_name=$(basename "$package_dir")
            if [ -f "$backup_dir/packages/$package_name/pubspec.yaml" ]; then
                cp "$backup_dir/packages/$package_name/pubspec.yaml" "$package_dir/"
            fi
        fi
    done

    # Restore app pubspec
    if [ -f "$backup_dir/apps/gossip_chat/pubspec.yaml" ]; then
        cp "$backup_dir/apps/gossip_chat/pubspec.yaml" "apps/gossip_chat/"
    fi

    print_success "Backup restored successfully"
    rm .version_test_backup
}

# Main function
main() {
    local action=${1:-test}
    local release_type=${2:-patch}
    local root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    cd "$root_dir"

    case "$action" in
        "test")
            print_info "🧪 Testing version update process..."
            print_info "Release type: $release_type"
            echo

            # Show current state
            show_versions "📊 BEFORE Version Update"

            # Create backup
            create_backup

            # Run version update
            print_info "🔄 Running version update script..."
            ./scripts/update_versions.sh "$release_type"

            # Show updated state
            show_versions "📊 AFTER Version Update"

            # Ask user what to do next
            echo
            print_info "What would you like to do next?"
            echo "1. Keep changes and test with 'melos bootstrap'"
            echo "2. Restore backup (undo changes)"
            echo "3. Exit (leave changes as-is)"
            read -p "Enter your choice (1/2/3): " choice

            case "$choice" in
                "1")
                    print_info "🔄 Running melos bootstrap to test dependencies..."
                    if command -v melos >/dev/null 2>&1; then
                        melos bootstrap
                        print_success "Melos bootstrap completed successfully!"
                        print_info "Changes are ready. You can now run 'git diff' to review."
                    else
                        print_warning "Melos not found. Install with: dart pub global activate melos"
                    fi
                    rm .version_test_backup 2>/dev/null || true
                    ;;
                "2")
                    restore_backup
                    ;;
                "3")
                    print_info "Exiting. Use './scripts/test_version_update.sh restore' to undo changes later."
                    ;;
                *)
                    print_warning "Invalid choice. Exiting without changes."
                    restore_backup
                    ;;
            esac
            ;;

        "restore")
            restore_backup
            ;;

        "clean")
            print_info "🧹 Cleaning up backup files..."
            rm -rf backups/
            rm .version_test_backup 2>/dev/null || true
            print_success "Cleanup completed"
            ;;

        "show")
            show_versions "📊 Current Versions"
            ;;

        *)
            print_error "Usage: $0 [test|restore|clean|show] [patch|minor|major]"
            echo
            echo "Commands:"
            echo "  test     - Test version update with backup/restore options"
            echo "  restore  - Restore from the last backup"
            echo "  clean    - Clean up all backup files"
            echo "  show     - Show current versions"
            echo
            echo "Release types (for test command):"
            echo "  patch    - Increment patch version (default)"
            echo "  minor    - Increment minor version"
            echo "  major    - Increment major version"
            exit 1
            ;;
    esac
}

# Check if we're in the right directory
if [[ ! -f "pubspec.yaml" ]] || [[ ! -f "scripts/update_versions.sh" ]]; then
    print_error "This script must be run from the monorepo root directory"
    exit 1
fi

# Run main function
main "$@"
