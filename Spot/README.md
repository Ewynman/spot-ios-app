# 🧱 High-Level Architecture

## Pattern: Pragmatic MVVM for SwiftUI
- **Views:** Lightweight and declarative (`SwiftUI`)
- **ViewModels:** Orchestrate data flow and user actions
- **Services:** Abstract Firebase and other platform APIs
- **Repositories/Cache:** Handle pagination and in-memory state for performance

### Data Sources
- **Firebase Auth** → Identity and session  
- **Firestore** → User profiles, spots, relationships  
- **Firebase Storage** → Images

### Cross-Cutting Concerns
- **Logging:** `SpotLogger`  
- **Performance:** `PerfMetrics`  
- **Styling:** `Constants.Colors` and `FontManager`

---

# ⚙️ Core Modules and Their Roles

## 1. Auth Layer

### `AuthService`
Single entry point for all authentication-related operations.

**Responsibilities:**
- Sign up, sign in, sign out  
- Create Firestore user document on first sign up  
- Password reset, email/password updates, reauthentication  
- Delete account (best-effort cleanup of Firestore and Storage assets)

**Notes:**
- Provides both `async/await` and callback-style APIs  
- Returns domain-level `AuthResult` to signal special UI states (e.g., _email already in use_)

### `AuthViewModel`
- Wraps `AuthService` and manages user-centric state (liked/bookmarked spots)
- Exposes convenience actions (like/unlike, bookmark/unbookmark, block user)
- Acts as an `@EnvironmentObject` so subviews can react to auth state

**Interaction Flow:**
```
Views (HomepageView, SpotCard)
   ↓
AuthViewModel
   ↓
AuthService
   ↓
Firebase Auth / Firestore
```

---

## 2. Feed Layer

### `HomepageView`
- Hosts navigation (Home / Search / Profile tabs)
- Contains a local `@StateObject FeedViewModel`
- Toggles between “Feed” and “Map” sub-views
- Initiates posting flow (gated by rules + email verification)

### `FeedViewModel`
Handles feed lifecycle:
- Initial load, pagination, refresh, deletion
- Derived UI state: `spots`, `mapSpots`, `isLoading`, `hasMore`, `deletingSpotIds`
- Communicates with:
  - `FeedRepository` → Shared stateful source of truth  
  - `FeedCache` → Data unification and refresh  
  - `SpotService` → Spot deletion (optimistic UI updates)

### `FeedRepository` / `FeedCache` *(inferred)*
- **FeedRepository:** Handles Firestore paging, cursors, aggregation  
- **FeedCache:** Consolidates results, refreshes, and de-dupes

**Interaction Flow:**
```
HomepageView
   ↓
FeedViewModel
   ↓
FeedRepository / FeedCache
   ↓
SpotService
```

---

## 3. Spot Presentation

### `SpotCard`
A self-contained component for displaying a single spot.

**Responsibilities:**
- Reads current user state from `authVM`
- Emits events upward (e.g., `onDelete`) to parent view
- Presents share/report/delete menus
- Logs via `SpotLogger` and `PerfMetrics`

**Interaction Flow:**
```
Parent View (FeedContentView / ProfileView)
   ↓
SpotCard
   ↳ uses authVM for like/bookmark/block
   ↳ triggers parent for delete
```

---

## 4. Profile Layer

### `ProfileView`
Displays a user’s profile (self or another user).

**Manages:**
- Header: avatar, username, counts  
- Tabs: “Spots” (grid/detail) and “Map”  
- Follow/unfollow and request flows  
- In-app menu (Likes, Bookmarks, Settings, Requests)

**Data Source:**  
`ProfileService.fetchProfile(for:)`

**Local State:**  
Selection, deletion confirmation, request counts

### `ProfileMapView`
- Dedicated map experience for a user’s spots  
- Keeps `MapKit` camera synced with selection  
- Responsive bottom panel for interactivity

### Supporting Services *(inferred)*
- `ProfileService` → Fetch aggregated profile data  
- `UserSpotService` → Follow/unfollow logic  
- `FollowRequestsService` → Live request counts

**Interaction Flow:**
```
ProfileView
   ↳ ProfileService (load/reload)
   ↳ UserSpotService (follow/unfollow)
   ↳ SpotService (deletion)
   ↳ ProfileMapView (render spots)
```

---

## 5. Tour & Onboarding

### `HomeTourHost`
Coordinates onboarding overlays and highlights UI elements.

**Responsibilities:**
- Wraps main content with a welcome sheet and overlay  
- Tracks UI frames (username, location, vibe, like/save)  
- Starts/stops via `AuthViewModel` and local tour manager

**Interaction Flow:**
```
HomepageView
   ↳ HomeTourHost
       ↳ HomeTourManager (per-user tour state)
```

---

# 🔁 Data Flow Summary

### Auth
```
View → AuthViewModel → AuthService → Firebase Auth / Firestore
```
- On sign up, creates user document with defaults  
- Mirrors liked/bookmarked IDs for fast UI

### Feed
```
HomepageView → FeedViewModel → FeedRepository / FeedCache → SpotService
```

### Profile
```
ProfileView → ProfileService → UserSpotService → FollowRequestsService
```
- Inline or map-based spot selection triggers `SpotCard` or bottom panel

### Spot Interactions
```
SpotCard (reads authVM)
   ↳ triggers like/bookmark actions
   ↳ delegates delete to parent ViewModel
```

---

# 🧩 State Management Principles

### Local View State
- Selections (`selectedSpot`), menus, sheets  
- Loading flags, deletion confirmations, errors

### Shared / Global State
- `AuthViewModel` as `@EnvironmentObject`  
- Shared repositories (e.g., `FeedRepository.shared`)

### Optimistic Updates
- Immediate UI updates with rollback on failure  
- Likes/bookmarks toggle instantly and reconcile with backend

---

# 🚨 Error Handling & Logging

- Errors caught at service or ViewModel boundaries  
- `SpotLogger` for structured logs (debug/info/warn/error)  
- `PerfMetrics` records performance milestones (e.g., first paint)

---

# 🧭 UI Composition & Navigation

- Uses `NavigationStack` for transitions  
- Custom bottom navigation (`BottomNavigationView`)  
- **Sheets & Overlays:**
  - Posting rules & post flow  
  - Share / report  
  - Custom menus  
  - Onboarding tour

---

# 🚀 Extending the App

### Add New User Actions
- Add methods to `AuthViewModel` (e.g., mute, block)  
- Use services for backend integration

### Add New Feed Filters
- Introduce filter state in `FeedViewModel`  
- Update queries in `FeedRepository`

### Add New Profile Sections
- Extend `ProfileService`  
- Add a new tab and subview

### Add Analytics
- Use `SpotLogger` consistently  
- Add `AnalyticsService` if event complexity increases

---

# 💡 Why This Architecture Works

- SwiftUI + MVVM keeps views declarative and testable  
- Services isolate platform specifics (`Firebase`, `Storage`, `MapKit`)  
- Repositories & caches decouple persistence from UI  
- Environment objects expose session state cleanly without prop-drilling
