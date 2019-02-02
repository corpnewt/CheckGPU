#!/usr/bin/env python
import os, sys
from Scripts import *

class CheckGPU:
    def __init__(self):
        self.i = ioreg.IOReg()
        self.r = run.Run()
        self.u = utils.Utils("CheckGPU")
        self.kextstat = None
        self.log = ""
        self.conn_types = {
            "<00080000>":"HDMI",
            "<00040000>":"DisplayPort",
            "<04000000>":"DVI",
            "<02000000>":"LVDS",
            "<01000000>":"Dummy Port"
        }
        self.ioreg = None

    def get_kextstat(self, force = False):
        # Gets the kextstat list if needed
        if not self.kextstat or force:
            self.kextstat = self.r.run({"args":"kextstat"})[0]
        return self.kextstat

    def locate(self, kext):
        # Gathers the kextstat list - then parses for loaded kexts
        ks = self.get_kextstat()
        # Verifies that our name ends with a space
        if not kext[-1] == " ":
            kext += " "
        for x in ks.split("\n")[1:]:
            if kext.lower() in x.lower():
                # We got the kext - return the version
                try:
                    v = x.split("(")[1].split(")")[0]
                except:
                    return "?.?"
                return v
        return None

    def lprint(self, message):
        print(message)
        self.log += message + "\n"

    def main(self):
        self.u.head()
        self.lprint("")
        self.lprint("Checking kexts:")
        self.lprint("")
        self.lprint("Locating Lilu...")
        lilu_vers = self.locate("Lilu")
        if not lilu_vers:
            self.lprint(" - Not loaded! AppleALC and WhateverGreen need this!")
        else:
            self.lprint(" - Found v{}".format(lilu_vers))
            self.lprint("Checking for Lilu plugins...")
            self.lprint(" - Locating AppleALC...")
            alc_vers = self.locate("AppleALC")
            if not alc_vers:
                self.lprint(" --> Not loaded! Onboard and HDMI/DP audio may not work!")
            else:
                self.lprint(" --> Found v{}".format(alc_vers))
            self.lprint(" - Locating WhateverGreen...")
            weg_vers = self.locate("WhateverGreen")
            if not weg_vers:
                self.lprint(" --> Not loaded! GFX and audio may not work!")
            else:
                self.lprint(" --> Found v{}".format(weg_vers))
        self.lprint("")
        self.lprint("Locating GPU devices...")
        igpu_list = self.i.get_devices([" IGPU@", " GFX"])
        if not len(igpu_list):
            self.lprint(" - None found!")
            self.lprint("")
        else:
            self.lprint(" - Located {}".format(len(igpu_list)))
            self.lprint("")
            self.lprint("Iterating GPU devices:")
            self.lprint("")
            gather = ["AAPL,ig-platform-id","built-in","device-id","hda-gfx","model","NVDAType","NVArch","AAPL,slot-name"]
            start  = "framebuffer-"
            for h in igpu_list:
                h_dict = self.i.get_device_info(h)[0] # Get first occurrence
                loc = self.i.get_device_path(h)
                loc = loc if len(loc) else "Unknown Location"ßß
                self.lprint(" - {} - {}".format(h_dict.get("name","Unknown"), loc))
                for x in sorted(h_dict.get("parts",{})):
                    if x in gather or x.startswith(start):
                        self.lprint(" --> {}: {}".format(x,h_dict["parts"][x]))
                self.lprint("")
        self.lprint("Locating Framebuffers and Displays...")
        fb_list = self.i.get_devices([" AppleIntelFramebuffer@", " NVDA,Display-", " ATY,AMD,RadeonFramebuffer@"])
        display = self.i.get_device_info("AppleDisplay",isclass=True)
        displays = {}
        if len(display):
            # Got at least one display - let's find out which fb they're connected to
            for d in display:
                if not "IODisplayPrefsKey" in d["parts"]:
                    continue
                # Get the path, and break it up - we should find our fb and GPU as the
                # last 2 path components that contain @
                path = d["parts"]["IODisplayPrefsKey"].split("/")[::-1]
                gpu = fb = None
                for x in path:
                    if not "@" in x:
                        continue
                    if not fb:
                        fb = x
                        continue
                    gpu = x
                    break
                if not gpu in displays:
                    displays[gpu] = []
                displays[gpu].append(fb)

        if not len(fb_list):
            self.lprint(" - None found!")
            self.lprint("")
        else:
            self.lprint(" - Located {}".format(len(fb_list)))
            self.lprint("")
            self.lprint("Iterating Framebuffer devices:")
            self.lprint("")
            gather = ["connector-type"]
            for f in fb_list:
                try:
                    name = f
                    f_dict = self.i.get_device_info(name+"  ")[0]
                except:
                    continue
                self.lprint(" - {}".format(name))
                # Let's look through and get whatever properties we need
                for x in sorted(f_dict.get("parts",{})):
                    if x in gather:
                        if x == "connector-type":
                            ct = self.conn_types.get(f_dict["parts"][x],"Unknown ({})".format(f_dict["parts"][x]))
                            self.lprint(" --> {}: {}".format(x, ct))
                        else:
                            self.lprint(" --> {}: {}".format(x,f_dict["parts"][x]))
                # Check if it's in our displays list
                for d in displays:
                    if name in displays[d]:
                        self.lprint(" --> Connected to Display")
            self.lprint("")

        print("Saving log...")
        print("")
        os.chdir(os.path.dirname(os.path.realpath(__file__)))
        with open("GPU.log","w") as f:
            f.write(self.log)
        print("Done.")
        print("")
        

if __name__ == '__main__':
    # os.chdir(os.path.dirname(os.path.realpath(__file__)))
    a = CheckGPU()
    a.main()
