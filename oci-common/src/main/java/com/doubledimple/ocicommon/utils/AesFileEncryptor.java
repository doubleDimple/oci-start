package com.doubledimple.ocicommon.utils;

import javax.crypto.BadPaddingException;
import javax.crypto.Cipher;
import javax.crypto.IllegalBlockSizeException;
import javax.crypto.NoSuchPaddingException;
import javax.crypto.spec.IvParameterSpec;
import javax.crypto.spec.SecretKeySpec;
import java.nio.charset.StandardCharsets;
import java.security.InvalidAlgorithmParameterException;
import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.util.Base64;

/**
 * @version 1.0.0
 * @ClassName AesFileEncryptor
 * @Description TODO
 * @Author renyx
 * @Date 2025-12-04 14:15
 */
public class AesFileEncryptor {
    private static final String ALGO = "AES/CBC/PKCS5Padding";

    /** 生成随机 AES-256 Key (Base64) */
    public static String generateMasterKey() {
        byte[] key = new byte[32]; // AES-256
        new SecureRandom().nextBytes(key);
        return Base64.getEncoder().encodeToString(key);
    }

    /** 随机 IV */
    public static byte[] generateIv() {
        byte[] iv = new byte[16];
        new SecureRandom().nextBytes(iv);
        return iv;
    }

    /** AES 加密整段文本 */
    public static String encrypt(String content, String base64Key, byte[] iv) throws Exception {
        byte[] key = Base64.getDecoder().decode(base64Key);

        Cipher cipher = Cipher.getInstance(ALGO);
        cipher.init(
                Cipher.ENCRYPT_MODE,
                new SecretKeySpec(key, "AES"),
                new IvParameterSpec(iv)
        );
        byte[] encrypted = cipher.doFinal(content.getBytes(StandardCharsets.UTF_8));
        return Base64.getEncoder().encodeToString(encrypted);
    }

    /** AES 解密整段文本 */
    public static String decrypt(String base64Data, String base64Key, byte[] iv) throws Exception {
        byte[] key = Base64.getDecoder().decode(base64Key);
        byte[] encrypted = Base64.getDecoder().decode(base64Data);

        Cipher cipher = Cipher.getInstance(ALGO);
        cipher.init(
                Cipher.DECRYPT_MODE,
                new SecretKeySpec(key, "AES"),
                new IvParameterSpec(iv)
        );
        byte[] decrypted = cipher.doFinal(encrypted);
        return new String(decrypted, StandardCharsets.UTF_8);
    }

    /** AES 加密二进制数据，返回 Base64 */
    public static String encryptBytes(byte[] data, String base64Key, byte[] iv) throws Exception {
        byte[] key = Base64.getDecoder().decode(base64Key);

        Cipher cipher = Cipher.getInstance(ALGO);
        cipher.init(
                Cipher.ENCRYPT_MODE,
                new SecretKeySpec(key, "AES"),
                new IvParameterSpec(iv)
        );
        byte[] encrypted = cipher.doFinal(data);

        return Base64.getEncoder().encodeToString(encrypted);
    }

    /** AES 解密二进制数据，输入 Base64，输出原始 bytes */
    public static byte[] decryptBytes(String base64Data, String base64Key, byte[] iv) throws Exception {
        try {
            byte[] key = Base64.getDecoder().decode(base64Key);
            byte[] encrypted = Base64.getDecoder().decode(base64Data);

            Cipher cipher = Cipher.getInstance(ALGO);
            cipher.init(
                    Cipher.DECRYPT_MODE,
                    new SecretKeySpec(key, "AES"),
                    new IvParameterSpec(iv)
            );
            return cipher.doFinal(encrypted);
        } catch (Exception e) {
            throw new RuntimeException("秘钥错误,无法解析");
        }
    }

}
