package com.doubledimple.ociserver.utils.google;

/**
 * @author doubleDimple
 * @date 2024:10:29日 20:28
 */
import lombok.Data;
import org.apache.commons.codec.binary.Base32;

import java.net.URLDecoder;
import java.nio.ByteBuffer;
import java.nio.charset.StandardCharsets;
import java.util.ArrayList;
import java.util.Base64;
import java.util.List;

public class GoogleAuthMigrationParser {

    @Data
    public static class OtpParameters {
        private String secret;
        private String name;
        private String issuer;
        private int algorithm = 1;
        private int digits = 6;
        private int type = 1;

        // Getters and setters
        public String getSecretInBase32() {
            if (secret == null) return null;
            // 先将 Base64 转回字节数组
            byte[] secretBytes = Base64.getDecoder().decode(secret);
            // 然后转换为 Base32
            return new Base32().encodeToString(secretBytes).replaceAll("=", "");
        }
    }

    public static List<OtpParameters> parseUri(String migrationUri) {
        try {
            // 解析URI数据
            String data = migrationUri.substring(migrationUri.indexOf("data=") + 5);
            String urlDecoded = URLDecoder.decode(data, StandardCharsets.UTF_8.name());
            byte[] decoded = Base64.getDecoder().decode(urlDecoded);
            ByteBuffer buffer = ByteBuffer.wrap(decoded);
            List<OtpParameters> accounts = new ArrayList<>();

            // 读取外层消息
            while (buffer.hasRemaining()) {
                int tag = readTag(buffer);
                int fieldNumber = tag >>> 3;

                if (fieldNumber == 1) { // OTP parameters
                    int length = (int) readVarint(buffer);
                    int endPosition = buffer.position() + length;
                    parseOtpParameters(buffer, endPosition, accounts);
                } else {
                    skipUnknownField(buffer, tag);
                }
            }

            return accounts;
        } catch (Exception e) {
            System.err.println("Error parsing migration data: " + e.getMessage());
            e.printStackTrace();
            throw new RuntimeException("Failed to parse migration data", e);
        }
    }

    private static void parseOtpParameters(ByteBuffer buffer, int endPosition, List<OtpParameters> accounts) {
        OtpParameters params = new OtpParameters();
        boolean validParams = false;

        while (buffer.position() < endPosition) {
            int tag = readTag(buffer);
            int fieldNumber = tag >>> 3;

            switch (fieldNumber) {
                case 1: // secret
                    int secretLength = (int) readVarint(buffer);
                    byte[] secretBytes = new byte[secretLength];
                    buffer.get(secretBytes);
                    params.setSecret(Base64.getEncoder().encodeToString(secretBytes));
                    validParams = true;
                    break;

                case 2: // name
                    int nameLength = (int) readVarint(buffer);
                    byte[] nameBytes = new byte[nameLength];
                    buffer.get(nameBytes);
                    params.setName(new String(nameBytes, StandardCharsets.UTF_8));
                    break;

                case 3: // issuer
                    int issuerLength = (int) readVarint(buffer);
                    byte[] issuerBytes = new byte[issuerLength];
                    buffer.get(issuerBytes);
                    params.setIssuer(new String(issuerBytes, StandardCharsets.UTF_8));
                    break;

                default:
                    skipUnknownField(buffer, tag);
                    break;
            }
        }

        if (validParams) {
            accounts.add(params);
            System.out.println("Successfully parsed: " + params);
        }
    }

    private static void skipUnknownField(ByteBuffer buffer, int tag) {
        int wireType = tag & 0x7;
        switch (wireType) {
            case 0: // Varint
                readVarint(buffer);
                break;
            case 1: // Fixed64
                buffer.position(buffer.position() + 8);
                break;
            case 2: // Length-delimited
                int length = (int) readVarint(buffer);
                buffer.position(buffer.position() + length);
                break;
            case 5: // Fixed32
                buffer.position(buffer.position() + 4);
                break;
            default:
                // 对于未知的类型，跳过一个字节
                buffer.position(buffer.position() + 1);
        }
    }

    private static int readTag(ByteBuffer buffer) {
        return (int) readVarint(buffer);
    }

    private static long readVarint(ByteBuffer buffer) {
        long value = 0;
        int shift = 0;

        while (buffer.hasRemaining()) {
            byte b = buffer.get();
            value |= (long) (b & 0x7F) << shift;
            if ((b & 0x80) == 0) {
                break;
            }
            shift += 7;
            if (shift >= 64) {
                throw new IllegalArgumentException("Varint is too long");
            }
        }

        return value;
    }

    private static void readField(ByteBuffer buffer) {
        // 1. 读取 tag，包含字段编号和 wire type
        int tag = buffer.get() & 0xFF;

        // 2. 解析 wire type (低3位)
        int wireType = tag & 0x7;

        // 3. 解析字段编号 (右移3位)
        int fieldNumber = tag >>> 3;

        // 4. 根据 wire type 处理相应类型的数据
        switch (wireType) {
            case 0: // Varint
                readVarint(buffer);
                break;

            case 1: // Fixed64
                buffer.position(buffer.position() + 8);
                break;

            case 2: // Length-delimited
                // 读取长度
                int length = (int) readVarint(buffer);
                // 跳过指定长度的数据
                buffer.position(buffer.position() + length);
                break;

            case 5: // Fixed32
                buffer.position(buffer.position() + 4);
                break;

            default:
                throw new IllegalArgumentException(
                        String.format("Unknown wire type: %d (field number: %d)", wireType, fieldNumber)
                );
        }
    }

    // 示例用法
    public static void main(String[] args) {
        String migrationUri = "otpauth-migration://offline?data=CjcKEP4eovjWG9YYu7W1FiKPyCISETEwMDQ5NDA3MjVAcXEuY29tGgplMDA0OTQwNzI1IAEoATACCjoKEMMomMAYRQdnMK/xhithGbsSE2xvdmVsZS5jbkBnbWFpbC5jb20aC2Zlcm5hbmRvdGJsIAEoATACCi8KFE2ovHvrdx2A3JFVcUxSXoUsBdAKEgZsb3ZlbGUaCVNwYWNlc2hpcCABKAEwAgo2Cgqx5lCaKX6nJvW6EhVtaXNub21tYXNpY0BnbWFpbC5jb20aC0JpbmFuY2UuY29tIAEoATACCkAKEEo/XpH3OwbB9c83ghKAcr4SF3Jlbnl1YW54aW4wMDFAZ21haWwuY29tGg1ld2FyZG9laHJsZWluIAEoATACCiYKFKNEo83H/I73mqAW8UDECjLthT4MEghyZWRvdHBheSABKAEwAgojChQxp5GWbjM1ghEebGcHRgPnpKkn1BIFdGhQYXkgASgBMAIKJAoKE6gixtdRrzFUuhIQc21zLWFjdGl2YXRlLm9yZyABKAEwAgoyChCwSapRadYxa9JSgjStuEuxEg5tb2thbmRlckBiay5ydRoIbW9rYW5kZXIgASgBMAIKNgoQuZYewwSl8gKRNsQ96ZB8gBISb2JqYm95QGhvdG1haWwuY29tGghtb2thbmRlciABKAEwAhACGAcgAA==";

        List<OtpParameters> accounts = parseUri(migrationUri);
        for (OtpParameters account : accounts) {
            System.out.println("\nAccount Details:");
            System.out.println("Name: " + account.getName());
            System.out.println("Issuer: " + account.getIssuer());
            System.out.println("Secret (Base64): " + account.getSecret());
            System.out.println("Secret (Base32): " + account.getSecretInBase32());
            System.out.println("Type: " + (account.getType() == 1 ? "TOTP" : "HOTP"));
            System.out.println("Algorithm: " + (account.getAlgorithm() == 1 ? "SHA1" : "Unknown"));
            System.out.println("Digits: " + account.getDigits());
        }
    }
}
