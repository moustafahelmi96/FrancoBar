<img src="icon/AppIcon.png" width="128" alt="FrancoBar icon">

# FrancoBar

A tiny floating bar for macOS that turns Franco / Arabizi into Arabic as you type.

Type `ana 3ayz a5rog enaharda`, pause, and `أنا عايز أخرج انهاردة` is already on your clipboard.

## Features

- **Floating bar, anywhere:** `⌥Space` shows or hides it over any app, on every Space, even in full screen.
- **Tuck it away:** drag the bar against any screen edge and it hides into a small tab there. Click the tab to bring it back; drag it away from the edge to undock.
- **Double-tap ⌘ to focus:** tap Command twice to jump straight into the bar from wherever you are.
- **Auto-copy:** the Arabic is copied as soon as you pause typing (0.6s by default).
- **Enter pastes:** press `↩` and the Arabic is pasted straight into the app you were typing in.
- **Alternatives:** up to 5 spellings for each word. Click any Arabic word, or press `⌘1`–`⌘5` for the last one.
- **Learns your words:** your picks are remembered. Use “Type my own…” for names and slang.
- **Convert selected text:** select Franco text in any app, press `⌥⇧Space`, and it's replaced with Arabic.
- **History:** the last 20 conversions, in the menu bar.
- **Settings:** both shortcuts, the pause length, auto-copy, Enter-to-paste, open at login.
- **Works offline:** words it has seen before are cached; new words fall back to built-in rules.

English words stay English: `ana 3ayz a3mel install lel app` → `أنا عايز أعمل install لل app`.
Particles are joined the Arabic way: `w el beit` → `والبيت`.

## Install

### Download (easiest)

1. Download **FrancoBar.zip** from the [latest release](https://github.com/moustafahelmi96/FrancoBar/releases/latest).
2. Unzip it and drag **FrancoBar.app** into **Applications**.
3. Open it. The first time, macOS will block it (see below).

Works on macOS 13+, on both Apple silicon and Intel Macs.

#### Opening it the first time

FrancoBar isn't signed with a paid Apple Developer ID, so macOS says it “can't be opened” or “could not verify” it.
This only happens once:

1. Try to open FrancoBar, then click **Done** (or **OK**) in the warning.
2. Open **System Settings → Privacy & Security** and scroll down to **Security**.
3. Next to *“FrancoBar was blocked…”*, click **Open Anyway**, then confirm with your password or Touch ID.

Or, from Terminal:

```bash
xattr -dr com.apple.quarantine /Applications/FrancoBar.app
```

After that it opens normally. Look for the **ع** icon in the menu bar; everything else is in there.

### Build from source

Needs macOS 13+ and the Xcode command line tools (`xcode-select --install`).

```bash
git clone https://github.com/moustafahelmi96/FrancoBar.git
cd FrancoBar
./build.sh install
```

- `./build.sh` builds `FrancoBar.app` in the repo folder.
- `./build.sh install` also copies it to `/Applications` and launches it.
- `./build.sh release` makes a universal build zipped as `FrancoBar.zip`.

### Accessibility permission

Double-tap ⌘ needs to watch the Command key, and “Enter pastes” and “Convert selected text” send ⌘C / ⌘V for you.
macOS only allows these after you grant FrancoBar
**Accessibility** access (System Settings → Privacy & Security → Accessibility). The rest of the app works without it.

The app is signed locally (ad-hoc), so after updating or rebuilding you may need to switch FrancoBar off and on again in that list.

## How conversion works

For each word, in order:

1. Your own words (`~/Library/Application Support/FrancoBar/dictionary.json`, also under **ع → Edit My Words…**)
2. English words, kept as typed. Detected with the macOS English spell checker, except for common Franco words
   that are also English (`law`, `mesh`, `bas`, `ya`…). The word as typed is always one of the alternatives, and your pick is remembered.
3. Results cached from earlier lookups (`cache.json` in the same folder)
4. Google Input Tools (`inputtools.google.com`)
5. Offline rules

> **Note:** `inputtools.google.com` is the unofficial endpoint behind Google's own input tools. It isn't a documented
> public API, so it could change or stop working. The words you type are sent to it. Without it, FrancoBar keeps
> working from your dictionary, the cache, and the offline rules.

## License

MIT
