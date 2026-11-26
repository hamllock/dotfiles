#!/usr/bin/env python3
"""Wi-Fi backend for WifiPopup.qml (NetworkManager / nmcli). Prints one JSON object.

  wifi.py status                  power, connected network, every network in range
  wifi.py connect <ssid> [pass]   saved -> bring it up; new -> connect (with password)
  wifi.py disconnect
  wifi.py forget <ssid>
  wifi.py power on|off
  wifi.py rescan
"""
import glob
import json
import re
import subprocess
import sys

ENV = {"LC_ALL": "C", "PATH": "/usr/bin:/bin"}


def nm(*args, timeout=10):
    r = subprocess.run(["nmcli", *args], capture_output=True, text=True, timeout=timeout, env=ENV)
    return r.returncode, r.stdout, r.stderr.strip()


def fields(line):
    """Split one `nmcli -t` line: ':' separates fields, '\\:' is a literal colon."""
    return [f.replace("\\:", ":").replace("\\\\", "\\") for f in re.split(r"(?<!\\):", line)]


def wifi_device():
    _, out, _ = nm("-t", "-f", "DEVICE,TYPE", "device")
    for line in out.splitlines():
        f = fields(line)
        if len(f) >= 2 and f[1] == "wifi":
            return f[0]
    return None


def saved_networks():
    _, out, _ = nm("-t", "-f", "NAME,TYPE", "connection", "show")
    return {f[0] for f in map(fields, out.splitlines()) if len(f) >= 2 and f[1] == "802-11-wireless"}


def status():
    if not glob.glob("/sys/class/net/*/wireless"):
        return {"present": False, "power": False, "connected": None, "networks": []}
    _, radio, _ = nm("radio", "wifi")
    if radio.strip() != "enabled":
        return {"present": True, "power": False, "connected": None, "networks": []}

    saved = saved_networks()
    _, out, _ = nm("-t", "-f", "IN-USE,SSID,SIGNAL,SECURITY,FREQ", "device", "wifi", "list", "--rescan", "no")
    best, connected = {}, None
    for line in out.splitlines():
        f = fields(line)
        if len(f) < 5 or not f[1]:
            continue                      # hidden networks have no SSID
        inuse, ssid, sig, sec, freq = f[:5]
        net = {"ssid": ssid, "signal": int(sig or 0), "security": "" if sec in ("", "--") else sec,
               "band": "5 GHz" if freq.startswith("5") else "6 GHz" if freq.startswith("6") else "2.4 GHz",
               "saved": ssid in saved}
        if inuse == "*":
            connected = dict(net)
        if ssid not in best or net["signal"] > best[ssid]["signal"]:
            best[ssid] = net

    if connected:
        dev = wifi_device()
        _, ip, _ = nm("-g", "IP4.ADDRESS", "device", "show", dev) if dev else (0, "", "")
        connected["ip"] = ip.split("|")[0].split("/")[0].strip()
        best.pop(connected["ssid"], None)

    nets = sorted(best.values(), key=lambda n: -n["signal"])
    return {"present": True, "power": True, "connected": connected, "networks": nets}


def connect(ssid, password=None):
    if ssid in saved_networks():
        code, out, err = nm("connection", "up", "id", ssid, timeout=45)
    else:
        args = ["device", "wifi", "connect", ssid] + (["password", password] if password else [])
        code, out, err = nm(*args, timeout=45)
        if code != 0:
            nm("connection", "delete", "id", ssid)   # don't keep a profile with a wrong password
    if code == 0:
        return {"ok": True}
    msg = err or out
    if re.search(r"secrets were required|password|802-1x|psk", msg, re.I):
        msg = "Wrong password"
    elif "No network with SSID" in msg:
        msg = "Network is out of range"
    else:
        msg = re.sub(r"^Error: ", "", msg.splitlines()[-1] if msg else "Couldn't connect")
    return {"ok": False, "error": msg}


def main():
    cmd, args = (sys.argv[1] if len(sys.argv) > 1 else "status"), sys.argv[2:]
    try:
        if cmd == "status":
            res = status()
        elif cmd == "connect":
            res = connect(args[0], args[1] if len(args) > 1 and args[1] else None)
        elif cmd == "disconnect":
            dev = wifi_device()
            code, _, err = nm("device", "disconnect", dev) if dev else (1, "", "No Wi-Fi device")
            res = {"ok": code == 0, "error": err}
        elif cmd == "forget":
            code, _, err = nm("connection", "delete", "id", args[0])
            res = {"ok": code == 0, "error": err}
        elif cmd == "power":
            code, _, err = nm("radio", "wifi", "on" if args and args[0] == "on" else "off")
            res = {"ok": code == 0, "error": err}
        elif cmd == "rescan":
            nm("device", "wifi", "rescan", timeout=15)
            res = {"ok": True}
        else:
            res = {"error": f"unknown command {cmd}"}
    except subprocess.TimeoutExpired:
        res = {"ok": False, "error": "Timed out"}
    print(json.dumps(res, separators=(",", ":")))


main()
