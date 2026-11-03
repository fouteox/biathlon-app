# Google Play

What the release workflow (`.github/workflows/release-android.yml`) sends to Google Play, and
how to set it up.

- `listings/<language>/`: the store listing in each of the app's languages, which
  `publish.sh` sends with each release. `PlayListingTest` keeps the texts within Google Play's
  limits.
- `publish.sh`: one edit of the [Google Play Developer API](https://developers.google.com/android-publisher/edits)
  that uploads the bundle, puts it on the internal testing track and updates the listings.

Each push to main that changes the app builds the release bundle, signed with the upload key,
with the workflow's run number as its version code. [Play App Signing](https://developer.android.com/studio/publish/app-signing)
then signs it with the app's key, which Google keeps.

## Setup

1. **Upload key**: generate it on your computer, never in the repository
   (`keytool -genkeypair -v -keystore upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000`),
   and keep a copy somewhere safe. In the repository's `production` environment, add:
   - the secrets `ANDROID_UPLOAD_KEYSTORE_BASE64` (`base64 -i upload.jks`),
     `ANDROID_UPLOAD_KEYSTORE_PASSWORD` and `ANDROID_UPLOAD_KEY_PASSWORD` (the same password, as
     keytool keeps PKCS12 key stores);
   - the variable `ANDROID_UPLOAD_KEY_ALIAS` (`upload`), which turns the workflow on.
2. **The app in the Play Console**: create it (package `com.fouteox.biathlon`), then upload by
   hand the signed bundle of a workflow run (its artifact) to the internal testing track: the
   API can't create an app.
3. **Access to the API**, without a key, through [Workload Identity Federation](https://github.com/google-github-actions/auth#workload-identity-federation-through-a-service-account),
   in the Google Cloud project of Firebase:
   - enable the Google Play Android Developer API and the IAM Service Account Credentials API;
   - create a service account, a workload identity pool and a provider for GitHub, restricted
     to this repository's main branch, and let the pool impersonate the service account;
   - in the Play Console, Users and permissions, invite the service account with the
     permissions to release to testing tracks and to edit the store listing;
   - in the `production` environment, add the variables `GOOGLE_WORKLOAD_IDENTITY_PROVIDER`
     (the provider's full name) and `GOOGLE_PLAY_SERVICE_ACCOUNT` (its email), which turn the
     upload on.

## In the Play Console only

- The privacy policy, the Data safety form, the content rating and the other App content
  declarations.
- The graphics: the 512×512 icon, the 1024×500 feature graphic and the screenshots
  ([requirements](https://support.google.com/googleplay/android-developer/answer/9866151)).
- A new personal developer account must run a closed test with at least 12 testers for 14
  days in a row before it can apply for production.
