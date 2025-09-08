# 🔢 Version Management Strategy

This document outlines the centralized version management strategy used in the Gossip Protocol monorepo.

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
## 🚀 Quick Commands

```bash
# 🎯 Smart versioning - updates base package + all dependencies automatically
dart run melos run version-patch   # Patch version (1.0.0 → 1.0.1)
dart run melos run version-minor   # Minor version (1.0.0 → 1.1.0)
dart run melos run version-major   # Major version (1.0.0 → 2.0.0)

# 🔄 Alternative: Version all packages to same version
dart run melos run version-all-patch

# 📊 Show current versions
dart run melos list
```

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
# 1. Update versions (automatic dependency management!)
dart run melos run version-patch

# 2. Run validation
dart run melos run pre-publish-check

# 3. Commit changes (if needed - versioning may auto-commit)
git add .
git commit -m "chore: release packages"

# 4. Publish packages
dart run melos run publish-packages

# 5. Push and tag
git push origin main
git tag "v$(grep '^version:' pubspec.yaml | sed 's/version: //')"
git push --tags
```

## 🛠️ Troubleshooting

### Common Issues

**"Melos bootstrap fails"**
- Run `dart run melos run version-patch` to sync versions and dependencies

### Debug Commands

```bash
# Check for circular dependencies
melos list --graph

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
