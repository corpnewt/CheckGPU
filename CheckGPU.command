#!/usr/bin/env python
import os, sys
from Scripts import *

class CheckGPU:
    def __init__(self):
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

    def get_devs(self,dev_list = None, force = False):
        # Iterate looking for our device(s)
        # returns a list of devices@addr
        if dev_list == None:
            return []
        if not isinstance(dev_list, list):
            dev_list = [dev_list]
        if force or not self.ioreg:
            self.ioreg = self.r.run({"args":["ioreg", "-l", "-p", "IOService", "-w0"]})[0].split("\n")
        igpu = []
        for line in self.ioreg:
            if any(x for x in dev_list if x in line) and "+-o" in line:
                igpu.append(line)
        return igpu

    def get_class_info(self, class_search = None, force = False):
        # Returns a list of all matched classes and their properties
        if not class_search:
            return []
        if force or not self.ioreg:
            self.ioreg = self.r.run({"args":["ioreg", "-l", "-p", "IOService", "-w0"]})[0].split("\n")
        dev = []
        primed = False
        current = None
        for line in self.ioreg:
            if not primed and not class_search in line:
                continue
            if not primed:
                # Has class - try to remove the "<class " header
                primed = True
                current = {"name":class_search.replace("<class ",""),"parts":{}}
                continue
            # Primed, but not IGPU
            if "+-o" in line:
                # Past our prime - see if we have a current, save
                # it to the list, and clear it
                primed = False
                if current:
                    dev.append(current)
                    current = None
                continue
            # Primed, not class, not next device - must be info
            try:
                name = line.split(" = ")[0].split('"')[1]
                current["parts"][name] = line.split(" = ")[1]
            except Exception as e:
                pass
        return dev

    def get_info(self, igpu):
        # Returns a dict of the properties of the IGPU device
        # as individual text items
        # First split up the text and find the device
        try:
            hid = igpu.split("+-o ")[1].split("  ")[0]
        except:
            return {}
        # Got our address - get the full info
        hd = self.r.run({"args":["ioreg", "-p", "IODeviceTree", "-n", hid, "-w0"]})[0]
        if not len(hd):
            return {"name":hid}
        primed = False
        idevice = {"name":"Unknown", "parts":{}}
        for line in hd.split("\n"):
            if not primed and not hid in line:
                continue
            if not primed:
                # Has our passed device
                try:
                    idevice["name"] = hid
                except:
                    idevice["name"] = "Unknown"
                primed = True
                continue
            # Primed, but not IGPU
            if "+-o" in line:
                # Past our prime
                primed = False
                continue
            # Primed, not IGPU, not next device - must be info
            try:
                name = line.split(" = ")[0].split('"')[1]
                idevice["parts"][name] = line.split(" = ")[1]
            except Exception as e:
                pass
        return idevice

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

    def get_path(self, acpi_path):
        # Iterates the acpi pathing and returns
        # the device path
        # For instance, consider the following:
        #
        # "acpi-path" = "IOACPIPlane:/_SB/PCI0@0/PEG1@10001/PEGP@0"
        #
        # Splitting it by "/" and then each sub section by "@" and taking
        # the second value (if it exists) - we then take that value, & 0xFF
        # to get the Function id, then >> 16 & 0xFF to get the Device id.
        #
        # The result is: PciRoot(0x0,0x0)/Pci(0x1,0x1)/Pci(0x0,0x0)
        #
        path = acpi_path.split("/")
        if not len(path):
            return None
        ff = int("0xFF",16)
        paths = []
        for p in path:
            if not "@" in p:
                continue
            try:
                node = int(p.split("@")[1],16)
                func = node & ff
                dev  = (node >> 16) & ff
            except:
                # Failed - bail
                return None
            label = "Pci" if len(paths) else "PciRoot"
            paths.append("{}({},{})".format(label,hex(dev),hex(func)))
        if len(paths):
            return "/".join(paths)
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
        igpu_list = self.get_devs([" IGPU@", " GFX"])
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
                h_dict = self.get_info(h)
                try:
                    loc = self.get_path(h_dict['parts']['acpi-path'].replace('"',""))
                except:
                    loc = "Unknown Location"
                self.lprint(" - {} - {}".format(h_dict.get("name","Unknown"), loc))
                for x in sorted(h_dict.get("parts",{})):
                    if x in gather or x.startswith(start):
                        self.lprint(" --> {}: {}".format(x,h_dict["parts"][x]))
                self.lprint("")
        self.lprint("Locating Framebuffers and Displays...")
        fb_list = self.get_devs([" AppleIntelFramebuffer@", " NVDA,Display-", " ATY,AMD,RadeonFramebuffer@"])
        display = self.get_class_info("<class AppleDisplay")
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
                    name = f.split("+-o ")[1].split("  ")[0]
                    f_dict = self.get_class_info(name+"  ")[0]
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
