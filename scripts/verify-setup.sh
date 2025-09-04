#!/bin/bash

# Gossip Monorepo Setup Verification Script
# This script verifies that all required tools and configurations are properly set up

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
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

print_info() {
    print_color $BLUE "ℹ️ $1"
}

# Track verification results
ERRORS=0
WARNINGS=0

# Add error
add_error() {
    ERRORS=$((ERRORS + 1))
    print_error "$1"
}

# Add warning
add_warning() {
    WARNINGS=$((WARNINGS + 1))
    print_warning "$1"
}

# Check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check version requirements
check_version() {
    local tool=$1
    local current_version=$2
    local min_version=$3
    local comparison_result

    # Simple version comparison (works for most semantic versions)
    comparison_result=$(printf '%s\n' "$min_version" "$current_version" | sort -V | head -n1)

    if [ "$comparison_result" = "$min_version" ]; then
        return 0  # Version is OK
    else
        return 1  # Version is too old
    fi
}

# Main verification function
main() {
    print_header "Gossip Monorepo Setup Verification"

    print_color $PURPLE "Checking development environment setup..."
    echo ""

    # Check Git
    if command_exists git; then
        GIT_VERSION=$(git --version | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        print_success "Git installed: v$GIT_VERSION"
    else
        add_error "Git is not installed. Please install Git first."
    fi

    # Check Dart SDK
    if command_exists dart; then
        DART_VERSION=$(dart --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if check_version "$DART_VERSION" "3.0.0"; then
            print_success "Dart SDK installed: v$DART_VERSION (>= 3.0.0)"
        else
            add_error "Dart SDK version $DART_VERSION is too old. Minimum required: 3.0.0"
        fi

        # Check if Dart is in PATH
        DART_PATH=$(which dart)
        print_info "Dart location: $DART_PATH"
    else
        add_error "Dart SDK is not installed or not in PATH"
    fi

    # Check Flutter SDK
    if command_exists flutter; then
        FLUTTER_VERSION=$(flutter --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        if check_version "$FLUTTER_VERSION" "3.16.0"; then
            print_success "Flutter SDK installed: v$FLUTTER_VERSION (>= 3.16.0)"
        else
            add_warning "Flutter SDK version $FLUTTER_VERSION might be too old. Recommended: >= 3.16.0"
        fi

        # Check Flutter doctor
        print_info "Running flutter doctor..."
        flutter doctor --version >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            print_success "Flutter installation is healthy"
        else
            add_warning "Flutter doctor reported issues. Run 'flutter doctor' for details."
        fi
    else
        add_error "Flutter SDK is not installed or not in PATH"
    fi

    # Check Melos
    if command_exists melos; then
        MELOS_VERSION=$(melos --version 2>&1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)
        print_success "Melos installed: v$MELOS_VERSION"
    else
        add_error "Melos is not installed. Run: dart pub global activate melos"
    fi

    # Check Android SDK (if available)
    if [ -n "$ANDROID_HOME" ] || [ -n "$ANDROID_SDK_ROOT" ]; then
        ANDROID_PATH=${ANDROID_HOME:-$ANDROID_SDK_ROOT}
        if [ -d "$ANDROID_PATH" ]; then
            print_success "Android SDK found at: $ANDROID_PATH"

            # Check for ADB
            if command_exists adb; then
                print_success "ADB is available"
            else
                add_warning "ADB not found in PATH. You may need to add Android SDK tools to PATH."
            fi
        else
            add_warning "Android SDK path exists in environment but directory not found: $ANDROID_PATH"
        fi
    else
        add_warning "Android SDK not detected. Set ANDROID_HOME or ANDROID_SDK_ROOT if you plan to build Android apps."
    fi

    echo ""
    print_header "Project Structure Verification"

    # Check if we're in the right directory
    if [ ! -f "melos.yaml" ]; then
        add_error "melos.yaml not found. Make sure you're in the project root directory."
    else
        print_success "Found melos.yaml in current directory"
    fi

    # Check required directories
    REQUIRED_DIRS=("packages" "apps" ".github" "scripts")
    for dir in "${REQUIRED_DIRS[@]}"; do
        if [ -d "$dir" ]; then
            print_success "Directory exists: $dir/"
        else
            add_error "Required directory missing: $dir/"
        fi
    done

    # Check packages
    if [ -d "packages" ]; then
        PACKAGE_COUNT=$(find packages -maxdepth 1 -type d | wc -l)
        PACKAGE_COUNT=$((PACKAGE_COUNT - 1))  # Subtract the packages directory itself
        if [ $PACKAGE_COUNT -gt 0 ]; then
            print_success "Found $PACKAGE_COUNT packages"

            # List packages
            for package_dir in packages/*/; do
                if [ -d "$package_dir" ]; then
                    package_name=$(basename "$package_dir")
                    if [ -f "$package_dir/pubspec.yaml" ]; then
                        print_info "  📦 $package_name"
                    else
                        add_warning "  📦 $package_name (missing pubspec.yaml)"
                    fi
                fi
            done
        else
            add_warning "No packages found in packages/ directory"
        fi
    fi

    # Check apps
    if [ -d "apps" ]; then
        APP_COUNT=$(find apps -maxdepth 1 -type d | wc -l)
        APP_COUNT=$((APP_COUNT - 1))  # Subtract the apps directory itself
        if [ $APP_COUNT -gt 0 ]; then
            print_success "Found $APP_COUNT app(s)"

            # List apps
            for app_dir in apps/*/; do
                if [ -d "$app_dir" ]; then
                    app_name=$(basename "$app_dir")
                    if [ -f "$app_dir/pubspec.yaml" ]; then
                        print_info "  📱 $app_name"
                    else
                        add_warning "  📱 $app_name (missing pubspec.yaml)"
                    fi
                fi
            done
        else
            add_warning "No apps found in apps/ directory"
        fi
    fi

    echo ""
    print_header "Configuration Files"

    # Check important configuration files
    CONFIG_FILES=(
        "melos.yaml:Monorepo configuration"
        "codemagic.yaml:CI/CD configuration"
        ".github/workflows/ci.yml:GitHub Actions CI"
        ".github/workflows/publish-packages.yml:Package publishing"
        "scripts/release.sh:Release management"
        "DEPLOYMENT.md:Deployment documentation"
    )

    for config in "${CONFIG_FILES[@]}"; do
        file="${config%%:*}"
        description="${config##*:}"

        if [ -f "$file" ]; then
            print_success "$description: $file"
        else
            add_warning "Missing $description: $file"
        fi
    done

    echo ""
    print_header "Development Environment"

    # Check if project is bootstrapped
    if [ -d ".dart_tool" ] && [ -f ".dart_tool/package_config.json" ]; then
        print_success "Project appears to be bootstrapped"
    else
        add_warning "Project may not be bootstrapped. Run 'melos bootstrap' to set up dependencies."
    fi

    # Check for common IDE files
    if [ -d ".vscode" ] || [ -d ".idea" ] || [ -f "*.iml" ]; then
        print_success "IDE configuration detected"
    else
        print_info "No IDE configuration detected (this is optional)"
    fi

    echo ""
    print_header "Network and Connectivity"

    # Check internet connection
    if ping -c 1 google.com >/dev/null 2>&1; then
        print_success "Internet connection is available"
    else
        add_warning "No internet connection detected. Some operations may fail."
    fi

    # Check pub.dev connectivity
    if command_exists curl; then
        if curl -s --head "https://pub.dev" | head -n 1 | grep -q "200 OK"; then
            print_success "pub.dev is accessible"
        else
            add_warning "Cannot reach pub.dev. Package operations may fail."
        fi
    fi

    echo ""
    print_header "Android Development Setup"

    # Check Java
    if command_exists java; then
        JAVA_VERSION=$(java -version 2>&1 | head -1 | cut -d'"' -f2 | cut -d'.' -f1-2)
        print_success "Java installed: v$JAVA_VERSION"
    else
        add_warning "Java not found. Required for Android development."
    fi

    # Check Gradle
    if command_exists gradle; then
        GRADLE_VERSION=$(gradle --version 2>&1 | grep "Gradle" | head -1 | grep -oE '[0-9]+\.[0-9]+')
        print_success "Gradle installed: v$GRADLE_VERSION"
    else
        print_info "Gradle not found globally (Flutter includes its own)"
    fi

    # Check keystore setup for app signing
    KEYSTORE_EXAMPLE="apps/gossip_chat/android/key.properties.example"
    KEYSTORE_ACTUAL="apps/gossip_chat/android/key.properties"

    if [ -f "$KEYSTORE_EXAMPLE" ]; then
        print_success "Keystore example file found"
        if [ -f "$KEYSTORE_ACTUAL" ]; then
            print_success "App signing keystore configured"
        else
            add_warning "App signing not configured. Copy $KEYSTORE_EXAMPLE to key.properties and configure for releases."
        fi
    else
        add_warning "Keystore example file missing"
    fi

    echo ""
    print_header "Verification Summary"

    # Print summary
    TOTAL_CHECKS=$((ERRORS + WARNINGS))

    if [ $ERRORS -eq 0 ] && [ $WARNINGS -eq 0 ]; then
        print_color $GREEN "🎉 All checks passed! Your development environment is ready."
    elif [ $ERRORS -eq 0 ]; then
        print_color $YELLOW "⚠️ Setup complete with $WARNINGS warning(s). Most functionality will work."
    else
        print_color $RED "❌ Setup incomplete. Found $ERRORS error(s) and $WARNINGS warning(s)."
        echo ""
        print_color $RED "Please fix the errors above before proceeding."
    fi

    echo ""
    print_header "Next Steps"

    if [ $ERRORS -eq 0 ]; then
        print_color $GREEN "Recommended next steps:"
        echo ""
        echo "1. 📦 Bootstrap the project:"
        echo "   melos bootstrap"
        echo ""
        echo "2. 🧪 Run tests to verify everything works:"
        echo "   melos run test"
        echo ""
        echo "3. 🔍 Check code quality:"
        echo "   melos run analyze"
        echo ""
        echo "4. 📱 Try running the demo app:"
        echo "   cd apps/gossip_chat && flutter run"
        echo ""
        echo "5. 📚 Read the deployment guide:"
        echo "   cat DEPLOYMENT.md"
    else
        print_color $RED "Please fix the errors above first, then:"
        echo ""
        echo "1. Run this script again: ./scripts/verify-setup.sh"
        echo "2. Check the project README: cat README.md"
        echo "3. Review the deployment guide: cat DEPLOYMENT.md"
    fi

    echo ""
    print_color $BLUE "For help and documentation:"
    echo "• Project README: README.md"
    echo "• Deployment Guide: DEPLOYMENT.md"
    echo "• Release Script: ./scripts/release.sh --help"
    echo "• GitHub Issues: https://github.com/da1nerd/gossip-mono/issues"

    # Return appropriate exit code
    if [ $ERRORS -gt 0 ]; then
        exit 1
    else
        exit 0
    fi
}

# Run main function
main "$@"
