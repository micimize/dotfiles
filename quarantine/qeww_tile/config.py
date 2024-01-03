from pathlib import Path
from typing import Any, Callable, Final, Iterable, Tuple, cast
from libqtile import bar, layout, widget
from libqtile.config import Click, Drag, Group, Key, Match, Screen
from libqtile.lazy import lazy
from libqtile.utils import guess_terminal
from libqtile import qtile as _qtile
from libqtile.core.manager import Qtile

from libqtile import hook
from libqtile.backend.base.window import Window
from libqtile.widget.quick_exit import QuickExit
from libqtile.widget.clock import Clock
from libqtile.widget.systray import Systray
from libqtile.widget.currentlayout import CurrentLayout
from libqtile.widget.groupbox import GroupBox
from libqtile.widget.prompt import Prompt
from libqtile.widget.windowname import WindowName
from libqtile.widget.chord import Chord
from libqtile.widget.textbox import TextBox
from libqtile.widget.bluetooth import Bluetooth
from libqtile.widget.clipboard import Clipboard
from libqtile.widget.net import Net

import sys,os.path


_flex_tree_path = (Path(os.path.realpath(__file__)).parent / "flex_tree").as_posix()
sys.path.append(_flex_tree_path)
from flex_tree import FlexTree


qtile: Qtile = _qtile

Modifiers = str | Iterable[str]

ALT: Final = "mod1"
NUM_LOCK: Final = "mod2"
COMMAND: Final = "mod4"
CONTROL: Final = "control"
SHIFT: Final = "shift"
SPACE: Final = "space"
RETURN: Final = "Return"
TAB: Final = "Tab"


terminal = "konsole" #"wezterm" #guess_terminal()
assert terminal is not None


# "macros" to be applied to the next series of windows as they're added
MOVE_AHEAD: Final[list[Callable[[Window], Any]]] = []



# TODO: volume, network, bluetooth, datetime, calendar,notifications, media maybe

# control: navigate
# alt: move stuff (alternate)

def _mods(mods: Modifiers = tuple()) -> list[str]:
    return [COMMAND, mods] if isinstance(mods, str) else [COMMAND, *mods]


def _dir_cluster(
    modifier: Modifiers,
    description: str,
    dir_keys: Tuple[str, str, str, str],
    actions: Tuple[Any, Any, Any, Any],
) -> Tuple[Key, Key, Key, Key]:
    modifier = _mods(modifier)
    left, down, up, right = dir_keys
    left_act, down_act, up_act, right_act = actions
    return (
        Key(modifier, left, left_act, desc=f"{description} left"),
        Key(modifier, down, down_act, desc=f"{description} down"),
        Key(modifier, up, up_act, desc=f"{description} up"),
        Key(modifier, right, right_act, desc=f"{description} right"),
    )

def flex_tree_window_navigation_and_movement(
    focus_modifier: Modifiers,
    swap_modifier: Modifiers,
    integrate_modifier: Modifiers,
    resize_modifier: Modifiers,
    resize_increment: int = 30,
    dir_keys: Tuple[str, str, str, str] = ('h', 'j', 'k', 'l'),
) -> Tuple[Key, ...]:
    focus_actions = _dir_cluster(focus_modifier, "Move window focus", dir_keys, (
        lazy.layout.left(),
        lazy.layout.down(),
        lazy.layout.up(),
        lazy.layout.right(),
    ))
    swap_actions = _dir_cluster(swap_modifier, "Swap window", dir_keys, (
        lazy.layout.move_left(),
        lazy.layout.move_down(),
        lazy.layout.move_up(),
        lazy.layout.move_right(),
    ))
    integrate_actions = _dir_cluster(integrate_modifier, "Integrate window", dir_keys, (
        lazy.layout.integrate_left(),
        lazy.layout.integrate_down(),
        lazy.layout.integrate_up(),
        lazy.layout.integrate_right(),
    ))

    resize_modifier = _mods(resize_modifier)
    left, down, up, right = dir_keys
    resize_actions = (
        Key(resize_modifier, left, lazy.layout.grow_width(-resize_increment), desc=f"Shrink window width"),
        Key(resize_modifier, down, lazy.layout.grow_height(-resize_increment), desc=f"Shrink window height"),
        Key(resize_modifier, up, lazy.layout.grow_height(resize_increment), desc=f"Grow window height"),
        Key(resize_modifier, right, lazy.layout.grow_width(resize_increment), desc=f"Grow window width"),
    )
    
    return (*focus_actions, *swap_actions, *integrate_actions, *resize_actions)

def init_margin_tree(
        # screen: Screen, layout: FlexTree
        ):
    """Populate the flex_tree tree with 'margin' terminal panes"""
    MOVE_AHEAD.extend((
        lambda left_w: None,
        lambda top_w: None,
        lambda right_w: (
            cast(FlexTree, qtile.current_layout).left(),
            cast(FlexTree, qtile.current_layout).mode_vertical_split(),
        ),
        lambda bottom_w: cast(FlexTree, qtile.current_layout).up(),
    ))
    for _ in range(3):
        qtile.spawn(terminal)

@hook.subscribe.client_managed
def move_ahead(client: Window):
    if not MOVE_AHEAD:
        return
    MOVE_AHEAD.pop(0)(client)


@hook.subscribe.startup_once
def autostart():
    return
    init_margin_tree()

keys = [
    # A list of available commands that can be bound to keys can be found
    # at https://docs.qtile.org/en/latest/manual/config/lazy.html
    *flex_tree_window_navigation_and_movement(
        focus_modifier=tuple(), # command your focus
        integrate_modifier=(CONTROL,), # command focus while controlling window position
        swap_modifier=ALT, # alternate this window with another's position
        resize_modifier=(SHIFT,), # shift window size
    ),
    Key(_mods(), "y", lazy.layout.mode_horizontal(), desc="Horizontal Mode: add next window to right"),
    Key(_mods(SHIFT), "y", lazy.layout.mode_horizontal_split(), desc="Horizontal Split Mode: Split and add next window to right"),
    Key(_mods(), "u", lazy.layout.mode_vertical(), desc="Vertical Mode: add next window down"),
    Key(_mods(SHIFT), "u", lazy.layout.mode_vertical_split(), desc="Vertical Split Mode: Split and add next window down"),
    Key(_mods(), "Return", lazy.spawn(terminal), desc="Launch terminal"),
    #
    Key(_mods(), "q", lazy.window.kill(), desc="Kill focused window"),
    Key(_mods(), "f", lazy.window.toggle_fullscreen(), desc="Toggle fullscreen for focused window"),
    Key(_mods(), "t", lazy.window.toggle_floating(), desc="Toggle floating on the focused window"),
    Key(_mods(CONTROL), "r", lazy.reload_config(), desc="Reload the config"),
    Key(_mods(CONTROL), "q", lazy.shutdown(), desc="Shutdown Qtile"),
    Key(_mods(), "r", lazy.spawncmd(), desc="Spawn a command using a prompt widget"),
    Key(_mods(), 'm', lazy.layout.toggle_minimize_inline()),
]

groups = [Group(i) for i in "123456789"]

for i in groups:
    keys.extend(
        [
            # mod1 + letter of group = switch to group
            Key(
                _mods(),
                i.name,
                lazy.group[i.name].toscreen(),
                desc="Switch to group {}".format(i.name),
            ),
            # mod1 + shift + letter of group = switch to & move focused window to group
            Key(
                [COMMAND, "shift"],
                i.name,
                lazy.window.togroup(i.name, switch_group=True),
                desc="Switch to & move focused window to group {}".format(i.name),
            ),
            # Or, use below if you prefer not to switch to that group.
            # # mod1 + shift + letter of group = move focused window to group
            # Key([mod, "shift"], i.name, lazy.window.togroup(i.name),
            #     desc="move focused window to group {}".format(i.name)),
        ]
    )

groups.append(Group('')) # Must be after `groups` is created


layouts = [
    FlexTree(
        border_normal='#333333',
        border_focus='#00e891',
        border_normal_fixed='#006863',
        border_focus_fixed='#00e8dc',
        border_width=1,
        border_width_single=0,
        margin=8,
        margin_single=8
    ),

    layout.Columns(border_focus_stack=["#d75f5f", "#8f3d3d"], border_width=4),
    layout.Max(),
    # Try more layouts by unleashing below layouts.
    # layout.Stack(num_stacks=2),
    # layout.Bsp(),
    # layout.Matrix(),
    # layout.MonadTall(),
    # layout.MonadWide(),
    # layout.RatioTile(),
    # layout.Tile(),
    # layout.TreeTab(),
    # layout.VerticalTile(),
    # layout.Zoomy(),
]

widget_defaults = dict(
    font="sans",
    fontsize=12,
    padding=3,
)
extension_defaults = widget_defaults.copy()

screens = [
    Screen(
        bottom=bar.Bar(
            widgets=[
                CurrentLayout(),
                GroupBox(),
                Prompt(),
                WindowName(),
                Chord(
                    chords_colors={
                        "launch": ("#ff0000", "#ffffff"),
                    },
                    name_transform=lambda name: name.upper(),
                ),
                Net(),
                Bluetooth(),
                TextBox("default config", name="default"),
                TextBox("Press &lt;M-r&gt; to spawn", foreground="#d75f5f"),
                # NB Systray is incompatible with Wayland, consider using StatusNotifier instead
                # widget.StatusNotifier(),
                Clock(format="%Y-%m-%d %a %I:%M %p"),
                QuickExit(),
            ],
            size=24,
            # border_width=[2, 0, 2, 0],  # Draw top and bottom borders
            # border_color=["ff00ff", "000000", "ff00ff", "000000"]  # Borders are magenta
        ),
        # You can uncomment this variable if you see that on X11 floating resize/moving is laggy
        # By default we handle these events delayed to already improve performance, however your system might still be struggling
        # This variable is set to None (no cap) by default, but you can set it to 60 to indicate that you limit it to 60 events per second
        # x11_drag_polling_rate = 60,
    ),
]

# Drag floating layouts.
mouse = [
    Drag(_mods(), "Button1", lazy.window.set_position_floating(), start=lazy.window.get_position()),
    Drag(_mods(), "Button3", lazy.window.set_size_floating(), start=lazy.window.get_size()),
    Click(_mods(), "Button2", lazy.window.bring_to_front()),
]

from libqtile.log_utils import logger
@hook.subscribe.client_new
def auto_kill_window(window:Window):
    if window.name.startswith("Desktop") and window.name.endswith("Plasma"):
        window.kill()

dgroups_key_binder = None
dgroups_app_rules = []  # type: list
follow_mouse_focus = False
bring_front_click = False
floats_kept_above = True
cursor_warp = False
floating_layout = layout.Floating(
    float_rules=[
        # Run the utility of `xprop` to see the wm class and name of an X client.
        *layout.Floating.default_float_rules,
        Match(wm_class="confirmreset"),  # gitk
        Match(wm_class="makebranch"),  # gitk
        Match(wm_class="maketag"),  # gitk
        Match(wm_class="ssh-askpass"),  # ssh-askpass
        Match(wm_class="plasmashell"),
        Match(wm_class="spectacle"),
        Match(wm_class="krunner"),
        Match(wm_class="ksmserver-logout-greeter"),
        Match(title="branchdialog"),  # gitk
        Match(title="pinentry"),  # GPG key password entry
    ]
)
auto_fullscreen = True
focus_on_window_activation = "smart"
reconfigure_screens = True

# If things like steam games want to auto-minimize themselves when losing
# focus, should we respect this or not?
auto_minimize = True

# When using the Wayland backend, this can be used to configure input devices.
wl_input_rules = None

# XXX: Gasp! We're lying here. In fact, nobody really uses or cares about this
# string besides java UI toolkits; you can see several discussions on the
# mailing lists, GitHub issues, and other WM documentation that suggest setting
# this string if your java app doesn't work correctly. We may as well just lie
# and say that we're a working one by default.
#
# We choose LG3D to maximize irony: it is a 3D non-reparenting WM written in
# java that happens to be on java's whitelist.
wmname = "LG3D"

