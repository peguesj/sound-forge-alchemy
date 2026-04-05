# xcconfig — Environment Injection Guide

## How SFA_SERVER_URL reaches Swift code

1. `Debug.xcconfig` sets `SFA_SERVER_URL = http://localhost:4000`
2. `Release.xcconfig` sets `SFA_SERVER_URL = https://app.soundforgealchemy.com`
3. `Info.plist` reads it via build setting substitution:
   ```xml
   <key>SFA_SERVER_URL</key>
   <string>$(SFA_SERVER_URL)</string>
   ```
4. Swift reads it at runtime:
   ```swift
   guard let urlString = Bundle.main.infoDictionary?["SFA_SERVER_URL"] as? String,
         let url = URL(string: urlString) else {
       fatalError("SFA_SERVER_URL not set in Info.plist")
   }
   ```

## Wiring xcconfig files in Xcode

1. Select the project (not a target) in the Project Navigator.
2. Open the **Info** tab.
3. Under **Configurations**, expand **Debug** and **Release**.
4. For the `SoundForgeAlchemy` target row, select `xcconfig/Debug` (Debug) and `xcconfig/Release` (Release) from the dropdown.

## CI Override

In GitHub Actions or any CI, pass the server URL as an xcodebuild argument:

```yaml
- name: Build
  run: bundle exec fastlane build
  env:
    SFA_SERVER_URL: https://staging.soundforgealchemy.com
```

Fastlane passes it through via `xcargs`:
```ruby
build_mac_app(xcargs: "SFA_SERVER_URL='#{ENV["SFA_SERVER_URL"] || "https://app.soundforgealchemy.com"}'")
```
