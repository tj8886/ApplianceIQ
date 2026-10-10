# Native US file verification

The live anonymous checks passed on October 10, 2026. Signed-in physical upload/download remains pending because this environment has no approved US test login. SQL rollback tests previously verified native Storage authorization and metadata finalization; they do not prove physical bytes. Hosted browser workflows remain pending separately.

Run the anonymous checks without credentials:

```bash
node scripts/migration/verify-native-file-bytes.mjs anonymous /tmp/aiq-file-anonymous.json
```

Signed-in modes use the existing US user access token from the approved test login, passed only through `AIQ_US_TEST_ACCESS_TOKEN`. The runner validates the user through Auth, confirmed email, US destination, and a dedicated organization whose slug begins `migration-file-test-`. The organization must already have reviewed native identity/membership access; this runner does not create or elevate users. Do not store the token in the repository or reports.

Set `AIQ_US_TEST_ORGANIZATION_ID` to that dedicated organization. Logo mode additionally needs saved settings and an owner/admin test member. `AIQ_US_TEST_REQUEST_ID` can supply a stable UUID for reservation replay. Manufacturer mode needs `AIQ_US_TEST_VENDOR_ID` with approved vendor/editor access in that test organization.

```bash
node scripts/migration/verify-native-file-bytes.mjs logo /tmp/aiq-file-logo.json
node scripts/migration/verify-native-file-bytes.mjs manufacturer /tmp/aiq-file-manufacturer.json
```

Each signed-in run reserves a unique path, uploads a valid 1-pixel PNG with overwrite disabled, downloads it through the native user's private access, and compares every byte and SHA-256. An ambiguous upload response is accepted only when the subsequent private download matches exactly. Manufacturer mode finalizes metadata while retaining unpublished status; it never publishes the asset. Logo mode verifies the pending reservation bytes without finalizing, so it does not replace the test organization's logo. Full logo finalization remains covered by SQL rollback tests and still needs hosted workflow verification with real bytes.

Files and reservations are retained. No DELETE, overwrite, publication, role changes, production branding changes, elevated keys, provider calls or production switch are performed. After a logo reservation expires, its pending read access expires too. Repeating manufacturer mode creates another retained draft; inspect the test library instead of rerunning blindly after a failed/ambiguous request. Output reports omit credentials and user identity; retain them with the migration evidence after actual runs.

Runner contract tests use mocked HTTP and must not be reported as a successful live signed-in byte transfer:

```bash
node scripts/migration/test-native-file-byte-runner.mjs
```
