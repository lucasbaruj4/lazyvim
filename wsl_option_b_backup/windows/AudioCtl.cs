using System;
using System.Runtime.InteropServices;

[Guid("5CDF2C82-841E-4546-9722-0CF74078229A"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IAudioEndpointVolume {
    int f(); int g(); int h(); int i();
    int SetMasterVolumeLevelScalar(float fLevel, Guid pguidEventContext);
    int j();
    int GetMasterVolumeLevelScalar(out float pfLevel);
    int k(); int l(); int m(); int n();
    int SetMute([MarshalAs(UnmanagedType.Bool)] bool bMute, Guid pguidEventContext);
    int GetMute(out bool pbMute);
}

[Guid("D666063F-1587-4E43-81F1-B948E807363F"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDevice {
    int Activate(ref Guid id, int clsCtx, int activationParams, out IAudioEndpointVolume aev);
}

[Guid("A95664D2-9614-4F35-A746-DE8DB63617E6"), InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
interface IMMDeviceEnumerator {
    int f();
    int GetDefaultAudioEndpoint(int dataFlow, int role, out IMMDevice endpoint);
}

[ComImport, Guid("BCDE0395-E52F-467C-8E3D-C4579291692E")]
class MMDeviceEnumeratorComObject { }

class Audio {
    static IAudioEndpointVolume Vol() {
        var enumerator = new MMDeviceEnumeratorComObject() as IMMDeviceEnumerator;
        IMMDevice dev;
        enumerator.GetDefaultAudioEndpoint(0, 1, out dev);
        var epvGuid = typeof(IAudioEndpointVolume).GUID;
        IAudioEndpointVolume epv;
        dev.Activate(ref epvGuid, 23, 0, out epv);
        return epv;
    }
    static float GetVolume() { float v; Vol().GetMasterVolumeLevelScalar(out v); return v; }
    static void SetVolume(float v) { Vol().SetMasterVolumeLevelScalar(v, Guid.Empty); }
    static bool GetMute() { bool m; Vol().GetMute(out m); return m; }
    static void SetMute(bool m) { Vol().SetMute(m, Guid.Empty); }

    static void Main(string[] args) {
        string action = args.Length > 0 ? args[0] : "status";
        switch (action) {
            case "unmute": SetMute(false); break;
            case "mute":   SetMute(true); break;
            case "toggle": SetMute(!GetMute()); break;
            case "set":
                SetMute(false);
                SetVolume(int.Parse(args[1]) / 100.0f);
                break;
            case "up":
                SetMute(false);
                SetVolume(Math.Min(1.0f, GetVolume() + 0.05f));
                break;
            case "down":
                SetVolume(Math.Max(0.0f, GetVolume() - 0.05f));
                break;
        }
        Console.WriteLine("volume=" + Math.Round(GetVolume() * 100) + " muted=" + GetMute());
    }
}
