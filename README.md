# Go Fundraise Pickup App

A Flutter app for tracking fundraiser pickups.

## Features

- **Import Orders**: Parse PDF or CSV files containing customer orders
- **Customer Search**: Fast search by name, email, or phone
- **Pickup Tracking**: Mark orders as picked up with volunteer initials
- **Photo Reference**: Capture and view photos of boxes and items
- **Export**: Generate CSV pickup logs for record keeping
- **Offline-First**: Works entirely offline - no internet required

## Setup

### Prerequisites

1. Install Flutter SDK (3.2.0 or later):
   ```bash
   # macOS with Homebrew
   brew install flutter

   # Or download from https://docs.flutter.dev/get-started/install
   ```

2. Verify installation:
   ```bash
   flutter doctor
   ```

### Getting Started

1. **Setup** (install dependencies and generate code):
   ```bash
   make setup
   ```

2. **Run the app** in development mode:
   ```bash
   make dev
   ```

   Or specify a device:
   ```bash
   flutter run -d ios      # iOS Simulator
   flutter run -d android  # Android Emulator
   flutter run -d macos    # macOS (desktop)
   flutter run -d chrome   # Web browser (or use: make web)
   ```

### Make Commands

| Command | Description |
|---------|-------------|
| `make dev` | Run in debug mode with hot reload |
| `make run` | Run in release mode |
| `make web` | Run in Chrome browser |
| `make web-port` | Run in Chrome on port 8080 |
| `make test` | Run tests |
| `make analyze` | Run Flutter analyzer |
| `make build-android` | Build APK |
| `make build-bundle` | Build App Bundle |
| `make build-ios` | Build iOS |
| `make build-web` | Build for web |
| `make serve-web` | Build and serve web locally |
| `make clean` | Clean build artifacts |
| `make get` | Get dependencies |
| `make upgrade` | Upgrade dependencies |
| `make generate` | Run build_runner (for drift) |
| `make watch` | Watch and regenerate code |
| `make format` | Format code |
| `make format-check` | Check formatting |
| `make check` | Run all checks (analyze, format, test) |
| `make setup` | Install deps and generate code |

### Building for Release

```bash
# iOS
make build-ios

# Android APK
make build-android

# Android App Bundle
make build-bundle

# Web (outputs to build/web/)
make build-web
```

### Web Platform Notes

The app runs on web with some limitations:
- **Database**: Uses IndexedDB instead of SQLite (data stays in browser)
- **File Import**: Uses browser file picker (works for PDF/CSV import)
- **Photos**: Camera access depends on browser permissions
- **Export/Share**: Downloads files instead of native share sheet

## Project Structure

```
lib/
├── main.dart                 # App entry point
├── core/
│   ├── database/            # SQLite database with Drift ORM
│   ├── models/              # Data models for parsing
│   ├── router.dart          # GoRouter navigation
│   └── utils/               # Utility functions
├── features/
│   ├── fundraiser/          # Fundraiser list screen
│   ├── import/              # PDF/CSV import & validation
│   ├── pickup/              # Customer search & pickup marking
│   ├── photo/               # Photo gallery & viewer
│   └── export/              # CSV export functionality
└── shared/
    ├── theme/               # App theme configuration
    └── widgets/             # Shared UI components
```

## Usage

### Importing Data

1. Tap "Import" on the home screen
2. Select a PDF or CSV file
3. Review parsed data
4. Tap "Import & Continue"

### During Pickup

1. Search for customer by name, phone, or email
2. Tap customer row to view details
3. Tap checkbox for quick pickup, or open details for confirmation
4. Take photos as needed for reference

### Exporting

1. From pickup screen, tap export icon
2. Configure what to include
3. Tap "Generate & Share CSV"
4. Share via email, AirDrop, etc.

## Supported File Formats

### PDF
- JD Sweid order summaries
- Little Caesars fundraiser reports (auto-detected)
- Standard fundraiser PDF formats with customer/order sections

### CSV
Required columns (flexible naming):
- Name (or First Name + Last Name)
- Email (optional)
- Phone (optional)
- Product/Item (optional)
- Quantity (optional)

## Technical Details

### Database

SQLite database with tables:
- `fundraisers` - Campaign information
- `customers` - Consolidated customer records
- `orders` - Individual orders
- `order_items` - Line items per order
- `pickup_events` - Pickup tracking
- `photos` - Reference photos

### Customer Consolidation

Duplicates are merged by:
1. Email (primary key)
2. Phone (secondary)
3. Name (fallback)

### Performance

- Indexed search fields for fast lookup
- Photo compression and thumbnails
- Debounced search (150ms)
- Max 50 results displayed, virtual scrolling

## License

Licensed under the Apache License, Version 2.0. See [LICENSE](LICENSE) for details.
