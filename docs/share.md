# Share a video

This guide is for persons with an account on **https://share.lichnovsky.eu** (Gokapi). It tells you
how to upload a video and share it with a link, for example in Discord. Discord accepts files of
only 20 MB. A link has no size limit.

The admin makes the accounts. If you do not have an account, ask the admin.

## Upload and share

1. Open https://share.lichnovsky.eu/admin and log in.
2. Before the upload, set the options for the link:
   - **Downloads:** turn the download limit **off**. Gokapi sets it to 1 download by default. Then
     the link stops after the first view, and the preview in Discord already counts as a view.
     Gokapi remembers your setting for the next uploads.
   - **Expiry:** after how many days the file is deleted. The default is 14 days, which is also the
     maximum.
   - **Password:** keep it empty. Discord can then show the video in the chat. If you set a
     password, persons must open the link and enter the password.
3. Drag the video into the upload area, or push the area and select the file. Maximum file size:
   5 GB.
4. Wait until the upload is complete. The file then shows in the list.
5. Copy the link:
   - **Hotlink:** a direct link to the video. Use it in Discord. Discord then shows the video in the
     chat.
   - **Download link:** opens a page with the file name and a download button.
6. Paste the link in Discord, or send it as you want.

The link works for all persons, also without an account. Each link has a long random ID. Persons
cannot find a link without the ID.

## Delete a file before it expires

1. Open https://share.lichnovsky.eu/admin.
2. In the list, find the file and push the delete icon.

The link then stops to work immediately.

## Problems

- **Discord shows only the link, not the video:** Use the hotlink, not the download link. Discord
  does not show videos that have a password. Some video formats do not play in Discord. MP4 with
  H.264 plays best.
- **The upload stops:** Do the upload again. Gokapi sends large files in parts. A bad connection can
  stop one part.
- **The link shows "file not found":** The file expired, or it reached its download limit. Upload
  the file again.
