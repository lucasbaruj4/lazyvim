Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;

[ComImport]
[Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
class MMDeviceEnumerator {}

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator {
    int EnumAudioEndpoints(int dataFlow, int dwStateMask, out IntPtr ppDevices);
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IntPtr ppEndpoint);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice {
    int Activate(ref Guid iid, int dwClsCtx, IntPtr pActivationParams, [MarshalAs(UnmanagedType.IUnknown)] out object ppInterface);
}

[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
    int RegisterControlChangeNotify(IntPtr pNotify);
    int UnregisterControlChangeNotify(IntPtr pNotify);
    int GetChannelCount(out uint pnChannelCount);
    int SetMasterVolumeLevel(float fLevelDB, ref Guid pguidEventContext);
    int SetMasterVolumeLevelScalar(float fLevel, ref Guid pguidEventContext);
    int GetMasterVolumeLevel(out float pfLevelDB);
    int GetMasterVolumeLevelScalar(out float pfLevel);
    int SetChannelVolumeLevel(uint nChannel, float fLevelDB, ref Guid pguidEventContext);
    int SetChannelVolumeLevelScalar(uint nChannel, float fLevel, ref Guid pguidEventContext);
    int GetChannelVolumeLevel(uint nChannel, out float pfLevelDB);
    int GetChannelVolumeLevelScalar(uint nChannel, out float pfLevel);
    int SetMute([MarshalAs(UnmanagedType.Bool)] bool bMute, ref Guid pguidEventContext);
    int GetMute(out bool pbMute);
    int GetVolumeStepInfo(out uint pnStep, out uint pnStepCount);
    int VolumeStepUp(ref Guid pguidEventContext);
    int VolumeStepDown(ref Guid pguidEventContext);
    int QueryHardwareSupport(out uint pdwHardwareSupportMask);
    int GetVolumeRange(out float pfLevelMinDB, out float pfLevelMaxDB, out float pfVolumeIncrementDB);
}

public static class AudioManager {
    private static IAudioEndpointVolume GetEpv() {
        Guid CLSID = new Guid("BCDE0395-E52F-467C-8E3D-C4579291692E");
        var enumerator = (IMMDeviceEnumerator)Activator.CreateInstance(Type.GetTypeFromCLSID(CLSID));
        IntPtr devPtr;
        enumerator.GetDefaultAudioEndpoint(0, 0, out devPtr);
        var device = (IMMDevice)Marshal.GetObjectForIUnknown(devPtr);
        Guid IID = new Guid("5CDF2C82-841E-4546-9722-0CF74078229A");
        object epvObj;
        device.Activate(ref IID, 0x17, IntPtr.Zero, out epvObj);
        return (IAudioEndpointVolume)epvObj;
    }
    public static float GetVolume() {
        var epv = GetEpv();
        float level;
        epv.GetMasterVolumeLevelScalar(out level);
        Marshal.ReleaseComObject(epv);
        return level * 100f;
    }
    public static bool GetMute() {
        var epv = GetEpv();
        bool isMuted;
        epv.GetMute(out isMuted);
        Marshal.ReleaseComObject(epv);
        return isMuted;
    }
}
"@
$vol = [Math]::Round( [AudioManager]::GetVolume() )
$mut = [AudioManager]::GetMute()
Write-Output $vol
Write-Output $(if ($mut) { "yes" } else { "no" })
