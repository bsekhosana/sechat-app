# CircleCI Setup Guide for SeChat

## Quick Start

1. **Connect GitHub Repository**
   - Go to [CircleCI](https://circleci.com)
   - Sign in with your GitHub account
   - Click "Add Projects"
   - Find your SeChat repository and click "Set Up Project"
   - Choose "Use existing config" (we already have `.circleci/config.yml`)

2. **Initial Test Run**
   - Push the config file to your main branch
   - CircleCI will automatically start the first build
   - This will run tests and build debug versions without signing

## Environment Variables Setup

### For Android Release Signing (Optional)
Add these in CircleCI Project Settings → Environment Variables:

```
ANDROID_KEYSTORE_BASE64=<base64-encoded-keystore>
ANDROID_STORE_PASSWORD=<your-keystore-password>
ANDROID_KEY_ALIAS=<your-key-alias>
ANDROID_KEY_PASSWORD=<your-key-password>
```

### For iOS App Store Signing (Optional)
```
IOS_DISTRIBUTION_CERT_BASE64=<base64-encoded-certificate>
IOS_DISTRIBUTION_CERT_PASSWORD=<certificate-password>
IOS_PROVISIONING_PROFILE_BASE64=<base64-encoded-provisioning-profile>
```

### For Google Play Console Upload (Optional)
```
GOOGLE_PLAY_SERVICE_ACCOUNT_KEY=<json-service-account-key>
```

### For TestFlight Upload (Optional)
```
APP_STORE_CONNECT_API_KEY=<json-api-key>
```

## How It Works

### Free Tier Benefits
- **6,000 build minutes/month** (plenty for Flutter builds)
- **3 concurrent jobs** (perfect for our workflow)
- **Unlimited public repositories**

### Workflow Stages
1. **Test**: Runs `flutter test` and `flutter analyze`
2. **Build**: Creates APK/AAB for Android and IPA for iOS
3. **Deploy**: Uploads to stores (if credentials provided)

### Smart Fallbacks
- If no signing credentials: builds debug versions
- If no deployment credentials: skips upload with helpful messages
- All builds create downloadable artifacts

## Cost Optimization

### Stay Under Monthly Limit
- **Android build**: ~10-15 minutes
- **iOS build**: ~15-20 minutes
- **Total per push**: ~30-35 minutes
- **Estimated builds per month**: ~170-200 builds

### Tips to Save Minutes
1. **Use branch filters**: Only build on main branch
2. **Skip unnecessary jobs**: Debug builds are faster
3. **Cache dependencies**: CircleCI automatically caches Flutter dependencies

## Troubleshooting

### Common Issues

**Build fails with "No signing credentials"**
- This is expected for first builds
- Add signing credentials or use debug builds for testing

**iOS build fails**
- Ensure Xcode version compatibility
- Check iOS deployment target in `ios/Podfile`

**Android build fails**
- Verify `android/app/build.gradle.kts` configuration
- Check if `key.properties` is properly referenced

### Debug Steps
1. Check CircleCI logs for specific error messages
2. Verify environment variables are set correctly
3. Test locally with `flutter build apk` and `flutter build ios`

## Next Steps

1. **Push the config file** to your repository
2. **Connect the project** in CircleCI dashboard
3. **Run first build** to verify everything works
4. **Add signing credentials** when ready for release builds
5. **Monitor usage** in CircleCI dashboard

## Migration from GitHub Actions

The CircleCI config mirrors your previous GitHub Actions workflow:
- Same build steps and conditions
- Same environment variable names
- Same artifact storage
- Same deployment logic

## Support

- **CircleCI Docs**: https://circleci.com/docs/
- **Flutter Orb**: https://circleci.com/developer/orbs/orb/circleci/flutter
- **Free Tier Limits**: https://circleci.com/pricing/ 