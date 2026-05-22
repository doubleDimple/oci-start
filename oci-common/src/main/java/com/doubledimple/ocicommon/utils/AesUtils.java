package com.doubledimple.ocicommon.utils;

import org.bouncycastle.jce.provider.BouncyCastleProvider;

import javax.crypto.Cipher;
import javax.crypto.Mac;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.Key;
import java.security.MessageDigest;
import java.security.Security;

/**
 * @version 1.0.0
 * @ClassName AesUtils
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-05-04 21:35
 */
public class AesUtils {

    public static String KEY_ALGORITHM = "AES";

    static {
        Security.addProvider(new BouncyCastleProvider());
    }

    public static byte[] encrypt(byte[] originalContent, byte[] encryptKey, int model, byte[] ivByte) {

        try {
            Cipher cipher = Cipher.getInstance(getTransformation(model));
            SecretKeySpec secretKeySpec = new SecretKeySpec(encryptKey, KEY_ALGORITHM);
            if (model == 0) {
                cipher.init(Cipher.ENCRYPT_MODE, secretKeySpec);
            }
            if (model == 1) {
                cipher.init(Cipher.ENCRYPT_MODE, secretKeySpec, new IvParameterSpec(ivByte));
            }
            return cipher.doFinal(originalContent);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    private static String getTransformation(int model) {

        if (model == 0) {
            return "AES/ECB/PKCS7Padding";
        }
        return "AES/CBC/PKCS7Padding";
    }


    public static byte[] decrypt(byte[] content, byte[] aesKey, int model, byte[] ivByte) {

        try {
            Cipher cipher = Cipher.getInstance(getTransformation(model));
            Key secretKeySpec = new SecretKeySpec(aesKey, KEY_ALGORITHM);
            if (model == 0) {
                cipher.init(Cipher.DECRYPT_MODE, secretKeySpec);
            }
            if (model == 1) {
                cipher.init(Cipher.DECRYPT_MODE, secretKeySpec, new IvParameterSpec(ivByte));
            }
            return cipher.doFinal(content);
        } catch (Exception e) {
            throw new RuntimeException(e);
        }
    }

    public static String sha256Hex(String data) {
        try {
            MessageDigest digest = MessageDigest.getInstance("SHA-256");
            byte[] hash = digest.digest(data.getBytes(StandardCharsets.UTF_8));
            return bytesToHex(hash);
        } catch (Exception e) {
            throw new RuntimeException("SHA256计算失败", e);
        }
    }

    // HMAC-SHA256函数
    public static byte[] hmacSha256(byte[] key, String data) {
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            SecretKeySpec secretKeySpec = new SecretKeySpec(key, "HmacSHA256");
            mac.init(secretKeySpec);
            return mac.doFinal(data.getBytes(StandardCharsets.UTF_8));
        } catch (Exception e) {
            throw new RuntimeException("HMAC-SHA256计算失败", e);
        }
    }

    // 字节数组转十六进制字符串
    public static String bytesToHex(byte[] bytes) {
        StringBuilder result = new StringBuilder();
        for (byte b : bytes) {
            result.append(String.format("%02x", b));
        }
        return result.toString();
    }
}
