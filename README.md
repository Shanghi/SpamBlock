# SpamBlock

###### Scary warning: Most of these addons were made long ago during Feenix days, then a lot was changed/added to prepare for Corecraft. Since it died, they still haven't been extensively tested on modern servers.

### [Downloads](https://github.com/Shanghi/SpamBlock/releases)

***

## Purpose:
* Can block duplicate messages on selected channel types until a set time passes.
* Can have a blacklist and whitelist for each channel type to always hide or show messages containing certain text.
* Can block messages that use game languages you don't know while in sanctuary areas like Shattrath - only there because it can be useful to see an enemy speak while in PvP places.
* Can change CLINK links into proper links.
* Can remove raid target icons from numbered channels (while keeping them in raid/yell/etc).
* Can translate spell and recipe links (just the name, not the prefix like "Alchemy: ").
* Can block or allow all messages from specific players or NPCs.
* Can block channel invitations from people that aren't friends, guild members, or group members.

To open the settings, use: **`/spamblock`**<br/>
To reset statistics, use: **`/spamblock stats reset`**

## Screenshots:
![!](https://i.imgur.com/PChqK3A.png)

![!](https://i.imgur.com/HUe79Pm.png)

## Duplicate Message Blocking:
Duplicate message blocking is split up into two groups of chat message types. The first, which have red names in the options, are more "spammy" and a longer timer to block each duplicate message may be suitable. The second group is for chat message types you might not want to block very long, but a 1 or 2 second duplicate block can still stop things like /spit spam or someone accidentally pressing a "USING DRUMS NOW!!!" macro 9999 times at once.

## Whitelist/Blacklist Blocking:
To set up blocked or allowed text, pick a chat message type from the dropdown menu then type each thing to block or allow on separate lines in the editboxes.

The "Normalize these messages" option should generally be kept on since it makes matching easier. It removes spaces, punctuation, icons like {skull}, and "...hic!", and changes "sh" to "s" to remove drunk slurs. Each line you write will be automatically changed in the same way if needed, so you can leave spaces and everything in.

The "Special: Names" group is for lists of exact player and NPC names.

## Advanced Blocking/Allowing:
Lua pattern matching can be used if you put a **`:`** at the beginning of a line in a block or allow list. Lua lines won't be automatically changed if message normalization is on, so you would have to remove spaces/punctuation/etc yourself if needed. Messages to match will be all lowercase, though.

This matches "anal [link]" but not "I'm at the canal" or "Analyzing... denied!" The "c" is the beginning of the link's color code.<br/>
**`:^analc`**

This matches WTS, WTB, WTE, and WTT:<br/>
**`:wt[sbet]`**

To match everything, use this. You could use it to block everything except what's on an allow list, or to always allow everything on that channel/chat type even if it matches something on the "All" block list.<br/>
**`:.`**

To block messages using some characters not normally used in English, you can use this (some people always have 1 invisible blocked character even when speaking English, so it requires there to be 2):<br/>
**`:[\204-\225\227-\240].+[\204-\225\227-\240]`**

To block most (maybe all) emote actions like /bow that don't specifically target you, open the Emote Action lists, uncheck normalization, and add these:<br/>
Block list: **`:.`**<br/>
Allow list: **`: you[ %.r]`**