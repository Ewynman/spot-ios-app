# Universal Links Implementation for Spot App

This document outlines the implementation of Universal Links and custom scheme handling for the Spot iOS app.

## Overview

The app now supports:
- **Universal Links**: `https://spotapp.online/s/:spotId` - Opens the app directly to a spot's detail view
- **Custom Scheme**: `spotapp://spot/:spotId` - Fallback for when Universal Links aren't available
- **Graceful Fallbacks**: Handles invalid spots, blocked users, and network errors

## Implementation Components

### 1. DeepLinkRouter (`Spot/Services/DeepLinkRouter.swift`)
- Parses URLs and maps them to typed routes
- Supports both Universal Links and custom schemes
- Validates spot IDs for security
- Logs analytics events for tracking

### 2. DeepLinkState (`Spot/ViewModels/DeepLinkState.swift`)
- Manages deep link navigation state
- Handles cold start vs warm start scenarios
- Fetches spot data from Firestore
- Manages loading and error states

### 3. URL Scheme Configuration
- **Custom Scheme**: `spotapp://`
- **Universal Links**: `https://spotapp.online/s/:spotId` and `https://www.spotapp.online/s/:spotId`

### 4. Associated Domains
- Entitlements file: `Spot/Spot.entitlements`
- Domains: `applinks:spotapp.online` and `applinks:www.spotapp.online`

## URL Patterns

### Universal Links
```
https://spotapp.online/s/ABC123
https://www.spotapp.online/s/ABC123
```

### Custom Scheme
```
spotapp://spot/ABC123
```

## Navigation Flow

### Cold Start (App Not Running)
1. User taps Universal Link
2. App launches and stores pending deep link
3. After authentication and app initialization, processes the deep link
4. Fetches spot data and navigates to detail view

### Warm Start (App Already Running)
1. User taps Universal Link
2. App immediately processes the deep link
3. Fetches spot data and navigates to detail view

### Custom Scheme
1. User taps custom scheme URL
2. App opens and immediately processes the deep link
3. Same navigation flow as warm start Universal Links

## Error Handling

### Spot Not Found
- Shows "Spot Unavailable" screen
- Logs analytics event with failure reason
- Provides "Go Back" action

### Blocked User
- Checks if spot owner is in user's blocked list
- Shows "Spot Unavailable" screen
- Logs analytics event

### Network Errors
- Shows "Spot Unavailable" screen
- Logs error details for debugging
- Provides retry mechanism via "Go Back"

### Invalid URLs
- Logs warning and ignores
- No user-facing error (graceful degradation)

## Analytics & Logging

### Success Events
- Origin (universal_link vs custom_scheme)
- Spot ID
- App version
- Cold vs warm start

### Failure Events
- Origin and spot ID
- Failure reason (not found, blocked, network error, etc.)
- App version and start type

### Logging Tags
- All logs use "SpotLogger" tag
- Include log levels (debug, info, warning, error)
- Filterable by tag and level in console

## Testing

### Manual Testing Checklist
1. **Universal Links (Cold Start)**
   - Install app → tap `https://spotapp.online/s/<validSpotId>` in Messages/Safari
   - App should open to correct spot detail

2. **Universal Links (Warm Start)**
   - Kill app → repeat above test
   - Should still route correctly after launch

3. **Custom Scheme**
   - From website, test `spotapp://spot/<id>`
   - App should open and route to spot

4. **Invalid Cases**
   - Invalid spot ID → "Spot not available" state
   - Deleted spot → "Spot not available" state
   - Blocked owner → "Spot unavailable" state

5. **Edge Cases**
   - Dark/light mode compatibility
   - Airplane mode (simulate fetch failure)
   - Unauthenticated user (should store pending link)

### Test Button
- Available in Settings → "Development & Testing" → "Test Deep Link"
- Uses hardcoded test spot ID
- Replace `test_spot_id` in `DeepLinkState.testDeepLink()` with real spot ID

## Configuration Requirements

### Xcode Project
1. **Associated Domains Capability**
   - Enable for both Debug and Release configurations
   - Add domains: `applinks:spotapp.online` and `applinks:www.spotapp.online`

2. **URL Schemes**
   - Add custom scheme: `spotapp`
   - Configure in Info.plist under `CFBundleURLTypes`

### Server-Side Requirements
1. **Apple App Site Association (AASA)**
   - Host at `https://spotapp.online/.well-known/apple-app-site-association`
   - Include app ID and associated domains

2. **Fallback Handling**
   - When app not installed, redirect to App Store
   - Handle invalid spot IDs gracefully

## Security Considerations

### URL Validation
- Spot IDs validated for length and character set
- Prevents injection attacks
- Sanitizes input before processing

### Privacy
- No PII in URLs
- Analytics limited to necessary parameters
- Blocked user checks prevent unauthorized access

### Rate Limiting
- Consider implementing rate limiting for spot fetching
- Prevent abuse of deep link endpoints

## Future Enhancements

### Potential Improvements
1. **Caching**: Cache frequently accessed spots
2. **Offline Support**: Handle offline scenarios gracefully
3. **Rich Links**: Add metadata for link previews
4. **Analytics Dashboard**: Track deep link usage patterns
5. **A/B Testing**: Test different deep link strategies

### Additional URL Patterns
- User profiles: `/u/:userId`
- Search results: `/search?q=query`
- Categories: `/category/:categoryId`

## Troubleshooting

### Common Issues
1. **Universal Links Not Working**
   - Check Associated Domains capability
   - Verify AASA file is accessible
   - Test on physical device (not simulator)

2. **Custom Scheme Not Working**
   - Verify URL scheme in Info.plist
   - Check bundle identifier matches

3. **Navigation Issues**
   - Ensure DeepLinkState is properly injected
   - Check authentication state handling

### Debug Logging
- Enable debug logging in console
- Filter by "SpotLogger" tag
- Check for specific error messages

## Dependencies

### Required Frameworks
- `FirebaseFirestore` - Spot data fetching
- `FirebaseAuth` - User authentication checks
- `SwiftUI` - UI components

### Internal Dependencies
- `SpotService` - Spot data operations
- `SpotLogger` - Logging utility
- `Constants` - App constants and colors
- `FontManager` - Typography management

## Support

For issues or questions about the Universal Links implementation:
1. Check console logs for error messages
2. Verify configuration in Xcode project
3. Test on physical device with real URLs
4. Review this documentation for troubleshooting steps
