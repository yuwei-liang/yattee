<div align="center">
  <img src="assets/yattee-y-logo.png" width="128" height="128" alt="Yattee Y logo: a whale with a play button" />
  <h1>Yattee Y</h1>
  <p>A personal fork of <a href="https://github.com/yattee/yattee">Yattee</a> for iPhone, Mac and Apple TV<br />
  一个自用的 Yattee 分支：配合自建的 Yattee Server 和 Claude 推荐，把它改成自己想要的样子。</p>

[![AGPL v3](https://shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0.en.html)
</div>

> **This is not the official app.** For Yattee itself, see [yattee/yattee](https://github.com/yattee/yattee),
> the [Yattee Server](https://github.com/yattee/yattee-server) and [docs.yattee.stream](https://docs.yattee.stream).
> Yattee Y is built for one person's devices, ships only through a private TestFlight, and is not offered for download.
> The code is public because Yattee is AGPL, and in case any of the ideas are useful to someone.

## What it adds

The goal of the home feed, in the owner's words: **learn and grow, and enjoy it, without being worked up by one-sided, sensational content.**

**Home and recommendations**
- Home is a recommendation feed picked by Claude on the server, each video with a one-line reason. Grid layout on Mac, wide iPad and Apple TV (four across).
- Feedback from any card: more like this, go deeper, not interested (with undo and an optional reason), never this channel. On Apple TV, long-press the card.
- **After-watch rating:** when a longer video ends, a bar offers 爽 (fun), 涨知识 (learned something), 被带节奏了 (felt manipulated) and 一般 (meh). It closes by itself if ignored and backs off after repeated ignores. "Felt manipulated" can also mean fewer videos from that channel, or send the video to unspin. Every watch also reports how much of the video was watched, so the recommender learns from finished watches rather than clicks.
- The feed's header says what the last round changed because of your feedback.
- Numbered series (#3, Game 3, 第3局…): the next episode is pinned first in Related and on home.
- **unspin:** send a video from its menu for an analysis of how its argument is built; reports are listed in the app.

**Playback**
- Tap a video anywhere to play it, like YouTube. A started video continues where it stopped without asking; details stay in the context menu.
- Chinese subtitles render correctly (bundled Noto Sans SC, because the system CJK fonts are outside mpv's reach).
- One-tap CC button that remembers the language (Chinese first, the first time), and a quality button that shows the current quality.
- A dropped stream no longer counts as finished: the player fetches a fresh stream and resumes.
- Sleep timer: 15/30/45/60 minutes or end of video, with a fade-out.

**Mac**
- Opens in a small window; T expands details, C floats comments over the right of the video, S toggles subtitles.
- YouTube-style keys: K or space, J/L ±10 s, 0–9 to jump, `,` `.` frame step, `<` `>` speed, N next. `?` or ⌘/ lists them all.

**Apple TV**
- Its own build with the same feed, direct play and rating bar. iCloud sync of the source list is off by default, since a TV usually reaches the server on the home network while phones use a remote address.

**Setup**
- Own bundle IDs, iCloud container and icon, so it installs next to the official app.
- A `yattee://add-source` link adds a server source with its login in one tap.

## How it fits together

The app talks to a Yattee Server. Recommendations, feedback, ratings, unspin and next-episode use endpoints that exist only in my modified server, which is not published here; against a stock Yattee Server the rest of the app works as usual. Claude runs on the server with the owner's own API key; the app never holds one.

Plans and history (in Chinese): [ROADMAP.md](ROADMAP.md). Build setup and notes for coding agents: [AGENTS.md](AGENTS.md).

## Building it yourself

Builds run on GitHub Actions (`.github/workflows/yattee-y-*.yml`) and need this fork's signing secrets. To build your own copy, replace the bundle IDs, app group, iCloud container and team listed in AGENTS.md with your own.

## Credits and license

The app is [Yattee](https://github.com/yattee/yattee), by its authors and contributors; this fork merges upstream regularly. Like Yattee, it is licensed under the [AGPL v3](https://www.gnu.org/licenses/agpl-3.0.en.html).
