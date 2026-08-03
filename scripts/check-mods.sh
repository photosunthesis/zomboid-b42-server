#!/usr/bin/env bash
#
# check-mods.sh — catch the two ways a Workshop mod update breaks your players,
#                 BEFORE they hit it.
#
# WHY THIS EXISTS
#   2026-08-03: WS 3629835761 ("Ladders?! B42.20") was restructured by its author
#   into per-build folders, which RENAMED its mod id — Ladders42131 (42.16 folder,
#   versionMax=42.19) became Ladders4220 (42.20 + common folders, versionMin=42.20).
#   Our Mods= still asked for the old id, so on a 42.20 server it resolved to
#   nothing:
#       WARN : Mod  at ZomboidFileSystem.loadModAndRequired> required mod
#              "Ladders42131" not found
#   The server booted anyway and happily advertised a mod id no 42.20 client can
#   produce either, so every client bounced on a mod mismatch. Nothing in the boot
#   sequence treats that as fatal, and the warning is one line in a 1.1 MB log.
#
#   The mods STAY on the Workshop on purpose: a Steam subscription is the only way
#   clients get mods automatically. Freezing a copy into Zomboid/mods/ would pin the
#   version, but then every player installs it by hand, forever — the opposite of
#   easy. So instead of pinning (Steam has no API to request an older revision of a
#   Workshop item anyway — WorkshopItems can only ever mean "latest"), this script
#   makes the update itself safe to ride: it tells you what changed and whether the
#   ids still resolve.
#
# WHAT IT CHECKS
#   1. DRIFT   — asks Steam for each WORKSHOP_IDS item's current time_updated and
#                compares it to what SteamCMD recorded locally. Anything newer
#                upstream WILL re-download on the next restart, and players whose
#                own Steam hasn't refreshed yet must relaunch PZ once afterwards.
#                Run this BEFORE a restart to know who needs to do what.
#   2. MOD IDS — walks every mod.info actually on disk, works out which ids are
#                loadable on this server's build (respecting versionMin/versionMax
#                and the per-build folder layout), and flags any MOD_IDS entry that
#                won't resolve — naming the replacement id when the same mod folder
#                now ships one. This is the check that would have caught the Ladders
#                rename the moment it landed.
#
# USAGE
#   ./scripts/check-mods.sh            # both checks
#   ./scripts/check-mods.sh drift      # only "what will re-download on next restart"
#   ./scripts/check-mods.sh ids        # only "does every MOD_IDS entry still resolve"
#
#   Exit code 0 = clean, 1 = something needs your attention. Safe to run while the
#   server is up; it only reads files and queries Steam's public API (no key, no
#   login). Run it after any restart whose log shows a fresh download.
#
set -euo pipefail

# Run from the REPO ROOT (this script's parent): every path below — .env,
# docker-compose.yaml, server-data/ — is relative to it.
cd "$(dirname "$0")/.."

MODE="${1:-all}"
case "$MODE" in
  all|drift|ids) ;;
  *) echo "usage: $0 [all|drift|ids]" >&2; exit 2 ;;
esac

exec python3 - "$MODE" <<'PYEOF'
import json, os, re, sys, urllib.request

MODE = sys.argv[1]
WORKSHOP = "server-data/workshop/content/108600"
ACF = "server-data/workshop/appworkshop_108600.acf"
ENV = ".env"
COMPOSE = "docker-compose.yaml"

problems = []


def env_list(key):
    """Read a semicolon-joined KEY=... line out of .env (last uncommented wins)."""
    out = []
    with open(ENV, encoding="utf-8", errors="replace") as fh:
        for line in fh:
            if line.startswith(key + "="):
                out = [x for x in line.split("=", 1)[1].strip().split(";") if x]
    return out


def server_build():
    """(major, minor, patch) of the server, from the pinned image tag in compose."""
    text = open(COMPOSE, encoding="utf-8", errors="replace").read()
    m = re.search(r"project-zomboid-dedicated-server:(\d+)\.(\d+)\.(\d+)", text)
    if not m:
        sys.exit("!! could not read the pz image tag from " + COMPOSE)
    return tuple(int(x) for x in m.groups())


def ver(s):
    """'42.19' / '42' / '42.20.1' -> a comparable 3-tuple. None if not a version."""
    if not s:
        return None
    m = re.match(r"^(\d+)(?:\.(\d+))?(?:\.(\d+))?$", s.strip())
    return tuple(int(x) if x else 0 for x in m.groups()) if m else None


# ── the mods actually on disk ────────────────────────────────────────────────
def scan_disk(build):
    """Every mod.info under the workshop cache, with whether it loads on `build`.

    B42 mods ship per-build subfolders (common/, 42/, 42.16/, 42.20/, ...). A
    variant is live only if its own versionMin/versionMax bracket the build AND its
    folder isn't for a build newer than ours.
    """
    found = []
    if not os.path.isdir(WORKSHOP):
        return found
    for wsid in sorted(os.listdir(WORKSHOP)):
        base = os.path.join(WORKSHOP, wsid, "mods")
        for dirpath, _dirnames, filenames in os.walk(base):
            if "mod.info" not in filenames:
                continue
            info = {}
            path = os.path.join(dirpath, "mod.info")
            with open(path, encoding="utf-8", errors="replace") as fh:
                for line in fh:
                    if "=" in line:
                        k, _, v = line.partition("=")
                        info[k.strip()] = v.strip()
            if not info.get("id"):
                continue
            rel = os.path.relpath(dirpath, base).split(os.sep)
            folder, verdir = rel[0], (rel[1] if len(rel) > 1 else "")
            vmin, vmax, vdir = ver(info.get("versionMin")), ver(info.get("versionMax")), ver(verdir)
            live = not ((vmin and build < vmin) or (vmax and build > vmax) or (vdir and vdir > build))
            found.append(
                dict(ws=wsid, folder=folder, verdir=verdir or "-", id=info["id"],
                     vmin=info.get("versionMin"), vmax=info.get("versionMax"), live=live)
            )
    return found


def check_ids():
    build = server_build()
    disk = scan_disk(build)
    listed = env_list("MOD_IDS")
    print("==> MOD IDS  (server build %s, %d ids listed, %d mod.info on disk)"
          % (".".join(map(str, build)), len(listed), len(disk)))
    if not disk:
        print("    -- workshop cache is empty; nothing downloaded yet. Skipping.")
        return

    live = {}
    for e in disk:
        live.setdefault(e["id"], []).append(e)

    broken = 0
    for mid in listed:
        entries = live.get(mid)
        if entries and any(e["live"] for e in entries):
            continue
        broken += 1
        if not entries:
            print('    !! %r is in MOD_IDS but NO mod.info on disk declares it.' % mid)
            print('       Either its Workshop item is missing from WORKSHOP_IDS, or the')
            print('       author renamed the id.')
            continue
        e = entries[0]
        print('    !! %r exists but is version-gated OUT on %s'
              % (mid, ".".join(map(str, build))))
        print('       ws %s, folder %s/%s, versionMin=%s versionMax=%s'
              % (e["ws"], e["folder"], e["verdir"], e["vmin"], e["vmax"]))
        # The usual cause: the author added a new per-build folder under the SAME mod
        # folder carrying a NEW id. Name it, because that's the fix.
        swaps = sorted({o["id"] for o in disk
                        if o["ws"] == e["ws"] and o["folder"] == e["folder"]
                        and o["live"] and o["id"] != mid})
        if swaps:
            print('       -> this item now provides %s on this build.'
                  % ", ".join(repr(s) for s in swaps))
            print('          Swap it in MOD_IDS (.env) and restart:')
            print('            %s  ->  %s' % (mid, swaps[0]))
        problems.append("mod id %r does not resolve" % mid)

    if not broken:
        print("    OK — every MOD_IDS entry resolves to a mod that loads on this build.")

    orphans = sorted(set(os.listdir(WORKSHOP)) - set(env_list("WORKSHOP_IDS"))) \
        if os.path.isdir(WORKSHOP) else []
    if orphans:
        print("    note: downloaded but no longer in WORKSHOP_IDS (harmless, just stale")
        print("          disk): %s" % ", ".join(orphans))


# ── what will re-download on the next restart ───────────────────────────────
def local_timeupdated():
    """wsid -> timeupdated, as SteamCMD recorded it in the .acf."""
    out = {}
    if not os.path.exists(ACF):
        return out
    text = open(ACF, encoding="utf-8", errors="replace").read()
    # WorkshopItemsInstalled is the authoritative "what's on disk" block; it comes
    # first, and a later block repeats each id with extra latest_* keys.
    block = text.split('"WorkshopItemsInstalled"', 1)[-1]
    for wsid, body in re.findall(r'"(\d{6,})"\s*\{([^}]*)\}', block):
        m = re.search(r'"timeupdated"\s*"(\d+)"', body)
        if m and wsid not in out:
            out[wsid] = int(m.group(1))
    return out


def steam_timeupdated(ids):
    """wsid -> (time_updated, title) from Steam's public, keyless API."""
    if not ids:
        return {}
    fields = [("itemcount", str(len(ids)))]
    fields += [("publishedfileids[%d]" % i, w) for i, w in enumerate(ids)]
    data = urllib.parse.urlencode(fields).encode()
    req = urllib.request.Request(
        "https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/",
        data=data, headers={"User-Agent": "tnc-zomboid-check-mods"})
    with urllib.request.urlopen(req, timeout=30) as resp:
        payload = json.load(resp)
    out = {}
    for d in payload.get("response", {}).get("publishedfiledetails", []):
        if d.get("result") == 1 and "time_updated" in d:
            out[d["publishedfileid"]] = (int(d["time_updated"]), d.get("title", "?"))
    return out


def check_drift():
    wanted = env_list("WORKSHOP_IDS")
    print("==> DRIFT  (%d workshop items; asking Steam what's changed)" % len(wanted))
    local = local_timeupdated()
    try:
        remote = steam_timeupdated(wanted)
    except Exception as exc:                                    # offline, rate limit
        print("    -- could not reach Steam (%s). Skipping drift check." % exc)
        return

    stale = []
    for wsid in wanted:
        have, up = local.get(wsid), remote.get(wsid)
        if not up:
            print("    ?? %s — Steam returned no details (deleted, private, or banned?)"
                  % wsid)
            problems.append("workshop item %s not resolvable on Steam" % wsid)
            continue
        if have is None:
            print("    +  %s will download for the FIRST time — %s" % (wsid, up[1]))
            stale.append(wsid)
        elif up[0] > have:
            print("    !! %s is OUT OF DATE and re-downloads on next restart — %s"
                  % (wsid, up[1]))
            stale.append(wsid)

    if not stale:
        print("    OK — every item matches Steam. A restart pulls nothing new, so no")
        print("         client can drift out of sync with the server.")
        return

    problems.append("%d workshop item(s) will change on next restart" % len(stale))
    print("")
    print("    An update can rename a mod id, which is what breaks clients — so after")
    print("    the restart that pulls these, run:")
    print("        ./scripts/check-mods.sh ids")
    print("    Then tell players to fully restart Project Zomboid once, so Steam")
    print("    refreshes their copy to the version the server just pulled.")


if MODE in ("all", "drift"):
    check_drift()
if MODE == "all":
    print("")
if MODE in ("all", "ids"):
    check_ids()

print("")
if problems:
    print("==> %d thing(s) need attention:" % len(problems))
    for p in problems:
        print("      - %s" % p)
    sys.exit(1)
print("==> Clean. Mods match Steam and every id resolves.")
PYEOF
