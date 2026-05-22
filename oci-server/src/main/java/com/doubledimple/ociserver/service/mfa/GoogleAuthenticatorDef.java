package com.doubledimple.ociserver.service.mfa;

import lombok.extern.slf4j.Slf4j;
import org.apache.commons.codec.binary.Base32;
import org.springframework.stereotype.Service;

import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.security.InvalidKeyException;
import java.security.NoSuchAlgorithmException;
import java.time.Instant;

/**
 * @author doubleDimple
 * @date 2024:11:02日 01:02
 */
@Service
@Slf4j
public class GoogleAuthenticatorDef {
    private static final int TIME_STEP = 30;  // 时间片长度，单位秒
    private static final int CODE_LENGTH = 6; // 验证码长度

    public String generateCode(String secretKey) {
        try {
            // 1. 获取当前时间戳
            long currentTime = Instant.now().getEpochSecond();
            // 2. 获取时间片数值
            long timeSlice = currentTime / TIME_STEP;

            // 调试信息
            if (log.isDebugEnabled()){
                log.debug("Current Time: " + currentTime);
                log.debug("Time Slice: " + timeSlice);
            }


            // 3. 解码密钥
            Base32 base32 = new Base32();
            byte[] decodedKey = base32.decode(secretKey);

            // 4. 生成 HMAC-SHA1 散列
            byte[] data = new byte[8];
            for (int i = 8; i-- > 0; timeSlice >>>= 8) {
                data[i] = (byte) timeSlice;
            }

            SecretKeySpec signKey = new SecretKeySpec(decodedKey, "HmacSHA1");
            Mac mac = Mac.getInstance("HmacSHA1");
            mac.init(signKey);
            byte[] hash = mac.doFinal(data);

            // 5. 动态截断
            int offset = hash[hash.length - 1] & 0xF;
            long truncatedHash = 0;
            for (int i = 0; i < 4; ++i) {
                truncatedHash <<= 8;
                truncatedHash |= (hash[offset + i] & 0xFF);
            }
            truncatedHash &= 0x7FFFFFFF;
            truncatedHash %= Math.pow(10, CODE_LENGTH);

            // 6. 补齐位数
            return String.format("%0" + CODE_LENGTH + "d", truncatedHash);

        } catch (NoSuchAlgorithmException | InvalidKeyException e) {
            throw new RuntimeException("Error generating TOTP", e);
        }
    }

    // 验证方法
    public boolean verify(String secretKey, String code) {
        try {
            // 获取当前代码
            String currentCode = generateCode(secretKey);
            // 调试信息
            if (log.isDebugEnabled()){
                log.debug("Input Code: " + code);
                log.debug("Generated Code: " + currentCode);
            }


            // 考虑前后 30 秒的容差
            return code.equals(currentCode) ||
                    code.equals(generateCodeForTime(secretKey, -30)) ||
                    code.equals(generateCodeForTime(secretKey, 30));

        } catch (Exception e) {
            throw new RuntimeException("Error verifying TOTP", e);
        }
    }

    // 用于调试：生成指定时间偏移的验证码
    private String generateCodeForTime(String secretKey, int secondsOffset) {
        try {
            long currentTime = Instant.now().getEpochSecond() + secondsOffset;
            long timeSlice = currentTime / TIME_STEP;

            Base32 base32 = new Base32();
            byte[] decodedKey = base32.decode(secretKey);

            byte[] data = new byte[8];
            for (int i = 8; i-- > 0; timeSlice >>>= 8) {
                data[i] = (byte) timeSlice;
            }

            SecretKeySpec signKey = new SecretKeySpec(decodedKey, "HmacSHA1");
            Mac mac = Mac.getInstance("HmacSHA1");
            mac.init(signKey);
            byte[] hash = mac.doFinal(data);

            int offset = hash[hash.length - 1] & 0xF;
            long truncatedHash = 0;
            for (int i = 0; i < 4; ++i) {
                truncatedHash <<= 8;
                truncatedHash |= (hash[offset + i] & 0xFF);
            }
            truncatedHash &= 0x7FFFFFFF;
            truncatedHash %= Math.pow(10, CODE_LENGTH);

            return String.format("%0" + CODE_LENGTH + "d", truncatedHash);

        } catch (Exception e) {
            throw new RuntimeException("Error generating TOTP", e);
        }
    }

    // 主方法用于测试
    public static void main(String[] args) {
        GoogleAuthenticatorDef ga = new GoogleAuthenticatorDef();
        String secretKey = "M7F3TXLHHI26ONJHX7CZWIRMIVGSO35L"; // 替换为您的密钥

        // 打印调试信息
        System.out.println("System Time: " + Instant.now());
        System.out.println("Generated Code: " + ga.generateCode(secretKey));

        // 测试验证
        String testCode = "123456"; // 替换为要验证的代码
        boolean isValid = ga.verify(secretKey, testCode);
        System.out.println("Verification result: " + isValid);
    }
}
