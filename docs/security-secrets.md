# Secrets and public builds

Personal addon URLs, provider credentials, Apple signing material and account
tokens must stay outside Git and public build artifacts. `.gitignore` is a
convenience, not a substitute for reviewing the exact publication payload.

The source gate uses Gitleaks 8.30.1 from an official archive pinned by SHA-256.
It scans all fetched Git refs using upstream default rules, with allow comments
disabled. Its report is redacted and stays outside uploaded artifact paths.
The reviewed baseline contains exact historical commit/path/rule/line
fingerprints: seven upstream YouTube client keys, two credentials in the
upstream KSPlayer demo that is outside the app target, and eight preference key
names. No whole directory or rule is excluded. New matches must be reviewed;
never add a personal credential to the baseline or bypass a push block.

CI starts after publication. Before pushing or uploading through an API, scan
the proposed diff or exact file payload locally as well. Inspect packaged
resources, logs and diagnostics before distributing an IPA. A passing scanner
cannot prove the absence of every possible secret format or personal datum.

If a real credential was public, revoke or rotate it at its issuing service.
Deleting a file, rewriting history or changing repository visibility cannot
revoke credentials or remove existing third-party copies.

These checks do not certify the application's network and storage security.
The LAN phone-import transport still needs confidentiality protection, initial
HTTP addon URLs remain a separate transport risk, and inherited plugin/media
request paths need their own reviews. Cloud credentials synchronization stays
disabled until its encryption and account isolation have been verified.
