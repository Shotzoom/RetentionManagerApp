# Changelog

## Latest Updates

### Upload Management & Retry Functionality
- **Added**: Upload status tracking for each message
  - Local Only: Message saved locally, not yet uploaded
  - Uploading: Currently being sent to API
  - Uploaded: Successfully synced with Apple
  - Failed: Upload error (with error message displayed)
- **Feature**: "Upload to API" button in message detail view
- **Feature**: "Retry Upload" for failed messages
- **Feature**: Context menu (right-click) for quick upload/retry from list
- **Visual**: Status badges and icons throughout the app
- **Visual**: Error messages displayed for failed uploads
- **Automatic**: Image upload handled before message upload
- **Safety**: Can delete stuck messages at any time

### Auto-Generated Message Identifiers
- **Changed**: Message identifiers are now auto-generated UUIDs
- **Benefit**: No need to manually create unique identifiers
- **UI Update**: Message ID is displayed as read-only text that can be copied

### Improved Message Content UI
- **Enhanced**: Separate, clearly labeled "Header" and "Body" fields
- **Added**: Helper text and examples for each field
  - Header: "Enter a short, compelling header"
  - Body: "Main message explaining the value of staying subscribed"
- **Improved**: Better visual distinction between header and body text areas

### Environment Selection
- **Added**: Sandbox/Production environment selector in Settings
- **Feature**: Switch between Apple's sandbox and production servers
- **Safety**: Defaults to Sandbox to prevent accidental production changes
- **Visibility**: Current environment displayed in main window subtitle

### Settings Enhancements
- **Environment**: Segmented control to select Sandbox or Production
- **Descriptions**: Clear explanations of when to use each environment
- **Persistence**: Environment selection saved across app launches

### Visual Improvements
- **Navigation Subtitle**: Shows "Sandbox Environment" or "Production Environment"
- **Message ID Display**: Monospaced font with copy-enabled text selection
- **Form Layout**: Improved spacing and organization in Add Message view

## API Configuration

### JWT Authentication
- **Implementation**: Custom ES256 signing using CryptoKit
- **Key File**: In-App Purchase key (.p8) imported through the configuration setup screen
- **Token Expiration**: 1 hour (automatically regenerated per request)
- **Base URLs**:
  - Sandbox: `https://api.storekit-sandbox.apple.com/inApps/v1/messaging`
  - Production: `https://api.storekit.apple.com/inApps/v1/messaging`

### Message Structure
Messages are uploaded with:
- **messageIdentifier**: UUID (auto-generated)
- **header**: Short, compelling text
- **body**: Detailed message content
- **locale**: Primary language (en, es, fr, de)
- **image**: Optional associated image

## Product Support
All 26 TOUR Caddie subscription product IDs supported:
- TOUR Caddie PRO (various tiers)
- TOUR Academy
- Golfplan
- All renewing variants

## Export Formats
- **CSV**: Ready for database import
- **SQL**: INSERT statements with full schema

## Translation Features
- **Languages**: English, Spanish, French, German
- **AI-Powered**: Automatic translation using Apple's FoundationModels
- **Manual Override**: Can manually edit any translation
- **Parallel Processing**: Header and body translated simultaneously
