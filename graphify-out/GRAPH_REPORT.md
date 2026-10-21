# Graph Report - Kinect  (2026-10-20)

## Corpus Check
- Corpus is ~12,304 words - fits in a single context window. You may not need a graph.

## Summary
- 400 nodes · 841 edges · 17 communities (14 shown, 3 thin omitted)
- Extraction: 92% EXTRACTED · 8% INFERRED · 0% AMBIGUOUS · INFERRED: 66 edges (avg confidence: 0.85)
- Token cost: 0 input · 0 output

## Community Hubs (Navigation)
- Activity Status & Reports Models
- Activity Detail Ticket UI
- App Entry & Profile Models
- Activity Forms & Auth Views
- Theme & Status Styling
- Activity Core Model
- Feedback & Metrics Services
- Activity Service Layer
- Supabase Schema & Triggers
- Moderation Actions Service
- Activity Form Edit/Create Logic
- Project Setup Documentation
- Custom Tab Bar Navigation
- Activity Discover/Explore Screen
- Card Styling ViewModifier
- Swift Package Manifest

## God Nodes (most connected - your core abstractions)
1. `Activity` - 37 edges
2. `ActivityDetailView` - 27 edges
3. `SupabaseManager` - 25 edges
4. `ActivityFormView` - 20 edges
5. `ActivityLevel` - 18 edges
6. `AuthStore` - 18 edges
7. `ReportReason` - 15 edges
8. `ActivityFilter` - 14 edges
9. `ActivityListView` - 14 edges
10. `ActivityFeedback` - 12 edges

## Surprising Connections (you probably didn't know these)
- `.body` --calls--> `RootView`  [INFERRED]
  Sources/Kinect/KinectApp.swift → Sources/Kinect/Views/RootView.swift
- `xtool` --references--> `xtool.yml Configuration`  [INFERRED]
  docs/SETUP.md → xtool.yml
- `.body` --references--> `Activity`  [INFERRED]
  Sources/Kinect/Views/Activities/ActivityListView.swift → Sources/Kinect/Models/Activity.swift
- `.body` --references--> `Activity`  [INFERRED]
  Sources/Kinect/Views/Activities/ActivityRowView.swift → Sources/Kinect/Models/Activity.swift
- `.body` --references--> `Activity`  [INFERRED]
  Sources/Kinect/Views/Activities/FeaturedActivityCard.swift → Sources/Kinect/Models/Activity.swift

## Import Cycles
- None detected.

## Hyperedges (group relationships)
- **Supabase Backend Setup Flow** — docs_setup_supabase_cli, docs_setup_supabase_migrations, docs_setup_seed_sql, docs_setup_secrets_swift [EXTRACTED 0.90]

## Communities (17 total, 3 thin omitted)

### Community 0 - "Activity Status & Reports Models"
Cohesion: 0.08
Nodes (33): ActivityExplicitStatus, abierta, cancelada, ActivityReport, NewActivityReport, ReportReason, actividadFalsa, contenidoInapropiado (+25 more)

### Community 1 - "Activity Detail Ticket UI"
Cohesion: 0.11
Nodes (21): SectionHeaderView, .body, StickyActionBar, .body, View, ActivityDetailView, .body, .body (+13 more)

### Community 2 - "App Entry & Profile Models"
Cohesion: 0.07
Nodes (11): Foundation, KinectApp, .body, Profile, ProfileUpdate, AuthStore, .isAdmin, .isSignedIn (+3 more)

### Community 3 - "Activity Forms & Auth Views"
Cohesion: 0.06
Nodes (19): ReportActivityView, .body, AuthView, .body, .canSubmit, Mode, signIn, signUp (+11 more)

### Community 4 - "Theme & Status Styling"
Cohesion: 0.08
Nodes (24): ActivityStatus, abierta, cancelada, completa, finalizada, .label, ButtonStyle, .fitcomInk (+16 more)

### Community 5 - "Activity Core Model"
Cohesion: 0.09
Nodes (16): ActivityEdit, ActivityLevel, avanzado, cualquierNivel, .id, intermedio, .label, principiante (+8 more)

### Community 6 - "Feedback & Metrics Services"
Cohesion: 0.10
Nodes (10): ActivityFeedback, NewActivityFeedback, FeedbackService, CapacitySnapshot, MetricsService, UsageMetrics, UsageMetricsView, .body (+2 more)

### Community 7 - "Activity Service Layer"
Cohesion: 0.15
Nodes (7): Activity, .canAcceptParticipants, ActivityService, CoordinationLinkParams, InsertedRow, ParticipationService, SupabaseManager

### Community 8 - "Supabase Schema & Triggers"
Cohesion: 0.19
Nodes (18): activities_after_insert_add_organizer, activities_before_update, activities_set_updated_at, on_auth_user_created, participations_before_change, profiles_set_updated_at, public.activities, public.activities_public (+10 more)

### Community 9 - "Moderation Actions Service"
Cohesion: 0.17
Nodes (7): ModerationActionType, ocultar, restablecer, NewModerationAction, ModerationService, ReportsModerationView, .body

### Community 10 - "Activity Form Edit/Create Logic"
Cohesion: 0.16
Nodes (9): ActivityFormView, .body, .canSave, .capacity, .estimatedCost, .isEditing, SaveAction, create (+1 more)

### Community 11 - "Project Setup Documentation"
Cohesion: 0.14
Nodes (13): Docker (local Supabase requirement), FITCOM (Kinect) iOS App, Secrets.swift (Supabase keys template), supabase/seed.sql (test data), Supabase Backend, Supabase CLI, supabase/migrations (DB schema), SwiftUI (+5 more)

### Community 12 - "Custom Tab Bar Navigation"
Cohesion: 0.27
Nodes (7): FitcomTab, create, explore, mine, profile, FitcomTabBar, .body

### Community 13 - "Activity Discover/Explore Screen"
Cohesion: 0.22
Nodes (6): ActivityListView, .availableSports, .greeting, .header, .initials, .searchBar

## Knowledge Gaps
- **75 isolated node(s):** `PackageDescription`, `principiante`, `intermedio`, `avanzado`, `cualquierNivel` (+70 more)
  These have ≤1 connection - possible missing edges or undocumented components. (Counts symbols only; 124 node(s) total have ≤1 connection when file, concept and rationale nodes are included.)
- **3 thin communities (<3 nodes) omitted from report** — run `graphify query` to explore isolated nodes.

## Suggested Questions
_Questions this graph is uniquely positioned to answer:_

- **Why does `View` connect `Activity Detail Ticket UI` to `Activity Forms & Auth Views`, `Theme & Status Styling`, `Activity Core Model`, `Feedback & Metrics Services`, `Moderation Actions Service`, `Activity Form Edit/Create Logic`, `Custom Tab Bar Navigation`, `Activity Discover/Explore Screen`, `Card Styling ViewModifier`?**
  _High betweenness centrality (0.260) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `Activity` (e.g. with `.body` and `.body`) actually correct?**
  _`Activity` has 3 INFERRED edges - model-reasoned connections that need verification._
- **What connects `PackageDescription`, `principiante`, `intermedio` to the rest of the system?**
  _75 weakly-connected nodes found - possible documentation gaps or missing edges._
- **Should `Activity Status & Reports Models` be split into smaller, more focused modules?**
  _Cohesion score 0.07729468599033816 - nodes in this community are weakly interconnected._
- **Why does `Activity` connect `Activity Service Layer` to `Activity Status & Reports Models`, `Activity Detail Ticket UI`, `Theme & Status Styling`, `Activity Core Model`, `Activity Form Edit/Create Logic`, `Activity Discover/Explore Screen`?**
  _High betweenness centrality (0.146) - this node is a cross-community bridge._
- **Are the 3 inferred relationships involving `ActivityDetailView` (e.g. with `.body` and `.body`) actually correct?**
  _`ActivityDetailView` has 3 INFERRED edges - model-reasoned connections that need verification._
- **Should `Activity Detail Ticket UI` be split into smaller, more focused modules?**
  _Cohesion score 0.10887949260042283 - nodes in this community are weakly interconnected._