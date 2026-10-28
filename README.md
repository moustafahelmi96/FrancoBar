# FrancoBar

A tiny floating bar for macOS that turns Franco / Arabizi into Arabic as you type.

Type `ana 3ayz a5rog enaharda`, pause, and `أنا عايز أخرج انهاردة` is already on your clipboard.

## Features

- **Floating bar, anywhere:** `⌥Space` shows or hides it over any app, on every Space, even in full screen.
- **Auto-copy:** the Arabic is copied as soon as you pause typing (0.6s by default).
- **Enter pastes:** press `↩` and the Arabic is pasted straight into the app you were typing in.
- **Alternatives:** up to 5 spellings for each word. Click any Arabic word, or press `⌘1`–`⌘5` for the last one.
- **Learns your words:** your picks are remembered. Use “Type my own…” for names and slang.
- **Convert selected text:** select Franco text in any app, press `⌥⇧Space`, and it's replaced with Arabic.
- **History:** the last 20 conversions, in the menu bar.
- **Settings:** both shortcuts, the pause length, auto-copy, Enter-to-paste, open at login.
- **Works offline:** words it has seen before are cached; new words fall back to built-in rules.

Particles are joined the Arabic way: `w el beit` → `والبيت`.

## Install

Needs macOS 13+ and the Xcode command line tools (`xcode-select --install`).

```bash
git clone https://github.com/moustafahelmi96/FrancoBar.git
cd FrancoBar
./build.sh install
```

`./build.sh` alone builds `FrancoBar.app` in the repo folder; `install` also copies it to `/Applications` and launches it.
The **ع** icon in the menu bar has everything else.

### Accessibility permission

“Enter pastes” and “Convert selected text” send ⌘C / ⌘V for you, which macOS only allows after you grant FrancoBar
**Accessibility** access (System Settings → Privacy & Security → Accessibility). The rest of the app works without it.

The build is signed locally (ad-hoc), so after rebuilding you may need to switch FrancoBar off and on again in that list.

## How conversion works

For each word, in order:

1. Your own words (`~/Library/Application Support/FrancoBar/dictionary.json`, also under **ع → Edit My Words…**)
2. Results cached from earlier lookups (`cache.json` in the same folder)
3. Google Input Tools (`inputtools.google.com`)
4. Offline rules

> **Note:** `inputtools.google.com` is the unofficial endpoint behind Google's own input tools. It isn't a documented
> public API, so it could change or stop working. The words you type are sent to it. Without it, FrancoBar keeps
> working from your dictionary, the cache, and the offline rules.

## License

MIT
