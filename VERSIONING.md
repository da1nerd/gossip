# 🔢 Version Management Strategy

This document outlines the centralized version management strategy used in the Gossip Protocol monorepo.

## 🚀 Usage

```bash
# Increment patch version (1.2.3 → 1.2.4)
melos run version-patch

# Increment minor version (1.2.3 → 1.3.0)
melos run version-minor

# Increment major version (1.2.3 → 2.0.0)
melos run version-major

# Test version update with backup/restore
melos run version-test

# 🔄 Alternative: Version all packages to same version
dart run melos run version-all-patch

# 📊 Show current versions
dart run melos list
```

## 📋 Release Process

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
