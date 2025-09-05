# 🔢 Version Management Strategy

This document outlines the centralized version management strategy used in the Gossip Protocol monorepo.

## 📋 Overview

The monorepo uses a **centralized versioning approach** where:

- 🎯 The root `pubspec.yaml` version is the **single source of truth**
- 📦 All packages in `/packages/` follow this version exactly
- 🔗 Internal package dependencies are automatically synchronized
- 📱 The app uses independent versioning for Play Store deployment
- 🏷️ GitHub releases are tagged with the package version

## 🏗️ Architecture

### Before (Old Approach)
- ❌ Each package had its own version
- ❌ Manual coordination required between packages
- ❌ Inconsistent dependency versions
- ❌ Complex release workflows with multiple version flags

### After (New Approach)
- ✅ Single version source in root `pubspec.yaml`
- ✅ Automatic synchronization of all packages
- ✅ Consistent internal dependencies
- ✅ Simplified release workflow

## 📂 Version Management Structure

```
gossip-mono/
├── pubspec.yaml                    # 🎯 SOURCE OF TRUTH (v1.2.3)
├── packages/
│   ├── gossip/pubspec.yaml        # 📦 Follows root (v1.2.3)
│   ├── gossip_crdts/pubspec.yaml  # 📦 Follows root (v1.2.3)
│   └── ...                        # 📦 All packages match
├── apps/
│   └── gossip_chat/pubspec.yaml   # 📱 Independent (v1.2.3+42)
└── scripts/
    ├── update_versions.sh          # 🔧 Version update script
    └── test_version_update.sh      # 🧪 Testing script
```

## 🚀 Usage

### Automated Release (GitHub Actions)

The recommended approach for production releases:

```bash
# Trigger release workflow
gh workflow run release.yml \
  -f release_type=patch \
  -f publish_packages=true \
  -f create_release=true
```

Or use the GitHub web interface:
1. Go to **Actions** → **Release Management**
2. Click **Run workflow**
3. Select release type (patch/minor/major)
4. Configure publishing options

### Local Development

#### Quick Commands via Melos

```bash
# Increment patch version (1.2.3 → 1.2.4)
melos run version-patch

# Increment minor version (1.2.3 → 1.3.0)  
melos run version-minor

# Increment major version (1.2.3 → 2.0.0)
melos run version-major

# Test version update with backup/restore
melos run version-test
```

#### Manual Scripts

```bash
# Test version update (with backup)
./scripts/test_version_update.sh test minor

# Direct version update  
./scripts/update_versions.sh patch

# Show current versions
./scripts/test_version_update.sh show

# Restore from backup
./scripts/test_version_update.sh restore
```

## 🔧 How It Works

### 1. Version Reading & Increment

```bash
# Read current version from root pubspec.yaml
current_version=$(grep "^version:" pubspec.yaml | sed 's/version: //' | xargs)

# Increment based on release type
case "$release_type" in
    "major") new_version="$((major + 1)).0.0" ;;
    "minor") new_version="$major.$((minor + 1)).0" ;;  
    "patch") new_version="$major.$minor.$((patch + 1))" ;;
esac
```

### 2. Package Version Synchronization

```bash
# Update all package pubspec.yaml files
for pubspec_file in packages/*/pubspec.yaml; do
    sed -i "s/^version: .*/version: $new_version/" "$pubspec_file"
done
```

### 3. Internal Dependency Updates

```bash
# Update dependencies between monorepo packages
for package_name in $internal_packages; do
    sed -i "s/^  $package_name: .*/  $package_name: ^$new_version/" pubspec.yaml
done
```

### 4. App Version Strategy

The app (`gossip_chat`) uses a **hybrid approach**:

- **Base version**: Follows the package version (e.g., `1.2.3`)
- **Build number**: Independent increment for Play Store (e.g., `+42`)
- **Result**: App version becomes `1.2.3+42`

This allows:
- ✅ Version consistency with packages
- ✅ Independent build numbering for app stores
- ✅ Proper semantic versioning

## 📋 Release Process

### Automated Workflow Steps

1. **🔍 Pre-checks**: Run tests, analysis, and formatting
2. **🔢 Version Update**: Increment root version, sync all packages  
3. **🔗 Dependency Sync**: Update internal package references
4. **📱 App Update**: Update app with new base version + build increment
5. **💾 Commit**: Create commit with version changes
6. **📦 Publish**: Publish all packages to pub.dev
7. **🏷️ Release**: Create GitHub release with changelog
8. **🚀 Deploy**: Codemagic automatically deploys app

### Manual Process

If you need to release manually:

```bash
# 1. Update versions
./scripts/update_versions.sh patch

# 2. Bootstrap dependencies  
melos bootstrap

# 3. Run validation
melos run pre-publish-check

# 4. Commit changes
git add .
git commit -m "chore: release v$(grep '^version:' pubspec.yaml | sed 's/version: //')"

# 5. Publish packages
melos run publish-packages

# 6. Push and tag
git push origin main
git tag "v$(grep '^version:' pubspec.yaml | sed 's/version: //')"
git push --tags
```

## 🧪 Testing & Validation

### Local Testing

The `test_version_update.sh` script provides safe testing:

```bash
# Test with automatic backup/restore
./scripts/test_version_update.sh test minor

# Options after test:
# 1. Keep changes and run melos bootstrap
# 2. Restore backup (undo all changes)  
# 3. Exit and decide later
```

### Validation Steps

The system automatically validates:

- ✅ Version format (semantic versioning)
- ✅ Package dependency consistency
- ✅ No circular dependencies
- ✅ All packages have valid versions
- ✅ Internal dependencies use compatible versions

## 🎯 Benefits

### For Developers

- 🚀 **Simplified releases**: Single command updates everything
- 🔒 **Consistency**: No version drift between packages
- 🧪 **Safe testing**: Backup/restore for local experiments
- 📊 **Visibility**: Clear version status across entire monorepo

### For Users

- 📦 **Predictable versions**: All packages release together
- 🔗 **Compatible dependencies**: No version conflicts
- 📈 **Clear releases**: Single version number per release
- 🏷️ **Easy tracking**: GitHub releases match package versions

### For CI/CD

- ⚡ **Fast releases**: Automated version coordination
- 🛡️ **Fewer errors**: No manual version management
- 📋 **Complete releases**: All packages updated atomically
- 🔄 **Rollback friendly**: Single commit contains all changes

## 🔄 Migration Guide

### From Manual Versioning

If you have packages with different versions:

1. **Choose target version**: Usually the highest existing version
2. **Update root**: Set `version:` in root `pubspec.yaml`
3. **Run sync**: `./scripts/update_versions.sh patch` (no increment)
4. **Test**: `melos bootstrap && melos run test`
5. **Commit**: Version synchronization commit

### From Melos `--patch/--minor/--major`

Replace old workflow steps:

```yaml
# OLD - Don't use anymore
- name: Version packages
  run: melos version --patch --no-private

# NEW - Use centralized approach  
- name: Update versions
  run: ./scripts/update_versions.sh patch
```

## 🚨 Important Notes

### Package Exclusions

- ✅ **Included**: All packages in `/packages/`
- ❌ **Excluded**: App in `/apps/` (uses independent versioning)
- ❌ **Excluded**: Root workspace (not publishable)

### Version Constraints

- **Internal dependencies**: Use `^1.2.3` (caret constraints)
- **External dependencies**: Follow package's existing constraints  
- **SDK constraints**: Remain unchanged during version updates

### Breaking Changes

When making breaking changes:

1. **Use major version**: `melos run version-major`
2. **Update documentation**: Reflect breaking changes
3. **Migration guide**: Help users upgrade
4. **Announcement**: Notify users via release notes

## 🛠️ Troubleshooting

### Common Issues

**"Version not found in pubspec.yaml"**
- Ensure root `pubspec.yaml` has a `version:` field
- Check file format and indentation

**"Melos bootstrap fails"**  
- Run `./scripts/update_versions.sh patch` to fix dependencies
- Check for circular dependencies

**"Git conflicts during release"**
- Ensure working directory is clean before running scripts
- Use `git stash` if you have uncommitted changes

**"Package publishing fails"**
- Verify pub.dev credentials: `dart pub token list`
- Check package names don't conflict with existing packages
- Ensure all packages pass `dart pub publish --dry-run`

### Debug Commands

```bash
# Show current state
./scripts/test_version_update.sh show

# Check dependencies
melos list --parsable --json | jq '.'

# Validate packages
melos run publish-dry-run

# Check git status
git status
git diff
```

## 📚 References

- [Semantic Versioning](https://semver.org/) - Version numbering standard
- [Melos](https://melos.invertase.dev/) - Monorepo management tool
- [pub.dev Publishing](https://dart.dev/tools/pub/publishing) - Package publishing guide
- [GitHub Actions](https://docs.github.com/en/actions) - CI/CD automation

---

**🎯 Key Takeaway**: One version to rule them all! The root `pubspec.yaml` is your single source of truth for package versioning.