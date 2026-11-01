#!/usr/bin/env python3
"""Power sampler for the heat/power probe (tests/_power_probe.gd), macOS on Apple silicon, no sudo.

Runs a command (usually a windowed Godot probe), samples once a second:
  - GPU energy from IOReport ("Energy Model" group, "GPU Energy" channel) -> watts
  - the child's CPU time (ps) -> CPU cores busy (1.0 = one core flat out)
and splits the samples into the phases the probe prints as
  PHASE <name> <unix_start> <unix_end> <extra...>
Prints a table per phase at the end. CPU energy channels read 0 without root, so CPU is reported in cores.

  python3 tools/power_sampler.py --idle 10 -- godot --path godot --audio-driver Dummy -s tests/_power_probe.gd
"""
import argparse
import re
import ctypes
import subprocess
import sys
import threading
import time
from ctypes import c_char_p, c_int64, c_long, c_uint32, c_uint64, c_void_p

CF = ctypes.CDLL("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
IOR = ctypes.CDLL("/usr/lib/libIOReport.dylib")
UTF8 = 0x08000100

CF.CFStringCreateWithCString.restype = c_void_p
CF.CFStringCreateWithCString.argtypes = [c_void_p, c_char_p, c_uint32]
CF.CFStringGetCString.restype = ctypes.c_bool
CF.CFStringGetCString.argtypes = [c_void_p, c_char_p, c_long, c_uint32]
CF.CFDictionaryGetCount.restype = c_long
CF.CFDictionaryGetCount.argtypes = [c_void_p]
CF.CFDictionaryCreateMutableCopy.restype = c_void_p
CF.CFDictionaryCreateMutableCopy.argtypes = [c_void_p, c_long, c_void_p]
CF.CFDictionaryGetValue.restype = c_void_p
CF.CFDictionaryGetValue.argtypes = [c_void_p, c_void_p]
CF.CFArrayGetCount.restype = c_long
CF.CFArrayGetCount.argtypes = [c_void_p]
CF.CFArrayGetValueAtIndex.restype = c_void_p
CF.CFArrayGetValueAtIndex.argtypes = [c_void_p, c_long]
CF.CFRelease.argtypes = [c_void_p]

IOR.IOReportCopyChannelsInGroup.restype = c_void_p
IOR.IOReportCopyChannelsInGroup.argtypes = [c_void_p, c_void_p, c_uint64, c_uint64, c_uint64]
IOR.IOReportCreateSubscription.restype = c_void_p
IOR.IOReportCreateSubscription.argtypes = [c_void_p, c_void_p, ctypes.POINTER(c_void_p), c_uint64, c_void_p]
IOR.IOReportCreateSamples.restype = c_void_p
IOR.IOReportCreateSamples.argtypes = [c_void_p, c_void_p, c_void_p]
IOR.IOReportCreateSamplesDelta.restype = c_void_p
IOR.IOReportCreateSamplesDelta.argtypes = [c_void_p, c_void_p, c_void_p]
IOR.IOReportChannelGetChannelName.restype = c_void_p
IOR.IOReportChannelGetChannelName.argtypes = [c_void_p]
IOR.IOReportChannelGetUnitLabel.restype = c_void_p
IOR.IOReportChannelGetUnitLabel.argtypes = [c_void_p]
IOR.IOReportSimpleGetIntegerValue.restype = c_int64
IOR.IOReportSimpleGetIntegerValue.argtypes = [c_void_p, c_void_p]


def cfstr(s):
    return CF.CFStringCreateWithCString(None, s.encode(), UTF8)


def pystr(ref):
    if not ref:
        return ""
    buf = ctypes.create_string_buffer(256)
    CF.CFStringGetCString(ref, buf, 256, UTF8)
    return buf.value.decode()


UNIT_J = {"mJ": 1e-3, "uJ": 1e-6, "nJ": 1e-9}


class GpuEnergy:
    def __init__(self):
        chans = IOR.IOReportCopyChannelsInGroup(cfstr("Energy Model"), None, 0, 0, 0)
        self.chans = CF.CFDictionaryCreateMutableCopy(None, CF.CFDictionaryGetCount(chans), chans)
        sub_ch = c_void_p()
        self.sub = IOR.IOReportCreateSubscription(None, self.chans, ctypes.byref(sub_ch), 0, None)
        self.sub_ch = sub_ch
        self.prev = IOR.IOReportCreateSamples(self.sub, self.sub_ch, None)

    def joules(self):
        """GPU joules since the last call."""
        cur = IOR.IOReportCreateSamples(self.sub, self.sub_ch, None)
        delta = IOR.IOReportCreateSamplesDelta(self.prev, cur, None)
        CF.CFRelease(self.prev)
        self.prev = cur
        arr = CF.CFDictionaryGetValue(delta, cfstr("IOReportChannels"))
        total = 0.0
        for i in range(CF.CFArrayGetCount(arr)):
            ch = CF.CFArrayGetValueAtIndex(arr, i)
            if pystr(IOR.IOReportChannelGetChannelName(ch)) == "GPU Energy":
                unit = pystr(IOR.IOReportChannelGetUnitLabel(ch)).strip()
                total += IOR.IOReportSimpleGetIntegerValue(ch, None) * UNIT_J.get(unit, 1e-9)
        CF.CFRelease(delta)
        return total


def cpu_seconds(pid):
    try:
        out = subprocess.run(["ps", "-o", "time=", "-p", str(pid)], capture_output=True, text=True).stdout.strip()
    except Exception:
        return None
    if not out:
        return None
    parts = out.split(":")
    secs = 0.0
    for p in parts:
        secs = secs * 60 + float(p)
    return secs


def gpu_times():
    """Accumulated GPU busy time (s) per pid, from the AGX user clients in the IORegistry (what Activity Monitor's
    GPU Time column reads). Lets the game's share of the system-wide GPU watts be separated from other apps."""
    out = subprocess.run(["ioreg", "-r", "-d", "1", "-w", "0", "-c", "AGXDeviceUserClient"],
                         capture_output=True, text=True).stdout
    times = {}
    for block in out.split("+-o ")[1:]:  # one registry entry each; its keys are sorted, AppUsage before the creator
        m = re.search(r'"IOUserClientCreator" = "pid (\d+)', block)
        if not m:
            continue
        ns = sum(int(x) for x in re.findall(r'"accumulatedGPUTime"=(\d+)', block))
        pid = int(m.group(1))
        times[pid] = times.get(pid, 0.0) + ns / 1e9
    return times


def thermal():
    out = subprocess.run(["pmset", "-g", "therm"], capture_output=True, text=True).stdout
    return " ".join(l.strip() for l in out.splitlines() if "=" in l) or "no thermal warning"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--idle", type=float, default=10.0, help="seconds of idle GPU baseline before the run")
    ap.add_argument("--log", default="/tmp/power_samples.tsv")
    ap.add_argument("cmd", nargs=argparse.REMAINDER)
    a = ap.parse_args()
    cmd = a.cmd[1:] if a.cmd and a.cmd[0] == "--" else a.cmd
    gpu = GpuEnergy()
    gpu.joules()
    idle = []
    t_end = time.time() + a.idle
    while time.time() < t_end:
        time.sleep(1.0)
        idle.append(gpu.joules())
    idle_w = sum(idle) / max(len(idle), 1)
    print(f"IDLE GPU {idle_w:.2f} W  thermal: {thermal()}", flush=True)

    proc = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    phases = []
    lines = []

    def reader():
        for line in proc.stdout:
            lines.append(line)
            sys.stdout.write(line)
            sys.stdout.flush()
            if line.startswith("PHASE "):
                p = line.split()
                phases.append((p[1], float(p[2]), float(p[3]), " ".join(p[4:])))

    th = threading.Thread(target=reader, daemon=True)
    th.start()
    samples = []  # (t_mid, gpu_w, cpu_cores, own_gpu_busy, all_gpu_busy)
    last_cpu = cpu_seconds(proc.pid)
    last_gt = gpu_times()
    last_t = time.time()
    gpu.joules()
    with open(a.log, "w") as log:
        log.write("t\tgpu_w\tcpu_cores\town_busy\tall_busy\n")
        while proc.poll() is None:
            time.sleep(1.0)
            now = time.time()
            j = gpu.joules()
            c = cpu_seconds(proc.pid)
            dt = now - last_t
            cores = (c - last_cpu) / dt if (c is not None and last_cpu is not None) else float("nan")
            gt = gpu_times()
            busy = {k: v - last_gt.get(k, 0.0) for k, v in gt.items() if v - last_gt.get(k, 0.0) > 0}
            own = busy.get(proc.pid, 0.0) / dt
            allb = sum(busy.values()) / dt
            last_gt = gt
            samples.append(((now + last_t) / 2, j / dt, cores, own, allb))
            log.write(f"{now:.2f}\t{j / dt:.3f}\t{cores:.3f}\t{own:.3f}\t{allb:.3f}\n")
            log.flush()  # an aborted run keeps its samples
            last_t, last_cpu = now, c
    th.join(timeout=2)
    print(f"\nthermal after run: {thermal()}")
    print(f"{'phase':<28}{'GPU W':>8}{'game W':>8}{'busy%':>7}{'others%':>8}{'CPU cores':>11}  probe")
    for name, t0, t1, extra in phases:
        sel = [s for s in samples if t0 <= s[0] <= t1]
        if not sel:
            print(f"{name:<28}  (no samples)")
            continue
        g = sum(s[1] for s in sel) / len(sel)
        c = sum(s[2] for s in sel) / len(sel)
        own = sum(s[3] for s in sel) / len(sel)
        allb = sum(s[4] for s in sel) / len(sel)
        game_w = (g - idle_w) * (own / allb) if allb > 0 else float("nan")
        print(f"{name:<28}{g:>8.2f}{game_w:>8.2f}{own * 100:>7.0f}{(allb - own) * 100:>8.0f}{c:>11.2f}  {extra}")


if __name__ == "__main__":
    main()
