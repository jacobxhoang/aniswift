#!/usr/bin/env bash
set -euo pipefail

: "${IOS_CERTIFICATE_BASE64:?Add IOS_CERTIFICATE_BASE64 to GitHub Actions secrets}"
: "${IOS_PROFILE_BASE64:?Add IOS_PROFILE_BASE64 to GitHub Actions secrets}"
if [[ -z "${IOS_CERTIFICATE_PASSWORD+x}" ]]; then
  echo "Set IOS_CERTIFICATE_PASSWORD." >&2
  exit 1
fi

scratch=$(mktemp -d)
keychain="$scratch/build.keychain-db"
profile_dir="$HOME/Library/MobileDevice/Provisioning Profiles"
profile_path=""
original_keychains=()
while IFS= read -r line; do
  line="${line#*\"}"
  original_keychains+=("${line%\"*}")
done < <(security list-keychains -d user)
cleanup() {
  if (("${#original_keychains[@]}" > 0)); then
    security list-keychains -d user -s "${original_keychains[@]}" || true
  fi
  security delete-keychain "$keychain" 2>/dev/null || true
  if [[ -n "$profile_path" ]]; then rm -f "$profile_path"; fi
  rm -rf "$scratch"
}
trap cleanup EXIT

printf '%s' "$IOS_CERTIFICATE_BASE64" | /usr/bin/base64 -D > "$scratch/certificate.p12"
printf '%s' "$IOS_PROFILE_BASE64" | /usr/bin/base64 -D > "$scratch/profile.mobileprovision"
security cms -D -i "$scratch/profile.mobileprovision" > "$scratch/profile.plist"

python3 - "$scratch" <<'PY'
import pathlib, plistlib, sys

folder = pathlib.Path(sys.argv[1])
with (folder / "profile.plist").open("rb") as f:
    profile = plistlib.load(f)
if not profile.get("ProvisionedDevices") or profile["Entitlements"].get("get-task-allow"):
    sys.exit("Use an Ad Hoc distribution provisioning profile with registered devices.")
team = profile["TeamIdentifier"][0]
app_id = profile["Entitlements"]["application-identifier"]
bundle_id = app_id.split(".", 1)[1]
if "*" in bundle_id:
    sys.exit("Use an explicit App ID for the provisioning profile.")
with (folder / "export.plist").open("wb") as f:
    plistlib.dump({
        "method": "release-testing",
        "teamID": team,
        "signingStyle": "manual",
        "signingCertificate": "Apple Distribution",
        "provisioningProfiles": {bundle_id: profile["UUID"]},
    }, f)
(folder / "profile-values").write_text("\n".join([profile["UUID"], team, bundle_id]) + "\n")
PY

{
  read -r uuid
  read -r team
  read -r bundle_id
} < "$scratch/profile-values"
mkdir -p "$profile_dir"
profile_path="$profile_dir/$uuid.mobileprovision"
cp "$scratch/profile.mobileprovision" "$profile_path"
keychain_password=$(openssl rand -hex 24)
security create-keychain -p "$keychain_password" "$keychain"
security set-keychain-settings -lut 21600 "$keychain"
security unlock-keychain -p "$keychain_password" "$keychain"
security import "$scratch/certificate.p12" -k "$keychain" -P "$IOS_CERTIFICATE_PASSWORD" -T /usr/bin/codesign
security set-key-partition-list -S apple-tool:,apple: -k "$keychain_password" "$keychain"
security list-keychains -d user -s "$keychain" "${original_keychains[@]}"

archive="$RUNNER_TEMP/Aniswift.xcarchive"
xcodebuild -project ios/Aniswift.xcodeproj -scheme Aniswift -configuration Release \
  -destination 'generic/platform=iOS' -archivePath "$archive" \
  "PRODUCT_BUNDLE_IDENTIFIER=$bundle_id" "DEVELOPMENT_TEAM=$team" \
  CODE_SIGN_STYLE=Manual 'CODE_SIGN_IDENTITY=Apple Distribution' "PROVISIONING_PROFILE_SPECIFIER=$uuid" archive
xcodebuild -exportArchive -archivePath "$archive" -exportPath "$scratch/export" \
  -exportOptionsPlist "$scratch/export.plist"
ipa=("$scratch/export/"*.ipa)
test -f "${ipa[0]}"
cp "${ipa[0]}" "$RUNNER_TEMP/Aniswift-Signed.ipa"
