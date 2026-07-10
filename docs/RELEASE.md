# Releasing Vibe Dashboard

Vibe is **un-sandboxed** (it reads `~/Code` and shells out to `git`/`make`), so it
is **not** a Mac App Store app. It ships the way every direct-download Mac app
does: a **Developer ID-signed, notarized, stapled DMG**. Gatekeeper then opens it
with no scary "unidentified developer" prompt.

The whole pipeline is `make release`. It is idempotent and prints exactly what it
does. But it needs **two credentials that only you can create** — Apple ties them
to your account, so they are deliberately not (and cannot be) in the repo:

1. a **Developer ID Application** certificate, and
2. a stored **notary credential profile**.

Set those up once (below), then every release is one command.

---

## One-time setup

### 0. Apple Developer Program

`make release-check` will tell you what's missing. If you are not enrolled, the
Developer ID certificate (step 1) is unavailable until you join the paid Apple
Developer Program ($99/yr).

### 1. Developer ID Application certificate

You currently have only **Apple Development** certificates (fine for running
locally, useless for distribution). Create the distribution cert:

- **Xcode ▸ Settings ▸ Accounts ▸** (your Apple ID) **▸ Manage Certificates ▸ +
  ▸ Developer ID Application**, or
- the Apple Developer website ▸ **Certificates, IDs & Profiles ▸ + ▸ Developer ID
  Application**, then download and double-click it into your login keychain.

Verify:

```bash
security find-identity -v -p codesigning | grep "Developer ID Application"
```

### 2. Notary credential profile

Store credentials once into a keychain profile named `vibe-notary` (release.sh
reuses it). Pick **one** credential type — the wrapper holds no secrets, it just
runs Apple's interactive `notarytool store-credentials`:

**App Store Connect API key (recommended — revocable, no password):**
create a key at App Store Connect ▸ Users and Access ▸ Integrations ▸ App Store
Connect API, download `AuthKey_XXXX.p8`, then:

```bash
./Scripts/notary-setup.sh --key ~/Downloads/AuthKey_XXXX.p8 \
                          --key-id XXXXXXXXXX --issuer <issuer-uuid>
```

**or Apple ID + app-specific password:** create one at appleid.apple.com ▸
Sign-In & Security ▸ App-Specific Passwords, then (it prompts for the password):

```bash
./Scripts/notary-setup.sh --apple-id you@example.com --team-id YOUR_TEAM_ID
```

> Never commit the `.p8` or the password. `.gitignore` already blocks `*.p8`,
> `AuthKey_*.p8`, `.env`, and friends.

### 3. Confirm

```bash
make release-check
```

Green on both the certificate and the notary profile ⇒ you're ready.

---

## Cutting a release

```bash
make release
```

which runs `Scripts/release.sh full`:

1. **archive** — Release config, **universal** (`arm64` + `x86_64`), Developer ID,
   hardened runtime (already on in `project.yml`), secure timestamp.
2. **export** — `xcodebuild -exportArchive` with `ExportOptions.plist`
   (`method: developer-id`; `__TEAM_ID__` is substituted with your detected team).
3. **notarize + staple the app** — zip it, `notarytool submit --wait`, then
   `stapler staple` so the app verifies **offline**; `spctl` assessment printed.
4. **DMG** — package the stapled app with an `/Applications` drop target
   (`Scripts/make-dmg.sh`, pure `hdiutil`).
5. **sign + notarize + staple the DMG** — so the downloaded `.dmg` itself is
   trusted on first mount.

Output lands in `dist/` (git-ignored): `dist/VibeDashboard-<version>.dmg`. The
version is the same `VERSION`-derived marketing string the app stamps.

Verify what a user's Mac will check:

```bash
spctl --assess --type open --context context:primary-signature -v dist/VibeDashboard-*.dmg
xcrun stapler validate dist/VibeDashboard-*.dmg
```

## Testing the bundle without the cert

To smoke-test the built app and the DMG layout **before** the certificate exists:

```bash
make dmg-local
```

builds an **unsigned** Release app and packages it to `dist/`. It will **not**
pass Gatekeeper (that's expected) — it's only for checking the bundle, icon,
Info.plist, and drag-install layout.

## Notes

- `dist/` is git-ignored; nothing from a release is committed.
- Universal build: if the `x86_64` slice ever causes a dependency hiccup, drop it
  by editing `ARCHS` in `Scripts/release.sh` (`archive_and_export`).
- The team id auto-detects from the Developer ID cert; override with
  `TEAM_ID=… make release` if you belong to more than one team.
- A fancier DMG (background image, positioned icons) is a later polish; the
  current one is a clean, conventional drag-to-Applications window.
