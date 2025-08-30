#!/usr/bin/env python3

"""
MIT License

Copyright (c) 2021 ZenithalHourlyRate

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
"""

import json
import sys
from xml.dom import minidom
from dateutil.parser import parse

cname = {}


def name(name):
    if name in cname:
        return cname[name]
    else:
        return name


def status(param):
    if not param["Idle"]:
        return "Y"
    else:
        if param["Result"]:
            return "S"
        else:
            return "F"


def help(name, items):
    for item in items:
        if item.getElementsByTagName("title")[0].childNodes[0].data == name:
            return item.getElementsByTagName("link")[0].childNodes[0].data
    return ""


def mirror_item(worker, param, help_items, sources):
    mirror = {
        "cname": name(worker),
        "desc": "",
        "url": "/" + worker,
        "status": f"{status(param)}{int(parse(param['LastFinished']).timestamp())}",
        "help": help(worker, help_items),
        "upstream": sources.get(worker, ""),
    }
    return mirror


def z_adhocs(lug, summary, mirrors, help_items, sources):
    for item in lug["repos"]:
        if "z_link_to" in item:
            for worker, param in summary["WorkerStatus"].items():
                if worker == item["z_link_to"]:
                    # use item name instead of worker, still use worker param
                    mirror = mirror_item(item["name"], param, help_items, sources)
                    mirrors.append(mirror)
        if "z_url" in item:
            for mirror in mirrors:
                if mirror["cname"] == name(item["name"]):
                    mirror["url"] = item["z_url"]


def main():
    global options
    global cname
    if len(sys.argv) < 5:
        print("help: mirrorz.py site.json lug.json summary.json help.xml cname.json")
        sys.exit(0)
    site = json.loads(open(sys.argv[1]).read())
    lug = json.loads(open(sys.argv[2]).read())
    summary = json.loads(open(sys.argv[3]).read())
    help_items = minidom.parse(sys.argv[4]).documentElement.getElementsByTagName("item")
    cname = json.loads(open(sys.argv[5]).read())
    mirrorz = {}
    mirrorz["site"] = site
    mirrorz["info"] = []
    mirrors = []
    sources = {item["name"]: item.get("source", "") for item in lug["repos"]}
    for worker, param in summary["WorkerStatus"].items():
        if worker.startswith(".") or worker == "sjtug-internal" or worker == "test":
            continue
        mirror = mirror_item(worker, param, help_items, sources)
        mirrors.append(mirror)

    z_adhocs(lug, summary, mirrors, help_items, sources)

    mirrorz["mirrors"] = mirrors
    mirrorz["extension"] = "D"
    mirrorz["endpoints"] = [
        {
            "label": "sjtug",
            "public": True,
            "resolve": site["url"].strip("https://"),
            "filter": ["V4", "V6", "SSL", "NOSSL"],
            "range": [
                "COUNTRY:CN",
                "REGION:SH",
                "ISP:CERNET",
                "202.120.0.0/18",
                "59.78.0.0/18",
                "111.186.0.0/18",
                "211.80.32.0/19",
                "211.80.80.0/20",
                "2001:250:6000::/48",
                "2001:251:7801::/48",
                "2001:256:100:2000::/56",
                "2001:da8:8000::/48",
                "2403:d400::/32",
                "2408:8026:380::/52",
            ],
        }
    ]

    print(json.dumps(mirrorz, indent=2))


if __name__ == "__main__":
    main()
