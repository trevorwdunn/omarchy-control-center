#!/usr/bin/env python3
"""Battery levels of peripherals the system does not report, as a JSON list.

UPower already covers Bluetooth devices and Logitech Unifying receivers. This
fills two gaps by asking the devices directly over hidraw:

Keychron mice. They report no standard HID battery, but answer a vendor
status query (output report 0xB3, command 0x06, on the 0xFFC1 config
interface) with report 0xB4, whose payload byte 19 holds the level in the low
seven bits and the charging flag in the top bit. The same query goes through
a 2.4 GHz receiver to the mouse linked to it. Keychron keyboards have no such
query and are not covered.

Logitech devices on a Bolt receiver, which the kernel does not drive. Each
paired slot is asked over HID++ 2.0 for its unified battery (feature 0x1004,
or 0x1000 on older devices) and its name. Receivers the kernel does drive are
left alone; their devices arrive through UPower.

Only read-only queries are sent. Each line of output is one device:
{"name", "kind", "percent", "charging"}.

Needs read/write access to the hidraw nodes; batteries.rules next to this
file grants it to the logged-in user (Solaar's udev rule also covers the
Logitech half).
"""


import glob
import json
import os
import select
import time

# ------------------------------------------------------------------ Keychron

VENDOR = "3434"
CONFIG_PAGE = b"\x06\xc1\xff"
NAMES = os.path.join(
    os.environ.get("XDG_CACHE_HOME", os.path.expanduser("~/.cache")),
    "omarchy", "keychron-names.json")
TIMEOUT = 0.4


def config_nodes():
    """Yield (hidraw path, product id, product name) per Keychron config interface."""
    for sysfs in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        try:
            uevent = dict(
                line.split("=", 1)
                for line in open(sysfs + "/device/uevent").read().splitlines() if "=" in line)
            descriptor = open(sysfs + "/device/report_descriptor", "rb").read()
        except OSError:
            continue
        ids = uevent.get("HID_ID", "").split(":")
        if len(ids) != 3 or ids[1][-4:].lower() != VENDOR or CONFIG_PAGE not in descriptor:
            continue
        name = " ".join(uevent.get("HID_NAME", "").split())
        # "Keychron Keychron M6" -> "Keychron M6"
        words = name.split()
        if len(words) > 1 and words[0] == words[1]:
            name = " ".join(words[1:])
        yield "/dev/" + os.path.basename(sysfs), ids[2][-4:].lower(), name


def exchange(fd, report, command, reply_ids):
    """Send one query and return the payload of the matching reply, or None."""
    while select.select([fd], [], [], 0)[0]:
        os.read(fd, 256)
    size = 63 if report == 0xB3 else 20
    os.write(fd, bytes([report, command]) + bytes(size - 1))
    deadline = time.monotonic() + TIMEOUT
    while True:
        left = deadline - time.monotonic()
        if left <= 0 or not select.select([fd], [], [], left)[0]:
            return None
        frame = os.read(fd, 256)
        if len(frame) > 2 and frame[0] in reply_ids and frame[1] == command:
            return frame[1:]


def keychron_linked(fd):
    """Product ids of the devices a receiver reports as connected."""
    payload = exchange(fd, 0xB5, 0x03, (0xB6,))
    out = []
    if payload:
        for i in range(min(payload[1], (len(payload) - 2) // 5)):
            entry = payload[2 + i * 5: 7 + i * 5]
            if entry[4] == 1:
                out.append("%02x%02x" % (entry[3], entry[2]))
    return out


def keychron_battery(fd):
    for _ in range(2):
        payload = exchange(fd, 0xB3, 0x06, (0xB4, 0xB6))
        if payload and len(payload) >= 20:
            level = payload[19] & 0x7F
            if level <= 100:
                return level, bool(payload[19] & 0x80)
    return None


def keychron():
    try:
        names = json.load(open(NAMES))
    except (OSError, ValueError):
        names = {}
    learned = dict(names)
    found = []
    for path, product, name in config_nodes():
        receiver = "link" in name.lower()
        try:
            fd = os.open(path, os.O_RDWR | os.O_NONBLOCK)
        except OSError:
            continue
        try:
            if receiver:
                devices = keychron_linked(fd)
                if not devices:
                    continue
                # A receiver is only ever a name for what is linked to it;
                # the real one is learned the first time that device is
                # seen on a cable.
                label = names.get(devices[0], "Keychron mouse")
            else:
                label = name
                learned[product] = name
            reading = keychron_battery(fd)
            if reading:
                found.append({"name": label, "kind": "mouse", "percent": reading[0],
                              "charging": reading[1]})
        except OSError:
            pass
        finally:
            os.close(fd)
    if learned != names:
        try:
            os.makedirs(os.path.dirname(NAMES), exist_ok=True)
            json.dump(learned, open(NAMES, "w"))
        except OSError:
            pass
    return found


# ------------------------------------------------------------ Logitech HID++

HIDPP_PAGE = b"\x06\x00\xff"
HIDPP_SOFTWARE_ID = 0x0B
HIDPP_TIMEOUT = 1.2
HIDPP_KINDS = {0: "keyboard", 2: "keyboard", 3: "mouse", 4: "mouse", 5: "mouse", 8: "headset"}
TIMED_OUT = object()


def hidpp_nodes():
    """HID++ interfaces of Logitech receivers no kernel driver has claimed."""
    for sysfs in sorted(glob.glob("/sys/class/hidraw/hidraw*")):
        try:
            uevent = open(sysfs + "/device/uevent").read().upper()
            descriptor = open(sysfs + "/device/report_descriptor", "rb").read()
            driver = os.path.basename(os.readlink(sysfs + "/device/driver"))
        except OSError:
            continue
        if ":0000046D:" not in uevent or driver != "hid-generic":
            continue
        if descriptor.startswith(HIDPP_PAGE) and b"\x85\x11" in descriptor:
            yield "/dev/" + os.path.basename(sysfs)


def hidpp_request(fd, slot, feature, function, params=b""):
    """One HID++ 2.0 call. Returns the reply parameters, None on an error
    reply (no such device or feature), or TIMED_OUT when nothing answers."""
    while select.select([fd], [], [], 0)[0]:
        os.read(fd, 64)
    head = bytes([slot, feature, (function << 4) | HIDPP_SOFTWARE_ID])
    os.write(fd, bytes([0x11]) + head + params + bytes(16 - len(params)))
    deadline = time.monotonic() + HIDPP_TIMEOUT
    while True:
        left = deadline - time.monotonic()
        if left <= 0 or not select.select([fd], [], [], left)[0]:
            return TIMED_OUT
        frame = os.read(fd, 64)
        if len(frame) < 7 or frame[1] != slot:
            continue
        if frame[0] == 0x11 and frame[2] == 0xFF and frame[3:5] == head[1:3]:
            return None
        if frame[0] == 0x10 and frame[2] == 0x8F and frame[3:5] == head[1:3]:
            return None
        if frame[0] == 0x11 and frame[1:4] == head:
            return frame[4:]


def hidpp_feature(fd, slot, feature_id):
    reply = hidpp_request(fd, slot, 0x00, 0, bytes([feature_id >> 8, feature_id & 0xFF]))
    if reply is TIMED_OUT:
        return TIMED_OUT
    return reply[0] if reply and reply[0] else None


def hidpp_battery(fd, slot):
    index = hidpp_feature(fd, slot, 0x1004)
    if index is TIMED_OUT:
        return None  # paired but asleep or out of range
    if index:
        reply = hidpp_request(fd, slot, index, 1)
        if reply and reply is not TIMED_OUT and reply[0] <= 100:
            return reply[0], reply[2] in (1, 2)
    index = hidpp_feature(fd, slot, 0x1000)
    if index and index is not TIMED_OUT:
        reply = hidpp_request(fd, slot, index, 0)
        if reply and reply is not TIMED_OUT and 0 < reply[0] <= 100:
            return reply[0], reply[2] in (1, 2, 4)
    return None


def hidpp_identity(fd, slot):
    index = hidpp_feature(fd, slot, 0x0005)
    if not index or index is TIMED_OUT:
        return "Logitech device", "other"
    reply = hidpp_request(fd, slot, index, 0)
    length = reply[0] if reply and reply is not TIMED_OUT else 0
    name = b""
    while len(name) < length:
        part = hidpp_request(fd, slot, index, 1, bytes([len(name)]))
        if not part or part is TIMED_OUT:
            break
        name += part[:length - len(name)]
    reply = hidpp_request(fd, slot, index, 2)
    kind = HIDPP_KINDS.get(reply[0], "other") if reply and reply is not TIMED_OUT else "other"
    return name.decode("utf-8", "replace").strip("\x00 ") or "Logitech device", kind


def logitech():
    found = []
    for path in hidpp_nodes():
        try:
            fd = os.open(path, os.O_RDWR | os.O_NONBLOCK)
        except OSError:
            continue
        try:
            for slot in range(1, 7):
                reading = hidpp_battery(fd, slot)
                if reading:
                    name, kind = hidpp_identity(fd, slot)
                    found.append({"name": name, "kind": kind, "percent": reading[0],
                                  "charging": reading[1]})
        except OSError:
            pass
        finally:
            os.close(fd)
    return found


if __name__ == "__main__":
    # Side by side: each waits on its own radio links.
    from concurrent.futures import ThreadPoolExecutor
    with ThreadPoolExecutor() as pool:
        jobs = [pool.submit(keychron), pool.submit(logitech)]
    print(json.dumps([device for job in jobs for device in job.result()]))
