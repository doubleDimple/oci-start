package com.doubledimple.ociserver.utils.google;

import org.apache.commons.codec.binary.Hex;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * @author doubleDimple
 * @date 2024:10:05日 13:11
 */
public class TOTPUtils {

    public static String generateTOTP(String key, String time, String returnDigits) {
        int codeDigits = Integer.decode(returnDigits);
        String result = null;
        try {
            byte[] keyBytes = Hex.decodeHex(key);
            byte[] data = Hex.decodeHex(time);
            SecretKeySpec signKey = new SecretKeySpec(keyBytes, "HmacSHA1");
            Mac mac = Mac.getInstance("HmacSHA1");
            mac.init(signKey);
            byte[] hash = mac.doFinal(data);

            int offset = hash[hash.length - 1] & 0xf;
            int binary = ((hash[offset] & 0x7f) << 24) |
                    ((hash[offset + 1] & 0xff) << 16) |
                    ((hash[offset + 2] & 0xff) << 8) |
                    (hash[offset + 3] & 0xff);

            int otp = binary % (int) Math.pow(10, codeDigits);
            result = Integer.toString(otp);
            while (result.length() < codeDigits) {
                result = "0" + result;
            }
        } catch (Exception e) {
            throw new RuntimeException("Error generating TOTP code", e);
        }
        return result;
    }
}
