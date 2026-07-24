using Microsoft.Win32;

namespace OciStart.Core;

/// <summary>Simple HKCU persistence (UserDefaults analogue).</summary>
internal static class SettingsStore
{
    private const string KeyPath = @"Software\OCI-Start\OciStart";

    public static string? GetString(string name)
    {
        using var key = Registry.CurrentUser.OpenSubKey(KeyPath);
        return key?.GetValue(name) as string;
    }

    public static void SetString(string name, string value)
    {
        using var key = Registry.CurrentUser.CreateSubKey(KeyPath);
        key?.SetValue(name, value, RegistryValueKind.String);
    }

    public static int GetInt(string name)
    {
        using var key = Registry.CurrentUser.OpenSubKey(KeyPath);
        return key?.GetValue(name) is int i ? i : 0;
    }

    public static void SetInt(string name, int value)
    {
        using var key = Registry.CurrentUser.CreateSubKey(KeyPath);
        key?.SetValue(name, value, RegistryValueKind.DWord);
    }

    public static bool GetBool(string name) => GetInt(name) != 0;

    public static void SetBool(string name, bool value) => SetInt(name, value ? 1 : 0);
}
