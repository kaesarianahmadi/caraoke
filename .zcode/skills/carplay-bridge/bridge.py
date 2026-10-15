#!/usr/bin/env python3
"""
CarPlay Bridge Controller for Caraoke App
Manages PlayPort daemon lifecycle, ports, and auto-browser opening.
"""

import argparse
import os
import signal
import subprocess
import sys
import time
import urllib.request

REPO_ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "../../.."))
PLAYPORT_DIR = os.path.join(REPO_ROOT, "tools/playport")
LOG_FILE = os.path.join(PLAYPORT_DIR, "playport.log")
DEFAULT_TOKEN = "caraoke"
DEFAULT_PORT = 8080
AIRPLAY_PORT = 7000

def get_wifi_ip() -> str:
    res = subprocess.run(["ipconfig", "getifaddr", "en0"], capture_output=True, text=True)
    ip = res.stdout.strip()
    if ip:
        return ip
    res = subprocess.run(["route", "get", "default"], capture_output=True, text=True)
    for line in res.stdout.splitlines():
        line = line.strip()
        if line.startswith("interface:"):
            iface = line.split(":", 1)[1].strip()
            ip_res = subprocess.run(["ipconfig", "getifaddr", iface], capture_output=True, text=True)
            ip = ip_res.stdout.strip()
            if ip and not ip.startswith("100."):
                return ip
    res = subprocess.run(["ifconfig"], capture_output=True, text=True)
    for line in res.stdout.splitlines():
        line = line.strip()
        if line.startswith("inet ") and not line.startswith("inet 127.") and not line.split()[1].startswith("100."):
            return line.split()[1]
    return "127.0.0.1"

def get_listening_pids(port: int):
    res = subprocess.run(["lsof", "-t", f"-i:{port}"], capture_output=True, text=True)
    return [int(p) for p in res.stdout.split() if p.isdigit()]

def is_port_listening(port: int) -> bool:
    return len(get_listening_pids(port)) > 0

def check_airplay_client() -> str:
    res = subprocess.run(["lsof", f"-i:{AIRPLAY_PORT}"], capture_output=True, text=True)
    for line in res.stdout.splitlines():
        if "ESTABLISHED" in line:
            for part in line.split():
                if "->" in part:
                    return part.split("->")[-1]
    return ""

def stop_server():
    pids = get_listening_pids(AIRPLAY_PORT) + get_listening_pids(DEFAULT_PORT)
    res = subprocess.run(["pgrep", "-f", "playport"], capture_output=True, text=True)
    for p in res.stdout.split():
        if p.isdigit():
            pids.append(int(p))
    pids = list(set(pids))
    if not pids:
        print("PlayPort is not running.")
        return
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    time.sleep(1)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    print("PlayPort server stopped. Ports released.")

def start_server(token: str = DEFAULT_TOKEN, auto_open: bool = True):
    if is_port_listening(DEFAULT_PORT):
        print(f"PlayPort is already running on port {DEFAULT_PORT}.")
        url = f"http://localhost:{DEFAULT_PORT}/?token={token}"
        if auto_open:
            subprocess.run(["open", url])
        return

    wifi_ip = get_wifi_ip()
    print(f"Detected LAN Wi-Fi IP: {wifi_ip}")
    print(f"Starting PlayPort daemon on {wifi_ip}:{AIRPLAY_PORT}...")

    cmd = [
        "./start.sh",
        "--http",
        "--bind", wifi_ip,
        "--token", token,
    ]

    with open(LOG_FILE, "a") as log_out:
        log_out.write(f"\n--- PlayPort started at {time.strftime('%Y-%m-%d %H:%M:%S')} ---\n")
        subprocess.Popen(
            cmd,
            cwd=PLAYPORT_DIR,
            stdout=log_out,
            stderr=log_out,
            preexec_fn=os.setpgrp,
        )

    url = f"http://localhost:{DEFAULT_PORT}/?token={token}"
    print(f"Waiting for PlayPort web server on port {DEFAULT_PORT}...")
    ready = False
    for _ in range(60):
        time.sleep(1)
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "HealthCheck"})
            with urllib.request.urlopen(req, timeout=1.0) as resp:
                if resp.status in (200, 302):
                    ready = True
                    break
        except Exception:
            if is_port_listening(DEFAULT_PORT):
                ready = True
                break

    if ready:
        print("PlayPort server is READY!")
        print(f"Web URL: {url}")
        print(f"AirPlay RTSP listening on: {wifi_ip}:{AIRPLAY_PORT}")
        if auto_open:
            print("Opening CarPlay display in your browser...")
            subprocess.run(["open", url])
        print("\nNext step: On iPhone, open Settings > General > CarPlay > select 'PlayPort'.")
    else:
        print(f"Failed to verify server readiness within 30s. Check logs at: {LOG_FILE}", file=sys.stderr)
        sys.exit(1)

def show_status():
    listening_http = is_port_listening(DEFAULT_PORT)
    listening_airplay = is_port_listening(AIRPLAY_PORT)
    client = check_airplay_client()

    print("=== CarPlay Bridge Status ===")
    print(f"Web UI (:8080)       : {'LISTENING' if listening_http else 'STOPPED'}")
    print(f"AirPlay RTSP (:7000)  : {'LISTENING' if listening_airplay else 'STOPPED'}")
    if client:
        print(f"iPhone Stream         : CONNECTED (Peer: {client})")
    else:
        print(f"iPhone Stream         : WAITING (No active CarPlay stream)")
    print(f"Log File              : {LOG_FILE}")
    print("=============================")

def main():
    parser = argparse.ArgumentParser(description="CarPlay Bridge Controller")
    subparsers = parser.add_subparsers(dest="command", required=True)

    start_p = subparsers.add_parser("start", help="Start PlayPort and open browser")
    start_p.add_argument("--token", default=DEFAULT_TOKEN, help="Session access token")
    start_p.add_argument("--no-open", action="store_true", help="Do not automatically open browser")

    subparsers.add_parser("stop", help="Stop PlayPort daemon")
    subparsers.add_parser("status", help="Check bridge and streaming status")

    args = parser.parse_args()

    if args.command == "start":
        start_server(token=args.token, auto_open=not args.no_open)
    elif args.command == "stop":
        stop_server()
    elif args.command == "status":
        show_status()

if __name__ == "__main__":
    main()
