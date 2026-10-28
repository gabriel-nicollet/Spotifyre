#!/usr/bin/env python3
"""Drives the driver harness (main.m) through scripts/phone.py and prints PASS or FAIL per check.

    THEOS=$HOME/theos ./build.sh
    xcrun simctl install <udid> build/DriverHarness.app && xcrun simctl launch <udid> com.vitrine.driverharness
    ./proof.py                     # PHONE_PORT=8095 unless set, the port build.sh serves on
"""
import json
import os
import struct
import subprocess
import sys
import tempfile
import threading
import time

HERE = os.path.dirname(os.path.abspath(__file__))
PHONE = os.path.join(HERE, "..", "..", "scripts", "phone.py")
os.environ.setdefault("PHONE_PORT", "8095")
failures = 0


def phone(*args):
    out = subprocess.run([sys.executable, PHONE, *args], capture_output=True, text=True).stdout
    return out if args[0] == "tree" else json.loads(out)


def check(ok, what):
    global failures
    failures += not ok
    print(f"{'PASS' if ok else 'FAIL'} {what}")


def lines(since):
    return [line["text"] for line in phone("log", "--since", str(since))["lines"]]


def last():
    return phone("state")["logSeq"]


phone("tab", "Home")
check("== window" in phone("tree"), "tree: GET /tree still answers with the tree")
check(phone("state")["top"] == "HarnessHome", "state: the top controller is Home")

start = last()
answer = phone("tap", "--id", "counter")
check(answer["ok"] and answer["hit"] == "UIButton", "tap --id: the finger lands on the button")
check(any(t.startswith("harness: button tapped") for t in lines(start)), "tap --id: the button's touch-up-inside action ran")

start = last()
phone("tap", "--id", "tapview")
check("harness: recognizer tap" in lines(start), "tap: a UITapGestureRecognizer recognized the touch")

start = last()
phone("longpress", "--id", "menubutton", "--duration", "1")
log = lines(start)
check("harness: menu will display" in log and "harness: finger up" in log
      and log.index("harness: menu will display") < log.index("harness: finger up"),
      "longpress: a primary-action menu opens on the touch down, before the finger lifts")
check(phone("state")["menu"] is True, "state: menu is up")
start = last()
check(phone("menu.pick", "Alpha")["ok"], "menu.pick: the row is found and tapped")
check(phone("wait", "--log", "harness: menu picked Alpha", "--timeout", "2")["ok"], "menu.pick: the row's action ran")
check(phone("wait", "--menu", "1", "--gone", "1", "--timeout", "2")["ok"], "wait --menu --gone: the menu closed")

answer = phone("scroll", "--id", "scroller", "--by", "0,500")
check(answer["ok"] and answer["after"] == [0, 500], "scroll: the scroll view moved by the offset")
phone("swipe", "--id", "scroller", "--by", "0,-300")
time.sleep(1.5)
offset = phone("find", "--id", "scroller")["views"][0]["contentOffset"][1]
check(offset > 850, f"swipe: a real fling moved the list past the 300 pt of the swipe ({offset:.0f})")

start = last()
phone("tap", "--id", "field")
phone("type", "hello driver")
check("harness: field text hello driver" in lines(start), "type: the text went into the tapped field")

shot = os.path.join(tempfile.gettempdir(), f"driver-proof-{os.getpid()}.png")
answer = phone("screenshot", shot)
with open(shot, "rb") as f:
    head = f.read(24)
width, height = struct.unpack(">II", head[16:24])
check(answer["ok"] and head[:8] == b"\x89PNG\r\n\x1a\n" and width > 1000, f"screenshot: a {width}x{height} PNG came back")
os.remove(shot)

check(phone("player.open")["ok"] and phone("wait", "--id", "Context menu")["ok"], "player.open: the bar opened the player")
check(phone("player.more")["ok"], "player.more: the ⋯ was tapped")
check(phone("wait", "--log", "harness: player menu will display", "--timeout", "3")["ok"], "wait --log: the ⋯'s menu came up")
phone("menu.pick", "Sleep timer")
check(phone("wait", "--log", "harness: player menu picked Sleep timer", "--timeout", "3")["ok"], "menu.pick: Sleep timer picked in the player's menu")
phone("player.close")
check(phone("state")["player"] is False, "player.close: the down arrow closed the player")

start = last()
phone("seek", "42")
phone("pause")
state = phone("state")["nowPlaying"]
phone("play")
phone("next")
log = lines(start)
check(state["position"] == 42 and state["paused"] and {"harness: player seekTo 42", "harness: player pause", "harness: player resume", "harness: player next"} <= set(log),
      "seek, pause, play, next: the player was told, and state reads it back")

phone("tab", "Search")
check(phone("state")["top"] == "HarnessSearch", "tab by title: Search is shown")
phone("tab", "0")
check(phone("state")["top"] == "HarnessHome", "tab by index: Home is shown again")

phone("settings.open")
check(phone("state")["top"] == "HarnessSettings", "settings.open: Mod Settings is pushed")
check(phone("settings.page", "Row 33")["ok"] and phone("wait", "--log", "harness: settings row Row 33")["ok"],
      "settings.page: a row below the fold is scrolled to and tapped")

check(phone("tap", "--id", "nope")["error"] == "no view matches id=nope", "tap: a missing view is an error, not a crash")

# The tree still answers while a command waits.
waiting = threading.Thread(target=phone, args=("wait", "--log", "never", "--timeout", "2"))
waiting.start()
time.sleep(0.3)
began = time.time()
phone("tree")
check(time.time() - began < 1 and waiting.is_alive(), "the tree is served while a wait runs")
waiting.join()

print("done," , "all passed" if not failures else f"{failures} failed")
sys.exit(1 if failures else 0)
