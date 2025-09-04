# 🚀 Setup Checklist

This checklist helps you verify that everything is properly configured for the Gossip Monorepo deployment pipeline.

## ✅ Prerequisites

### Development Environment
- [ ] **Flutter SDK** (stable channel, >= 3.16.0) installed
- [ ] **Dart SDK** (>= 3.0.0) installed
- [ ] **Git** installed and configured
- [ ] **Melos** package manager installed (`dart pub global activate melos`)
- [ ] **Android SDK** installed (for app development)
- [ ] **Java/JDK** installed (for Android builds)

### Accounts & Services
- [ ] **GitHub** account with repository access
- [ ] **pub.dev** account for package publishing
- [ ] **Google Play Console** account for app deployment
- [ ] **Codemagic** account for CI/CD

## 📦 Package Publishing Setup

### pub.dev Configuration
- [ ] Logged into pub.dev: `dart pub token add https://pub.dev`
- [ ] Copied credentials from `~/.pub-cache/credentials.json`
- [ ] Added `PUB_CREDENTIALS` secret to GitHub repository
- [ ] Verified all packages have proper metadata in `pubspec.yaml`:
  - [ ] `gossip` package updated
  - [ ] `gossip_crdts` package updated
  - [ ] `gossip_event_sourcing` package updated
  - [ ] `gossip_typed_events` package updated

### GitHub Actions Setup
- [ ] Repository secrets configured:
  - [ ] `PUB_CREDENTIALS` (pub.dev authentication JSON)
- [ ] GitHub Actions workflows present:
  - [ ] `.github/workflows/ci.yml`
  - [ ] `.github/workflows/publish-packages.yml`
  - [ ] `.github/workflows/release.yml`
- [ ] Branch protection rules enabled for `main` branch

## 📱 App Deployment Setup

### Android Signing
- [ ] Generated release keystore: `gossip-chat-release-key.keystore`
- [ ] Created `apps/gossip_chat/android/key.properties` (from template)
- [ ] **Never committed keystore or key.properties to git!**
- [ ] Updated `android/app/build.gradle.kts` with signing config
- [ ] Created `proguard-rules.pro` for release optimization

### Google Play Console
- [ ] Created app in Google Play Console
- [ ] Generated service account in Google Cloud Console
- [ ] Downloaded service account JSON key file
- [ ] Enabled Google Play Developer API
- [ ] Granted service account permissions in Play Console
- [ ] Added app to internal testing track

### Codemagic Configuration
- [ ] Connected GitHub repository to Codemagic
- [ ] Uploaded Android keystore to Codemagic
- [ ] Set keystore reference name as `keystore_reference`
- [ ] Created environment variable group `google_play`
- [ ] Added `GCLOUD_SERVICE_ACCOUNT_CREDENTIALS` with service account JSON
- [ ] Updated email notification addresses in `codemagic.yaml`
- [ ] Verified `codemagic.yaml` configuration

## 🧪 Testing & Validation

### Local Testing
- [ ] Run verification script: `./scripts/verify-setup.sh`
- [ ] Bootstrap project: `melos bootstrap`
- [ ] Run all tests: `melos run test`
- [ ] Check code quality: `melos run analyze`
- [ ] Verify formatting: `melos run format`
- [ ] Test package publishing (dry run): `melos run publish-dry-run`

### App Testing
- [ ] Build debug APK: `cd apps/gossip_chat && flutter build apk --debug`
- [ ] Test on physical Android devices (2+ devices required)
- [ ] Verify P2P messaging works offline
- [ ] Test permissions flow on different Android versions

### CI/CD Testing
- [ ] Create test pull request to trigger CI
- [ ] Verify GitHub Actions run successfully
- [ ] Test Codemagic build (without publishing)
- [ ] Verify all environment variables are accessible

## 🚀 Deployment Verification

### Package Publishing Pipeline
- [ ] Make test change to a package
- [ ] Push to `main` branch
- [ ] Verify GitHub Actions detects package changes
- [ ] Confirm packages publish to pub.dev
- [ ] Check pub.dev package pages for updates

### App Deployment Pipeline
- [ ] Update app version in `pubspec.yaml`
- [ ] Push to `main` branch
- [ ] Verify Codemagic triggers build
- [ ] Confirm AAB uploads to Play Store internal track
- [ ] Check Play Console for successful upload

## 🔐 Security Checklist

### Secrets Management
- [ ] All sensitive files are in `.gitignore`
- [ ] No secrets committed to repository
- [ ] Environment variables properly secured
- [ ] Service account has minimal required permissions

### Files to Never Commit
- [ ] `apps/gossip_chat/android/key.properties`
- [ ] `apps/gossip_chat/android/*.keystore`
- [ ] `apps/gossip_chat/android/*.jks`
- [ ] `~/.pub-cache/credentials.json`
- [ ] Any Google Cloud service account JSON files

## 📋 Final Steps

### Documentation
- [ ] Updated README.md with project information
- [ ] Reviewed DEPLOYMENT.md for completeness
- [ ] Updated package README files
- [ ] Added CHANGELOG entries if needed

### Team Setup
- [ ] Shared setup instructions with team members
- [ ] Documented custom configurations
- [ ] Set up monitoring and alerts
- [ ] Planned release schedule and process

## 🆘 Troubleshooting

If you encounter issues, check these common problems:

### Package Publishing Issues
- [ ] Verify `PUB_CREDENTIALS` secret is correct
- [ ] Check package versions are incremented
- [ ] Ensure all tests pass
- [ ] Verify package metadata is complete

### App Build Issues
- [ ] Check Android SDK is properly installed
- [ ] Verify keystore file exists and is accessible
- [ ] Ensure all required permissions are in AndroidManifest.xml
- [ ] Run `flutter doctor -v` to check setup

### CI/CD Issues
- [ ] Check GitHub Actions logs for specific errors
- [ ] Verify all environment variables are set
- [ ] Ensure branch protection rules allow workflows
- [ ] Check Codemagic logs and configuration

## 🎯 Success Criteria

You've successfully completed setup when:

- ✅ All tests pass locally and in CI
- ✅ Packages automatically publish when changed
- ✅ App automatically builds and deploys to Play Store
- ✅ No secrets are committed to repository
- ✅ Team members can follow the same process
- ✅ Documentation is complete and accurate

## 📞 Support

If you need help:

1. **Run the verification script**: `./scripts/verify-setup.sh`
2. **Check the logs**: GitHub Actions, Codemagic, local terminal
3. **Review documentation**: README.md, DEPLOYMENT.md
4. **Create an issue**: GitHub repository issues
5. **Check common solutions**: Troubleshooting sections in docs

---

**🎉 Once all items are checked, you're ready to deploy!**

Use these commands to get started:

```bash
# Verify everything is working
./scripts/verify-setup.sh

# Run a full release process
./scripts/release.sh full

# Or trigger individual operations
melos run publish-dry-run    # Test package publishing
melos run app-build-aab      # Test app building
```
