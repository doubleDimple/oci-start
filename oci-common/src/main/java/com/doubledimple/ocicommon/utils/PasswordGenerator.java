package com.doubledimple.ocicommon.utils;

/**
 * @version 1.0.0
 * @ClassName PasswordGenerator
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-05-11 13:09
 */
import java.security.SecureRandom;

public class PasswordGenerator {

    public static final  String HELP_INIT_PASSWORD = "10086.fit";

    private static final String UPPERCASE = "ABCDEFGHIJKLMNOPQRSTUVWXYZ";
    private static final String LOWERCASE = "abcdefghijklmnopqrstuvwxyz";
    private static final String DIGITS = "0123456789";
    private static final String ALL_CHARS = UPPERCASE + LOWERCASE + DIGITS;
    private static final int PASSWORD_LENGTH = 10;

    public static String generatePassword() {
        return "OciStart2025";
    }

    public static String generatePassword2() {
        SecureRandom random = new SecureRandom();
        StringBuilder password = new StringBuilder(PASSWORD_LENGTH);

        // 确保至少包含一个大写字母、一个小写字母和一个数字
        password.append(UPPERCASE.charAt(random.nextInt(UPPERCASE.length())));
        password.append(LOWERCASE.charAt(random.nextInt(LOWERCASE.length())));
        password.append(DIGITS.charAt(random.nextInt(DIGITS.length())));

        // 填充剩余的字符
        for (int i = 3; i < PASSWORD_LENGTH; i++) {
            password.append(ALL_CHARS.charAt(random.nextInt(ALL_CHARS.length())));
        }

        // 打乱密码字符顺序
        return shuffleString(password.toString(), random);
    }

    private static String shuffleString(String input, SecureRandom random) {
        char[] characters = input.toCharArray();
        for (int i = characters.length - 1; i > 0; i--) {
            int j = random.nextInt(i + 1);
            char temp = characters[i];
            characters[i] = characters[j];
            characters[j] = temp;
        }
        return new String(characters);
    }

    public static void main(String[] args) {
        String password = generatePassword();
        System.out.println("Generated password: " + password);

        // 生成多个密码示例
        System.out.println("\n更多密码示例：");
        for (int i = 0; i < 5; i++) {
            System.out.println(generatePassword());
        }
    }
}
