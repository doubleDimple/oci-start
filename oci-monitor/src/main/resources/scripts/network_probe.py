#!/usr/bin/env python3
"""Bounded, outbound network measurements for the VPS monitor (protocol 1).

The resource-reporting shell runs in a separate systemd service. Each network
job uses an isolated process so even a blocked system DNS lookup is bounded.
Only the coordinator reads the credential; targets never receive that header.
"""

import http.client
import ipaddress
import json
import math
import multiprocessing
import os
import re
import shutil
import signal
import socket
import ssl
import stat
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request


VERSION = "1"
MAX_WORKERS = 4
MAX_BODY = 262144
MAX_PENDING = 16
MAX_REPORT_AGE = 120
STOP = False
ACTIVE_PING = None


class ProbeError(Exception):
    def __init__(self, code, http_status=None):
        super().__init__(code)
        self.code = code
        self.http_status = http_status


class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        return None


def number(value, minimum, maximum):
    return type(value) is int and minimum <= value <= maximum


def clean_host(value):
    if not isinstance(value, str) or not value or len(value) > 253:
        raise ProbeError("internal_error")
    try:
        return str(ipaddress.ip_address(value))
    except ValueError:
        pass
    if any(ord(ch) < 33 or ord(ch) == 127 for ch in value):
        raise ProbeError("internal_error")
    try:
        host = value.rstrip(".").encode("idna").decode("ascii")
    except UnicodeError:
        raise ProbeError("internal_error")
    if len(host) > 253 or not all(re.fullmatch(r"[A-Za-z0-9](?:[A-Za-z0-9-]{0,61}[A-Za-z0-9])?", part)
                                   for part in host.split(".")):
        raise ProbeError("internal_error")
    return host


def target_parts(kind, target):
    if not isinstance(target, str) or len(target) > 2048 or target != target.strip():
        raise ProbeError("internal_error")
    if any(ord(ch) < 33 or ord(ch) == 127 for ch in target):
        raise ProbeError("internal_error")
    if kind == "icmp":
        return clean_host(target.strip("[]")), None, None
    if kind == "tcp":
        try:
            return str(ipaddress.ip_address(target)), 80, None
        except ValueError:
            pass
        parsed = urllib.parse.urlsplit("//" + target)
        if parsed.path or parsed.query or parsed.fragment or parsed.username is not None or parsed.password is not None:
            raise ProbeError("internal_error")
        try:
            port = parsed.port if parsed.port is not None else 80
            if not 1 <= port <= 65535:
                raise ProbeError("internal_error")
            return clean_host(parsed.hostname), port, None
        except ValueError:
            raise ProbeError("internal_error")
    if kind == "http":
        try:
            parsed = urllib.parse.urlsplit(target)
            if parsed.scheme not in ("http", "https") or parsed.username is not None or parsed.password is not None or parsed.fragment:
                raise ProbeError("internal_error")
            host = clean_host(parsed.hostname)
            port = parsed.port if parsed.port is not None else (443 if parsed.scheme == "https" else 80)
            if not 1 <= port <= 65535:
                raise ProbeError("internal_error")
            return host, port, parsed
        except ValueError:
            raise ProbeError("internal_error")
    raise ProbeError("unsupported")


def validate_job(value):
    if not isinstance(value, dict):
        return None
    execution_id = value.get("executionId")
    task_id = value.get("taskId")
    if not isinstance(execution_id, str) or not re.fullmatch(r"[A-Za-z0-9_-]{1,128}", execution_id):
        return None
    if not isinstance(task_id, str) or not re.fullmatch(r"[1-9][0-9]{0,18}", task_id):
        return None
    if not isinstance(value.get("revision"), str) or not re.fullmatch(r"(?:0|[1-9][0-9]{0,18})", value["revision"]):
        return None
    if not number(value.get("sampleCount"), 1, 10) or not number(value.get("timeoutMs"), 500, 10000):
        return None
    if value.get("type") not in ("icmp", "tcp", "http"):
        return None
    try:
        target_parts(value["type"], value.get("target"))
    except (ProbeError, ValueError):
        return None
    return {key: value[key] for key in ("executionId", "taskId", "revision", "type", "target", "sampleCount", "timeoutMs")}


def resolve(host, port):
    try:
        addresses = socket.getaddrinfo(host, port, socket.AF_UNSPEC, socket.SOCK_STREAM)
    except socket.gaierror:
        raise ProbeError("dns_error")
    for family, socktype, protocol, _, address in addresses:
        if family in (socket.AF_INET, socket.AF_INET6):
            return family, socktype, protocol, address
    raise ProbeError("dns_error")


def tcp_sample(host, port, timeout):
    family, socktype, protocol, address = resolve(host, port)
    started = time.monotonic()
    with socket.socket(family, socktype, protocol) as connection:
        connection.settimeout(timeout)
        connection.connect(address)
    return (time.monotonic() - started) * 1000.0, None


def icmp_sample(host, timeout):
    global ACTIVE_PING
    command = shutil.which("ping")
    if not command:
        raise ProbeError("unsupported")
    family, _, _, address = resolve(host, None)
    args = [command, "-n", "-6" if family == socket.AF_INET6 else "-4", "-c", "1",
            "-W", str(max(1, math.ceil(timeout))), address[0]]
    environment = dict(os.environ)
    environment["LC_ALL"] = "C"
    try:
        ACTIVE_PING = subprocess.Popen(args, stdin=subprocess.DEVNULL, stdout=subprocess.PIPE,
                                       stderr=subprocess.STDOUT, env=environment, shell=False)
        try:
            output, _ = ACTIVE_PING.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            raise ProbeError("timeout")
        output = output[:65536].decode("ascii", "replace")
        packets = re.search(r"(\d+)\s+packets transmitted,\s*(\d+)\s+(?:packets\s+)?received", output)
        stats = re.search(r"(?:rtt|round-trip)[^=]*=\s*([\d.]+)/([\d.]+)/([\d.]+)(?:/[\d.]+)?\s*ms", output)
        if packets and int(packets.group(1)) == 1 and int(packets.group(2)) == 0:
            raise ProbeError("timeout")
        if ACTIVE_PING.returncode != 0:
            if "permitted" in output.lower() or "invalid option" in output.lower() or "not supported" in output.lower():
                raise ProbeError("unsupported")
            raise ProbeError("network_error")
        if not packets or int(packets.group(1)) != 1 or int(packets.group(2)) != 1 or not stats:
            raise ProbeError("internal_error")
        latency = float(stats.group(2))
        if not math.isfinite(latency) or latency < 0:
            raise ProbeError("internal_error")
        return latency, None
    finally:
        if ACTIVE_PING is not None:
            if ACTIVE_PING.poll() is None:
                ACTIVE_PING.kill()
            ACTIVE_PING.communicate()
            ACTIVE_PING = None


def http_sample(host, port, parsed, timeout):
    # Includes DNS, connection, TLS (HTTPS), and response headers; never reads the body.
    context = ssl.create_default_context()
    connection = (http.client.HTTPSConnection(host, port, timeout=timeout, context=context)
                  if parsed.scheme == "https" else http.client.HTTPConnection(host, port, timeout=timeout))
    path = urllib.parse.quote(parsed.path or "/", safe="/%:@!$&'()*+,;=-._~")
    if parsed.query:
        path += "?" + urllib.parse.quote(parsed.query, safe="%=&;:+/?@!$'()*,-._~")
    try:
        started = time.monotonic()
        connection.request("GET", path, headers={"User-Agent": "oci-network-probe/1", "Connection": "close"})
        response = connection.getresponse()
        latency = (time.monotonic() - started) * 1000.0
        if not 200 <= response.status < 400:
            raise ProbeError("http_error", response.status)
        return latency, response.status
    finally:
        connection.close()


def classify_error(error):
    if isinstance(error, ProbeError):
        return error.code, error.http_status
    if isinstance(error, socket.gaierror):
        return "dns_error", None
    if isinstance(error, (socket.timeout, TimeoutError)):
        return "timeout", None
    if isinstance(error, ConnectionRefusedError):
        return "connection_refused", None
    if isinstance(error, (ssl.SSLError, http.client.HTTPException)):
        return "http_error", None
    if isinstance(error, OSError):
        return "network_error", None
    return "internal_error", None


def blank_result(job):
    return {"executionId": job["executionId"], "taskId": job["taskId"], "revision": job["revision"],
            "attempts": 0, "successful": 0, "avgMs": None, "minMs": None, "maxMs": None,
            "status": "error", "errorCode": "internal_error", "httpStatus": None}


def child_stop(signum, frame):
    global ACTIVE_PING
    if ACTIVE_PING is not None and ACTIVE_PING.poll() is None:
        ACTIVE_PING.kill()
    raise SystemExit(0)


def execute_job(job, output):
    signal.signal(signal.SIGTERM, child_stop)
    signal.signal(signal.SIGINT, child_stop)
    result = blank_result(job)
    values = []
    errors = []
    try:
        host, port, parsed = target_parts(job["type"], job["target"])
        for _ in range(job["sampleCount"]):
            result["attempts"] += 1
            try:
                timeout = job["timeoutMs"] / 1000.0
                started = time.monotonic()
                if job["type"] == "icmp":
                    latency, http_status = icmp_sample(host, timeout)
                elif job["type"] == "tcp":
                    latency, http_status = tcp_sample(host, port, timeout)
                else:
                    latency, http_status = http_sample(host, port, parsed, timeout)
                if not math.isfinite(latency) or latency < 0:
                    raise ProbeError("internal_error")
                if latency > 60000 or time.monotonic() - started > timeout:
                    raise ProbeError("timeout")
                values.append(latency)
                if http_status is not None:
                    result["httpStatus"] = http_status
            except Exception as error:
                code, http_status = classify_error(error)
                if code == "unsupported":
                    result.update(status="unsupported", attempts=0, successful=0, errorCode="unsupported")
                    return
                errors.append(code)
                if http_status is not None:
                    result["httpStatus"] = http_status
        result["successful"] = len(values)
        if values:
            result.update(avgMs=round(sum(values) / len(values), 3), minMs=round(min(values), 3), maxMs=round(max(values), 3))
        result["status"] = "success" if len(values) == job["sampleCount"] else ("partial" if values else "failed")
        result["errorCode"] = errors[-1] if errors else None
    except Exception as error:
        result["errorCode"], result["httpStatus"] = classify_error(error)
    finally:
        try:
            output.send(result)
        except (OSError, BrokenPipeError):
            pass
        output.close()


def stop_handler(signum, frame):
    global STOP
    STOP = True


def load_config(path):
    info = os.lstat(path)
    if not stat.S_ISREG(info.st_mode) or info.st_uid != 0 or info.st_mode & 0o077:
        raise ValueError("configuration permissions must be 600")
    with open(path, "r", encoding="utf-8") as source:
        config = json.load(source)
    base = config.get("serverUrl", "").rstrip("/")
    parsed = urllib.parse.urlsplit(base)
    if parsed.scheme not in ("http", "https") or not parsed.hostname or parsed.username or parsed.password or parsed.query or parsed.fragment:
        raise ValueError("invalid server URL")
    if parsed.port is not None and not 1 <= parsed.port <= 65535:
        raise ValueError("invalid server port")
    token = config.get("credential")
    if not isinstance(token, str) or not re.fullmatch(r"[A-Za-z0-9_-]{32,256}", token):
        raise ValueError("invalid credential")
    return base, token


def post_json(base, credential, path, payload):
    data = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    request = urllib.request.Request(base + path, data=data, method="POST", headers={
        "Authorization": "Bearer " + credential, "Content-Type": "application/json",
        "User-Agent": "oci-network-probe/1", "Accept": "application/json"})
    # Never forward a credential through a redirect or implicit environment proxy.
    opener = urllib.request.build_opener(urllib.request.ProxyHandler({}), NoRedirect())
    with opener.open(request, timeout=10) as response:
        body = response.read(MAX_BODY + 1)
        if len(body) > MAX_BODY:
            raise ValueError("response too large")
        value = json.loads(body.decode("utf-8"))
        if not isinstance(value, dict):
            raise ValueError("invalid response")
        return value


def request_process(base, credential, path, payload, sender):
    signal.signal(signal.SIGTERM, child_stop)
    signal.signal(signal.SIGINT, child_stop)
    try:
        sender.send({"httpStatus": 200, "body": post_json(base, credential, path, payload)})
    except urllib.error.HTTPError as error:
        sender.send({"httpStatus": error.code})
    except Exception:
        sender.send({"httpStatus": 0})
    finally:
        sender.close()


def finish_process(process, receiver):
    if process.is_alive():
        process.terminate()
    process.join(timeout=0.5)
    if process.is_alive():
        try:
            os.kill(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        process.join(timeout=0.5)
    receiver.close()


def notify_ready():
    address = os.environ.get("NOTIFY_SOCKET")
    if not address:
        return
    if address.startswith("@"):
        address = "\0" + address[1:]
    with socket.socket(socket.AF_UNIX, socket.SOCK_DGRAM) as notification:
        notification.connect(address)
        notification.sendall(b"READY=1")


def main():
    check_only = len(sys.argv) == 3 and sys.argv[1] == "--check"
    if len(sys.argv) != 2 and not check_only:
        print("Usage: network_probe.py [--check] CONFIG", file=sys.stderr)
        return 2
    try:
        base, credential = load_config(sys.argv[-1])
    except Exception:
        print("Network probe configuration is invalid or unreadable.", file=sys.stderr)
        return 2
    if check_only:
        return 0
    signal.signal(signal.SIGTERM, stop_handler)
    signal.signal(signal.SIGINT, stop_handler)
    context = multiprocessing.get_context("spawn")
    running = {}
    request = None
    pending = []
    completed = {}
    next_poll = 0.0
    next_report = 0.0
    backoff = 5.0
    capabilities = ["tcp", "http"] + (["icmp"] if shutil.which("ping") else [])
    notify_ready()
    print("Network probe protocol 1 started.", flush=True)
    try:
        while not STOP:
            now = time.monotonic()
            for execution_id, active in list(running.items()):
                process, receiver, job, deadline = active
                result = None
                if receiver.poll():
                    try:
                        result = receiver.recv()
                    except (EOFError, OSError):
                        pass
                if result is None and (now >= deadline or not process.is_alive()):
                    result = blank_result(job)
                    result["errorCode"] = "timeout" if now >= deadline else "internal_error"
                if result is not None:
                    finish_process(process, receiver)
                    del running[execution_id]
                    pending.append((now, result))
                    completed[execution_id] = now
            completed = {key: stamp for key, stamp in completed.items() if now - stamp < MAX_REPORT_AGE}
            pending = [(stamp, report) for stamp, report in pending if now - stamp < MAX_REPORT_AGE]
            if request is not None:
                process, receiver, operation, report_id, deadline = request
                response = None
                if receiver.poll():
                    try:
                        response = receiver.recv()
                    except (EOFError, OSError):
                        pass
                if response is None and (now >= deadline or not process.is_alive()):
                    response = {"httpStatus": 0}
                if response is not None:
                    finish_process(process, receiver)
                    request = None
                    status = response.get("httpStatus", 0)
                    body = response.get("body", {})
                    accepted = status == 200 and isinstance(body, dict) and body.get("success") is True
                    data = body.get("data", {}) if isinstance(body, dict) else {}
                    if operation == "report":
                        if accepted or status in (400, 404, 409, 410):
                            pending = [item for item in pending if item[1]["executionId"] != report_id]
                        next_report = now + (0.25 if accepted else 10)
                    else:
                        jobs = data.get("jobs") if isinstance(data, dict) else None
                        if not accepted or not isinstance(jobs, list) or len(jobs) > MAX_WORKERS:
                            jobs = []
                            next_poll = now + backoff
                            backoff = min(60.0, backoff * 2)
                        else:
                            backoff = 5.0
                            next_poll = now + 10
                    if status in (401, 403):
                        # Revoked/rotated credentials need a new authenticated installation.
                        print("Network probe credential was rejected; service is stopping.", flush=True)
                        break
                    if operation == "poll":
                        active_task_ids = {active[2]["taskId"] for active in running.values()}
                        for raw in jobs:
                            job = validate_job(raw)
                            if job is None or job["executionId"] in running or job["executionId"] in completed or job["taskId"] in active_task_ids:
                                continue
                            if len(running) >= MAX_WORKERS or len(pending) + len(running) >= MAX_PENDING:
                                break
                            receiver, sender = context.Pipe(duplex=False)
                            process = context.Process(target=execute_job, args=(job, sender), daemon=True)
                            process.start()
                            sender.close()
                            deadline = time.monotonic() + job["sampleCount"] * job["timeoutMs"] / 1000.0 + 5
                            running[job["executionId"]] = (process, receiver, job, deadline)
                            active_task_ids.add(job["taskId"])
            if request is None:
                operation = None
                if pending and now >= next_report:
                    operation = "report"
                    payload = pending[0][1]
                    report_id = payload["executionId"]
                elif now >= next_poll:
                    operation = "poll"
                    report_id = None
                    payload = {"version": VERSION, "capabilities": capabilities,
                               "availableSlots": 0 if pending else MAX_WORKERS - len(running)}
                if operation:
                    receiver, sender = context.Pipe(duplex=False)
                    process = context.Process(target=request_process, args=(base, credential, "/api/network-quality/agent/" + operation, payload, sender), daemon=True)
                    process.start()
                    sender.close()
                    request = (process, receiver, operation, report_id, now + 12)
            time.sleep(0.25)
    finally:
        if request is not None:
            finish_process(request[0], request[1])
        for process, receiver, _, _ in running.values():
            if process.is_alive():
                process.terminate()
        for process, receiver, _, _ in running.values():
            finish_process(process, receiver)
    return 0


if __name__ == "__main__":
    sys.exit(main())
