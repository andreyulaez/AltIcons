# AltIcons

A utility to manage alternative app icons in xcode projects

Features:
- Adding new `.appiconset` icon sets from 1024×1024 images
- Auto-resizing all required sizes for iOS
- Automatically updating `Info.plist` and `.pbxproj`
- Modes:
  - **Add** – adds icons if they don’t already exist
  - **Replace** – removes all alternative icons and adds new ones
  - **Remove All** – removes all alternative icons from the project

## Usage

1. Build and run the app from Xcode
2. Select mode (Add / Replace / Remove All)
3. Provide paths to:
   - icons folder if needed (`*.png` or `*.jpg`, 1024×1024, no alpha
   - `.xcassets` folder
   - `Info.plist`
   - `.xcodeproj` directory
4. Press `Run`
