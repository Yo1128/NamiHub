"""Verify close-to-tray and the restore callback on the integration test's own window."""
import ctypes
from ctypes import wintypes
import json
import ssl
import sys
import time
import urllib.request

pid, url, public_cert = sys.argv[1:]
user = ctypes.windll.user32
found = []


@ctypes.WINFUNCTYPE(wintypes.BOOL, wintypes.HWND, wintypes.LPARAM)
def visit(hwnd, _):
    owner = wintypes.DWORD()
    user.GetWindowThreadProcessId(hwnd, ctypes.byref(owner))
    title = ctypes.create_unicode_buffer(128)
    user.GetWindowTextW(hwnd, title, len(title))
    if owner.value == int(pid) and title.value == "NamiHub":
        found.append(hwnd)
    return True


user.EnumWindows(visit, 0)
if len(found) != 1:
    raise RuntimeError("Expected one window belonging to the test process")
hwnd = wintypes.HWND(found[0])


def wait_visible(wanted):
    for _ in range(100):
        if bool(user.IsWindowVisible(hwnd)) == wanted:
            return
        time.sleep(.035)
    raise RuntimeError("Unexpected native window visibility")


user.PostMessageW(hwnd, 0x0010, 0, 0)  # WM_CLOSE
try:
    wait_visible(False)
    with urllib.request.urlopen(url + "/v1/info", context=ssl.create_default_context(cafile=public_cert), timeout=5) as response:
        assert json.load(response)["apiVersion"] == 1
finally:
    user.PostMessageW(hwnd, 0x8000 + 12, 0, 0x0202)  # tray left-up callback
    wait_visible(True)
