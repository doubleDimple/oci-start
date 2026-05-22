package com.doubledimple.ociserver.utils;

import java.security.KeyFactory;
import java.security.PrivateKey;
import java.security.PublicKey;
import java.security.Signature;
import java.security.spec.PKCS8EncodedKeySpec;
import java.security.spec.X509EncodedKeySpec;
import java.util.Base64;

/**
 * @version 1.0.0
 * @ClassName SignatureUtil
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-30 11:18
 */
public class SignatureUtil {

    private static final String ALGORITHM = "RSA";
    private static final String SIGNATURE_ALGORITHM = "SHA256withRSA";

    /**
     * 使用私钥对数据进行签名
     * @param data 要签名的数据
     * @param privateKeyBase64 Base64编码的私钥
     * @return Base64编码的签名
     */
    public static String sign(String data, String privateKeyBase64) throws Exception {
        byte[] keyBytes = Base64.getDecoder().decode(privateKeyBase64);
        PKCS8EncodedKeySpec pkcs8KeySpec = new PKCS8EncodedKeySpec(keyBytes);
        KeyFactory keyFactory = KeyFactory.getInstance(ALGORITHM);
        PrivateKey privateKey = keyFactory.generatePrivate(pkcs8KeySpec);

        Signature signature = Signature.getInstance(SIGNATURE_ALGORITHM);
        signature.initSign(privateKey);
        signature.update(data.getBytes("UTF-8"));

        byte[] signed = signature.sign();
        return Base64.getEncoder().encodeToString(signed);
    }
}
