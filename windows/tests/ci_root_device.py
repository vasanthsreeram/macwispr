"""Create a root-enumerated device and install its signed driver (what `devcon install <inf> <hwid>` does).

Used on disposable CI runners to add the VB-Audio Virtual Cable, a signed virtual
audio driver, so the app can capture from a real Windows audio endpoint.

    python ci_root_device.py <path.inf> <hardware id>
"""
import ctypes
import sys
from ctypes import wintypes

setupapi = ctypes.WinDLL("setupapi", use_last_error=True)
newdev = ctypes.WinDLL("newdev", use_last_error=True)


class GUID(ctypes.Structure):
    _fields_ = [("Data1", wintypes.DWORD), ("Data2", wintypes.WORD), ("Data3", wintypes.WORD), ("Data4", ctypes.c_ubyte * 8)]


class SP_DEVINFO_DATA(ctypes.Structure):
    _fields_ = [("cbSize", wintypes.DWORD), ("ClassGuid", GUID), ("DevInst", wintypes.DWORD), ("Reserved", ctypes.c_size_t)]


DICD_GENERATE_ID = 0x1
SPDRP_HARDWAREID = 0x1
DIF_REGISTERDEVICE = 0x19
INSTALLFLAG_FORCE = 0x1
INVALID_HANDLE = ctypes.c_void_p(-1).value

setupapi.SetupDiGetINFClassW.argtypes = (wintypes.LPCWSTR, ctypes.POINTER(GUID), wintypes.LPWSTR, wintypes.DWORD, ctypes.POINTER(wintypes.DWORD))
setupapi.SetupDiCreateDeviceInfoList.argtypes = (ctypes.POINTER(GUID), wintypes.HWND)
setupapi.SetupDiCreateDeviceInfoList.restype = ctypes.c_void_p
setupapi.SetupDiCreateDeviceInfoW.argtypes = (ctypes.c_void_p, wintypes.LPCWSTR, ctypes.POINTER(GUID), wintypes.LPCWSTR, wintypes.HWND, wintypes.DWORD, ctypes.POINTER(SP_DEVINFO_DATA))
setupapi.SetupDiSetDeviceRegistryPropertyW.argtypes = (ctypes.c_void_p, ctypes.POINTER(SP_DEVINFO_DATA), wintypes.DWORD, ctypes.c_void_p, wintypes.DWORD)
setupapi.SetupDiCallClassInstaller.argtypes = (wintypes.DWORD, ctypes.c_void_p, ctypes.POINTER(SP_DEVINFO_DATA))
setupapi.SetupDiDestroyDeviceInfoList.argtypes = (ctypes.c_void_p,)
newdev.UpdateDriverForPlugAndPlayDevicesW.argtypes = (wintypes.HWND, wintypes.LPCWSTR, wintypes.LPCWSTR, wintypes.DWORD, ctypes.POINTER(wintypes.BOOL))


def check(ok, what):
    if not ok:
        raise OSError(f"{what} failed: Win32 error {ctypes.get_last_error()}")


def main(inf: str, hwid: str) -> None:
    guid = GUID()
    class_name = ctypes.create_unicode_buffer(256)
    check(setupapi.SetupDiGetINFClassW(inf, ctypes.byref(guid), class_name, 256, None), "SetupDiGetINFClass")
    dev_set = setupapi.SetupDiCreateDeviceInfoList(ctypes.byref(guid), None)
    check(dev_set and dev_set != INVALID_HANDLE, "SetupDiCreateDeviceInfoList")
    try:
        info = SP_DEVINFO_DATA(cbSize=ctypes.sizeof(SP_DEVINFO_DATA))
        check(setupapi.SetupDiCreateDeviceInfoW(dev_set, class_name.value, ctypes.byref(guid), None, None,
                                                DICD_GENERATE_ID, ctypes.byref(info)), "SetupDiCreateDeviceInfo")
        multi_sz = ctypes.create_unicode_buffer(hwid + "\0")
        check(setupapi.SetupDiSetDeviceRegistryPropertyW(dev_set, ctypes.byref(info), SPDRP_HARDWAREID,
                                                         multi_sz, ctypes.sizeof(multi_sz)), "SetDeviceRegistryProperty")
        check(setupapi.SetupDiCallClassInstaller(DIF_REGISTERDEVICE, dev_set, ctypes.byref(info)), "DIF_REGISTERDEVICE")
    finally:
        setupapi.SetupDiDestroyDeviceInfoList(dev_set)
    reboot = wintypes.BOOL()
    check(newdev.UpdateDriverForPlugAndPlayDevicesW(None, hwid, inf, INSTALLFLAG_FORCE, ctypes.byref(reboot)),
          "UpdateDriverForPlugAndPlayDevices")
    print(f"installed {hwid} (class {class_name.value}); reboot required: {bool(reboot.value)}")


if __name__ == "__main__":
    main(sys.argv[1], sys.argv[2])
