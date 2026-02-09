.PHONY: run dev build-android build-ios build-web test analyze clean get upgrade

# Run the app (release mode)
run:
	flutter run --release

# Run the app in debug mode with hot reload
dev:
	flutter run

# Run the app in web browser
web:
	flutter run -d chrome

# Run web with a specific port
web-port:
	flutter run -d chrome --web-port=8080

# Build Android APK
build-android:
	flutter build apk --release

# Build Android App Bundle
build-bundle:
	flutter build appbundle --release

# Build iOS
build-ios:
	flutter build ios --release

# Build web
build-web:
	flutter build web --release

# Serve built web app locally
serve-web: build-web
	cd build/web && python3 -m http.server 8080

# Run tests
test:
	flutter test

# Run analyzer
analyze:
	flutter analyze

# Clean build artifacts
clean:
	flutter clean

# Get dependencies
get:
	flutter pub get

# Upgrade dependencies
upgrade:
	flutter pub upgrade

# Generate code (for drift, etc.)
generate:
	dart run build_runner build --delete-conflicting-outputs

# Watch and regenerate code
watch:
	dart run build_runner watch --delete-conflicting-outputs

# Format code
format:
	dart format lib test

# Check formatting
format-check:
	dart format --set-exit-if-changed lib test

# Run all checks (analyze, format check, test)
check: analyze format-check test

# Install dependencies and generate code
setup: get generate
