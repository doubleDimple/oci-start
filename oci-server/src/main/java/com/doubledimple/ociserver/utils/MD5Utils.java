package com.doubledimple.ociserver.utils;

import java.nio.charset.StandardCharsets;

/**
 * @version 1.0.0
 * @ClassName MD5Utils
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-12-28 16:02
 */
public class MD5Utils {
    private static final int[] ROTATE_AMOUNTS = {
            7, 12, 17, 22,  // Round 1 shifts
            5, 9, 14, 20,   // Round 2 shifts
            4, 11, 16, 23,  // Round 3 shifts
            6, 10, 15, 21   // Round 4 shifts
    };

    private static final int[] CONSTANTS = {
            0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee, // Round 1
            0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
            0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
            0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
            0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa, // Round 2
            0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
            0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
            0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
            0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c, // Round 3
            0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
            0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
            0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
            0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039, // Round 4
            0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
            0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
            0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391
    };

    private int a;
    private int b;
    private int c;
    private int d;

    public String hash(String message, boolean is16bit) {
        // 重置初始值
        a = 0x67452301;
        b = 0xEFCDAB89;
        c = 0x98BADCFE;
        d = 0x10325476;

        byte[] bytes = message.getBytes(StandardCharsets.UTF_8);
        byte[] padded = padMessage(bytes);

        int[] words = new int[padded.length / 4];
        for (int i = 0; i < words.length; i++) {
            words[i] = (padded[i * 4] & 0xff) |
                    ((padded[i * 4 + 1] & 0xff) << 8) |
                    ((padded[i * 4 + 2] & 0xff) << 16) |
                    ((padded[i * 4 + 3] & 0xff) << 24);
        }

        processMessage(words);

        if (is16bit) {
            return String.format("%08x%08x", b, c);
        } else {
            return String.format("%08x%08x%08x%08x", a, b, c, d);
        }
    }

    private byte[] padMessage(byte[] message) {
        int originalLength = message.length;
        int paddingLength = (448 - (originalLength * 8 + 1)) % 512;
        if (paddingLength < 0) {
            paddingLength += 512;
        }
        paddingLength = (paddingLength + 1) / 8;

        byte[] padded = new byte[originalLength + paddingLength + 8];
        System.arraycopy(message, 0, padded, 0, originalLength);

        // Add padding bit
        padded[originalLength] = (byte) 0x80;

        // Add length in bits
        long lengthInBits = originalLength * 8L;
        for (int i = 0; i < 8; i++) {
            padded[padded.length - 8 + i] = (byte) (lengthInBits >>> (i * 8));
        }

        return padded;
    }

    private void processMessage(int[] words) {
        int aa, bb, cc, dd;

        for (int i = 0; i < words.length; i += 16) {
            aa = a;
            bb = b;
            cc = c;
            dd = d;

            // Round 1
            for (int j = 0; j < 16; j++) {
                int f = (b & c) | ((~b) & d);
                int g = j;
                int temp = d;
                d = c;
                c = b;
                b = b + leftRotate(a + f + CONSTANTS[j] + words[i + g],
                        ROTATE_AMOUNTS[j % 4]);
                a = temp;
            }

            // Round 2
            for (int j = 16; j < 32; j++) {
                int f = (d & b) | (c & (~d));
                int g = (5 * j + 1) % 16;
                int temp = d;
                d = c;
                c = b;
                b = b + leftRotate(a + f + CONSTANTS[j] + words[i + g],
                        ROTATE_AMOUNTS[4 + (j % 4)]);
                a = temp;
            }

            // Round 3
            for (int j = 32; j < 48; j++) {
                int f = b ^ c ^ d;
                int g = (3 * j + 5) % 16;
                int temp = d;
                d = c;
                c = b;
                b = b + leftRotate(a + f + CONSTANTS[j] + words[i + g],
                        ROTATE_AMOUNTS[8 + (j % 4)]);
                a = temp;
            }

            // Round 4
            for (int j = 48; j < 64; j++) {
                int f = c ^ (b | (~d));
                int g = (7 * j) % 16;
                int temp = d;
                d = c;
                c = b;
                b = b + leftRotate(a + f + CONSTANTS[j] + words[i + g],
                        ROTATE_AMOUNTS[12 + (j % 4)]);
                a = temp;
            }

            a += aa;
            b += bb;
            c += cc;
            d += dd;
        }
    }

    private int leftRotate(int x, int n) {
        return (x << n) | (x >>> (32 - n));
    }

    // 使用示例
    public static void main(String[] args) {
        MD5Utils md5 = new MD5Utils();
        String input = "32f9f906017f12c2b8c608bbd33c4dc6";

        System.out.println("32位 MD5: " + md5.hash(input, false));
        System.out.println("16位 MD5: " + md5.hash(input, true));
    }
}
