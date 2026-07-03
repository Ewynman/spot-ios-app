# Firebase App Distribution Setup Guide

This guide explains how to set up the GitHub Secrets required for automated Firebase App Distribution builds.

## Overview

The deployment workflow (`.github/workflows/deploy.yml`) requires several secrets to be configured in your GitHub repository. This guide will walk you through obtaining and setting up each one.

---

## Firebase Information (Already Configured)

✅ **Firebase Project ID**: `spot-a6a75`  
✅ **Firebase App ID**: `1:415359921164:ios:66b52b0b2c5f0f2eb59229`  
✅ **Bundle ID**: `com.edwardwynman.Spot`  
✅ **Team ID**: `55JK72KR4W`

---

## Required GitHub Secrets

Navigate to your repository: **Settings** → **Secrets and variables** → **Actions** → **New repository secret**

### 1. FIREBASE_APP_ID

**Value**: `1:415359921164:ios:66b52b0b2c5f0f2eb59229`

This is the Firebase iOS App ID from your Firebase project.

---

### 2. FIREBASE_SERVICE_ACCOUNT_JSON

**What it is**: A service account key for Firebase authentication.

**How to get it**:

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select project: `spot`
3. Click the gear icon → **Project settings**
4. Go to **Service accounts** tab
5. Click **Generate new private key**
6. Download the JSON file
7. Copy the **entire contents** of the JSON file
8. Paste as the secret value (it should look like):
   ```json
   {
     "type": "service_account",
     "project_id": "spot-a6a75",
     "private_key_id": "...",
     "private_key": "-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----\n",
     "client_email": "firebase-adminsdk-xxxxx@spot-a6a75.iam.gserviceaccount.com",
     ...
   }
   ```

---

### 3. GOOGLE_SERVICE_INFO_PLIST_BASE64

**What it is**: Your Firebase configuration file (`GoogleService-Info.plist`) encoded in base64. This file is required for the app to initialize Firebase services (Analytics, Crashlytics, App Check).

**How to get it**:

#### Step 1: Download GoogleService-Info.plist

1. Go to [Firebase Console](https://console.firebase.google.com/)
2. Select project: `spot-a6a75`
3. Click the gear icon → **Project settings**
4. Scroll down to **Your apps** section
5. Find the iOS app: `com.edwardwynman.Spot`
6. Click **Download GoogleService-Info.plist**
7. Save the file to your computer

#### Step 2: Convert to Base64

```bash
cd ~/Downloads  # or wherever you saved the plist
base64 -i GoogleService-Info.plist | pbcopy
# The base64 string is now in your clipboard
```

#### Step 3: Add to GitHub Secrets

- Secret name: `GOOGLE_SERVICE_INFO_PLIST_BASE64`
- Secret value: Paste from clipboard (should be a long string of letters and numbers)

**Why this is needed**: The app calls `FirebaseApp.configure()` on launch, which requires `GoogleService-Info.plist` to be present. Without this file, the app will crash immediately on startup. This file is excluded from the repository via `.gitignore` for security reasons, so it must be injected during the CI build process.

---

### 4. APPLE_CERTIFICATE_BASE64

**What it is**: Your Apple Distribution certificate exported as a .p12 file and encoded in base64.

**How to get it**:

#### Step 1: Export Certificate from Keychain (on Mac)

```bash
# 1. Open Keychain Access app
# 2. Select "login" keychain
# 3. Select "My Certificates" category
# 4. Find "Apple Distribution: Edward Wynman (55JK72KR4W)" or similar
# 5. Right-click → Export "Apple Distribution..."
# 6. Save as: Certificates.p12
# 7. Set a password (remember this for next step!)
```

#### Step 2: Convert to Base64

```bash
# In Terminal:
cd ~/Downloads  # or wherever you saved the .p12
base64 -i Certificates.p12 | pbcopy
# The base64 string is now in your clipboard
```

#### Step 3: Add to GitHub Secrets

- Secret name: `APPLE_CERTIFICATE_BASE64`
- Secret value: Paste from clipboard (should be a long string of letters and numbers)

---

### 5. APPLE_CERTIFICATE_PASSWORD

**What it is**: The password you set when exporting the .p12 certificate.

**How to get it**: This is the password you chose in Step 1 above.

- Secret name: `APPLE_CERTIFICATE_PASSWORD`
- Secret value: Your password (keep it secure!)

---

### 6. PROVISIONING_PROFILE_BASE64

**What it is**: Your App Store distribution provisioning profile, encoded in base64.

**How to get it**:

#### Step 1: Download Provisioning Profile

1. Go to [Apple Developer Portal](https://developer.apple.com/account/resources/profiles/list)
2. Find your distribution profile for `com.edwardwynman.Spot`
3. Download it (will be named something like `Spot_Distribution.mobileprovision`)

#### Step 2: Convert to Base64

```bash
cd ~/Downloads  # or wherever you downloaded the profile
base64 -i Spot_Distribution.mobileprovision | pbcopy
# The base64 string is now in your clipboard
```

#### Step 3: Add to GitHub Secrets

- Secret name: `PROVISIONING_PROFILE_BASE64`
- Secret value: Paste from clipboard

---

### 7. KEYCHAIN_PASSWORD

**What it is**: A temporary password for the CI keychain (can be any secure string).

**How to get it**: Generate a random password or use a password generator.

```bash
# Generate a random password:
openssl rand -base64 32
```

- Secret name: `KEYCHAIN_PASSWORD`
- Secret value: Your generated password

---

## Alternative: Using Fastlane Match (Recommended for Teams)

If you prefer a more automated approach, consider using [Fastlane Match](https://docs.fastlane.tools/actions/match/) to manage certificates and provisioning profiles.

Benefits:
- Easier team collaboration
- Automatic certificate management
- No manual base64 encoding
- Simpler CI/CD setup

---

## Verification Checklist

Before triggering a build, verify you have:

- [ ] `FIREBASE_APP_ID` set to `1:415359921164:ios:66b52b0b2c5f0f2eb59229`
- [ ] `FIREBASE_SERVICE_ACCOUNT_JSON` (full JSON from Firebase)
- [ ] `GOOGLE_SERVICE_INFO_PLIST_BASE64` (base64-encoded GoogleService-Info.plist)
- [ ] `APPLE_CERTIFICATE_BASE64` (base64-encoded .p12)
- [ ] `APPLE_CERTIFICATE_PASSWORD` (your .p12 password)
- [ ] `PROVISIONING_PROFILE_BASE64` (base64-encoded .mobileprovision)
- [ ] `KEYCHAIN_PASSWORD` (any secure random string)

---

## Testing the Setup

Once all secrets are configured:

1. **Merge a PR to main** - The workflow will trigger automatically
2. **Or manually trigger**: Go to **Actions** → **Deploy to Firebase** → **Run workflow**
3. **Monitor the build**: Check the Actions tab for progress
4. **Verify build**: Check Firebase App Distribution console for the new build

---

## Troubleshooting

### "App crashes immediately on launch"

- **Most common cause**: Missing `GOOGLE_SERVICE_INFO_PLIST_BASE64` secret
- Verify the secret is set in GitHub repository settings
- Verify the base64 encoding is correct (try re-encoding)
- Check GitHub Actions logs for "GoogleService-Info.plist installation failed"
- The app requires this file to initialize Firebase - without it, `FirebaseApp.configure()` will crash

### "No identity found" error

- Verify `APPLE_CERTIFICATE_BASE64` is correctly encoded
- Verify `APPLE_CERTIFICATE_PASSWORD` is correct
- Ensure the certificate is a **Distribution** certificate (not Development)

### "No matching provisioning profile found"

- Verify `PROVISIONING_PROFILE_BASE64` is correctly encoded
- Ensure the profile is for **App Store** distribution
- Ensure the profile includes your Team ID: `55JK72KR4W`
- Ensure the profile is for Bundle ID: `com.edwardwynman.Spot`

### "Could not install to Firebase"

- Verify `FIREBASE_SERVICE_ACCOUNT_JSON` is complete and valid JSON
- Ensure the service account has **Firebase App Distribution Admin** role
- Verify `FIREBASE_APP_ID` matches your Firebase project

### Build succeeds but no Firebase upload

- Check if the `testers` group exists in Firebase App Distribution
- Create the group: Firebase Console → App Distribution → Testers & Groups

---

## Next Steps

After setup is complete:

1. ✅ Secrets configured
2. ✅ Workflow triggers on merge to main
3. ✅ Build number auto-increments
4. ✅ Release notes generated from PR
5. ✅ IPA uploaded to Firebase App Distribution
6. ✅ Testers notified automatically

## Support

For issues:
- Check GitHub Actions logs for detailed error messages
- Review [Firebase App Distribution docs](https://firebase.google.com/docs/app-distribution)
- Review [Apple Developer docs](https://developer.apple.com/documentation/)
