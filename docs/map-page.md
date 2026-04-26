# Map Page (Discovery Map)

This document describes the **Map** tab end-to-end: the UI composition, state machine, lifecycle, MapKit integration, viewport-driven data pipeline, caching, and server contract. It is written against the current implementation in the codebase.

> The map is the second tab in `BottomTabNavigationView` (`selectedTab == 1`) and is constructed as `MapView(spots: [])` — the `spots` argument is a vestigial init parameter; data is always loaded from the view model.

> Spot has **three map surfaces**:
> 1. The global discovery map (this doc, sections 1–12).
> 2. The per-user **profile map** embedded inside `ProfileView` (section 13).
> 3. The post-flow **location picker** (`LocationMapView`) used by both `LocationSelectionView` and `EditSpotView` to capture/adjust a spot's coordinates (section 14).
>
> Surfaces 1 and 2 are *display* maps (render existing spots) built on `MKMapView` via UIViewRepresentable. Surface 3 is a *picker* map (capture coordinates) built on SwiftUI's native `Map`. They share visual language (same `green_marker` asset, same forced light mode) but differ in implementation, data flow, and lifecycle.

---

## 1) Module map

| Layer | File | Role |
| --- | --- | --- |
| Discovery UI | `Spot/Views/Home/MapView.swift` | SwiftUI screen, `ClusteredSpotMap` (UIViewRepresentable wrapper around `MKMapView`), `FullBleedPanel` bottom sheet |
| Profile UI | `Spot/Views/Components/ProfileMapView.swift` | Embedded inside `ProfileView`'s `"Map"` tab; renders only the profile owner's spots (see section 13) |
| Location picker UI | `Spot/Views/PostFlow/LocationSelectionView.swift` (`LocationMapView`) | Sheet shown by `LocationSelectionView` and `EditSpotView` to confirm or adjust a spot's coordinates (see section 14) |
| Marker asset | `Spot/Views/Components/SpotMapMarker.swift` | SwiftUI marker view + `SpotAnnotation` model (used by previews / legacy SwiftUI Map path) |
| View model | `Spot/ViewModels/MapViewModel.swift` | Holds `visibleSpots`, debounces region loads, merges results (discovery map only) |
| Loader (actor) | `Spot/Services/Map/MapViewportLoader.swift` | Talks to Supabase RPC (v2) or Firestore (legacy), caches per quantized viewport |
| RPC client | `Spot/Services/Feed/FeedAPI.swift` | `fetchMapSpots(...)` calls `public.get_map_spots_v1`, batch-signs primary images |
| Flags | `Spot/Services/Feed/FeedFlags.swift` | `useSupabaseMapRPC` (default `true`) toggles v2 vs legacy path |
| Telemetry | `Spot/Models/Logs/MapViewLogs.swift`, `MapViewModelLogs.swift`, `FeedSupabaseLogs.swift` | Structured logs for the screen, VM, and RPC layer |
| Engagement | `Spot/Services/Feed/FeedEventService.swift` | Records `map_pin_tap` and `detail_open` events when a discovery pin is selected |
| Location | `Spot/Managers/LocationManager.swift` | Singleton CoreLocation wrapper; supplies `getUserRegion()` and `userLocation` |
| Detail render | `Spot/Views/Components/SpotCard.swift` | Card rendered inside both maps' bottom panels after a pin tap |

---

## 2) UI composition

### Screen layout (top → bottom)

```
NavigationStack
└── GeometryReader
    └── ZStack(alignment: .bottom)
        ├── ClusteredSpotMap            ← full-bleed MKMapView (UIViewRepresentable)
        │   • map.showsUserLocation = true
        │   • mapStyle: standard, POIs excluded, no traffic
        │   • forced light mode
        │
        └── safeAreaInset(edge: .bottom) → bottomInset(height:)
            └── FullBleedPanel?         ← present only when selectedSpot != nil
                ├── X close button (top-leading)
                └── SpotCard(source: "Map")
```

The split between the map and the bottom panel is achieved with **`.safeAreaInset(edge: .bottom)`** instead of stacking sheets. This keeps the underlying `MKMapView` continuously alive — important because tearing down/recreating the Metal-backed map view during a sheet transition was causing a Metal command-buffer crash. The map simply gets a smaller drawable area when a spot is selected.

### Key SwiftUI `@State` on `MapView`

| State | Purpose |
| --- | --- |
| `mapVM: MapViewModel` (`@StateObject`) | Holds the `visibleSpots` published array |
| `locationManager: LocationManager` (`@StateObject`, singleton) | Drives initial centering on the user |
| `cameraPosition: MapCameraPosition` | Used by the legacy SwiftUI `Map` (kept around but unused on the active path) |
| `selectedSpot: Spot?` | Drives the bottom panel; `nil` means panel collapsed |
| `hasPerformedInitialFit: Bool` | One-shot guard so we only auto-fit once on appear |
| `regionLoadTask: Task<Void, Never>?` | Cancellable handle reserved for future view-level debouncing |
| `refitRequestID: Int` | Bumping it asks `ClusteredSpotMap` to re-fit annotations on the next pass (used after closing the panel) |

### Bottom panel sizing

`openPanelHeight(in:)` computes the panel's height every layout pass instead of hard-coding it. It scales with available height and orientation:

- compact vertical size class → 40% of the height
- regular vertical size class → 55% of the height
- floor of 280pt, ceiling of 92% of the screen

The panel uses a spring transition (`.spring(response: 0.32, dampingFraction: 0.85)`) and a `.move(edge: .bottom)` insertion/removal. It paints `Constants.Colors.background` and ignores the bottom safe area so it visually merges with the home indicator.

### Navigation chrome

- The native nav bar is hidden (`.toolbar(.hidden, for: .navigationBar)`).
- The `NavigationStack` registers a `Route.profile(userId:)` destination so taps inside the embedded `SpotCard` (e.g. on the author avatar) can push `ProfileView`.
- The top safe area is also painted with `Constants.Colors.background` to avoid a white notch strip in light mode.

---

## 3) The MapKit layer (`ClusteredSpotMap`)

`ClusteredSpotMap` is a `UIViewRepresentable` that wraps `MKMapView`. SwiftUI's native `Map` is intentionally *not* used on this screen because we need:

1. Native MKMapView clustering (`MKClusterAnnotation`),
2. Custom annotation views with the `green_marker` asset,
3. Predictable Metal teardown to avoid the crash mentioned above.

### `makeUIView`

```text
let map = MKMapView(frame: .zero)
map.delegate = coordinator
map.pointOfInterestFilter = .excludingAll
map.showsTraffic = false
map.showsUserLocation = true
map.overrideUserInterfaceStyle = .light
map.preferredConfiguration = MKStandardMapConfiguration(
    elevationStyle: .flat,
    emphasisStyle: .default
)
map.register(MKAnnotationView.self,            forAnnotationViewWithReuseIdentifier: "SpotImage")
map.register(MKMarkerAnnotationView.self,      forAnnotationViewWithReuseIdentifier: MKMapViewDefaultClusterAnnotationViewReuseIdentifier)
map.setRegion(LocationManager.shared.getUserRegion(), animated: false)
```

The default region is the user's location (5km radius) when CoreLocation has resolved; otherwise **Miami Beach (25.7907, -80.1300)** is the hard-coded fallback (`LocationManager.defaultLocation`).

### `updateUIView` — diffing annotations

Each SwiftUI render passes a fresh `spots: [Spot]` array. The representable diffs by `Spot.id`:

```text
if existingIds != newIds:
    map.removeAnnotations(existing)
    map.addAnnotations(new SpotPointAnnotation list)
    if currentCenter is within 10km of LocationManager.getUserRegion()
       OR there were no existing annotations:
       map.showAnnotations(new, animated: false)   // auto-fit
```

The 10km guard prevents auto-zooming away after the user has manually panned to another part of the world.

It also honors a `refitRequestID: Int`. When the parent view bumps that integer (currently only when the user closes the bottom panel), `updateUIView` re-fits all current `SpotPointAnnotation`s with `showAnnotations(animated: true)`.

### `dismantleUIView` — Metal-safe teardown

To avoid Metal command-buffer crashes when SwiftUI reclaims the host view, dismantling explicitly:

1. Nils the delegate.
2. Removes annotations and overlays.
3. Disables `showsUserLocation`.
4. Hides the view (`isHidden`, `alpha = 0`).
5. Schedules a 150ms `DispatchQueue.main.asyncAfter` no-op so Metal has time to flush the in-flight frame before the view is freed.

### Annotations and clustering — `MKMapViewDelegate`

```text
mapView(_:viewFor annotation:):
    if MKUserLocation                  → return nil   (use Apple's default blue dot)
    if MKClusterAnnotation             → MKMarkerAnnotationView, primary color tint
    if SpotPointAnnotation             → MKAnnotationView with image = "green_marker"
                                         clusteringIdentifier = "spot"
                                         centerOffset = (0, -h * 0.4)  // tip-on-coordinate
                                         canShowCallout = false
    fallback (asset missing)           → MKMarkerAnnotationView, primary tint
```

Because every `SpotPointAnnotation` shares `clusteringIdentifier = "spot"`, MapKit auto-clusters them at far zoom levels. Tapping a cluster runs:

```text
mapView.showAnnotations(cluster.memberAnnotations, animated: true)
```

…which zooms the camera to the bounding region of the cluster's children, expanding it.

### Pin selection flow

```text
mapView(_:didSelect view:)
    cluster?     → expand cluster (above)
    spot pin?    → set region span to 0.01° × 0.01° around the pin (close-up zoom)
                   parent.onSelect(spot, coordinate)
                       → MapView.select(spot, coord)
                            selectedSpot = spot
                            FeedEventService.record(.mapPinTap, spotId: spot.id)
                            FeedEventService.record(.detailOpen, spotId: spot.id,
                                                    metadata: ["surface": "map_panel"])
```

`map_pin_tap` and `detail_open` are durable engagement events; they hit `record_feed_event_v1` and feed the user/vibe affinity tables that personalize the home feed ranker. The map screen is therefore one of the inputs to home feed personalization.

### Camera updates from the user's location

`CLLocationManagerDelegate` updates land in `LocationManager.userLocation`. `MapView` listens via `.onChange(of: locationManager.userLocation)` and, **only on the very first non-nil value with no spot already selected**, calls `updateCameraToUser()` (which re-bases the SwiftUI camera on the user region). Independently, the `MKMapViewDelegate` also handles `didUpdate userLocation` and one-shot recenters the underlying MKMapView with `setRegion` on first fix.

This dual path is intentional: the SwiftUI camera state is kept correct for any future SwiftUI `Map` usage, while the MKMapView is recentered immediately by the delegate so the user doesn't see the camera "jump twice".

---

## 4) Data pipeline

### Sequence diagram

```mermaid
sequenceDiagram
    participant Map as MKMapView (delegate)
    participant View as MapView
    participant VM as MapViewModel
    participant Loader as MapViewportLoader (actor)
    participant RPC as FeedAPI
    participant PG as Supabase / Postgres
    participant Storage as Supabase Storage

    Map->>View: regionDidChangeAnimated(region)
    View->>VM: loadForRegion(region)
    VM->>VM: cancel prior task; sleep 250ms (debounce)
    VM->>Loader: load(region, perTileLimit=250)
    Loader->>Loader: compute bbox + quantized cache key
    alt cache hit (TTL 60s)
        Loader-->>VM: cached [Spot]
    else cache miss
        Loader->>RPC: fetchMapSpots(min/max lat/lng, center, limit)
        RPC->>PG: rpc("get_map_spots_v1", params)
        PG-->>RPC: [MapSpotRow]
        RPC->>Storage: createSignedURLs(paths, expiresIn: 7d)
        Storage-->>RPC: signed URLs
        RPC-->>Loader: rows + url map
        Loader->>Loader: rows.map(toSpot(primaryURL:))
        Loader->>Loader: cache + LRU bookkeeping
        Loader-->>VM: hydrated [Spot]
    end
    VM->>VM: mergeRetainingExisting(current, fresh)
    VM-->>View: visibleSpots = merged
    View-->>Map: updateUIView diff → addAnnotations
```

### Step-by-step

#### A. Region change → debounced load

Every region change emits a `regionDidChangeAnimated` callback. `MapView` forwards it to `MapViewModel.loadForRegion(_:)` only when `FeedFlags.useSupabaseMapRPC` is `true` (which it is by default).

`loadForRegion` debounces with **250ms** of `Task.sleep`. Each new call cancels the previous task, so rapid pan/zoom collapses into a single fetch once motion settles.

```swift
func loadForRegion(_ region: MKCoordinateRegion, limit: Int = 250) {
    regionLoadTask?.cancel()
    regionLoadTask = Task { [weak self] in
        try? await Task.sleep(nanoseconds: 250_000_000)
        if Task.isCancelled { return }
        // ... call MapViewportLoader and assign visibleSpots
    }
}
```

#### B. Bounding box + quantized cache key

`MapViewportLoader.loadFromRPC` derives a `BoundingBox` from `region.center ± span/2`, clamped to `(-90…90, -180…180)` with a **0.001° floor** on each half-span (prevents degenerate zero-area bounds at extreme zoom-in).

It then computes a **quantized cache key** — bbox edges are rounded to a coarse grid that scales with viewport span:

| Span (°) | Grid step (°) |
| --- | --- |
| > 5 | 1.0 |
| > 1 | 0.25 |
| > 0.25 | 0.05 |
| > 0.06 | 0.01 |
| ≤ 0.06 | 0.0025 |

This lets adjacent micro-pans hit the same cache slot. Cache entries TTL after **60 seconds** and are bounded by a **32-entry LRU**.

#### C. RPC: `get_map_spots_v1`

`FeedAPI.fetchMapSpots(...)` POSTs:

```text
rpc("get_map_spots_v1", {
  p_min_lat, p_min_lng,
  p_max_lat, p_max_lng,
  p_center_lat, p_center_lng,
  p_limit          // default 250
})
```

The Postgres function runs a PostGIS bounding-box query on `public.spots`, applies the same privacy/blocking rules as `get_home_feed_v1` (private accounts only visible if the viewer follows them; blocked authors filtered out), and returns up to `p_limit` rows ordered by `distance_meters` from the viewport center.

Each row is a **`MapSpotRow`** (DTO), decoded from snake_case JSON:

```swift
struct MapSpotRow {
    let spotId: UUID
    let userId: UUID
    let vibeTagId: UUID?
    let caption: String?
    let latitude: Double?
    let longitude: Double?
    let locationName: String?
    let createdAt: Date?
    let authorUsername: String?
    let authorProfileImageUrl: String?
    let vibeName: String?
    let primaryStoragePath: String?
    let primaryPublicUrl: String?
    let distanceMeters: Double?
}
```

Note this is **lighter than `HomeFeedRow`** — no like/save counts, no `seen_before`, no full image array — because the map only needs to drop a single pin per spot.

#### D. Primary image signing (batched)

Map cells display one thumbnail; `FeedAPI.resolvePrimaryImageURLs(for: rows)` resolves all of them in **one batched call** to Supabase Storage:

1. Rows whose `primaryPublicUrl` is already an absolute `http(s)` URL pass through unchanged.
2. Remaining `primaryStoragePath` (or, for legacy rows, `primaryPublicUrl` used as a path) are deduped and submitted to `supabase.storage.from("spots").createSignedURLs(paths, expiresIn: 604_800)` — a 7-day signed URL.
3. The resulting `[UUID: String]` map is keyed by `spotId`.

This keeps the request count low even on dense urban viewports — a 250-pin response yields one RPC + one batched signing call, not 251 round trips.

#### E. Hydration → `Spot`

Each row is converted via `MapSpotRow.toSpot(primaryURL:)`:

```swift
Spot(
    id: spotId.uuidString,
    userId: userId.uuidString,
    username: authorUsername,
    userProfileImageURL: authorProfileImageUrl,
    imageURL: primaryURL,
    thumbnailURL: primaryURL,
    vibeTag: vibeName,
    vibeTags: vibeName.map { [$0] },
    latitude: latitude,
    longitude: longitude,
    locationName: locationName,
    likes: nil, isLiked: nil, isSaved: nil,
    createdAt: createdAt,
    authorIsPrivate: nil,
    imageURLs: nil      // full gallery loaded lazily by the detail panel
)
```

`likes`, `isLiked`, `isSaved`, and `imageURLs` are deliberately `nil`. When a user taps a pin, the embedded `SpotCard` lazily fetches the full gallery via `FeedAPI.fetchAllImageURLs(for:)` and lazily resolves like/save state through the regular spot-detail services. That keeps the map render path fast.

#### F. Merge into `visibleSpots`

`MapViewModel.mergeRetainingExisting` keeps already-rendered pins on screen during a viewport-driven refetch. Without it, panning briefly would clear all pins and re-add them, causing flicker:

```swift
var byId: [String: Spot] = [:]
for s in current { byId[s.id!] = s }
for s in fresh   { byId[s.id!] = s }   // fresh wins on conflict (newer signed URL)
return Array(byId.values)
```

Fresh rows always win on conflict because their primary URLs may be newer signed values. The `ClusteredSpotMap.updateUIView` diff then only removes/adds the deltas.

---

## 5) Lifecycle hooks

### `onAppear`

```text
locationManager.startUpdatingLocation()
performInitialFitIfNeeded()
if FeedFlags.useSupabaseMapRPC:
    mapVM.loadForRegion(LocationManager.shared.getUserRegion())   // first paint
else:
    mapVM.loadAllSpots()                                          // legacy
```

`performInitialFitIfNeeded()` is a one-shot helper:

- if there are already valid spots cached in `visibleSpots`, do nothing — the next region change will trigger a refresh anyway.
- otherwise, recenter the SwiftUI camera on the user region.

### `onDisappear`

```text
locationManager.stopUpdatingLocation()
selectedSpot = nil          // collapse panel; releases SpotCard's image references
mapVM.clearVisibleSpots()   // also cancels pending region load
regionLoadTask?.cancel()
regionLoadTask = nil
```

Clearing `selectedSpot` before dismantling is important; it lets `SpotCard` release any large image data it's holding before MapKit's Metal teardown runs.

### `onChange(of: locationManager.userLocation)`

Fires the very first time CoreLocation resolves a fix. Recenters the SwiftUI camera **only if** no spot is currently selected and we haven't done the initial fit yet — so a user who starts panning before location resolves doesn't get yanked back.

### `onChange(of: mapVM.visibleSpots)`

Calls `performInitialFitIfNeeded()` again. Idempotent because of the `hasPerformedInitialFit` guard.

---

## 6) Bottom panel (`FullBleedPanel`)

```text
VStack(spacing: 0) {
    HStack {                                   // close affordance
        Button(action: onClose) {
            Image(systemName: "xmark")
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Constants.Colors.primary)
                .padding(8)
        }
        Spacer()
    }
    .padding(.top, 8)
    .padding(.horizontal, 16)

    SpotCard(
        spot: spot,
        showUserInfo: true,
        userId: nil,
        onDelete: { },
        source: "Map"          // identifies origin for analytics inside SpotCard
    )
    .padding(.horizontal, 16)
    .padding(.bottom, 24)
}
.background(Constants.Colors.background)
.ignoresSafeArea(edges: .bottom)
```

### Closing

```swift
private func closePanel() {
    SpotLogger.log(MapViewLogs.homeSheetClose)
    selectedSpot = nil
    refitRequestID += 1   // tell ClusteredSpotMap to refit pins now that we have full height again
}
```

Bumping `refitRequestID` makes `ClusteredSpotMap.updateUIView` re-call `showAnnotations(annotations, animated: true)`, expanding the camera back out to fit all visible pins after the panel collapses.

---

## 7) Feature flags

All flags live in `Spot/Services/Feed/FeedFlags.swift`:

| Flag | Default | Meaning for the map |
| --- | --- | --- |
| `useSupabaseMapRPC` | `true` | When `true`, map uses `get_map_spots_v1` + PostGIS. When `false`, falls back to the legacy Firestore geohash tile loader. The `loadAllSpots` legacy entrypoint is a no-op under the v2 flag (see `MapViewModel.loadAllSpots`). |
| `pageSize` | 24 | Not used by the map directly, but `MapViewportLoader.load` takes a `perTileLimit` (default 250 for Supabase, 200 for legacy) — these are independent budgets. |

The flag gating is checked **at every callsite** rather than at boot, so the path can be flipped at runtime in debug builds without restarting.

### Legacy Firestore path (kept for emergency rollback)

When `useSupabaseMapRPC = false`, `MapViewportLoader.loadFromGeohashTiles` runs:

1. Compute geohash precision from `region.span.latitudeDelta` (4 → 8 chars depending on zoom).
2. Take the center prefix + its 8 neighbors (covers viewport edges).
3. For each missing prefix, run a Firestore query:
   ```text
   collection("spots")
     .order(by: "geohash")
     .where("geohash", >=, prefix)
     .where("geohash", <,  endRange(prefix))
     .limit(perTileLimit)
   ```
4. Fan-in results, cache per-prefix in a 128-entry actor-local dictionary.
5. Pass through `AuthorPrivacyCache.filter(spots:)` (privacy/follow/block enforcement is **client-side** on this path; Postgres does it server-side on the v2 path).

This path is functionally complete but not the active one and is documented here only for rollback context.

---

## 8) Telemetry / logging

| Event | Where | When |
| --- | --- | --- |
| `MapViewLogs.homeSheetClose` | `MapView.closePanel()` | User taps the X to close the bottom panel |
| `MapViewModelLogs.mapLoadedAllSpots` | `MapViewModel.loadForRegion` (and legacy `loadAllSpots`) | After every successful viewport fetch; details: `count` returned, `merged` size after dedupe |
| `MapViewModelLogs.loadAllSpotsFailed` | `MapViewModel.loadAllSpots` (legacy) | Legacy path failure |
| `FeedSupabaseLogs.mapRPCSucceeded` | `FeedAPI.fetchMapSpots` | RPC OK; details: `returned`, `limit`, `durationMs` |
| `FeedSupabaseLogs.mapRPCFailed` | `FeedAPI.fetchMapSpots` and `MapViewportLoader.loadFromRPC` | RPC threw; details: `error`, `durationMs`, `limit` |
| `FeedSupabaseLogs.primaryImageSigned` | `FeedAPI.batchResolvePrimaryURLs` | Phase = `"map"`; reports `rows`, `signed`, `batchPaths` |
| `FeedSupabaseLogs.primaryImageSignFailed` | Same | Storage signing failed |
| `FeedEventServiceLogs.eventRecorded` | `FeedEventService.fireAndForget` | Each `map_pin_tap` / `detail_open` |

---

## 9) Engagement signals

Tapping a pin records two events (in this order):

1. **`map_pin_tap`** — primary signal that the user opted into a specific pin.
2. **`detail_open`** with `metadata = ["surface": "map_panel"]` — same shape as opening detail from the home feed, lets the server distinguish map-originated detail opens from feed-originated ones.

Both events go through `FeedEventService.record(_:spotId:metadata:)`, which:

- Wraps `record_feed_event_v1` (Postgres function).
- Updates `feed_impressions` (last_seen_at, view_count) **and** `user_vibe_affinities` / `user_creator_affinities`.
- Is fire-and-forget — the UI never blocks on telemetry.

This means **map exploration directly trains the home feed ranker**. A user who only ever discovers via the map still accumulates the affinity signal needed for personalization elsewhere.

---

## 10) Caching summary

| Cache | Layer | Key | Bound | TTL |
| --- | --- | --- | --- | --- |
| Quantized viewport cache | `MapViewportLoader` (actor) | quantized bbox string | 32 entries (LRU) | 60s |
| Geohash tile cache (legacy) | `MapViewportLoader` (actor) | geohash prefix | 128 entries | none (cleared via `clearCache()`) |
| Privacy/follow/block | `AuthorPrivacyCache` | viewer + author IDs | TTL-backed | 5 min |
| Signed image URLs | Supabase server-side | storage path | n/a | 7 days |

`clearCache()` on the loader can be used by callers (e.g. on sign-out) to drop both caches synchronously.

---

## 11) Constants & tunables

| Constant | Value | Source |
| --- | --- | --- |
| Region debounce | 250 ms | `MapViewModel.regionDebounceNs` |
| RPC per-request limit | 250 spots | `MapViewModel.loadForRegion(limit:)` default |
| Pin tap zoom span | 0.01° × 0.01° | `ClusteredSpotMap.Coordinator.didSelect` |
| Auto-fit drift threshold | 10,000 m | `ClusteredSpotMap.updateUIView` |
| Default user region radius | 5,000 m | `LocationManager.getUserRegion(radiusInMeters:)` |
| Default fallback location | Miami Beach (25.7907, -80.1300) | `LocationManager.defaultLocation` |
| Min bbox half-span | 0.001° | `MapViewportLoader.boundingBox` |
| Viewport cache TTL | 60 s | `MapViewportLoader.viewportCacheTTL` |
| Viewport cache LRU cap | 32 | `MapViewportLoader.maxCachedViewports` |
| Signed URL expiry | 604,800 s (7 days) | `FeedAPI.spotImageSignedURLExpirySeconds` |
| Storage bucket | `"spots"` | `FeedAPI.spotsStorageBucketId` |
| Bottom panel min height | 280 pt | `MapView.openPanelHeight` |
| Bottom panel max height | 92% of screen | `MapView.openPanelHeight` |
| Metal flush window | 150 ms | `ClusteredSpotMap.dismantleUIView` |

---

## 12) Failure modes & safeguards

- **Cancellation safety.** Both the VM debounce task and the actor-isolated loader respect `Task.isCancelled`. Pan/zoom storms collapse to a single executed fetch.
- **Empty/error responses are non-destructive.** `MapViewportLoader.loadFromRPC` returns `[]` on failure; `MapViewModel.mergeRetainingExisting` then keeps existing pins on screen rather than blanking the map.
- **Privacy on the wire.** With `useSupabaseMapRPC = true`, Postgres enforces privacy/blocking. The client cannot accidentally leak a private author's pin by skipping a filter step.
- **No location permission.** `LocationManager.getUserRegion()` falls back to the Miami Beach default coordinates, so the map is always viewable.
- **Asset missing.** If `green_marker` is unavailable (asset catalog miss), `viewFor annotation:` falls back to a tinted `MKMarkerAnnotationView` so pins still render.
- **Metal teardown crash.** `dismantleUIView` and the `selectedSpot = nil` on `onDisappear` cooperate to release Metal-backed resources before SwiftUI deallocates the host view.
- **Stale signed URLs.** Cached `Spot` rows are only valid for the cache TTL (60s), well under the 7-day signed-URL expiry. A long-lived session that pans back to an old viewport will refetch (and resign) before URLs could expire.

---

## 13) Profile map (`ProfileMapView`)

Embedded inside `ProfileView` as one of two profile content tabs (`"Spots"` and `"Map"`), the profile map shows **only the profile owner's spots**. It is a separate component from the discovery map and intentionally simpler — it has no viewport loader, no RPC, no cache, and no clustering.

### Where it lives

- File: `Spot/Views/Components/ProfileMapView.swift`
- Used by: `Spot/Views/Profile/ProfileView.swift` (`selectedTab == "Map"`)
- Data source: `ProfileViewModel.spots` (the array already fetched by the profile screen for the `"Spots"` grid; the map just renders the same `[Spot]`).

```text
ProfileView
├── header (full or collapsed depending on selectedSpot / isMapExpanded)
├── tabs row: ["Spots", "Map"]
└── if selectedTab == "Map":
        ProfileMapView(
            spots: viewModel.spots,
            onSpotTap:        { tapped → selectedSpot = tapped },
            onDeleteSpot:     { spot   → showDeleteConfirm },
            onCollapseChange: { expanded → isMapExpanded = expanded }
        )
```

### Component structure

```text
ProfileMapView
└── GeometryReader
    └── ZStack(alignment: .bottom)
        ├── InnerProfileSpotMap            ← UIViewRepresentable around MKMapView
        │   • showsUserLocation NOT set     (it's the profile owner's pins, not the viewer)
        │   • mapStyle: standard, POIs excluded, light mode
        │   • clustering disabled (clusteringIdentifier = nil)
        │
        └── safeAreaInset(edge: .bottom) → insetContent(height:)
            └── ProfileFullBleedPanel?     ← only when selectedSpot != nil
                ├── X close button (top-right)
                └── SpotCard(source: "ProfileMap")
```

### Key differences vs. the discovery map

| Aspect | Discovery map (`MapView`) | Profile map (`ProfileMapView`) |
| --- | --- | --- |
| Data source | `get_map_spots_v1` RPC, viewport-driven | `ProfileViewModel.spots` (already in memory) |
| Loader | `MapViewportLoader` (actor, cached) | None — pure rendering |
| Debounce | 250 ms on region change | n/a |
| Clustering | On (`clusteringIdentifier = "spot"`) | Off (every spot gets its own pin) |
| Panel height | Dynamic (40–55% of screen, 280pt floor) | **Fixed 320 pt** |
| User location | Shown (blue dot) | Not shown |
| Default region | Miami Beach (`LocationManager.defaultLocation`) | Miami Beach hard-coded inline (25.7617, −80.1918) |
| Initial fit | One-shot, only if there are no spots already | Always fits all the user's pins on appear and on `spotsSignature` change |
| Pin tap span | 0.01° × 0.01° | 0.002° × 0.002° (tighter) **+ camera shifted south by `markerOffset`** so the pin sits above the panel |
| Engagement events | `map_pin_tap` + `detail_open` recorded | None recorded by the map; the embedded `SpotCard` records its own events |
| Tab bar handling | n/a | **Hidden while a spot is selected** (`.toolbar(.hidden, for: .tabBar)`) |
| Header coupling | Independent screen | Header collapses in the parent `ProfileView` while the map is expanded |

### Initial region selection

In `init(spots:...)`, `ProfileMapView` precomputes a region from the spots array via the static `regionToFit(_:)` helper:

```text
regionToFit(spots):
    coords = spots.compactMap { (lat, lon) }
    if coords empty → return nil
    bbox = bounding box of coords
    center = bbox center
    latDelta = max(0.02, (maxLat - minLat) * 1.3)        // 30% padding, min 0.02°
    lonDelta = max(0.02, (maxLon - minLon) * 1.3)
    return MKCoordinateRegion(center, span)
```

If no spots exist (empty profile), the camera falls back to a **hard-coded Miami region** (25.7617, −80.1918, 0.1° × 0.1° span). This is intentionally different from `LocationManager.defaultLocation` so the profile map doesn't depend on the location manager's lifecycle.

### Camera management — the "no zoom-out on selection" rule

The defining behavioral quirk of the profile map is that **selecting a spot must always zoom the camera in, never out**. Two pieces of code cooperate to enforce that:

1. **`select(_:_:_:)`** computes a target span:

   ```text
   targetSpan = 0.002° × 0.002°
   if currentSpan < targetSpan:
       finalSpan = currentSpan * 0.5     // already zoomed in tighter — go tighter
   else:
       finalSpan = targetSpan
   ```

2. **`InnerProfileSpotMap.updateUIView`** applies the new region differently depending on `selectedSpot`:

   ```text
   if selectedSpot != nil:
       map.setRegion(region, animated: true)         // always honor zoom-in
   else:
       only call setRegion if center moved > 100 m   // avoid re-snap thrash
   ```

   It also **skips the annotation diff entirely while a spot is selected**, so removing/re-adding the array can't trigger an auto-fit that would zoom back out.

### Marker-offset trick (`markerOffset` default = 100)

When a spot is selected, the camera should put the marker visually above the bottom panel — not under it. `select` converts the desired pixel offset into degrees of latitude using the current span and view height:

```swift
let latPerPoint = baseRegion.span.latitudeDelta / max(viewSize.height, 1)
let adjustedCenter = CLLocationCoordinate2D(
    latitude:  coordinate.latitude  - latPerPoint * markerOffset,   // shift camera SOUTH
    longitude: coordinate.longitude
)
```

Result: the pin lifts ~`markerOffset` points above geometric center, leaving the lower portion of the map free for the 320pt panel.

### `MapCameraPosition` extraction (workaround)

`ProfileMapView` keeps state as a SwiftUI `MapCameraPosition` even though it bridges to a UIKit `MKMapView`. There's no public API to read the underlying `MKCoordinateRegion` from `MapCameraPosition`, so it uses **`Mirror` reflection**:

```swift
private func extractRegion(from position: MapCameraPosition) -> MKCoordinateRegion {
    let mirror = Mirror(reflecting: position)
    for child in mirror.children {
        if let region = child.value as? MKCoordinateRegion { return region }
    }
    return Self.regionToFit(spots) ?? <hard-coded Miami fallback>
}
```

This is fragile across iOS versions but currently necessary; if a future iOS adds public access, this should be the first thing to delete.

### Annotations — `InnerProfileSpotMap`

```text
makeUIView:
    map = MKMapView(frame: .zero)
    map.delegate = coordinator
    map.pointOfInterestFilter = .excludingAll
    map.showsTraffic = false
    map.overrideUserInterfaceStyle = .light
    map.preferredConfiguration = MKStandardMapConfiguration(elevationStyle: .flat)
    register: MKAnnotationView ("SpotImage"), MKMarkerAnnotationView (cluster reuse id)

    initialAnns = spots → ProfileSpotPointAnnotation
    if !initialAnns.isEmpty:
        map.addAnnotations(initialAnns)
        map.showAnnotations(initialAnns, animated: false)   // initial fit
    else:
        map.setRegion(region, animated: false)
```

`viewFor annotation:` is similar to the discovery map but explicitly clears `clusteringIdentifier`. The selected pin is given a 1.3× CGAffineTransform; non-selected pins reset to `.identity`. (Note: the discovery map applies the same scale via SwiftUI's `.scaleEffect` in its inert SwiftUI fallback `SpotMap`; the profile map applies it via UIKit transforms directly on the annotation view.)

### Selection flow

```text
mapView(_:didSelect view:)
    spot pin?    → parent.onSelect(spot, coordinate)
                       → ProfileMapView.select(spot, coord, viewSize)
                            selectedSpot = spot
                            onSpotTap?(spot)              ← hands the spot to ProfileView
                            onCollapseChange?(true)       ← parent collapses its header
                            cameraPosition = adjusted region (zoom in + marker offset)
                            (animated with .spring response 0.32, damping 0.85)
```

Closing the panel:

```text
onClose / onBackToAll:
    selectedSpot = nil
    zoomToFitAllPins()                  ← refit all the user's spots
    onCollapseChange?(false)            ← parent restores full header
```

`onBackToAll` and `onClose` currently do the same thing; the panel header is wired to the X button only, but the API supports a future "Back to all spots" affordance.

### Bottom panel: `ProfileFullBleedPanel`

```text
VStack(spacing: 0):
    ZStack:                            // header strip, height 32
        HStack { Spacer(); Button(xmark, action: onClose) }
    SpotCard(
        spot: spot,
        showUserInfo: true,
        userId: nil,
        onDelete: onDelete,            // bubbles to ProfileView's delete confirm
        source: "ProfileMap"
    )
    .padding(.horizontal, 16)
    .padding(.bottom, 16)
.background(Constants.Colors.background)
.ignoresSafeArea()
```

Critically, the panel uses **`.zIndex(10)`** and `.toolbar(.hidden, for: .tabBar)` is applied at the `ProfileMapView` scope when `selectedSpot != nil`. Without hiding the tab bar, its hit-test rectangle would steal taps on the `SpotCard`'s like/save buttons that overlap the bottom of the panel.

### Lifecycle

| Event | Behavior |
| --- | --- |
| `init` | Computes initial `cameraPosition` from `regionToFit(spots)` or the inline Miami fallback. |
| `onAppear` | If no spot is selected, runs `zoomToFitAllPins()` (animated). |
| `onChange(spotsSignature)` | If no spot is selected, refits all pins. `spotsSignature` is the joined string of spot IDs — changes only when the array contents change, so additions/removals trigger refit but a state-only re-render does not. |
| `onChange(selectedSpot)` | When a spot was selected and is now `nil`, refits all pins. Selection direction is handled inside `select(...)`. |
| `onDisappear` | Sets `selectedSpot = nil` to release `SpotCard` image references before `MKMapView` is dismantled. |
| `dismantleUIView` | Same Metal-safe teardown pattern as the discovery map: nil the delegate, remove annotations/overlays, hide the view, schedule a 150 ms async marker for Metal flush. |

### `ProfileView` ↔ `ProfileMapView` integration

The parent `ProfileView` has its own `selectedSpot` and `isMapExpanded` state, both fed by the callbacks:

- `onSpotTap` → `ProfileView.selectedSpot = tapped`. This is what drives the **collapsed profile header** layout (smaller header strip + larger map area when a spot is selected).
- `onDeleteSpot` → opens the delete confirmation alert in `ProfileView`, then `ProfileViewModel.deleteSpot` performs the optimistic removal from `viewModel.spots`. The change in `viewModel.spots` propagates back into `ProfileMapView`, whose `onChange(spotsSignature)` re-runs `zoomToFitAllPins()`.
- `onCollapseChange` → toggles `isMapExpanded` with a spring animation. This drives the parent's "full header vs. minimal header" branch (`if selectedSpot == nil && !(selectedTab == "Map" && isMapExpanded)`).
- Switching tabs via the `["Spots", "Map"]` row also clears `selectedSpot` so the profile header pops back to full size.

### Constants & tunables (profile map)

| Constant | Value | Source |
| --- | --- | --- |
| Default fallback region center | (25.7617, −80.1918) | `ProfileMapView.init` and `extractRegion` |
| Default fallback span | 0.1° × 0.1° | same |
| Fit-padding multiplier | 1.3× | `regionToFit` |
| Fit min span | 0.02° | `regionToFit` |
| Pin-tap target span | 0.002° × 0.002° | `select(...)` |
| Already-zoomed-in tightening | × 0.5 | `select(...)` |
| Marker offset | 100 pt | `markerOffset` (default arg) |
| Panel height | 320 pt (fixed) | `openPanelHeight(in:)` |
| Region-update threshold (no selection) | 100 m | `InnerProfileSpotMap.updateUIView` |
| Spring | response 0.32, damping 0.85 | `select`, `zoomToFitAllPins`, `closePanel` |
| Metal flush window | 150 ms | `dismantleUIView` |

### What the profile map deliberately does *not* do

- **No RPC.** All rendering is from the in-memory `[Spot]` already on `ProfileViewModel`.
- **No clustering.** A profile is by definition bounded; clustering would hide the user's actual content from a viewer scrolling their map.
- **No engagement telemetry from the map itself.** Pin taps do not record `map_pin_tap` (that event semantically means "discovery surface"). The embedded `SpotCard` continues to record its own `detail_open`-style events when relevant.
- **No CoreLocation usage.** The map never centers on the *viewer's* location — only on the *profile owner's* spots.

## 14) Location picker (`LocationMapView`)

Used by the post-creation flow to **capture** a coordinate (rather than display existing spots). Unlike sections 1–13, this is a SwiftUI-native `Map(position:)` — not an `MKMapView` wrapped in a UIViewRepresentable — and it has no view model, no loader, and no caching layer.

### Where it lives

- File: `Spot/Views/PostFlow/LocationSelectionView.swift` (`struct LocationMapView`)
- Mounted as a **sheet** by two callers:
  - `LocationSelectionView` (creating a new spot): every "Adjust Pin", search-result tap, and "Use as custom place" path sets `selectedLocation` and toggles `showingMap = true`.
  - `EditSpotView` (editing an existing spot's location): tapping "Change" presents the same sheet seeded from the spot's current coords.
- Output: invokes `onConfirm: (LocationData) -> Void` and dismisses.

```text
LocationSelectionView           or          EditSpotView
    └── .sheet(isPresented: $showingMap)
        └── LocationMapView(
                location: <seed LocationData>,
                onConfirm: { selectedLocation = $0; showingMap = false }
            )
```

### Component structure

```text
LocationMapView (NavigationStack > ZStack)
├── Map(position: $position) {
│     UserAnnotation()                         // blue dot when permission granted
│   }
│   • mapStyle: default standard, light mode forced
│   • .onMapCameraChange(frequency: .continuous)   ← drives reverse geocode
│
├── overlay(.center): Image("green_marker")    // fixed pin, allowsHitTesting=false, y-offset −20
│                                              // the MAP moves under the pin, not the pin
│
├── overlay(.topTrailing): VStack {
│       MapUserLocationButton()
│       MapCompass()
│       MapPitchToggle()
│       MapScaleView()
│   }
│
└── VStack {                                   // chrome
        HStack: mappin.circle.fill + currentLocationName        // top "name chip"
        Spacer()
        Button("Confirm Location") { confirmWithUpsert() }      // primary CTA
    }

Toolbar:
    leading "Cancel" → dismiss
```

### Inverted UX: marker is fixed, map moves

This is the defining behavioral difference from the discovery / profile maps. The user pans the map until the desired location is under the **fixed center marker**; they don't tap a pin. The marker is rendered as a SwiftUI overlay with `.allowsHitTesting(false)` so it can never intercept gestures.

`Map`'s underlying region is read every frame via:

```swift
.onMapCameraChange(frequency: .continuous) { context in
    let center = context.region.center
    draggedLocation = LocationData(
        coordinate: center,
        placeName: draggedLocation.placeName,
        address: draggedLocation.address,
        isCustomName: draggedLocation.isCustomName
    )
    geocodeDebouncer.schedule { self.updateDraggedLocation(to: center) }
}
```

`draggedLocation`'s coordinate is updated synchronously every frame (so the UI is always in sync with what the user sees), but the **name** is only refreshed after debouncing.

### Reverse-geocoding pipeline

There are **two debounce layers** stacked here:

1. The shared `Debouncer(interval: 0.85)` (`geocodeDebouncer.schedule`) — collapses many continuous-camera ticks into one call to `updateDraggedLocation`.
2. Inside `updateDraggedLocation`, an **additional** `DispatchQueue.main.asyncAfter(deadline: .now() + 0.85, execute: work)` further delays the actual `CLGeocoder.reverseGeocodeLocation` call. The previous `geocodeWorkItem` is canceled and `geocoder.cancelGeocode()` aborts any in-flight Apple geocode request before queuing a new one.

The geocoder builds a `prettyName` from the placemark by preferring `placemark.name`, falling back to `"<city>, <state>"`, and finally to the previous name. Pretty name only **replaces** `draggedLocation.placeName` if the user hasn't already typed a custom name (`isCustomName == false`). This preserves user-typed labels even as the user keeps panning.

The composed `address` is `"<city>, <state>, <country>"` joined by `", "` with empty parts dropped. Errors land in `LocationSelectionViewLogs.reverseGeocodeFailed` (debug level) and are otherwise silent — including `CLError.network` and `CLError.geocodeFoundNoResult`, both of which are explicitly ignored.

### Initial region

Hard-coded close-up zoom around the seed location (no auto-fit math here):

```swift
init(location: LocationData, onConfirm: ...) {
    let region = MKCoordinateRegion(
        center: location.coordinate,
        span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
    )
    _position = State(initialValue: .region(region))
    _draggedLocation = State(initialValue: location)
    _currentLocationName = State(initialValue: location.placeName)
}
```

The seed `LocationData` always exists when this sheet opens — `LocationSelectionView` only flips `showingMap = true` after `selectedLocation` is set; `EditSpotView` only opens it when `mapSeedLocation` is non-nil.

### Confirmation: optional Firestore upsert

Tapping **Confirm Location** runs `confirmWithUpsert()`:

1. If the selected location is a **custom name** (`isCustomName == true`):
   1. Run `PlaceNameValidator` on `placeName`.
   2. If `.ok(let norm)`, query `places` for `name_lower == norm`. If a doc exists, **merge** updated `latitude`/`longitude`/`address`/`updatedAt`. If not, create a new doc with `{name, name_lower, latitude, longitude, address, createdAt, postsCount: 0, createdBy: <uid>}`.
   3. Failures log `LocationSelectionViewLogs.upsertPlaceFailed` (debug) — non-fatal; the callback still fires.
   4. If validation rejects (`.tooShort`, `.tooLong`, `.blocked`), logs `blockedCustomPlaceSkipUpsert` and returns the location to the caller without writing anything.
2. Non-custom selections (Apple POIs / `places`-collection matches selected from the search list) skip the upsert path entirely — they already exist in `places` or will be referenced by Apple coordinates.
3. Always invokes `onConfirm(selected)` at the end. The dismissal is the caller's responsibility.

So this map does write to the database on a happy path — the only one of the three map surfaces to do so.

### Lifecycle

| Event | Behavior |
| --- | --- |
| `init` | Seeds `position`, `draggedLocation`, `currentLocationName` from the input `LocationData`. |
| `onAppear` | Force-resigns first responder (`UIResponder.resignFirstResponder`) to dismiss any keyboard left over from `LocationSelectionView`'s search field — avoids spurious input-accessory-view layout-constraint console noise. |
| `.onMapCameraChange(.continuous)` | Updates `draggedLocation.coordinate` synchronously; schedules a debounced reverse geocode. |
| `Cancel` toolbar button | Calls SwiftUI `dismiss` — no `onConfirm` invocation. |
| `Confirm Location` button | Runs `confirmWithUpsert` on a `Task`; the upsert is async but the UI does **not** show a loading state. The geocode debounce may still be in flight; the comment notes "Always allow confirm; we'll upsert name later if geocode still running." |

### Important constants

| Constant | Value | Source |
| --- | --- | --- |
| Initial span | 0.01° × 0.01° | `LocationMapView.init` |
| Marker overlay y-offset | −20 pt | `overlay(alignment: .center)` |
| Marker size | 40 × 40 pt | same |
| Geocode debounce (outer) | 0.85 s | `Debouncer(interval: 0.85)` |
| Geocode debounce (inner) | 0.85 s | `DispatchQueue.main.asyncAfter` in `updateDraggedLocation` |
| Forced color scheme | `.light` | `.preferredColorScheme(.light)` |

### Telemetry

All from `LocationSelectionViewLogs`:

| Event | When |
| --- | --- |
| `reverseGeocodeFailed` | `CLGeocoder` returned an error (debug level — most failures are transient) |
| `upsertPlaceFailed` | Firestore write threw during custom-place upsert |
| `blockedCustomPlaceSkipUpsert` | `PlaceNameValidator` rejected the typed name; the upsert is skipped but the coordinate is still returned |

(Other `LocationSelectionViewLogs` cases — `loadingNearbyPlaces`, `searchingPlaces`, etc. — fire from the parent search screen, not from `LocationMapView` itself.)

### Comparison: all three map surfaces side-by-side

| Aspect | Discovery (`MapView`) | Profile (`ProfileMapView`) | Picker (`LocationMapView`) |
| --- | --- | --- | --- |
| Purpose | Browse all spots near a viewport | Browse one user's spots | Capture/edit a coordinate for a new or existing post |
| Underlying view | `MKMapView` via UIViewRepresentable | `MKMapView` via UIViewRepresentable | SwiftUI `Map(position:)` |
| Pins shown | Server-returned `Spot` rows | The profile owner's `Spot` rows | None — only `UserAnnotation` (blue dot) |
| Marker | Tappable pins, clustered | Tappable pins, no cluster | **Fixed center overlay**, non-interactive |
| Selection model | Tap pin → bottom panel | Tap pin → smaller bottom panel + camera shift | No selection — current coord = camera center |
| Data source | `get_map_spots_v1` RPC, viewport-driven | `ProfileViewModel.spots` (already in memory) | Single `LocationData` seed in / single `LocationData` out |
| Caching | Quantized viewport LRU, 60 s TTL | None | None |
| Reverse geocoding | No | No | Yes — debounced 0.85 s |
| Writes to backend | No (read-only) | No (read-only; SpotCard may write engagement events) | **Yes** — optional `places` Firestore upsert on confirm |
| Engagement events | `map_pin_tap`, `detail_open` | None from the map itself | None |
| Tab bar handling | Covered by safeAreaInset panel | Hidden while a spot is selected | n/a (presented as a sheet) |
| Initial region | User location (or Miami Beach default) | Bounding box of profile's spots, or Miami fallback | 0.01° span around seed `LocationData.coordinate` |
| Dismissal | Tab change | `selectedSpot = nil` collapses panel | Cancel toolbar button or post-confirm |
| Color scheme | Forced light | Forced light | Forced light |

The visual language (light mode, `green_marker` asset, primary tint) is consistent across all three so they read as one design system, even though the implementation strategies differ.

## 15) Practical mental model

1. **Show the camera somewhere sensible.** User location → fall back to Miami Beach.
2. **On every settle, ask Postgres for pins inside the bounding box.** Debounced, deduped at the viewport level.
3. **Sign the primary image for each row in one batch.** Skip the full gallery.
4. **Hand `Spot` rows to MapKit, which clusters and renders.** Diff-driven, not full-clear.
5. **On pin tap, record engagement events and slide up a `SpotCard`.** Detail data is fetched lazily inside the card, not by the map.
6. **On disappear, drain it all** — release Metal, cancel tasks, stop CoreLocation.

For the profile map, replace steps 2–4 with: **"render whatever the parent already has, fit the camera to it, never zoom out on selection."**

For the location picker, the entire pipeline is: **"seed → pan → debounce → reverse-geocode → confirm (with optional `places` upsert) → callback."**
