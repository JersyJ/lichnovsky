# Movies and series

This guide is for all persons with a Jellyfin account. It tells you how to watch, and how to ask
for a movie or series that is not in the library. You do not need the admin for these steps.

| App | Address | Use |
|---|---|---|
| **Jellyfin** | https://tv.lichnovsky.eu | Watch |
| **Seerr** | https://watchlist.lichnovsky.eu | Ask for a movie or series |

The two apps work at home on the Wi-Fi. Away from home, they work only when Tailscale is on in
your phone or laptop.

## Watch

- **TV, phone or tablet:** Install the *Jellyfin* app (Android TV, Google TV, iOS, Android, LG,
  Samsung). Enter the server address `https://tv.lichnovsky.eu`. Then enter your username and
  password.
- **Computer:** Open the address in a browser. If a video stops or does not start in the browser,
  use the Jellyfin app. The app can play more video formats.
- **Subtitles and audio:** During playback, use the speech-bubble icon and the speaker icon.

The system adds Czech and English subtitles automatically. This usually occurs in less than one
hour after a title arrives.

## Ask for a movie or series

1. Open **Seerr**. Sign in with your **Jellyfin** username and password.
2. Search for the title. You can also look in *Trending* and *Popular*.
3. Open the title and push **Request**.
4. For a series, select the seasons. If a season is not complete, each new episode arrives
   automatically.
5. Wait. The badge on the title shows the status:

   | Badge | Status |
   |---|---|
   | *Pending* | The admin must approve the request. |
   | *Requested* / *Processing* | The request is approved. The system searches for the title or downloads it. |
   | *Partially Available* | Some episodes or seasons are ready. |
   | *Available* | The title is ready in Jellyfin. |

Most titles arrive in less than one hour. A very new or rare title can take some days. The system
downloads the title when a good copy is available. You do not have to make the request again.

**Missing episodes:** Seerr can only request full seasons. If some episodes of a series are
missing, tell the admin which episodes. The admin adds them.

**Quality:** Movies and series arrive in 1080p. All devices can play 1080p. If you want a title in
4K for a large TV, ask the admin. The TV apps can play 4K. Most browsers and old phones cannot.

**Language:** Movies and series arrive in their original language, with Czech and English
subtitles. For example, an English movie has English audio.

## Report a problem with a video

Examples of problems: wrong language, bad quality, subtitles that are not in sync, a missing
episode.

1. In **Seerr**, open the title.
2. Push **Report an Issue**.
3. Select the problem and write a short note.

The admin gets a message and can replace the video.
