# Releasing LarkBar

Releases are built locally with `scripts/release.sh` and published as GitHub releases. Each release
has a `.dmg` (drag to Applications), a `.zip` of the app, and `SHA256SUMS.txt`.

## One-time setup

1. **Developer ID certificate.** Install a "Developer ID Application" certificate with its private
   key in your login keychain. Check with:

   ```sh
   security find-identity -v -p codesigning | grep "Developer ID Application"
   ```

   If more than one is listed, pick one by SHA-1:
   `export LARKBAR_SIGNING_IDENTITY=<sha1>`.

2. **Notary credentials.** Create an app-specific password at
   [account.apple.com](https://account.apple.com) and store it as a notarytool profile:

   ```sh
   xcrun notarytool store-credentials larkbar-notary \
     --apple-id you@example.com --team-id <TEAMID> --password <app-specific-password>
   ```

   Use a different profile name with `export LARKBAR_NOTARY_PROFILE=<name>`. If notarytool reports
   *"A required agreement is missing or has expired"*, the account holder must accept the latest
   agreement at [developer.apple.com/account](https://developer.apple.com/account).

3. **Sparkle update-signing key.** Installed copies only accept updates signed with LarkBar's
   EdDSA key. It lives in the login keychain under the Sparkle account `larkbar`, and a backup is in
   the Passwords app ("LarkBar - Sparkle update signing key"). On a new Mac, save the backup to a
   file and import it (the tool comes with the Sparkle package, after one build):

   ```sh
   build/DerivedData/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account larkbar -f <file>
   ```

   Then delete the file. Never generate a new key: existing installs would reject every update.

4. **Tools.** Xcode 16+, the GitHub CLI (`gh auth login`), and optionally
   `brew install xcodegen`.

## Cutting a release

1. Bump the version in `project.yml`: `MARKETING_VERSION` (e.g. `0.0.2`) and
   `CURRENT_PROJECT_VERSION` (increase by 1 every release). Run `xcodegen generate`.
2. Write release notes in `release-notes/<version>.md`.
3. Commit: `git commit -am "Release 0.0.2"`.
4. Build, sign, notarize and publish:

   ```sh
   scripts/release.sh --publish
   ```

   This runs the tests, archives a Release build signed with your Developer ID and the hardened
   runtime, notarizes and staples the app and the DMG, signs the zip for Sparkle and writes
   `appcast.xml`, writes checksums, pushes the branch, and
   creates the `v<version>` GitHub release with the files attached.

5. Download the DMG from the release page in a browser, install it, and check it opens without a
   Gatekeeper warning.

Outputs land in `build/release/<version>/`. Run without `--publish` to build only.

## Options

| Command | Result |
| --- | --- |
| `scripts/release.sh` | Signed and notarized, not published |
| `scripts/release.sh --skip-notarize` | Signed with Developer ID, not notarized. Users must click **Open Anyway** in Privacy & Security |
| `scripts/release.sh --unsigned` | Ad-hoc signed. For building your own copy without an Apple account |
| `scripts/release.sh --publish` | Any of the above, then publish to GitHub |
| `ALLOW_DIRTY=1 scripts/release.sh` | Build from uncommitted changes (never for a published release) |

## Replacing a release's files

To re-upload files for an existing version (for example, once a build that was published without
notarization has been notarized), run `scripts/release.sh --publish` again from the same commit.
It uploads to the existing release with `--clobber` instead of creating a new one. Update the
release notes on GitHub if they mention notarization.

## Automatic updates

LarkBar uses [Sparkle](https://sparkle-project.org). Installed copies check
`https://github.com/rajatkapoor/larkbar/releases/latest/download/appcast.xml` once a day, and from
**Check for Updates…** in the menu. Every release must include `appcast.xml`, and the latest release
is what users are offered, so publish releases in order and don't mark a pre-release as latest.
