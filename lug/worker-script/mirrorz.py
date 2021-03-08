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
import xml
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


def main():
    global options
    global cname
    if len(sys.argv) < 5:
        print("help: mirrorz.py site.json summary.json help.xml cname.json")
        sys.exit(0)
    site = json.loads(open(sys.argv[1]).read())
    summary = json.loads(open(sys.argv[2]).read())
    help_items = minidom.parse(
        sys.argv[3]).documentElement.getElementsByTagName("item")
    cname = json.loads(open(sys.argv[4]).read())
    mirrorz = {}
    mirrorz["site"] = site
    mirrorz["info"] = []
    mirrors = []
    for worker, param in summary["WorkerStatus"].items():
        if worker.startswith(".") or worker == 'sjtug-internal' or worker == 'test':
            continue
        mirror = {
            "cname": name(worker),
            "desc": "",
            "url": "/" + worker,
            "status": f"{status(param)}{int(parse(param['LastFinished']).timestamp())}",
            "help": help(worker, help_items),
            "upstream": ""
        }
        mirrors.append(mirror)

    mirrorz["mirrors"] = mirrors
    print(json.dumps(mirrorz))


if __name__ == '__main__':
    main()
