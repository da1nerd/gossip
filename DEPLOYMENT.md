# 📦 Deployment Guide

This guide covers the complete setup and deployment process for the Gossip Monorepo, including package publishing to pub.dev and app deployment to the Google Play Store.

## 🏗️ Project Structure

```
gossip-mono/
├── packages/                    # Dart packages for pub.dev
│   ├── gossip/                 # Core gossip protocol library
│   ├── gossip_crdts/          # CRDT extensions
│   ├── gossip_event_sourcing/ # Event sourcing library
│   └── gossip_typed_events/   # Type-safe event extensions
├── apps/
│   └── gossip_chat/           # Flutter chat demo app
├── .github/workflows/         # GitHub Actions
├── codemagic.yaml            # Codemagic CI/CD config
└── melos.yaml               # Monorepo management
```

## 🚀 Quick Start

### Prerequisites

1. **Flutter SDK** (stable channel)
2. **Dart SDK** (>=3.0.0)
3. **Melos** package manager
4. **GitHub** account with repository access
5. **pub.dev** account for package publishing
6. **Google Play Console** account for app deployment
7. **Codemagic** account for CI/CD

### Initial Setup

```bash
# Clone the repository
git clone https://github.com/yourusername/gossip-mono.git
cd gossip-mono

# Install Melos
dart pub global activate melos

# Bootstrap the project
melos bootstrap

# Run tests to verify setup
melos run test
```

## 📱 App Deployment to Play Store

The Flutter app is automatically deployed to Google Play Store via **Codemagic** when changes are merged to the `main` branch.

### 1. Android Signing Setup

#### Generate Release Keystore

```bash
cd apps/gossip_chat/android
keytool -genkey -v -keystore gossip-chat-release-key.keystore \
  -alias gossip-chat -keyalg RSA -keysize 2048 -validity 10000
```

#### Create Key Properties File

Create `apps/gossip_chat/android/key.properties`:

```properties
storePassword=YOUR_KEYSTORE_PASSWORD
keyPassword=YOUR_KEY_PASSWORD
keyAlias=gossip-chat
storeFile=../gossip-chat-release-key.keystore
```

**⚠️ Never commit `key.properties` or keystore files to version control!**

### 2. Google Play Console Setup

1. **Create App**: Go to Google Play Console and create a new app
2. **Generate Service Account**:
   - Go to Google Cloud Console
   - Create a new service account
   - Download the JSON key file
   - Enable Google Play Developer API

3. **Grant Permissions**:
   - In Play Console, go to Settings → API access
   - Link your service account
   - Grant necessary permissions (Release Manager or higher)

### 3. Codemagic Configuration

#### Environment Variables in Codemagic

1. **Android Signing**:
   - Upload your keystore file
   - Set keystore reference name as `keystore_reference`

2. **Google Play Publishing** (Environment Group: `google_play`):
   ```
   GCLOUD_SERVICE_ACCOUNT_CREDENTIALS = <paste your service account JSON content>
   ```

3. **Email Notifications**:
   - Update email addresses in `codemagic.yaml`

#### Workflow Triggers

- **Production Release**: Push to `main` branch
- **Debug Build**: Pull requests (builds APK for testing)

### 4. App Release Process

```bash
# 1. Update app version
cd apps/gossip_chat
# Edit pubspec.yaml version field

# 2. Test locally
flutter test
flutter build appbundle --release

# 3. Commit and push to main
git add .
git commit -m "Release v1.0.2"
git push origin main

# 4. Codemagic will automatically:
#    - Build release AAB
#    - Upload to Play Store (internal track)
#    - Send notification email
```

## 📦 Package Publishing to pub.dev

Dart packages are automatically published to pub.dev via **GitHub Actions** when package changes are detected in the `main` branch.

### 1. pub.dev Account Setup

#### Get Publishing Credentials

```bash
# Login to pub.dev
dart pub token add https://pub.dev

# Copy credentials (needed for GitHub secrets)
cat ~/.pub-cache/credentials.json
```

#### GitHub Repository Secrets

Add the following secret in GitHub Settings → Secrets and variables → Actions:

- **`PUB_CREDENTIALS`**: Content of your `~/.pub-cache/credentials.json`

### 2. Package Publishing Workflow

The workflow automatically:
- Detects changes in `packages/` directory
- Runs pre-publish checks (tests, analysis, formatting)
- Publishes updated packages to pub.dev
- Creates release summary

#### Manual Package Operations

```bash
# Check what would be published
melos run publish-dry-run

# Run pre-publish checks
melos run pre-publish-check

# Manually publish all packages
melos run publish-packages

# Version bump all packages
melos version --all --no-private
```

### 3. Package Release Process

```bash
# 1. Make changes to packages
cd packages/gossip
# Edit your code...

# 2. Update version in pubspec.yaml
# version: 1.0.2

# 3. Test the package
dart test
dart pub publish --dry-run

# 4. Commit and push
git add .
git commit -m "feat(gossip): add new vector clock feature"
git push origin main

# 5. GitHub Actions will automatically:
#    - Detect package changes
#    - Run tests and validation
#    - Publish to pub.dev
#    - Create release summary
```

## 🔧 Development Workflow

### Branch Strategy

```
main                 # Production branch - triggers deployments
├── develop         # Integration branch
├── feature/xyz     # Feature branches
└── hotfix/abc     # Emergency fixes
```

### Conventional Commits

This project uses [Conventional Commits](https://www.conventionalcommits.org/) for standardized commit messages and automated changelog generation.

#### Commit Message Format

```
<type>(<scope>): <description>

[optional body]

[optional footer(s)]
```

#### Types

| Type | Description | Changelog Section |
|------|-------------|------------------|
| `feat` | A new feature | Features |
| `fix` | A bug fix | Bug Fixes |
| `docs` | Documentation only changes | Documentation |
| `style` | Changes that don't affect code meaning (whitespace, formatting) | - |
| `refactor` | Code change that neither fixes a bug nor adds a feature | Code Refactoring |
| `perf` | Performance improvements | Performance |
| `test` | Adding missing tests or correcting existing tests | Tests |
| `build` | Changes affecting build system or external dependencies | Build System |
| `ci` | Changes to CI configuration files and scripts | CI |
| `chore` | Other changes that don't modify src or test files | Maintenance |
| `revert` | Reverts a previous commit | Reverts |

#### Scopes

Use one of these scopes to specify which part of the project is affected:

**Packages:**
- `gossip` - Core gossip protocol library
- `gossip_crdts` - CRDT extensions package
- `gossip_event_sourcing` - Event sourcing library
- `gossip_typed_events` - Type-safe events package

**Apps:**
- `chat` - Gossip chat demo app
- `app` - General app-related changes

**Infrastructure:**
- `ci` - Continuous integration
- `deps` - Dependencies
- `config` - Configuration files
- `docs` - Documentation
- `release` - Release management

#### Examples

```bash
# Features
git commit -m "feat(gossip): add vector clock synchronization"
git commit -m "feat(chat): implement P2P message encryption"
git commit -m "feat(gossip_crdts): add G-Counter CRDT implementation"

# Bug fixes
git commit -m "fix(gossip): resolve race condition in event ordering"
git commit -m "fix(chat): prevent duplicate messages in UI"
git commit -m "fix(gossip_event_sourcing): handle projection rebuild errors"

# Documentation
git commit -m "docs(gossip): add vector clock usage examples"
git commit -m "docs: update deployment guide with new steps"
git commit -m "docs(chat): add P2P testing instructions"

# Refactoring
git commit -m "refactor(gossip): extract transport interface"
git commit -m "refactor(chat): reorganize service layer architecture"

# Performance
git commit -m "perf(gossip): optimize event batching algorithm"
git commit -m "perf(chat): reduce memory usage in message store"

# Tests
git commit -m "test(gossip): add integration tests for anti-entropy"
git commit -m "test(chat): add P2P connection reliability tests"

# Build system
git commit -m "build(deps): upgrade Flutter to 3.16.0"
git commit -m "build: add ProGuard rules for release builds"

# CI/CD
git commit -m "ci: add automated package publishing workflow"
git commit -m "ci: configure Codemagic for Play Store deployment"

# Maintenance
git commit -m "chore: update copyright notices"
git commit -m "chore(deps): bump dependency versions"
git commit -m "chore(release): prepare v1.2.0"

# Breaking changes (add ! after type/scope)
git commit -m "feat(gossip)!: change API signature for createEvent"
git commit -m "refactor(chat)!: rename service methods for consistency"

# Multi-line commits with body and footer
git commit -m "feat(gossip): implement event compression

This reduces network bandwidth usage by 60% during
gossip exchanges between peers.

Closes #123
Co-authored-by: John Doe <john@example.com>"
```

#### Breaking Changes

For breaking changes, add `!` after the type/scope:

```bash
git commit -m "feat(gossip)!: change vector clock API"
git commit -m "refactor(chat)!: restructure service initialization"
```

Or use the footer:

```bash
git commit -m "feat(gossip): add new sync algorithm

BREAKING CHANGE: The syncEvents method signature has changed.
See migration guide for details."
```

### Recommended Workflow

1. **Create Feature Branch**:
   ```bash
   git checkout -b feature/new-gossip-feature
   ```

2. **Make Changes**:
   ```bash
   # Work on packages or app
   melos run test        # Run tests
   melos run analyze     # Check code quality
   melos run format      # Format code
   ```

3. **Commit with Conventional Format**:
   ```bash
   git add .
   git commit -m "feat(gossip): add new vector clock feature"
   ```

4. **Create Pull Request**:
   - CI runs automatically
   - Code review required
   - All checks must pass

5. **Merge to Main**:
   - Triggers deployments
   - App builds and deploys to Play Store
   - Packages publish to pub.dev (if changed)
   - Changelog generated from commit messages

### Local Development Commands

```bash
# Bootstrap project (run after git clone or pull)
melos bootstrap

# Run all tests
melos run test

# Analyze all packages
melos run analyze

# Format all code
melos run format

# Build debug APK
melos run app-build-apk

# Build release AAB
melos run app-build-aab

# Clean all packages
melos clean

# Check for outdated dependencies
melos run outdated

# Get dependencies for all packages
melos run get-all

# Upgrade all dependencies
melos run upgrade-all
```

## 🐛 Troubleshooting

### Common Issues

#### App Build Failures

```bash
# Clear Flutter cache
flutter clean
cd apps/gossip_chat && flutter clean

# Regenerate dependencies
melos clean && melos bootstrap

# Check Android setup
flutter doctor -v
```

#### Package Publishing Issues

```bash
# Validate package before publishing
cd packages/gossip
dart pub publish --dry-run

# Check pub.dev credentials
dart pub token list

# Re-authenticate if needed
dart pub token add https://pub.dev
```

#### Codemagic Build Issues

1. Check build logs in Codemagic dashboard
2. Verify environment variables are set correctly
3. Ensure keystore is properly uploaded
4. Check Google Play Console permissions

#### GitHub Actions Issues

1. Check workflow logs in Actions tab
2. Verify `PUB_CREDENTIALS` secret is set
3. Ensure branch protection rules allow workflow runs
4. Check package versions are incremented

### Debug Commands

```bash
# Check package dependency tree
melos deps-check

# List all packages
melos list

# Check package publish status
melos run publish-dry-run

# View package information
cd packages/gossip && dart pub deps
```

## 🔐 Security Considerations

### Secrets Management

- **Never commit**: keystores, credentials, API keys
- **Use environment variables**: for sensitive configuration
- **Rotate credentials**: regularly update tokens and keys
- **Limit permissions**: use minimal required permissions

### Files to Keep Secure

```
# Never commit these files:
apps/gossip_chat/android/key.properties
apps/gossip_chat/android/*.keystore
apps/gossip_chat/android/*.jks
~/.pub-cache/credentials.json
google-services.json (if using Firebase)
```

## 📊 Monitoring and Analytics

### Build Monitoring

- **Codemagic**: Build status and logs
- **GitHub Actions**: Workflow execution logs
- **Play Console**: App release status and metrics
- **pub.dev**: Package download statistics

### Useful Dashboards

1. **Codemagic Apps Dashboard**: Build history and status
2. **GitHub Repository Insights**: Code activity and PRs
3. **Play Console Analytics**: App performance and user metrics
4. **pub.dev Package Pages**: Download stats and popularity

## 🆘 Support and Resources

### Documentation

- [Melos Documentation](https://melos.invertase.dev/)
- [Codemagic Flutter Docs](https://docs.codemagic.io/flutter/)
- [pub.dev Publishing Guide](https://dart.dev/tools/pub/publishing)
- [Flutter Android Deployment](https://docs.flutter.dev/deployment/android)

### Community

- **GitHub Issues**: Report bugs and feature requests
- **Discussions**: Ask questions and share ideas
- **Discord/Slack**: Real-time community chat

### Emergency Contacts

- **Repository Maintainer**: @yourusername
- **DevOps Lead**: Contact for CI/CD issues
- **Security Issues**: security@yourcompany.com

---

## 📝 Changelog

### v1.0.1 - 2025-01-XX
- ✅ Initial deployment setup
- ✅ Automated package publishing
- ✅ Codemagic Play Store integration
- ✅ GitHub Actions CI/CD

### Next Steps
- [ ] Add iOS deployment
- [ ] Implement semantic versioning automation
- [ ] Add performance monitoring
- [ ] Set up crash reporting

---

**Last Updated**: January 2025  
**Next Review**: February 2025