# tg-npcreactions

[Standalone] NPC Reacts Player Held Weapon FiveM Script

[Preview Video](https://streamable.com/lvv0ix)

## What it does

When a player walks near NPCs with a visible threatening weapon, nearby NPCs notice the danger and react before any shot is fired. Depending on distance and aiming state, they may hesitate for a short moment, look toward the player, then flee.

## Install

Add this resource to your `server.cfg`:

```cfg
ensure tg-npcreactions
```

## Performance model

The script sleeps while the player is not holding a threatening weapon. It scans streamed peds only when needed, limits reactions per scan, and stores cooldowns so the same NPC is not re-tasked constantly.
