# Leave Ledger

A personal iOS app for tracking Comp Time, Vacation, and Sick leave balances with a calendar-first UX, dual Official/Forecast balance views, and a Supabase backend.

## Architecture

- **Platform:** iOS 17+ / iPadOS (Universal), SwiftUI
- **Local Storage:** SwiftData (offline-first)
- **Backend:** Supabase (Postgres + Edge Functions)
- **Pattern:** MVVM with `@Observable`
- **Auth:** Single-user device UUID stored in Keychain (no login required)

## Project Structure

```
LeaveLedger/
├── LeaveLedger.xcodeproj/
├── LeaveLedger/
│   ├── App/                    # App entry point
│   ├── Models/                 # Data models (LeaveEntry, PayPeriod, UserProfile, enums)
│   ├── Services/               # Business logic
│   │   ├── BalanceEngine.swift     # Core balance calculation engine
│   │   ├── PayPeriodService.swift  # Pay period & payday computation
│   │   ├── DataStore.swift         # SwiftData persistence layer
│   │   ├── SupabaseService.swift   # Supabase REST sync
│   │   ├── ExportService.swift     # CSV & PDF export
│   │   ├── ICSService.swift        # iCal feed generation
│   │   └── KeychainService.swift   # Secure device UUID storage
│   ├── Utilities/              # Date helpers
│   ├── ViewModels/             # AppViewModel (central state)
│   └── Views/                  # SwiftUI views
│       ├── Home/               # Calendar home screen
│       ├── Calendar/           # Month grid components
│       ├── Ledger/             # Leave type ledger tables
│       ├── Settings/           # App settings
│       └── Components/         # Shared components (MainTabView)
├── LeaveLedgerTests/           # Unit tests
└── Assets.xcassets/
supabase/
├── migrations/
│   └── 001_initial.sql         # Database schema
└── functions/
    └── leave-ics/
        └── index.ts            # Edge Function for iCal feed
```

## Setup

### 1. Open in Xcode

```bash
open LeaveLedger/LeaveLedger.xcodeproj
```

Select your development team in Signing & Capabilities. Build and run on a simulator or device running iOS 17+.

### 2. Supabase Configuration (Optional)

The app works fully offline without Supabase. To enable cloud sync:

1. Create a Supabase project at [supabase.com](https://supabase.com)
2. Run the migration:
   ```bash
   # Using Supabase CLI
   supabase db push
   # Or manually run supabase/migrations/001_initial.sql in the SQL Editor
   ```
3. Deploy the Edge Function:
   ```bash
   supabase functions deploy leave-ics
   ```
4. Add your Supabase credentials to the Xcode build settings:
   - In Xcode, select the LeaveLedger target
   - Go to Build Settings > User-Defined
   - Set `SUPABASE_URL` to your project URL (e.g., `https://xxxx.supabase.co`)
   - Set `SUPABASE_ANON_KEY` to your anon/public key

   Alternatively, create a `Config.xcconfig` file:

   ```
   SUPABASE_URL = https://your-project.supabase.co
   SUPABASE_ANON_KEY = your-anon-key-here
   ```

   And reference it in the project's build configuration.

### 3. Create Your Profile

On first launch, the app automatically creates a local profile with default values:

- Anchor Payday: February 6, 2026
- Sick Starting Balance: 801.84 hours
- Vacation Starting Balance: 33.72 hours
- Comp Starting Balance: 0.25 hours
- Sick Accrual Rate: 7.88 hours/payday
- Vacation Accrual Rate: 6.46 hours/payday

All values are editable in Settings.

## How Official vs Forecast Balances Work

### Official Balance

The Official balance represents what has been **posted** — the balance as of the most recent payday that has actually occurred.

- Updated only on paydays
- Includes entries from pay periods whose payday has already passed
- Vacation and Sick accrue automatically on each payday
- Comp has no automatic accrual; only manual entries

### Forecast Balance

The Forecast balance shows what the balance **would be** if all scheduled entries occur through a given date.

- Updates immediately when entries are added/edited/deleted
- Includes all entries with a date on or before the target date
- Includes accruals for all paydays on or before the target date
- Independent of posting — it's a projection

### Posting Rules

| Event                        | Forecast Impact                     | Official Impact                     |
| ---------------------------- | ----------------------------------- | ----------------------------------- |
| Vacation/Sick payday accrual | Included when payday <= target date | Included when payday <= last payday |
| Leave usage entry            | Immediate on entry date             | After pay period's payday occurs    |
| Comp accrual entry           | Immediate on entry date             | After pay period's payday occurs    |
| Adjustment entry             | Immediate on entry date             | After pay period's payday occurs    |

### Pay Period Mapping

Given anchor payday February 6, 2026:

- Pay Period End = Payday - 7 days (January 30)
- Pay Period Start = Pay Period End - 13 days (January 17)
- Period length: 14 days (inclusive)
- Paydays repeat every 14 days

An entry's pay period is determined by its date. The entry is "posted" to Official when that pay period's payday occurs.

## Features

### Calendar View (Home)

- Month grid with Apple Calendar-like design
- Payday labels on pay Fridays
- Color-coded entry chips per day
- Balance popover for any date (tap chart icon)
- Tap any day to view/add/edit entries

### Balance Summary Cards

- Comp, Vacation, Sick cards at top of home screen
- Shows both Official and Forecast with "as of" dates
- Forecast mode toggle: End of Month / Today / Selected Day

### Entry Editor

- Leave type picker (Comp / Vacation / Sick)
- Action picker (Accrued / Used / Adjustment)
- Quick hour buttons: 5h, 12h, 24h
- 0.25h stepper (+/-)
- Custom numeric input
- Notes field
- Adjustment direction (positive/negative)

### Ledger Views

- Separate tabs for Comp, Vacation, and Sick
- Chronological entry list with posted/pending status
- Upcoming accrual events (virtual rows, not stored)
- Swipe to edit/delete
- Balance summary at top

### Settings

- Anchor payday configuration
- Starting balance adjustment
- Accrual rate configuration
- 0.25h rounding toggle (default: on)
- iCal feed URL with copy button
- Token regeneration for security
- CSV export via share sheet
- PDF monthly summary export
- Supabase sync trigger

### iCal Calendar Feed

Subscribe in Apple Calendar using the feed URL shown in Settings.

The feed includes:

- All leave entries as all-day events
- Payday events with accrual amounts
- Color categories (Green for accrued, Red for used)
- Deep links back to the app (`leaveLedger://entry/<uuid>`)

The feed is served by a Supabase Edge Function, authenticated by a random token stored in your profile.

### Data Export

- **CSV:** All entries with date, type, action, hours, notes
- **PDF:** Monthly summary with balance overview and entry list

## Color Coding

| Entry Type                          | Color           |
| ----------------------------------- | --------------- |
| Comp Accrued                        | Green           |
| Any Usage (Comp/Vacation/Sick Used) | Red             |
| Payday Accrual (Vacation/Sick)      | Teal            |
| Positive Adjustment                 | Green (lighter) |
| Negative Adjustment                 | Red (lighter)   |

## Running Tests

In Xcode:

1. Open `LeaveLedger.xcodeproj`
2. Press `Cmd+U` to run all tests

Or via command line:

```bash
xcodebuild test \
  -project LeaveLedger/LeaveLedger.xcodeproj \
  -scheme LeaveLedger \
  -destination 'platform=iOS Simulator,name=iPhone 15'
```

### Test Coverage

The test suite (`BalanceEngineTests.swift`) verifies:

1. **Pay period calculations:**
   - Anchor pay period boundaries (Jan 17-30 for Feb 6 payday)
   - Forward/backward pay period mapping
   - Payday detection and last-payday computation

2. **Official balance at anchor payday:**
   - Starting balances match (Sick: 801.84, Vac: 33.72, Comp: 0.25)

3. **Official balance forward with accruals:**
   - Sick at next payday: 801.84 + 7.88 = 809.72

4. **Vacation usage scenario:**
   - 24h vacation used on Feb 2 (in Feb 20 pay period)
   - Forecast as of Feb 5: reflects -24h immediately
   - Official as of Feb 6: unchanged (entry not yet posted)
   - Official as of Feb 20: reflects usage + accrual

5. **Comp accrual and usage:**
   - Comp entries only post after their pay period's payday

6. **Adjustments (positive and negative)**
7. **Posted vs Pending status**
8. **Soft-deleted entry exclusion**
9. **Backward balance computation (previous paydays)**
10. **Multiple entries across pay periods**

## Defaults & Design Decisions

1. **Auth:** Single-user device UUID in Keychain. No login screen. RLS policies are permissive for the anon role since this is a personal app. For multi-user, switch to Supabase Auth with JWT-based RLS.

2. **System accrual events:** Computed dynamically by the BalanceEngine, not stored as database rows. They appear as virtual rows in the Ledger views.

3. **Hours storage:** `Decimal` type in Swift (maps to `NUMERIC(10,2)` in Postgres). Never uses `Double` for balance calculations.

4. **Entry sign convention:** The `hours` field stores a positive number. The sign is derived from the action type: `used` = negative, `accrued` = positive, `adjustment` = depends on `adjustment_sign`.

5. **Offline-first:** The app reads/writes to SwiftData immediately. Supabase sync is triggered manually from Settings (can be extended to auto-sync on app foreground).

6. **Conflict resolution:** Last-write-wins based on `updated_at` timestamp.

7. **Theme:** Defaults to dark mode (`preferredColorScheme(.dark)`). Respects system setting if changed.

8. **Deep links:** URL scheme `leaveLedger://entry/<uuid>` navigates to the entry's date.

## Requirements

- Xcode 15+
- iOS 17.0+
- Swift 5.9+
- Supabase project (optional, for cloud sync and iCal feed)
