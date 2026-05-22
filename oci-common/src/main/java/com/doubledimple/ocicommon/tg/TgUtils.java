package com.doubledimple.ocicommon.tg;

/**
 * @version 1.0.0
 * @ClassName TgUtils
 * @Description TODO
 * @Author doubleDimple
 * @Date 2026-01-03 17:54
 */
public class TgUtils {


    public static String getMaskedDisplayName(String text) {
        if (text == null || text.length() <= 1) {
            return text;
        }
        String first = text.substring(0, 1);
        String middle = text.substring(1, text.length() - 1);
        String last = text.substring(text.length() - 1);
        return first + "<tg-spoiler>" + middle + "</tg-spoiler>" + last;
    }
}
