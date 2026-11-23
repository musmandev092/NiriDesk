from . import data, kickstart, validate
from .probe import GIB, ROLE_TEXT, human

FS_NOTE = {
    "btrfs": "btrfs: compression, subvolumes, snapshots possible.",
    "ext4": "ext4: the classic Linux filesystem.",
    "xfs": "xfs: fast for large files; cannot shrink.",
}
SYSTEM = ["NIRIDESK  (~818 packages, ~833 with toolbox; +4 with NVIDIA)",
          "niri + DMS, Brave, foot, Thunar, FeatherPad, galculator, imv, mpv, Disks,",
          "LocalSend, CUPS, Urdu/Arabic/Indic/Thai/CJK fonts. One lean system for everyone."]


def keyboard(c):
    loc = c.locale
    s = loc.layout + (f" ({loc.variant})" if loc.variant else "")
    if loc.layout2:
        s += f" + {loc.layout2}" + (f" ({loc.variant2})" if loc.variant2 else "")
    return s


def locale_value(c):
    return f"{data.locale_name(c.locale.language)}, {keyboard(c)}"


def repos_value(c):
    r = c.repos
    f = "one mirror" if r.fedora else "mirror list"
    return f + (", testing" if r.testing else "")


def software_value(c, env):
    extra = f", +{len(c.packages)} package(s)" if c.packages else ""
    return profile_value(c, env) + extra


def time_value(c):
    return c.time.zone + ("" if c.time.utc else ", local clock") + ("" if c.time.ntp else ", no sync")


def zram_size(ram):
    return min(ram, 8 * GIB)


swapfile_gib = validate.swapfile_gib


def sleep_value(c, ram):
    z = f"zram {zram_size(ram) // GIB} GiB" if ram >= GIB else "zram"
    return z + (", hibernate on" if c.hibernate else ", hibernate off")


def disk_obj(c, probe):
    return validate.selected_disk(c, probe)


def disk_value(c, probe):
    d = disk_obj(c, probe)
    name = d["name"] if d else "no disk"
    mode = "erase" if c.disk.mode == "erase" else "alongside"
    enc = "LUKS2" if c.disk.encrypt else "no encryption"
    return f"{name}, {mode}, {c.disk.fs}, {enc}"


def disk_plan(c, probe, ram=0):
    d = disk_obj(c, probe)
    if not d:
        return [("No disk chosen.", "err")]
    out = [(f"PLANNED LAYOUT  {d['name']}", "bold"), f"{d['model'] or 'disk'}  {human(d['size'])}", ""]
    enc = "LUKS2 (argon2id)" if c.disk.encrypt else "not encrypted"
    if c.disk.mode == "erase":
        out += ["EFI     600 MiB  new", "/boot   2 GiB    ext4"]
        if c.disk.fs == "btrfs":
            out += [f"system  rest     {enc}", "        btrfs zstd:1", "        root  /", "        home  /home"]
        else:
            scheme = "LVM" if c.disk.scheme == "lvm" else "plain"
            out += [f"system  rest     {enc}", f"        {scheme} {c.disk.fs}", "        /"]
            if c.disk.home:
                out.append("        /home (separate)")
        out.append("")
        if d["windows"]:
            out.append((f"! ERASES Windows and everything else on {d['name']}", "err"))
        elif d["parts"]:
            out.append((f"! ERASES: {d['contents']} on this disk", "err"))
        else:
            out.append("The disk is empty.")
    else:
        size = f"{c.disk.size_gib} GiB" if c.disk.size_gib else f"all free ({d['free'] // GIB} GiB)"
        for p in d["parts"]:
            tag = "EFI, reused" if p["name"] == d["esp"] else "kept"
            what = ROLE_TEXT.get(p.get("role"), p["fstype"] or "-")
            out.append(f"{p['name']:<10} {human(p['size']):>8}  {what:<18} {tag}")
        out += [f"new /boot  2 GiB ext4", f"new Linux  {size}  {enc}", f"           {c.disk.fs}" +
                (" root + home" if c.disk.fs == "btrfs" else " /"), "", "Other systems are never changed."]
        if d["bitlocker"]:
            out.append(("! Keep the BitLocker recovery key ready", "warn"))
        if d["hibernated"]:
            out.append(("! Turn off Fast Startup in Windows first", "warn"))
    out.append("")
    out.append(sleep_value(c, ram))
    return out


def confirm_word(c, probe):
    d = disk_obj(c, probe)
    if c.disk.mode == "alongside":
        return "INSTALL"
    return "WIPE-WINDOWS" if d and d["windows"] else "WIPE"


def auth_value(c, secrets):
    s = c.auth.admin.name or "not set"
    if c.auth.users:
        s += f" +{len(c.auth.users)}"
    return s


def boot_value(c):
    return f"GRUB, {c.boot.timeout} s" + ("" if c.boot.os_prober else ", no other systems")


def ssh_value(c):
    if not c.ssh.enabled:
        return "off"
    return f"on, {len(c.ssh.keys)} key(s)"


def profile_value(c, env):
    p = "NiriDesk"
    if kickstart.wants_nvidia(c, env):
        p += " + NVIDIA"
    if c.profile.toolbox:
        p += " + toolbox"
    return p


def services_value(c):
    return f"BT {'on' if c.services.bluetooth else 'off'}, print {'on' if c.services.printing else 'off'}"


def network_value(c, probe, online):
    link = probe.link()
    if not online:
        return "offline"
    if link:
        return f"{'Wi-Fi ' + link['name'] if link['type'] == 'wifi' else 'wired'}"
    return "online"


def packages_value(c):
    return "none" if not c.packages else f"{len(c.packages)}: " + ", ".join(c.packages[:3]) + ("..." if len(c.packages) > 3 else "")


def ntp_value(c):
    if not c.time.ntp:
        return "off"
    return "on" + (f", {len(c.time.servers)} server(s)" if c.time.servers else "")


def review(c, secrets, probe, env):
    d = disk_obj(c, probe)
    users = f"{c.auth.admin.fullname} ({c.auth.admin.name}) admin"
    for u in c.auth.users:
        users += f"; {u.name}{' admin' if u.admin else ''}"
    users += "; root " + ("locked" if c.auth.root_locked else "password")
    dline = "no disk"
    if d:
        what = "-> ERASED" if c.disk.mode == "erase" else "-> free space only"
        dline = f"{d['name']} {d['model']} {human(d['size'])}  {what}"
    enc = "LUKS2 " if c.disk.encrypt else "UNENCRYPTED "
    layout = f"{enc}{c.disk.fs}" + (" root+home" if c.disk.fs == "btrfs" else "")
    extra = f", {len(c.packages)} extra package(s)" if c.packages else ""
    return [
        ("Computer", f"{c.hostname}  {c.time.zone} ({'UTC' if c.time.utc else 'local'} clock)  NTP {'on' if c.time.ntp else 'off'}"),
        ("Locale", f"{data.locale_name(c.locale.language)}, keyboard {keyboard(c)}, {c.locale.font} text size"),
        ("Accounts", users),
        ("Disk", dline),
        ("", layout),
        ("Memory", sleep_value(c, probe.ram())),
        ("Software", f"{profile_value(c, env)}{extra}"),
        ("Services", services_value(c) + "; firewall, power profiles on; no SSH server"),
        ("Network", ("copy connections" if c.network.installed == "copy" else "save nothing") +
         (f", static {c.network.address}" if c.network.wired == "static" else ", DHCP")),
        ("Repos", repos_value(c) + "; DMS " + ("cache" if c.repos.copr_cache else "COPR") + ", RPM Fusion, Brave, personal repo"),
        ("Boot", boot_value(c) + (f", args: {c.boot.args}" if c.boot.args else "")),
    ]
