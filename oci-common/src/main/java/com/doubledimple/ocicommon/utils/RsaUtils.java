package com.doubledimple.ocicommon.utils;

import javax.crypto.Cipher;
import java.nio.charset.StandardCharsets;
import java.security.KeyFactory;
import java.security.KeyPair;
import java.security.KeyPairGenerator;
import java.security.NoSuchAlgorithmException;
import java.security.PrivateKey;
import java.security.spec.PKCS8EncodedKeySpec;
import java.util.Base64;

/**
 * @version 1.0.0
 * @ClassName RsaUtils
 * @Description TODO
 * @Author doubleDimple
 * @Date 2026-02-06 08:54
 */
public class RsaUtils {

    private static final String KEY_GEN_ALGORITHM = "RSA";

    private static final String CIPHER_ALGORITHM = "RSA/ECB/PKCS1Padding";

    /**
     * 生成密钥对 (公钥和私钥)
     */
    public static KeyPair generateKeyPair() throws NoSuchAlgorithmException {
        KeyPairGenerator generator = KeyPairGenerator.getInstance(KEY_GEN_ALGORITHM);
        generator.initialize(2048);
        return generator.generateKeyPair();
    }

    /**
     * 获取公钥字符串 (Base64编码)
     */
    public static String getPublicKeyString(KeyPair keyPair) {
        return Base64.getEncoder().encodeToString(keyPair.getPublic().getEncoded());
    }

    /**
     * 获取私钥字符串 (Base64编码)
     */
    public static String getPrivateKeyString(KeyPair keyPair) {
        return Base64.getEncoder().encodeToString(keyPair.getPrivate().getEncoded());
    }

    /**
     * 私钥解密
     * @param encryptedText 经过 Base64 编码的密文
     * @param privateKeyStr Base64 编码的私钥
     */
    public static String decrypt(String encryptedText, String privateKeyStr) throws Exception {
        byte[] keyBytes = Base64.getDecoder().decode(privateKeyStr);
        PKCS8EncodedKeySpec spec = new PKCS8EncodedKeySpec(keyBytes);
        KeyFactory keyFactory = KeyFactory.getInstance(KEY_GEN_ALGORITHM);
        PrivateKey privateKey = keyFactory.generatePrivate(spec);
        Cipher cipher = Cipher.getInstance(CIPHER_ALGORITHM);
        cipher.init(Cipher.DECRYPT_MODE, privateKey);
        byte[] buffer = Base64.getDecoder().decode(encryptedText.replace(" ", "+"));
        byte[] decryptedBytes = cipher.doFinal(buffer);
        return new String(decryptedBytes, StandardCharsets.UTF_8);
    }
}
