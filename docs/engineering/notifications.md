# Notifications

**Owner**: Engineering  
**Last Updated**: 2026-07-02

## Overview

Spot implements a local notification system for social events, specifically follow requests and follow acceptances. Users are prompted to grant notification permissions after completing the first-run onboarding tour.

## Architecture

### Permission Request Flow

1. User completes the first-run onboarding tour (all steps through `.finale`) **OR** skips the tour
2. After 600ms delay, `BottomTabNavigationView` checks notification permission status
3. If status is `.notDetermined`, presents `NotificationPermissionView` sheet
4. User grants or denies permissions through the system dialog
5. Permission status is tracked in `PermissionManager.notificationStatus`

**Important**: Notification permissions are requested regardless of whether the user completes or skips onboarding, ensuring all users have the opportunity to enable notifications.

### Notification Service

**Location**: `Spot/Services/NotificationService.swift`

The `NotificationService` singleton manages local notification delivery and action handling:

- **Categories**:
  - `FOLLOW_REQUEST` — New incoming follow request
  - `FOLLOW_ACCEPTED` — Your follow request was accepted

- **Actions**:
  - Accept Follow Request (foreground)
  - View Follow Request (foreground)
  - View Profile (foreground)

### Notification Types

#### Follow Request Accepted ✅

**Trigger**: When a user accepts another user's follow request  
**Implementation**: Client-side local notification  
**Status**: ✅ Implemented

When User B accepts User A's follow request:
- `FollowRequestsService.accept()` is called
- Service fetches User B's username from database
- `NotificationService.notifyFollowRequestAccepted()` sends a local notification
- User A receives: "Follow Request Accepted — [username] accepted your follow request"

**Code Path**:
```
FollowRequestsView (Accept button) 
  → FollowRequestsService.accept()
  → notifyFollowRequestAcceptedByCurrentUser()
  → NotificationService.notifyFollowRequestAccepted()
```

#### Follow Request Received ⚠️

**Trigger**: When a user receives a new follow request  
**Implementation**: ⚠️ **Requires backend implementation**  
**Status**: ⚠️ Infrastructure ready, but needs backend trigger

**Current Limitation**: The client cannot detect when another user sends a follow request without:
1. Polling the `follow_requests` table (inefficient, battery-draining)
2. Real-time subscriptions (Supabase Realtime, but still client-initiated)
3. Backend push notifications (proper solution)

**Recommended Production Implementation**:

Use Supabase Edge Functions or database triggers to send push notifications when a follow request is created:

1. **Database Trigger** (PostgreSQL):
```sql
CREATE OR REPLACE FUNCTION notify_follow_request_received()
RETURNS TRIGGER AS $$
BEGIN
  -- Call Edge Function to send push notification
  PERFORM net.http_post(
    url := 'https://[project].supabase.co/functions/v1/send-notification',
    headers := jsonb_build_object('Authorization', 'Bearer [service_role_key]'),
    body := jsonb_build_object(
      'type', 'follow_request_received',
      'target_user_id', NEW.target_user_id,
      'requester_id', NEW.requester_id
    )
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER on_follow_request_created
  AFTER INSERT ON follow_requests
  FOR EACH ROW
  WHEN (NEW.status = 'pending')
  EXECUTE FUNCTION notify_follow_request_received();
```

2. **Edge Function** (`supabase/functions/send-notification/index.ts`):
```typescript
import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2"

serve(async (req) => {
  const { type, target_user_id, requester_id } = await req.json()
  
  // Fetch requester username
  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!
  )
  
  const { data: requester } = await supabase
    .from('users')
    .select('username')
    .eq('id', requester_id)
    .single()
  
  // Fetch target user's push token (would need to be stored in database)
  const { data: targetUser } = await supabase
    .from('user_push_tokens')
    .select('token')
    .eq('user_id', target_user_id)
    .single()
  
  if (!targetUser?.token) {
    return new Response(JSON.stringify({ error: 'No push token' }), { status: 400 })
  }
  
  // Send push notification via APNs (Apple Push Notification service)
  // Implementation depends on push notification provider (e.g., Firebase, OneSignal, direct APNs)
  
  return new Response(JSON.stringify({ success: true }))
})
```

3. **Client Setup**:
   - Store device push token in `user_push_tokens` table after permission grant
   - Register for remote notifications in `AppDelegate.application(_:didRegisterForRemoteNotificationsWithDeviceToken:)`
   - Handle remote notifications in `UNUserNotificationCenterDelegate` methods

### Notification Actions

#### App-Side Handling

**Location**: `AppDelegate+UNUserNotificationCenterDelegate`

When a user taps a notification or action button:

1. `userNotificationCenter(_:didReceive:withCompletionHandler:)` is called
2. Action identifier is matched to `NotificationService.NotificationAction` cases
3. Navigation is triggered via `NotificationCenter` posts:
   - `.navigateToFollowRequests` — Opens Follow Requests screen
   - `.navigateToFollowRequestsAndAccept` — Opens Follow Requests and auto-accepts
   - `.navigateToProfile` — Opens a specific user's profile

#### Navigation Handling

Navigation events are posted via `NotificationCenter.default.post()`. Consumers (e.g., `ProfileView`, `BottomTabNavigationView`) can observe these notifications and respond accordingly.

**Example**:
```swift
.onReceive(NotificationCenter.default.publisher(for: .navigateToFollowRequests)) { _ in
    // Switch to Profile tab and navigate to Follow Requests
    selectedTab = 4
    showFollowRequests = true
}
```

## Security Considerations

- Notification content never includes sensitive data (user IDs are in `userInfo`, not body)
- All notification actions require foreground activation (user must unlock device)
- Database RLS policies ensure users can only accept follow requests directed to them
- Service-role keys must never be included in client-side code

## Future Enhancements

### Required for Production

- [ ] Implement push notification backend (Edge Functions + APNs)
- [ ] Store device push tokens in database
- [ ] Handle remote notification registration in AppDelegate
- [ ] Add database trigger for follow request creation
- [ ] Add notification preferences UI (allow users to mute specific notification types)

### Optional

- [ ] Comment notifications (when commenting is implemented)
- [ ] Batch notifications (e.g., "3 new follow requests")
- [ ] Rich notifications with profile pictures
- [ ] Notification history in-app
- [ ] Notification sounds customization

## Testing

### Manual Testing

1. **Permission Grant After Completing Onboarding**:
   - Sign up for a new account
   - Complete onboarding tour through all steps
   - After finale, notification permission sheet should appear
   - Grant permissions → verify `PermissionManager.notificationStatus == .authorized`

2. **Permission Grant After Skipping Onboarding**:
   - Sign up for a new account
   - Start onboarding tour
   - Tap "Skip" button on any step
   - After 600ms, notification permission sheet should appear
   - Grant permissions → verify `PermissionManager.notificationStatus == .authorized`

2. **Follow Request Accepted Notification**:
   - User A sends follow request to User B (private account)
   - User B accepts the request
   - User A should receive local notification: "Follow Request Accepted — [User B username] accepted your follow request"
   - Tap notification → should navigate to User B's profile

3. **Notification Actions**:
   - Long-press on a follow request notification
   - Verify action buttons appear: "Accept", "View"
   - Tap "Accept" → should navigate to Follow Requests screen
   - Tap "View Profile" on follow accepted notification → should navigate to profile

### Automated Testing

Current test coverage:
- ✅ `PermissionManager.requestNotificationPermission()` unit tests
- ✅ Onboarding flow includes notification permission prompt
- ❌ **Missing**: End-to-end UI tests for notification flow (requires simulator notification delivery)

## Known Limitations

1. **Follow Request Received Notifications**: Requires backend implementation (see above)
2. **No Comment Notifications**: Commenting feature not yet implemented
3. **No Like Notifications**: Intentionally excluded per product requirements
4. **Local Notifications Only**: Production app should use remote push notifications for reliability and backend triggering

## References

- [Apple Human Interface Guidelines — Notifications](https://developer.apple.com/design/human-interface-guidelines/notifications)
- [UserNotifications Framework](https://developer.apple.com/documentation/usernotifications)
- [Supabase Edge Functions](https://supabase.com/docs/guides/functions)
- [Apple Push Notification Service](https://developer.apple.com/documentation/usernotifications/setting_up_a_remote_notification_server)
