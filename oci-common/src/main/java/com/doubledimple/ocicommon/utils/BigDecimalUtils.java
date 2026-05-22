package com.doubledimple.ocicommon.utils;

import java.math.BigDecimal;
import java.math.RoundingMode;

/**
 * @version 1.0.0
 * @ClassName BigDecimalUtils
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-11-30 16:09
 */
public class BigDecimalUtils {


    public static BigDecimal toCost(String s) {
        if (s == null || s.trim().isEmpty()) return BigDecimal.ZERO;
        try {
            return new BigDecimal(s.trim()).setScale(6, RoundingMode.HALF_UP);
        } catch (Exception e) {
            return BigDecimal.ZERO;
        }
    }
}
