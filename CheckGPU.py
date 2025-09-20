#!/usr/bin/env python
import os, sys, binascii
from Scripts import utils, ioreg, run

class CheckGPU:
    def __init__(self):
        self.u = utils.Utils("CheckGPU")
        # Verify running OS
        if not sys.platform.lower() == "darwin":
            self.u.head("Wrong OS!")
            print("")
            print("This script can only be run on macOS!")
            print("")
            self.u.grab("Press [enter] to exit...")
            exit(1)
        self.i = ioreg.IOReg()
        self.r = run.Run()
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

    def get_boot_args(self):
        # Attempts to pull the boot-args from nvram
        out = self.r.run({"args":["nvram","-p"]})
        for l in out[0].split("\n"):
            if "boot-args" in l:
                return "\t".join(l.split("\t")[1:])
        return None

    def get_os_version(self):
        # Scrape sw_vers
        prod_name  = self.r.run({"args":["sw_vers","-productName"]})[0].strip()
        prod_vers  = self.r.run({"args":["sw_vers","-productVersion"]})[0].strip()
        build_vers = self.r.run({"args":["sw_vers","-buildVersion"]})[0].strip()
        if build_vers: build_vers = "({})".format(build_vers)
        return " ".join([x for x in (prod_name,prod_vers,build_vers) if x])

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
        os_vers = self.get_os_version()
        self.lprint("Current OS Version: {}".format(os_vers or "Unknown!"))
        self.lprint("")
        boot_args = self.get_boot_args()
        self.lprint("Current boot-args: {}".format(boot_args or "None set!"))
        self.lprint("")
        self.lprint("Locating GPU devices...")
        all_devs = self.i.get_all_devices(plane="IOService")
        self.lprint("")
        self.lprint("Iterating for devices with matching class-code...")
        gpus = [x for x in all_devs.values() if x.get("info",{}).get("class-code","").endswith("0300>")]
        if not len(gpus):
            self.lprint(" - None found!")
            self.lprint("")
        else:
            self.lprint(" - Located {}".format(len(gpus)))
            self.lprint("")
            self.lprint("Iterating GPU devices:")
            self.lprint("")
            gather = (
                "AAPL,ig-platform-id",
                "built-in",
                "device-id",
                "vendor-id",
                "hda-gfx",
                "model",
                "NVDAType",
                "NVArch",
                "AAPL,slot-name",
                "acpi-path"
            )
            start  = "framebuffer-"
            fb_checks = (" AppleIntelFramebuffer@", " NVDA,Display-", "class AtiFbStub")
            for g in sorted(gpus, key=lambda x:x.get("device_path","?")):
                g_dict = g.get("info",{})
                pcidebug_check = g_dict.get("pcidebug","").replace("??:??.?","")
                loc = g.get("device_path")
                self.lprint(" - {} - {}".format(g["name"], loc or "Could Not Resolve Device Path"))
                for x in sorted(g_dict):
                    if x in gather or x.startswith(start):
                        val = g_dict[x]
                        # Strip formatting from ioreg
                        if x in ("device-id","vendor-id"):
                            try:
                                val = "0x"+binascii.hexlify(binascii.unhexlify(val[1:5])[::-1]).decode().upper()
                            except:
                                pass
                        elif val.startswith('<"') and val.endswith('">'):
                            try:
                                val = val[2:-2]
                            except:
                                pass
                        elif val.startswith("<") and val.endswith(">"):
                            try:
                                val = "0x"+binascii.hexlify(binascii.unhexlify(val[1:-1])[::-1]).decode().upper()
                            except:
                                pass
                        elif val[0] == val[-1] == '"':
                            try:
                                val = val[1:-1]
                            except:
                                pass
                        self.lprint(" --> {}: {}".format(x,val))
                self.lprint("")
                self.lprint("Connectors:")
                self.lprint("")
                # Check for any framebuffers or connected displays here
                name_check = g["line"] # Use the line to prevent mismatching
                primed = False
                last_fb = None
                fb_list = []
                connected = "Connected to Display"
                for line in self.i.get_ioreg():
                    if name_check in line:
                        primed = len(line.split("+-o ")[0])
                        continue
                    if primed is False:
                        continue
                    # Make sure se have the right device
                    # by verifying the pcidebug value
                    if "pcidebug" in line and not pcidebug_check in line:
                        # Unprime - wrong device
                        primed = False
                        continue
                    # We're primed check for any framebuffers
                    # or if we left our scope
                    if "+-o " in line and len(line.split("+-o ")[0]) <= primed:
                        break
                    if any(f in line for f in fb_checks):
                        # Got a framebuffer - list it
                        fb_list.append(" - "+line.split("+-o ")[1].split("  <class")[0])
                    if '"connector-type"' in line and fb_list:
                        # Got a connector type after a framebuffer
                        conn = line.split(" = ")[-1]
                        fb_list.append(" --> connector-type: {}".format(
                            self.conn_types.get(conn,"Unknown Connector ({})".format(conn))
                        ))
                    if any(c in line for c in ("<class AppleDisplay,","<class AppleBacklightDisplay,","<class IODisplayConnect,")) and fb_list:
                        # Got a display after a framebuffer - append that as well
                        if not fb_list[-1].endswith(connected):
                            # If we listed a connector-type, prefix with " ----> ",
                            # otherwise just use " --> "
                            prefix = " --> " if fb_list[-1].startswith(" - ") else " ----> "
                            fb_list.append(prefix+connected)
                if fb_list:
                    self.lprint("\n".join(fb_list))
                else:
                    self.lprint(" - None found!")
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
