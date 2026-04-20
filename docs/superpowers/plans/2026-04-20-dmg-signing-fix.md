# DMG Signing Fix Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Update `Scripts/build_dmg.sh` so the generated `dist/PowerShell.app` is ad-hoc re-signed after bundle assembly, verified locally, and then packaged into a DMG that no longer trips the current “app is damaged” Gatekeeper failure on other machines.

**Architecture:** Keep the existing manual app-bundle assembly and DMG creation flow, but insert one bundle-level signing step and one verification step between bundle creation and DMG staging. Preserve the current output paths and packaging format, and only adjust the script’s post-build behavior and terminal output.

**Tech Stack:** Bash, `swift build`, `codesign`, `hdiutil`, macOS app bundle structure

---

## File Structure

- Modify: `Scripts/build_dmg.sh` — release packaging script that builds the binary, assembles `dist/PowerShell.app`, creates `dist/PowerShell.dmg`, and prints user guidance.
- No new source files.
- No new automated test files; verification is command-driven because the change is isolated to one packaging shell script.

## Baseline Notes

- The repository currently has a pre-existing unrelated red test: `Tests/PowerShellTests/NLDetectorTests.swift:30` (`testEnglishNL`). Do not treat that failure as part of this task.
- Because the global `swift test` baseline is already red, verification for this task should focus on the packaging script and signature checks described below.

### Task 1: Capture the current failure as the regression baseline

**Files:**
- Modify: none
- Test: `Scripts/build_dmg.sh`

- [ ] **Step 1: Reproduce the current broken artifact**

Run:

```bash
./Scripts/build_dmg.sh
codesign --verify --deep --strict --verbose=2 dist/PowerShell.app
```

Expected: `./Scripts/build_dmg.sh` completes, but the `codesign --verify` command fails with a bundle/signature mismatch such as:

```text
dist/PowerShell.app: code has no resources but signature indicates they must be present
```

- [ ] **Step 2: Confirm the script currently lacks a bundle signing step**

Read `Scripts/build_dmg.sh` and confirm that the app bundle is assembled with these existing commands but no `codesign` call after them:

```bash
cp "${PROJECT_DIR}/.build/release/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "${PROJECT_DIR}/Sources/PowerShell/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"
cat > "${APP_BUNDLE}/Contents/Info.plist" << 'PLIST'
```

Expected: the script goes directly from bundle assembly to `hdiutil create` without signing the final `.app`.

- [ ] **Step 3: Record the failure reason before editing**

Use this root-cause statement while implementing:

```text
The Mach-O binary carries an ad-hoc/linker signature, but the final app bundle contents are assembled afterward, so the distributed .app is not a fully re-signed bundle.
```

Expected: implementation remains focused on fixing the missing final bundle signing step, not on unrelated DMG changes.

### Task 2: Add final bundle signing and verification to the packaging script

**Files:**
- Modify: `Scripts/build_dmg.sh:11-85`
- Test: `Scripts/build_dmg.sh`

- [ ] **Step 1: Write the failing check that the updated script must satisfy**

The updated script must make this command pass after packaging:

```bash
codesign --verify --deep --strict --verbose=2 dist/PowerShell.app
```

Expected before implementation: this check fails against the current script output.

- [ ] **Step 2: Add the signing step after bundle assembly**

Edit `Scripts/build_dmg.sh` so the bundle creation section becomes:

```bash
echo "==> Creating app bundle..."
rm -rf "${APP_BUNDLE}"
mkdir -p "${APP_BUNDLE}/Contents/MacOS"
mkdir -p "${APP_BUNDLE}/Contents/Resources"

cp "${PROJECT_DIR}/.build/release/${APP_NAME}" "${APP_BUNDLE}/Contents/MacOS/${APP_NAME}"
cp "${PROJECT_DIR}/Sources/PowerShell/Resources/AppIcon.icns" "${APP_BUNDLE}/Contents/Resources/AppIcon.icns"

cat > "${APP_BUNDLE}/Contents/Info.plist" << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh_CN</string>
    <key>CFBundleExecutable</key>
    <string>PowerShell</string>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIdentifier</key>
    <string>com.powershell.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>PowerShell</string>
    <key>CFBundleDisplayName</key>
    <string>PowerShell</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSSupportsAutomaticTermination</key>
    <true/>
    <key>NSSupportsSuddenTermination</key>
    <true/>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.developer-tools</string>
</dict>
</plist>
PLIST

echo "==> Signing app bundle..."
codesign --force --deep --sign - "${APP_BUNDLE}"

echo "==> Verifying app bundle signature..."
codesign --verify --deep --strict --verbose=2 "${APP_BUNDLE}"
```

Expected: the final `.app` is re-signed only after all bundle files are in place, and the script fails early if signature verification does not pass.

- [ ] **Step 3: Keep DMG creation after successful verification**

Ensure the DMG section stays after the new verification step and still uses the verified app bundle:

```bash
echo "==> Creating DMG..."
DMG_PATH="${DIST_DIR}/${APP_NAME}.dmg"
rm -f "${DMG_PATH}"

DMG_STAGING="$(mktemp -d)"
cp -R "${APP_BUNDLE}" "${DMG_STAGING}/"
ln -s /Applications "${DMG_STAGING}/Applications"

hdiutil create -volname "${APP_NAME}" \
    -srcfolder "${DMG_STAGING}" \
    -ov -format UDZO \
    "${DMG_PATH}"

rm -rf "${DMG_STAGING}"
```

Expected: no DMG is produced if the `.app` cannot be verified.

- [ ] **Step 4: Update the completion message to match the new behavior**

Replace the existing unsigned-app note:

```bash
echo "    Note: The app is not codesigned. Recipients may need to:"
echo "    1. Right-click the app -> Open (first launch)"
echo "    2. Or run: xattr -cr /Applications/PowerShell.app"
```

with:

```bash
echo "    Note: The app bundle was ad-hoc signed and verified locally."
echo "    It should no longer be flagged as damaged when shared via DMG."
echo "    First launch on another Mac may still require allowing an unidentified developer app."
```

Expected: script output no longer claims the bundle is unsigned.

### Task 3: Verify the packaging fix end-to-end

**Files:**
- Modify: none
- Test: `Scripts/build_dmg.sh`

- [ ] **Step 1: Run the updated packaging script**

Run:

```bash
./Scripts/build_dmg.sh
```

Expected: output includes both of these lines before DMG creation:

```text
==> Signing app bundle...
==> Verifying app bundle signature...
```

and the script exits successfully.

- [ ] **Step 2: Verify the rebuilt app bundle passes local signature validation**

Run:

```bash
codesign --verify --deep --strict --verbose=2 dist/PowerShell.app
codesign -dv --verbose=4 dist/PowerShell.app
```

Expected:

```text
dist/PowerShell.app: valid on disk
dist/PowerShell.app: satisfies its Designated Requirement
```

and the detailed output shows an ad-hoc signature on the rebuilt app bundle rather than the previous broken bundle state.

- [ ] **Step 3: Verify the DMG artifact still exists**

Run:

```bash
ls -lh dist/PowerShell.app dist/PowerShell.dmg
```

Expected: both artifacts exist and have fresh timestamps from the current run.

- [ ] **Step 4: Record the manual cross-machine acceptance check**

Perform this manual validation outside the script:

```text
1. Send dist/PowerShell.dmg to a second Mac.
2. Download the DMG normally so Gatekeeper quarantine is applied.
3. Mount the DMG, drag PowerShell.app to /Applications, and open it.
4. Confirm the previous “PowerShell.app is damaged and can’t be opened” dialog no longer appears.
5. If macOS instead warns that the developer cannot be verified, treat that as acceptable for this task.
```

Expected: the damaged-app dialog is gone; unidentified-developer friction is still acceptable because notarization is explicitly out of scope.

### Task 4: Commit the packaging fix

**Files:**
- Modify: `Scripts/build_dmg.sh`
- Test: none

- [ ] **Step 1: Review the final diff**

Run:

```bash
git diff -- Scripts/build_dmg.sh
```

Expected: the diff shows only the new bundle signing step, the new verification step, and the updated completion message.

- [ ] **Step 2: Commit the change**

Run:

```bash
git add Scripts/build_dmg.sh
git commit -m "fix: re-sign app bundle before DMG packaging"
```

Expected: one commit containing only the packaging-script fix.

## Spec Coverage Check

- Re-sign the final `.app` after bundle assembly: covered by Task 2 Step 2.
- Verify the `.app` locally before creating the DMG: covered by Task 2 Step 2 and Task 3 Step 2.
- Keep the existing DMG creation flow: covered by Task 2 Step 3.
- Update terminal guidance to reflect ad-hoc signing instead of “unsigned”: covered by Task 2 Step 4.
- Keep Developer ID/notarization out of scope: preserved throughout Tasks 2 and 3.

## Placeholder / Consistency Check

- No `TODO`, `TBD`, or implied follow-up placeholders remain.
- All commands reference the same file path: `Scripts/build_dmg.sh`.
- All verification steps consistently use `dist/PowerShell.app` and `dist/PowerShell.dmg`.
