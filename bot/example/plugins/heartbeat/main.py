from __future__ import annotations


def setup(bot):
    interval = float(bot.plugin_settings("heartbeat").get("interval", 60))

    @bot.interval(interval, name="heartbeat", room_ids=None, enabled=True)
    def heartbeat(ctx):
        ctx.store.set("last_run_count", ctx.run_count)
        text = ctx.config.get("text", "heartbeat")
        return f"{text} #{ctx.run_count}"
