# Movies and shows

How to watch, and how to ask for something that isn't there yet. For everyone with a Jellyfin
account; nothing here needs the admin.

| | Address | For |
|---|---|---|
| **Jellyfin** | https://tv.lichnovsky.eu | watching |
| **Seerr** | https://watchlist.lichnovsky.eu | asking for a movie or show |

Both work **at home on the Wi-Fi** and, away from home, **with Tailscale switched on** on your phone
or laptop. Without Tailscale they don't open outside home. That's on purpose.

## Watching

- **TV, phone, tablet:** the *Jellyfin* app (Android TV, Google TV, iOS, Android, LG, Samsung …).
  Server address `https://tv.lichnovsky.eu`, then your username and password.
- **Computer:** the address in a browser. The Jellyfin apps play more video formats than a
  browser, so if a video stutters or won't start in the browser, try the app.
- **Subtitles and audio:** the speech-bubble and speaker icons while playing. Czech and English
  subtitles are added automatically, usually within an hour of a title appearing.

## Asking for a movie or show

1. Open **Seerr** and sign in with your **Jellyfin** username and password (the same account).
2. Search for the title, or browse *Trending* and *Popular*.
3. Open it and press **Request**.
   - **Show:** choose which seasons. A season that is still airing gets each new episode by itself.
4. Wait. The title's badge tells you where it is:

   | Badge | Meaning |
   |---|---|
   | *Pending* | waiting for the admin to approve |
   | *Requested* / *Processing* | approved; being searched for or downloaded |
   | *Partially Available* | some episodes or seasons are ready |
   | *Available* | ready: it's in Jellyfin |

Most things appear within an hour. Something very new or rare can take days: it is found and
downloaded automatically as soon as a good copy exists, so you don't have to ask again.

**Missing a few episodes** of a show that's already there? Seerr can only ask for whole seasons;
tell the admin which episodes, and they'll be added.

Movies and shows come in their **original language** (an English film in English), with Czech and
English subtitles.

## Something's wrong with a video

Wrong language, bad quality, out-of-sync subtitles, missing episode: on the title in **Seerr**,
press **Report an Issue**, choose what's wrong and add a note. The admin gets a message and can
replace it.
