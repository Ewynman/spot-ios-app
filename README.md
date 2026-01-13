# Spot Architecture Documentation

## Table of Contents
1. [System Overview](#system-overview)
2. [Architecture Patterns](#architecture-patterns)
3. [Core Flows](#core-flows)
   - [Login Flow](#login-flow)
   - [Posting Flow](#posting-flow)
   - [Account Deletion Flow](#account-deletion-flow)
   - [Feed Algorithm Flow](#feed-algorithm-flow)
   - [Deep Linking Flow](#deep-linking-flow)
   - [Moderation Flow](#moderation-flow)
4. [Component Architecture](#component-architecture)
5. [Data Flow](#data-flow)

---

## System Overview

Spot is a location-based social media iOS application built with SwiftUI and Firebase. The app enables users to discover and share "spots" (location-tagged photos with vibe tags) through a personalized feed algorithm.

### Technology Stack
- **Frontend**: SwiftUI (iOS)
- **Backend**: Firebase (Auth, Firestore, Storage)
- **Architecture**: MVVM with Service Layer
- **State Management**: `@Published`, `@StateObject`, `@EnvironmentObject`

### Key Services
- **Firebase Auth**: User authentication and session management
- **Firestore**: NoSQL database for users, spots, and relationships
- **Firebase Storage**: Image storage and CDN
- **CoreLocation**: Location services and geocoding

---

## Architecture Patterns

### MVVM Pattern
- **Views**: SwiftUI declarative UI components
- **ViewModels**: Observable objects managing UI state and business logic
- **Services**: Stateless service classes abstracting Firebase APIs
- **Repositories**: Stateful data management with pagination and caching

### Service Layer
- **AuthService**: Authentication operations
- **SpotService**: Spot CRUD operations
- **FeedRepository**: Feed pagination and ranking
- **SearchService**: Search functionality
- **UserSpotService**: User-spot interactions (likes, bookmarks)

---

## Core Flows

### Login Flow

\`\`\`mermaid
flowchart TD
    A[User Opens App] --> B{RootView Checks Auth State}
    B -->|Not Authenticated| C[WelcomeView]
    B -->|Authenticated| D{Email Verified?}
    D -->|No| E[ConfirmEmailView]
    D -->|Yes| F[HomepageView]
    
    C --> G[User Taps Login]
    G --> H[LoginView]
    H --> I[User Enters Email/Password]
    I --> J[LoginView Calls AuthService.signIn]
    
    J --> K[AuthService: Trim & Lowercase Email]
    K --> L[Firebase Auth.signIn]
    L --> M{Success?}
    
    M -->|No| N[Handle Error Codes]
    N -->|17008: Invalid Email| O[Show: Invalid Email]
    N -->|17009/17011: Wrong Credentials| P[Show: Incorrect Email/Password]
    N -->|17010: Network Error| Q[Show: Network Error]
    N --> H
    
    M -->|Yes| R[AuthViewModel.listenToAuthState]
    R --> S[Firebase Auth State Listener Triggered]
    S --> T[AuthViewModel Updates State]
    T --> U[Set isAuthenticated = true]
    U --> V[Set userId]
    V --> W[Refresh User Data]
    W --> X[Load User Spot Lists]
    X --> Y[Load Blocked Users]
    Y --> Z[Check Fresh Install Flag]
    Z -->|First Login| AA[Request Permissions]
    Z -->|Not First| AB[Skip Permissions]
    AA --> D
    AB --> D
    
    style A fill:#e1f5ff
    style F fill:#c8e6c9
    style M fill:#fff9c4
    style N fill:#ffcdd2
\`\`\`

**Key Components:**
- `LoginView`: UI for email/password input
- `AuthService.signIn()`: Core authentication logic
- `AuthViewModel`: Manages auth state and user data
- `RootView`: Routes based on authentication state

**Error Handling:**
- Maps Firebase error codes to user-friendly messages
- Handles network errors gracefully
- Validates input before submission

---

### Posting Flow

\`\`\`mermaid
flowchart TD
    A[User Taps + Button] --> B{Email Verified?}
    B -->|No| C[Show Verify Toast]
    B -->|Yes| D[Show PostingRulesView]
    
    D --> E[User Agrees to Rules]
    E --> F[PostFlowView Opens]
    
    F --> G[Step 1: PhotoSelectionView]
    G --> H[User Selects Images]
    H --> I{Images Selected?}
    I -->|No| G
    I -->|Yes| J[Step 2: LocationSelectionView]
    
    J --> K[User Selects Location]
    K --> L{Location Selected?}
    L -->|No| J
    L -->|Yes| M[Step 3: VibeSelectionView]
    
    M --> N[User Selects Vibe Tag]
    N --> O{Vibe Selected?}
    O -->|No| M
    O -->|Yes| P[User Taps Post]
    
    P --> Q[Validate All Fields]
    Q --> R{Valid?}
    R -->|No| S[Show Error Toast]
    R -->|Yes| T[Set isUploading = true]
    
    T --> U{Image Count?}
    U -->|Single| V[SpotUploader.uploadSpot image:]
    U -->|Multiple| W[SpotUploader.uploadSpot images:]
    
    V --> X[Get Current User Data]
    W --> X
    X --> Y[Fetch Username & Profile Image]
    Y --> Z[Compress Image to JPEG 0.7]
    Z --> AA[Generate UUID postId]
    AA --> AB[Upload to Firebase Storage]
    
    AB --> AC{Upload Success?}
    AC -->|No| AD[Show Error & Cleanup]
    AC -->|Yes| AE[Get Download URL]
    
    AE --> AF[Reverse Geocode Location]
    AF --> AG[Generate GeoHash]
    AG --> AH[Fetch Author Privacy Status]
    AH --> AI[Create Spot Document]
    
    AI --> AJ["Set Data: postId, userId, username,<br/>imageURLs, vibeTag, location,<br/>geohash, authorIsPrivate, createdAt"]
    AJ --> AK[Ensure VibeTag Exists Globally]
    AK --> AL[Write to Firestore spots/]
    
    AL --> AM{Document Created?}
    AM -->|No| AN[Cleanup Uploaded Images]
    AM -->|Yes| AO[Increment User Vibe Stats]
    
    AO --> AP[PostFlowView.awaitModerationAndFinish]
    AP --> AQ[Fetch Latest Spot by User]
    AQ --> AR[Poll Moderation Status]
    
    AR --> AS{Status?}
    AS -->|pending| AT[Wait 1s, Retry up to 20s]
    AT --> AR
    AS -->|approved| AU[ModerationPolicy.evaluate]
    AS -->|rejected| AV[Delete Spot Document]
    
    AU --> AW{Scores Pass?}
    AW -->|Yes| AX[Show Success Banner]
    AW -->|No| AY[Show Violation Message]
    
    AV --> AY
    AX --> AZ[Dismiss PostFlowView]
    AZ --> BA[Refresh Feed]
    AY --> BB[Set isPosting = false]
    
    style A fill:#e1f5ff
    style AX fill:#c8e6c9
    style AM fill:#fff9c4
    style AD fill:#ffcdd2
    style AY fill:#ffcdd2
\`\`\`

**Key Components:**
- `PostFlowView`: Multi-step wizard UI
- `SpotUploader`: Handles image upload and document creation
- `VibeTagService`: Ensures vibe tags exist globally
- `ModerationPolicy`: Evaluates moderation scores

**Error Handling:**
- Validates all fields before submission
- Cleans up uploaded images on failure
- Handles moderation timeouts gracefully

---

### Account Deletion Flow

\`\`\`mermaid
flowchart TD
    A[User Opens Settings] --> B[SettingsView]
    B --> C[User Taps Delete Account]
    C --> D[Show Confirmation Toggle]
    D --> E[User Enters Password]
    E --> F[User Confirms Deletion]
    F --> G[AuthViewModel.deleteAccount]
    
    G --> H[AuthService.deleteAccount]
    H --> I{User Authenticated?}
    I -->|No| J[Return Error: No User]
    I -->|Yes| K[Reauthenticate with Password]
    
    K --> L{Reauth Success?}
    L -->|No| M[Return Error]
    L -->|Yes| N[Fetch User Document]
    
    N --> O[Get Profile Image URL]
    O --> P[Query User's Spots]
    P --> Q[Create DispatchGroup]
    
    Q --> R[For Each Spot]
    R --> S[Delete Spot Images from Storage]
    S --> T[Delete Spot Document]
    T --> U{More Spots?}
    U -->|Yes| R
    U -->|No| V[Delete Profile Image]
    
    V --> W[Wait for All Deletions]
    W --> X[Delete User Document]
    X --> Y[Delete Firebase Auth User]
    
    Y --> Z{Delete Success?}
    Z -->|No| AA[Return Error]
    Z -->|Yes| AB[Auth State Listener Fires]
    
    AB --> AC[AuthViewModel Updates State]
    AC --> AD[Set isAuthenticated = false]
    AD --> AE[Clear User Data]
    AE --> AF[Clear Deep Link State]
    AF --> AG[Clear Privacy Cache]
    AG --> AH[RootView Routes to WelcomeView]
    
    style A fill:#e1f5ff
    style AH fill:#c8e6c9
    style K fill:#fff9c4
    style M fill:#ffcdd2
    style AA fill:#ffcdd2
\`\`\`

**Key Components:**
- `AuthService.deleteAccount()`: Orchestrates deletion
- `DispatchGroup`: Coordinates async deletions
- `Firebase Storage`: Image cleanup
- `Firestore`: Document deletion

**Safety Measures:**
- Requires password reauthentication
- Best-effort cleanup (continues on individual failures)
- Clears all user-related caches

---

### Feed Algorithm Flow

\`\`\`mermaid
flowchart TD
    A[User Opens Feed] --> B[FeedViewModel.loadInitialSpots]
    B --> C[FeedRepository.loadInitial]
    
    C --> D[Load Social Lists]
    D --> E[UserSpotService.getSocialLists]
    E --> F[Get Followee IDs & Requested Follows]
    
    F --> G[Parallel Fetch Candidates]
    G --> H[FeedCandidateService.fetchRecent]
    G --> I[FeedCandidateService.fetchFolloweesRecent]
    
    H --> J["Query: spots/ orderBy createdAt DESC"]
    I --> K["Query: spots/ where userId IN followeeIds<br/>orderBy createdAt DESC<br/>Chunked by 10"]
    
    J --> L[Merge Results]
    K --> L
    
    L --> M[AuthorPrivacyCache.warm]
    M --> N[Batch Fetch Author Privacy Status]
    N --> O[Fetch Following List]
    O --> P[Fetch Blocked Users]
    
    P --> Q[Privacy Filter]
    Q --> R{Author Private?}
    R -->|Yes| S{Viewer Following?}
    R -->|No| T[Include Spot]
    S -->|Yes| T
    S -->|No| U[Exclude Spot]
    
    T --> V{Blocked User?}
    V -->|Yes| U
    V -->|No| W[FeedRanker.score]
    
    U --> X[Filtered Spots]
    W --> X
    
    X --> Y[Build Ranking Context]
    Y --> Z["Context: followeeIds, userVibeStats,<br/>userLocation, seenSpotIds"]
    
    Z --> AA[Rank Followees Bucket]
    AA --> AB[Sort by FeedRanker.score DESC]
    
    Z --> AC[Rank Global Bucket]
    AC --> AD[Sort by FeedRanker.score DESC]
    
    AB --> AE[FeedRanker.blend]
    AD --> AE
    
    AE --> AF[Calculate Scores]
    AF --> AG["Vibe Score: 45% weight<br/>userVibeStats[vibeTag] / total"]
    AF --> AH["Freshness Score: 25% weight<br/>exp -ageHours / 72"]
    AF --> AI["Affinity Score: 20% weight<br/>1 if followee, else 0"]
    AF --> AJ["Distance Score: 10% weight<br/>1 if <25km, else decays"]
    
    AG --> AK[Final Score = Sum Weighted Scores]
    AH --> AK
    AI --> AK
    AJ --> AK
    
    AK --> AL[Blend Strategy]
    AL --> AM[Target: 50% Followees, 50% Global]
    AM --> AN[Apply Creator Cap: Max 2 per Creator]
    AN --> AO[Remove Duplicates]
    
    AO --> AP[Return Blended Feed]
    AP --> AQ[FeedRepository.spots = blended]
    AQ --> AR[FeedViewModel.spots = repo.spots]
    AR --> AS[HomepageView Renders Feed]
    
    AS --> AT[User Scrolls]
    AT --> AU[FeedViewModel.loadMoreSpots]
    AU --> AV[FeedRepository.loadMore]
    AV --> AW[Fetch Next Page with Cursor]
    AW --> X
    
    style A fill:#e1f5ff
    style AS fill:#c8e6c9
    style W fill:#fff9c4
    style U fill:#ffcdd2
\`\`\`

**Ranking Algorithm Details:**

**Scoring Formula:**
\`\`\`
score = (0.45 × vibeScore) + (0.25 × freshnessScore) + 
        (0.20 × affinityScore) + (0.10 × distanceScore)
\`\`\`

**Component Scores:**
- **Vibe Score**: \`userVibeStats[vibeTag] / totalVibeStats\` (0-1)
- **Freshness Score**: \`exp(-ageHours / 72)\` (exponential decay)
- **Affinity Score**: \`1.0\` if followee, else \`0.0\`
- **Distance Score**: \`1.0\` if ≤25km, else \`25km / distanceKm\`

**Blending Strategy:**
- Target ratio: 50% followees, 50% global
- Creator cap: Maximum 2 spots per creator per page
- Deduplication: Removes spots already seen
- Backfill: Fills remaining slots if under target

**Key Components:**
- `FeedRepository`: Manages pagination and cursors
- `FeedCandidateService`: Fetches candidate spots
- `FeedRanker`: Scores and blends spots
- `AuthorPrivacyCache`: Filters private content

---

### Deep Linking Flow

\`\`\`mermaid
flowchart TD
    A[User Clicks Link] --> B{Link Type?}
    B -->|Universal Link| C[https://spotapp.online/s/:spotId]
    B -->|Custom Scheme| D[spotapp://spot/:spotId]
    
    C --> E[RootView.onContinueUserActivity]
    D --> F[RootView.onOpenURL]
    
    E --> G[DeepLinkState.handleDeepLink]
    F --> G
    
    G --> H[DeepLinkRouter.parseURL]
    H --> I{URL Valid?}
    I -->|No| J[Route: .unknown]
    I -->|Yes| K[Extract spotId]
    
    K --> L[DeepLinkRouter.isValidSpotId]
    L --> M{Valid Format?}
    M -->|No| J
    M -->|Yes| N[Route: .spotDetail spotId]
    
    N --> O{User Authenticated?}
    O -->|No| P[Store Pending Deep Link]
    P --> Q[Show WelcomeView]
    Q --> R[After Login: Process Pending]
    
    O -->|Yes| S[DeepLinkState.navigateToSpot]
    S --> T[Set isNavigatingToSpot = true]
    T --> U[Set isLoadingSpot = true]
    
    U --> V[Fetch Spot from Firestore]
    V --> W["Firestore.collection spots/.document spotId"]
    W --> X{Spot Exists?}
    
    X -->|No| Y[Set showSpotUnavailable = true]
    X -->|Yes| Z[Check Privacy Filter]
    
    Z --> AA{Author Private?}
    AA -->|Yes| AB{Viewer Following?}
    AA -->|No| AC[Include Spot]
    AB -->|Yes| AC
    AB -->|No| Y
    
    AC --> AD[Set spotDetailSpot]
    AD --> AE[Set isLoadingSpot = false]
    AE --> AF[RootView Shows Overlay]
    
    AF --> AG[SpotCard Overlay]
    AG --> AH[User Views Spot]
    AH --> AI[User Taps Back]
    AI --> AJ[DeepLinkState.dismissSpotDetail]
    AJ --> AK[Clear Navigation State]
    
    Y --> AL[Show SpotUnavailableView]
    AL --> AM[User Dismisses]
    AM --> AJ
    
    style A fill:#e1f5ff
    style AF fill:#c8e6c9
    style I fill:#fff9c4
    style Y fill:#ffcdd2
\`\`\`

**Key Components:**
- `DeepLinkRouter`: Parses URLs and routes
- `DeepLinkState`: Manages navigation state
- `RootView`: Handles URL events
- `AuthorPrivacyCache`: Filters private content

**Supported URL Formats:**
- Universal: \`https://spotapp.online/s/{spotId}\`
- Custom Scheme: \`spotapp://spot/{spotId}\`
- Query Variant: \`spotapp://open?spotId={spotId}\`

---

### Moderation Flow

\`\`\`mermaid
flowchart TD
    A[Spot Uploaded to Firestore] --> B[Cloud Function Triggered]
    B --> C[Extract Image URL]
    C --> D[Call Moderation API]
    D --> E[Azure Content Moderator / Similar]
    
    E --> F[Get Moderation Scores]
    F --> G[Scores: sexual, violence, hate, selfHarm]
    
    G --> H[Update Spot Document]
    H --> I[Set moderation.status = pending]
    I --> J[Set moderation.scores = {...}]
    
    J --> K[PostFlowView Polls Status]
    K --> L[Fetch Latest Spot Document]
    L --> M{moderation.status?}
    
    M -->|pending| N[Wait 1 Second]
    N --> O{Timeout?}
    O -->|No < 20s| L
    O -->|Yes| P[Show Timeout Message]
    
    M -->|approved| Q[ModerationPolicy.evaluate]
    M -->|rejected| R[Delete Spot Document]
    
    Q --> S[Check Score Thresholds]
    S --> T{sexual >= 3?}
    T -->|Yes| U[Block: over_threshold:sexual]
    T -->|No| V{violence >= 3?}
    
    V -->|Yes| W[Block: over_threshold:violence]
    V -->|No| X{hate >= 4?}
    
    X -->|Yes| Y[Block: over_threshold:hate]
    X -->|No| Z{selfHarm >= 3?}
    
    Z -->|Yes| AA[Block: over_threshold:selfHarm]
    Z -->|No| AB[Approve Spot]
    
    U --> AC[Show Violation Message]
    W --> AC
    Y --> AC
    AA --> AC
    
    R --> AC
    AB --> AD[Show Success Banner]
    AD --> AE[Dismiss PostFlowView]
    AE --> AF[Refresh Feed]
    
    AC --> AG[Set isPosting = false]
    P --> AG
    
    style A fill:#e1f5ff
    style AD fill:#c8e6c9
    style M fill:#fff9c4
    style AC fill:#ffcdd2
    style P fill:#ffcdd2
\`\`\`

**Moderation Thresholds:**
- **Sexual Content**: Block at score ≥ 3
- **Violence**: Block at score ≥ 3
- **Hate Speech**: Block at score ≥ 4
- **Self-Harm**: Block at score ≥ 3

**Key Components:**
- `ModerationPolicy`: Evaluates scores against thresholds
- `PostFlowView.awaitModerationAndFinish()`: Polls for status
- Cloud Function: Processes images and updates documents

---

## Component Architecture

### View Layer
\`\`\`
Views/
├── Auth/
│   ├── LoginView
│   ├── SignupView
│   └── ConfirmEmailView
├── Home/
│   ├── HomepageView
│   └── MapView
├── PostFlow/
│   ├── PostFlowView
│   ├── PhotoSelectionView
│   ├── LocationSelectionView
│   └── VibeSelectionView
├── Profile/
│   └── ProfileView
└── Components/
    └── SpotCard
\`\`\`

### ViewModel Layer
\`\`\`
ViewModels/
├── AuthViewModel (EnvironmentObject)
├── FeedViewModel
├── ProfileViewModel
└── SearchViewModel
\`\`\`

### Service Layer
\`\`\`
Services/
├── Auth/
│   └── AuthService
├── Spots/
│   ├── SpotService
│   └── SpotUploader
├── Feed/
│   ├── FeedRepository
│   ├── FeedRanker
│   └── FeedCandidateService
├── Search/
│   └── SearchService
└── UserSpotService
\`\`\`

### Data Models
\`\`\`
Models/
├── Spot
├── User
├── Place
└── VibeTag
\`\`\`

---

## Data Flow

### Authentication Flow
\`\`\`
LoginView → AuthViewModel → AuthService → Firebase Auth
                                    ↓
                            Firestore (User Document)
                                    ↓
                            AuthViewModel (State Update)
                                    ↓
                            RootView (Route to Home)
\`\`\`

### Posting Flow
\`\`\`
PostFlowView → SpotUploader → Firebase Storage (Images)
                                    ↓
                            Firestore (Spot Document)
                                    ↓
                            Cloud Function (Moderation)
                                    ↓
                            PostFlowView (Poll Status)
                                    ↓
                            FeedRepository (Refresh)
\`\`\`

### Feed Flow
\`\`\`
HomepageView → FeedViewModel → FeedRepository
                                    ↓
                            FeedCandidateService (Fetch)
                                    ↓
                            AuthorPrivacyCache (Filter)
                                    ↓
                            FeedRanker (Score & Blend)
                                    ↓
                            FeedViewModel (Update State)
                                    ↓
                            HomepageView (Render)
\`\`\`

---

## Key Design Decisions

### 1. Privacy Filtering
- **AuthorPrivacyCache**: Actor-based cache for thread-safe privacy checks
- **Denormalization**: \`authorIsPrivate\` stored on spot documents
- **Batch Fetching**: Chunked queries to minimize Firestore reads

### 2. Feed Ranking
- **On-Device Ranking**: Reduces server load, enables real-time personalization
- **Weighted Scoring**: Configurable weights for different signals
- **Creator Diversity**: Caps per-creator spots to prevent feed dominance

### 3. Image Moderation
- **Async Processing**: Non-blocking upload with polling
- **Client-Side Evaluation**: \`ModerationPolicy\` evaluates scores locally
- **Graceful Degradation**: Timeout handling for slow moderation APIs

### 4. State Management
- **Shared Repositories**: \`FeedRepository.shared\` for single source of truth
- **Environment Objects**: \`AuthViewModel\` accessible throughout app
- **Optimistic Updates**: Immediate UI updates with rollback on failure

### 5. Error Handling
- **Structured Logging**: \`SpotLogger\` with consistent format
- **User-Friendly Messages**: Mapped error codes to readable text
- **Retry Logic**: Built into pagination and moderation polling

---

## Performance Optimizations

1. **Privacy Cache**: 5-minute TTL reduces Firestore reads
2. **Batch Queries**: Chunked \`whereField(..., in: [...])\` queries
3. **Image Compression**: JPEG 0.7 quality before upload
4. **Lazy Loading**: \`LazyVStack\` for feed rendering
5. **Pagination**: Cursor-based pagination with \`DocumentSnapshot\`
6. **Deduplication**: Prevents duplicate spots in feed

---

## Security Considerations

1. **Reauthentication**: Required for sensitive operations (delete account)
2. **Privacy Filtering**: Server-side rules + client-side cache
3. **Input Validation**: Username, email, and location validation
4. **Moderation**: Content moderation before public visibility
5. **Firestore Rules**: Server-side security rules for data access

---

## Future Enhancements

1. **Offline Support**: Local caching with sync
2. **Push Notifications**: Real-time updates for interactions
3. **Analytics**: Event tracking and user behavior analysis
4. **A/B Testing**: Feed algorithm experimentation
5. **Advanced Search**: Full-text search with Algolia or similar