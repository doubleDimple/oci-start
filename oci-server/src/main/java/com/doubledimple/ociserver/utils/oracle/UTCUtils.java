package com.doubledimple.ociserver.utils.oracle;

import java.time.Instant;
import java.time.LocalDate;
import java.time.LocalTime;
import java.time.ZoneId;
import java.time.ZoneOffset;

/**
 * @version 1.0.0
 * @ClassName UTCUtils
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-06-29 16:29
 */
public class UTCUtils {

    // UTC时区（与Oracle数据库时间一致）
    private static final ZoneId UTC_ZONE = ZoneOffset.UTC;

    /**
     * 获取当天的开始和结束时间（UTC时区，与Oracle返回时间一致）
     * @return [开始时间, 结束时间]
     */
    public static Instant[] getTodayRange() {
        Instant now = Instant.now();
        LocalDate today = now.atZone(UTC_ZONE).toLocalDate();

        Instant start = today.atStartOfDay(UTC_ZONE).toInstant();
        Instant end = today.atTime(LocalTime.MAX).atZone(UTC_ZONE).toInstant();

        return new Instant[]{start, end};
    }

    /**
     * 获取指定时间当天的开始和结束时间（UTC时区）
     * @param instant 指定时间
     * @return [开始时间, 结束时间]
     */
    public static Instant[] getDayRange(Instant instant) {
        LocalDate date = instant.atZone(UTC_ZONE).toLocalDate();

        Instant start = date.atStartOfDay(UTC_ZONE).toInstant();
        Instant end = date.atTime(LocalTime.MAX).atZone(UTC_ZONE).toInstant();

        return new Instant[]{start, end};
    }

    // 测试
    public static void main(String[] args) {
        Instant[] range = getTodayRange();
        System.out.println("开始时间: " + range[0]);
        System.out.println("结束时间: " + range[1]);
    }
}
