from __future__ import annotations


def setup(bot):
    @bot.command("ping", aliases=("p",), help="测试 bot 是否在线")
    def ping(ctx):
        reply_text = ctx.config.get("reply_text", "pong")
        count = ctx.store.incr("ping_count")
        return f"{reply_text}：{ctx.sender_name}，我在线。本插件已响应 {count} 次。"

    @bot.command("whoami", help="显示发送者信息")
    def whoami(ctx):
        member = ctx.sender_member()
        role = "群主" if ctx.is_owner() else "管理员" if ctx.is_admin() else "成员"
        name = member.display_name if member else ctx.sender_name
        return f"你是 {name}，UID {ctx.sender_id}，身份：{role}"

    @bot.command("member", help="查找群成员，例如 /member 昵称或UID")
    def member(ctx):
        if not ctx.arg_text:
            return "用法：/member 昵称或UID"
        target = ctx.find_member(ctx.arg_text)
        if target is None:
            return f"没有找到群成员：{ctx.arg_text}"
        role = "群主" if target.is_owner else "管理员" if target.is_admin else target.role or "成员"
        return f"{target.display_name} / UID {target.id} / {role}"
