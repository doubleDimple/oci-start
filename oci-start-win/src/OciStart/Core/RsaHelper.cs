using System.Security.Cryptography;
using System.Text;

namespace OciStart.Core;

/// <summary>RSA PKCS#1 v1.5 encrypt for login password (align Mac RSAHelper).</summary>
public static class RsaHelper
{
    public static string? Encrypt(string plainText, string publicKeyBase64)
    {
        try
        {
            var cleaned = publicKeyBase64
                .Replace("-----BEGIN PUBLIC KEY-----", "")
                .Replace("-----END PUBLIC KEY-----", "")
                .Replace("-----BEGIN RSA PUBLIC KEY-----", "")
                .Replace("-----END RSA PUBLIC KEY-----", "")
                .Replace("\r", "")
                .Replace("\n", "")
                .Replace(" ", "");

            var der = Convert.FromBase64String(cleaned);
            using var rsa = RSA.Create();
            try
            {
                rsa.ImportSubjectPublicKeyInfo(der, out _);
            }
            catch
            {
                rsa.ImportRSAPublicKey(der, out _);
            }

            var cipher = rsa.Encrypt(Encoding.UTF8.GetBytes(plainText), RSAEncryptionPadding.Pkcs1);
            return Convert.ToBase64String(cipher);
        }
        catch
        {
            return null;
        }
    }

    public static string? ExtractPublicKeyFromLoginHtml(string html)
    {
        // window.RSA_PUBLIC_KEY = "...."
        const string marker = "window.RSA_PUBLIC_KEY";
        var idx = html.IndexOf(marker, StringComparison.Ordinal);
        if (idx < 0) return null;
        var eq = html.IndexOf('=', idx);
        if (eq < 0) return null;
        var q1 = html.IndexOf('"', eq);
        if (q1 < 0) return null;
        var q2 = html.IndexOf('"', q1 + 1);
        if (q2 < 0) return null;
        return html.Substring(q1 + 1, q2 - q1 - 1);
    }
}
