from __future__ import annotations


def setup(bot):
    @bot.command("echo", help="复读文本，例如 /echo 你好")
    def echo(ctx):
        if not ctx.arg_text:
            return "用法：/echo 要复读的文本"
        return ctx.arg_text

    @bot.command("say", help="让 bot 发送一条群消息，例如 /say 大家好")
    def say(ctx):
        if not ctx.arg_text:
            return "用法：/say 要发送的文本"
        ctx.send_group(ctx.room_id, ctx.arg_text)
        ctx.log.info("say command sent a message to room %s", ctx.room_id)
        return None
