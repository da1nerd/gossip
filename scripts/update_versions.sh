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

# Function to increment version
increment_version() {
    local version=$1
    local release_type=$2

    # Split version into parts
    IFS='.' read -ra VERSION_PARTS <<< "$version"
    major=${VERSION_PARTS[0]}
    minor=${VERSION_PARTS[1]}
    patch=${VERSION_PARTS[2]}

    case "$release_type" in
        "major")
            major=$((major + 1))
            minor=0
            patch=0
            ;;
        "minor")
            minor=$((minor + 1))
            patch=0
            ;;
        "patch"|*)
            patch=$((patch + 1))
            ;;
    esac

    echo "$major.$minor.$patch"
}

# Function to update version in pubspec.yaml
update_pubspec_version() {
    local pubspec_file=$1
    local new_version=$2

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        sed -i '' "s/^version: .*/version: $new_version/" "$pubspec_file"
    else
        # Linux
        sed -i "s/^version: .*/version: $new_version/" "$pubspec_file"
    fi
}

# Main function
main() {
    local release_type=${1:-patch}
    local root_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

    print_info "Starting version update process..."
    print_info "Release type: $release_type"
    print_info "Root directory: $root_dir"

    # Check if we're in the right directory
    if [[ ! -f "$root_dir/pubspec.yaml" ]]; then
        print_error "Could not find root pubspec.yaml file"
        exit 1
    fi

    # Get current version from root pubspec.yaml
    current_version=$(grep "^version:" "$root_dir/pubspec.yaml" | sed 's/version: //' | xargs)
    if [[ -z "$current_version" ]]; then
        print_error "Could not extract version from root pubspec.yaml"
        exit 1
    fi

    print_info "Current root version: $current_version"

    # Calculate new version
    new_version=$(increment_version "$current_version" "$release_type")
    print_info "New version will be: $new_version"

    # Update root pubspec.yaml
    print_info "Updating root pubspec.yaml..."
    update_pubspec_version "$root_dir/pubspec.yaml" "$new_version"
    print_success "Updated root pubspec.yaml to version $new_version"

    # Find all package pubspec.yaml files (excluding apps, root, and backups)
    package_pubspecs=()
    while IFS= read -r -d '' file; do
        # Skip the root pubspec.yaml, app pubspecs, and backup directories
        if [[ "$file" != "$root_dir/pubspec.yaml" ]] && [[ "$file" != *"/apps/"* ]] && [[ "$file" != *"/backups/"* ]]; then
            package_pubspecs+=("$file")
        fi
    done < <(find "$root_dir" -name "pubspec.yaml" -print0)

    if [[ ${#package_pubspecs[@]} -eq 0 ]]; then
        print_warning "No package pubspec.yaml files found"
    else
        print_info "Found ${#package_pubspecs[@]} package(s) to update:"

        # Update each package pubspec.yaml
        for pubspec_file in "${package_pubspecs[@]}"; do
            relative_path=${pubspec_file#$root_dir/}
            package_dir=$(dirname "$relative_path")
            package_name=$(basename "$package_dir")

            print_info "  - $package_name ($relative_path)"

            # Get current package version for comparison
            current_pkg_version=$(grep "^version:" "$pubspec_file" | sed 's/version: //' | xargs)

            # Update version
            update_pubspec_version "$pubspec_file" "$new_version"
            print_success "    Updated $package_name from $current_pkg_version to $new_version"
        done
    fi

    # Update package dependencies to use the new version
    print_info "Updating internal package dependencies..."

    for pubspec_file in "${package_pubspecs[@]}"; do
        relative_path=${pubspec_file#$root_dir/}
        package_dir=$(dirname "$relative_path")
        package_name=$(basename "$package_dir")

        # Update dependencies on other packages in the monorepo
        for dep_pubspec in "${package_pubspecs[@]}"; do
            dep_relative_path=${dep_pubspec#$root_dir/}
            dep_package_dir=$(dirname "$dep_relative_path")
            dep_package_name=$(basename "$dep_package_dir")

            # Skip self-reference
            if [[ "$package_name" == "$dep_package_name" ]]; then
                continue
            fi

            # Check if this package depends on the other package
            if grep -q "^  $dep_package_name:" "$pubspec_file"; then
                print_info "  - Updating $dep_package_name dependency in $package_name"
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    # macOS
                    sed -i '' "s/^  $dep_package_name: .*/  $dep_package_name: ^$new_version/" "$pubspec_file"
                else
                    # Linux
                    sed -i "s/^  $dep_package_name: .*/  $dep_package_name: ^$new_version/" "$pubspec_file"
                fi
                print_success "    Updated $dep_package_name dependency to ^$new_version"
            fi
        done
    done

    # Generate summary
    print_success "Version update completed!"
    echo
    print_info "Summary:"
    print_info "  - Root version: $current_version → $new_version"
    print_info "  - Updated ${#package_pubspecs[@]} package(s)"
    print_info "  - Updated internal package dependencies"
    echo
    print_info "Next steps:"
    print_info "  1. Review the changes with 'git diff'"
    print_info "  2. Run 'melos bootstrap' to update dependencies"
    print_info "  3. Run tests to ensure everything works"
    print_info "  4. Commit the changes"

    # Export the new version for use in CI
    if [[ -n "$GITHUB_ENV" ]]; then
        echo "NEW_VERSION=$new_version" >> "$GITHUB_ENV"
    fi

    # Output for GitHub Actions
    if [[ -n "$GITHUB_OUTPUT" ]]; then
        echo "new_version=$new_version" >> "$GITHUB_OUTPUT"
    fi
}

# Check arguments
if [[ $# -gt 1 ]]; then
    print_error "Usage: $0 [patch|minor|major]"
    exit 1
fi

if [[ $# -eq 1 && "$1" != "patch" && "$1" != "minor" && "$1" != "major" ]]; then
    print_error "Invalid release type: $1"
    print_error "Valid options: patch, minor, major"
    exit 1
fi

# Run main function
main "$@"
