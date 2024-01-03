#!/home/mjr/code/personal/dotfiles/.venv/bin/python
import asyncio
from datetime import datetime
import os

import rofi_menu


class OutputSomeTextItem(rofi_menu.Item):
    """Output arbitrary text on selection"""
    async def on_select(self, meta):
        # any python code
        await asyncio.sleep(0.1)
        return rofi_menu.Operation(rofi_menu.OP_OUTPUT, (
            "💢 simple\n"
            "💥 multi-\n"
            "💫 <b>line</b>\n"
            "💣 <i>text</i>\n"
        ))


class DoAndExitItem(rofi_menu.Item):
    """Do something and exit"""
    async def on_select(self, meta):
        os.system('notify-send msg')
        return rofi_menu.Operation(rofi_menu.OP_EXIT)


class CurrentDatetimeItem(rofi_menu.Item):
    """Show current datetime inside menu item"""
    async def load(self, meta):
        self.state = datetime.now().strftime('%A %d. %B %Y (%H:%M:%S)')

    async def render(self, meta):
        return f"🕑 {self.state}"


class CounterItem(rofi_menu.Item):
    """Increment counter on selection"""
    async def load(self, meta):
        await super().load(meta)
        self.state = self.state or 0
        meta.session.setdefault("counter_total", 0)

    async def on_select(self, meta):
        self.state += 1
        meta.session["counter_total"] += 1
        return await super().on_select(meta)

    async def render(self, meta):
        per_menu_item = self.state
        total = meta.session["counter_total"]
        return f"🏃 Selected #{per_menu_item} time(s) (across menu items #{total})"


class HandleUserInputMenu(rofi_menu.Menu):
    allow_user_input = True

    class CustomItem(rofi_menu.Item):
        async def render(self, meta):
            entered_text = meta.session.get("text", "[ no text ]")
            return f"You entered: {entered_text}"

    items = [CustomItem()]

    async def on_user_input(self, meta):
        meta.session['text'] = meta.user_input
        return rofi_menu.Operation(rofi_menu.OP_REFRESH_MENU)


main_menu = rofi_menu.Menu(
    prompt="menu",
    items=[
        OutputSomeTextItem("Output anything"),
        DoAndExitItem("Do something and exit"),
        CurrentDatetimeItem(),
        CounterItem(),
        CounterItem(),
        rofi_menu.NestedMenu("User input", HandleUserInputMenu()),
    ],
)


if __name__ == "__main__":
    rofi_menu.run(main_menu)