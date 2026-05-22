package com.doubledimple.ocicommon.utils;

import lombok.Data;
import lombok.extern.slf4j.Slf4j;

import java.time.*;
import java.time.format.DateTimeFormatter;
import java.time.temporal.ChronoUnit;
import java.util.Calendar;
import java.util.Date;

/**
 * @author doubleDimple
 * @date 2024:10:25日 05:22
 */
@Slf4j
public class DateTimeUtils {

    // 默认的日期格式
    public static final String DEFAULT_DATE_FORMAT = "yyyy-MM-dd";
    public static final String DEFAULT_DATETIME_FORMAT = "yyyy-MM-dd HH:mm:ss";
    public static final String DEFAULT_TIME_FORMAT = "HH:mm:ss";

    // 使用UTC时区，因为OCI API使用UTC时间
    private static final ZoneId UTC_ZONE = ZoneId.of("UTC");

    // 系统默认时区，用于本地时间转换
    private static final ZoneId SYSTEM_ZONE = ZoneId.systemDefault();


    private static final ZoneId BEIJING_ZONE = ZoneId.of("Asia/Shanghai");

    // 常见日期时间格式
    private static final String[] patterns = {
            "yyyy-MM-dd",
            "yyyy/MM/dd",
            "yyyy.MM.dd",
            "yyyy-MM-dd HH:mm:ss",
            "yyyy/MM/dd HH:mm:ss",
            "yyyy.MM.dd HH:mm:ss",
            "yyyy-MM-dd'T'HH:mm:ss"
    };

    /**
     * 获取当前日期
     *
     * @return 当前日期 (yyyy-MM-dd)
     */
    public static String getCurrentDate() {
        return LocalDate.now().format(DateTimeFormatter.ofPattern(DEFAULT_DATE_FORMAT));
    }

    /**
     * 获取当前日期和时间
     *
     * @return 当前日期和时间 (yyyy-MM-dd HH:mm:ss)
     */
    public static String getCurrentDateTime() {
        return LocalDateTime.now().format(DateTimeFormatter.ofPattern(DEFAULT_DATETIME_FORMAT));
    }

    /**
     * 获取当前时间
     *
     * @return 当前时间 (HH:mm:ss)
     */
    public static String getCurrentTime() {
        return LocalTime.now().format(DateTimeFormatter.ofPattern(DEFAULT_TIME_FORMAT));
    }

    /**
     * 将字符串转为 LocalDate
     *
     * @param dateStr 日期字符串
     * @param format  日期格式
     * @return 转换后的 LocalDate
     */
    public static LocalDate parseDate(String dateStr, String format) {
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern(format);
        return LocalDate.parse(dateStr, formatter);
    }

    /**
     * 将字符串转为 LocalDateTime
     *
     * @param dateTimeStr 日期时间字符串
     * @param format      日期时间格式
     * @return 转换后的 LocalDateTime
     */
    public static LocalDateTime parseDateTime(String dateTimeStr, String format) {
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern(format);
        return LocalDateTime.parse(dateTimeStr, formatter);
    }

    /**
     * 将 LocalDate 转换为字符串
     *
     * @param date   LocalDate 对象
     * @param format 日期格式
     * @return 转换后的日期字符串
     */
    public static String formatDate(LocalDate date, String format) {
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern(format);
        return date.format(formatter);
    }

    public static String formatDate(LocalDate date) {
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern(DEFAULT_DATETIME_FORMAT);
        return date.format(formatter);
    }

    /**
     * 将 LocalDateTime 转换为字符串
     *
     * @param dateTime LocalDateTime 对象
     * @param format   日期时间格式
     * @return 转换后的日期时间字符串
     */
    public static String formatDateTime(LocalDateTime dateTime, String format) {
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern(format);
        return dateTime.format(formatter);
    }

    /**
     * LocalDateTime 转换为 Date
     *
     * @param dateTime LocalDateTime 对象
     * @return 转换后的 Date 对象
     */
    public static Date toDate(LocalDateTime dateTime) {
        ZonedDateTime zonedDateTime = dateTime.atZone(ZoneId.systemDefault());
        return Date.from(zonedDateTime.toInstant());
    }

    /**
     * Date 转换为 LocalDateTime
     *
     * @param date Date 对象
     * @return 转换后的 LocalDateTime 对象
     */
    public static LocalDateTime toLocalDateTime(Date date) {
        Instant instant = date.toInstant();
        return LocalDateTime.ofInstant(instant, ZoneId.systemDefault());
    }

    /**
     * 计算两个日期之间的天数差
     *
     * @param startDate 开始日期
     * @param endDate   结束日期
     * @return 天数差
     */
    public static long daysBetween(LocalDate startDate, LocalDate endDate) {
        return ChronoUnit.DAYS.between(startDate, endDate);
    }

    /**
     * 计算两个日期字符串之间的天数差
     * 支持格式：yyyy-MM-dd / yyyy/MM/dd / yyyy.MM.dd
     *
     * @param start 开始日期字符串
     * @param end   结束日期字符串
     * @return 天数差
     */
    public static long daysBetween(String start, String end) {
        try {
            LocalDate startDate = parseDate(start);
            LocalDate endDate = parseDate(end);
            return ChronoUnit.DAYS.between(startDate, endDate);
        } catch (Exception e) {
            return 0L;
        }
    }

    public static long daysBetweenCurrent(String start) {
        try {
            LocalDate startDate = parseToLocalDate(start);
            LocalDate endDate = LocalDate.now();
            return ChronoUnit.DAYS.between(startDate, endDate);
        } catch (Exception e) {
            return 0L;
        }
    }

    /**
     * 将日期字符串解析为 LocalDate（自动识别常见格式）
     */
    private static LocalDate parseDate(String dateStr) {
        return LocalDate.parse(dateStr, DateTimeFormatter.ISO_LOCAL_DATE);
    }

    private static LocalDate parseToLocalDate(String input) {

        for (String p : patterns) {
            try {
                DateTimeFormatter f = DateTimeFormatter.ofPattern(p);
                if (p.contains("HH")) {
                    return LocalDateTime.parse(input, f).toLocalDate();
                } else {
                    return LocalDate.parse(input, f);
                }
            } catch (Exception ignored) {}
        }

        throw new IllegalArgumentException("无法解析日期：" + input);
    }

    public static LocalDate extractDate(String dateTimeStr) {
        // 自动截取 yyyy-MM-dd
        String date = dateTimeStr.substring(0, 10);
        return LocalDate.parse(date);
    }

    /**
     * 计算两个日期时间之间的小时差
     *
     * @param startDateTime 开始日期时间
     * @param endDateTime   结束日期时间
     * @return 小时差
     */
    public static long hoursBetween(LocalDateTime startDateTime, LocalDateTime endDateTime) {
        return ChronoUnit.HOURS.between(startDateTime, endDateTime);
    }

    /**
     * 判断给定日期是否在当前日期之前
     *
     * @param date 要判断的日期
     * @return true 表示在当前日期之前，false 表示之后
     */
    public static boolean isBeforeToday(LocalDate date) {
        return date.isBefore(LocalDate.now());
    }

    /**
     * 判断给定日期是否在当前日期之后
     *
     * @param date 要判断的日期
     * @return true 表示在当前日期之后，false 表示之前
     */
    public static boolean isAfterToday(LocalDate date) {
        return date.isAfter(LocalDate.now());
    }

    /**
     * 获取某天的开始时间 (00:00:00)
     *
     * @param date LocalDate 对象
     * @return 对应的 LocalDateTime (当天的 00:00:00)
     */
    public static LocalDateTime getStartOfDay(LocalDate date) {
        return date.atStartOfDay();
    }

    /**
     * 获取某天的结束时间 (23:59:59)
     *
     * @param date LocalDate 对象
     * @return 对应的 LocalDateTime (当天的 23:59:59)
     */
    public static LocalDateTime getEndOfDay(LocalDate date) {
        return date.atTime(LocalTime.MAX);
    }

    /**
     * 将秒转换为格式化时间 (HH:mm:ss)
     *
     * @param seconds 秒数
     * @return 格式化后的时间字符串
     */
    public static String formatSecondsToTime(long seconds) {
        long hours = seconds / 3600;
        long minutes = (seconds % 3600) / 60;
        long secs = seconds % 60;
        return String.format("%02d:%02d:%02d", hours, minutes, secs);
    }

    /**
     * 将时间戳转换为日期时间字符串，使用默认格式 (yyyy-MM-dd HH:mm:ss)
     *
     * @param timestamp 时间戳(毫秒)
     * @return 格式化后的日期时间字符串
     */
    public static String formatTimestamp(long timestamp) {
        return formatTimestamp(timestamp, DEFAULT_DATETIME_FORMAT);
    }

    /**
     * 将时间戳转换为指定格式的日期时间字符串
     *
     * @param timestamp 时间戳(毫秒)
     * @param format   日期时间格式
     * @return 格式化后的日期时间字符串
     */
    public static String formatTimestamp(long timestamp, String format) {
        LocalDateTime dateTime = LocalDateTime.ofInstant(
                Instant.ofEpochMilli(timestamp),
                ZoneId.systemDefault()
        );
        return formatDateTime(dateTime, format);
    }

    /**
     * 将时间戳转换为LocalDateTime对象
     *
     * @param timestamp 时间戳(毫秒)
     * @return LocalDateTime对象
     */
    public static LocalDateTime timestampToLocalDateTime(long timestamp) {
        return LocalDateTime.ofInstant(
                Instant.ofEpochMilli(timestamp),
                ZoneId.systemDefault()
        );
    }

    /**
     * 将LocalDateTime转换为时间戳(毫秒)
     *
     * @param localDateTime LocalDateTime对象
     * @return 时间戳(毫秒)
     */
    public static long localDateTimeToTimestamp(LocalDateTime localDateTime) {
        return localDateTime.atZone(ZoneId.systemDefault())
                .toInstant()
                .toEpochMilli();
    }


    /**
    * 获取亚洲时间
    */
    public static String genAsiaTime(){
        ZonedDateTime asiaTime = ZonedDateTime.now(ZoneId.of("Asia/Shanghai"));
        String formattedAsiaTime = asiaTime.format(DateTimeFormatter.ofPattern(DEFAULT_DATETIME_FORMAT));
        return formattedAsiaTime;
    }

    /**
     * 将本地LocalDateTime转换为UTC的Date
     */
    public static Date toUTCDate(LocalDateTime localDateTime) {
        return Date.from(localDateTime
                .atZone(SYSTEM_ZONE)    // 先转换为系统时区
                .withZoneSameInstant(UTC_ZONE)  // 转换为UTC时区
                .toInstant());
    }

    /**
     * 获取当天开始时间（UTC）
     */
    public static Date getUTCStartOfDayUtc(LocalDate date) {
        return toUTCDate(date.atStartOfDay());
    }

    /**
     * 获取当前时间对应月份的1号的开始时间（本地时区）
     *
     * @return 当月1号的Date对象
     */
    public static Date getFirstDayOfCurrentMonth() {
        LocalDate firstDayOfMonth = LocalDate.now().withDayOfMonth(1);
        LocalDateTime startOfFirstDay = firstDayOfMonth.atStartOfDay();
        return toDate(startOfFirstDay);
    }

    /**
     * 获取当前时间对应月份的1号的开始时间（UTC）
     *
     * @return 当月1号UTC零点对应的Date对象
     */
    public static Date getFirstDayOfCurrentMonthUtc() {
        LocalDate firstDayOfMonth = LocalDate.now();
        firstDayOfMonth = firstDayOfMonth.withDayOfMonth(1);
        return getUTCStartOfDayUtc(firstDayOfMonth);
    }

    /**
     * 获取当天结束时间（UTC）
     */
    public static Date getUTCEndOfDayUtc(LocalDate date) {
        return toUTCDate(date.atTime(LocalTime.MAX));
    }

    /**
     * 将UTC时间转换为本地时间
     */
    public static LocalDateTime toLocalDateTimeUTC(Date utcDate) {
        return LocalDateTime.ofInstant(utcDate.toInstant(), SYSTEM_ZONE);
    }

    /**
     * 获取当前月份第一天的UTC零点时间
     * @return 当月第一天的UTC零点时间
     */
    public static Date getCurrentMonthFirstDayUtc() {
        // 获取当前日期
        LocalDate today = LocalDate.now();
        // 获取当前月份的第一天
        LocalDate firstDayOfMonth = today.withDayOfMonth(1);
        // 转换为UTC时间
        return getUTCStartOfDayUtc(firstDayOfMonth);
    }

    // ==================== 时区相关时间范围检查功能 ====================

    /**
     * 将24小时制的小时转换为标准时间格式
     *
     * @param hour 24小时制的小时 (0-23)
     * @return 格式化的标准时间字符串 (HH:mm)
     */
    public static String getStandardTime(int hour) {
        if (hour < 0 || hour > 23) {
            throw new IllegalArgumentException("小时必须在0-23范围内");
        }

        LocalTime time = LocalTime.of(hour, 0);
        return time.format(DateTimeFormatter.ofPattern("HH:mm"));
    }

    /**
     * 检查当前时间是否在指定小时的前后5分钟范围内（系统默认时区）
     *
     * @param targetHour 目标小时 (0-23)
     * @return 是否在范围内
     */
    public static boolean isWithinTimeRangeSimple(int targetHour) {
        return isWithinTimeRange(targetHour, 5, SYSTEM_ZONE);
    }

    /**
     * 检查当前时间是否在指定小时的前后指定分钟范围内（系统默认时区）
     *
     * @param targetHour 目标小时 (0-23)
     * @param rangeMinutes 范围分钟数
     * @return 是否在范围内
     */
    public static boolean isWithinTimeRange(int targetHour, int rangeMinutes) {
        return isWithinTimeRange(targetHour, rangeMinutes, SYSTEM_ZONE);
    }


    public static boolean isWithinTimeRange(int targetHour){
        return isWithinTimeRange(targetHour,5, BEIJING_ZONE);
    }
    /**
     * 检查指定时区的当前时间是否在指定小时的前后指定分钟范围内
     *
     * @param targetHour 目标小时 (0-23)
     * @param rangeMinutes 范围分钟数
     * @param zoneId 时区
     * @return 是否在范围内
     */
    public static boolean isWithinTimeRange(int targetHour, int rangeMinutes, ZoneId zoneId) {
        if (targetHour < 0 || targetHour > 23) {
            throw new IllegalArgumentException("小时必须在0-23范围内");
        }
        if (rangeMinutes < 0) {
            throw new IllegalArgumentException("范围分钟数必须大于等于0");
        }

        LocalTime now = LocalTime.now(zoneId);
        LocalTime targetTime = LocalTime.of(targetHour, 0);

        return isTimeWithinRange(now, targetTime, rangeMinutes);
    }

    /**
     * 检查指定时间是否在目标小时的前后指定分钟范围内
     *
     * @param checkTime 要检查的时间
     * @param targetHour 目标小时 (0-23)
     * @param rangeMinutes 范围分钟数
     * @return 是否在范围内
     */
    public static boolean isWithinTimeRange(LocalTime checkTime, int targetHour, int rangeMinutes) {
        if (targetHour < 0 || targetHour > 23) {
            throw new IllegalArgumentException("小时必须在0-23范围内");
        }
        if (rangeMinutes < 0) {
            throw new IllegalArgumentException("范围分钟数必须大于等于0");
        }

        LocalTime targetTime = LocalTime.of(targetHour, 0);
        return isTimeWithinRange(checkTime, targetTime, rangeMinutes);
    }

    /**
     * 核心方法：判断两个时间是否在指定分钟范围内
     *
     * @param currentTime 当前时间
     * @param targetTime 目标时间
     * @param rangeMinutes 范围分钟数
     * @return 是否在范围内
     */
    private static boolean isTimeWithinRange(LocalTime currentTime, LocalTime targetTime, int rangeMinutes) {
        // 计算时间差（分钟）
        long minutesDiff = Math.abs(ChronoUnit.MINUTES.between(targetTime, currentTime));

        // 处理跨午夜的情况
        // 例如：目标时间23:00，当前时间00:02，实际差距应该是62分钟，但跨天后需要特殊处理
        long altDiff = 1440 - minutesDiff; // 1440 = 24小时 * 60分钟
        minutesDiff = Math.min(minutesDiff, altDiff);

        return minutesDiff <= rangeMinutes;
    }

    /**
     * 检查亚洲/上海时区的当前时间是否在指定小时范围内
     *
     * @param targetHour 目标小时 (0-23)
     * @param rangeMinutes 范围分钟数
     * @return 是否在范围内
     */
    public static boolean isWithinTimeRangeAsia(int targetHour, int rangeMinutes) {
        return isWithinTimeRange(targetHour, rangeMinutes, ZoneId.of("Asia/Shanghai"));
    }

    /**
     * 检查UTC时区的当前时间是否在指定小时范围内
     *
     * @param targetHour 目标小时 (0-23)
     * @param rangeMinutes 范围分钟数
     * @return 是否在范围内
     */
    public static boolean isWithinTimeRangeUTC(int targetHour, int rangeMinutes) {
        return isWithinTimeRange(targetHour, rangeMinutes, UTC_ZONE);
    }

    public static String formatDate(Date date) {
        if (date == null) {
            return null;
        }
        LocalDateTime localDateTime = toLocalDateTime(date);
        return formatDateTime(localDateTime, DEFAULT_DATETIME_FORMAT);
    }

    /**
     * 获取系统当前时间，并根据与亚洲/上海时区的差异，返回适合前端展示的格式。
     *
     * 示例1：系统时区为 Asia/Shanghai
     *   2025-11-22 14:20:55 (Asia/Shanghai)
     *
     * 示例2：系统时区为 UTC
     *   系统时间：2025-11-22 06:20:55 (UTC) | 北京时间：2025-11-22 14:20:55 (Asia/Shanghai)
     *
     * @return 格式化后的可读时间字符串
     */
    public static String getReadableZoneTime() {
        ZonedDateTime now = ZonedDateTime.now();
        ZoneId systemZone = now.getZone();
        ZoneId shanghaiZone = ZoneId.of("Asia/Shanghai");

        // 时间格式化器
        DateTimeFormatter formatter = DateTimeFormatter.ofPattern(DEFAULT_DATETIME_FORMAT);

        // 格式化系统时区时间
        String systemTimeStr = now.format(formatter) + " (" + systemZone + ")";

        // 格式化北京时间
        String shanghaiTimeStr =
                now.withZoneSameInstant(shanghaiZone).format(formatter) + " (" + shanghaiZone + ")";

        // 如果系统就是北京时间
        if (systemZone.equals(shanghaiZone)) {
            return shanghaiTimeStr;
        }

        // 系统不是北京时间 → 展示两个
        return "系统时间：" + systemTimeStr + " | 北京时间：" + shanghaiTimeStr;
    }

    /**
     * 判断当前系统时间（小时）是否在指定时间范围内（不支持跨天）
     *
     * 规则：
     *  - null / "" / "null" → 返回 true
     *  - 必须是 "start-end" 格式
     *  - start < end（不支持跨天）
     *  - 0-24 表示全天
     *
     * 示例：
     *  "1-8"  true/false
     *  "0-24" true
     *  "15-5" false（不支持跨天）
     */
    public static boolean isCurrentHourInRange(String hourRange) {

        // null / "" / "null" 都视为 true
        if (hourRange == null || hourRange.trim().isEmpty() || "null".equalsIgnoreCase(hourRange.trim())) {
            return true;
        }

        hourRange = hourRange.trim();

        // 必须包含 "-"
        if (!hourRange.contains("-")) {
            return false;
        }

        String[] parts = hourRange.split("-");
        if (parts.length != 2) {
            return false;
        }

        try {
            int start = Integer.parseInt(parts[0].trim());
            int end = Integer.parseInt(parts[1].trim());

            // 必须合法
            if (start < 0 || start > 23 || end < 1 || end > 24) {
                return false;
            }

            // 不支持跨天 + 不支持 start == end
            if (start >= end) {
                return false;
            }

            int now = LocalTime.now().getHour();

            // 0-24 全天
            if (start == 0 && end == 24) {
                return true;
            }

            // 普通范围：start <= now < end
            return now >= start && now < end;

        } catch (Exception e) {
            //todo.如果出现异常,暂时忽略它,
            return true;
        }
    }

    public static Date getStartOfYesterday() {
        Calendar cal = Calendar.getInstance();
        cal.add(Calendar.DATE, -1);
        cal.set(Calendar.HOUR_OF_DAY, 0);
        cal.set(Calendar.MINUTE, 0);
        cal.set(Calendar.SECOND, 0);
        cal.set(Calendar.MILLISECOND, 0);
        return cal.getTime();
    }

    public static Date getStartOfToday() {
        Calendar cal = Calendar.getInstance();
        cal.set(Calendar.HOUR_OF_DAY, 0);
        cal.set(Calendar.MINUTE, 0);
        cal.set(Calendar.SECOND, 0);
        cal.set(Calendar.MILLISECOND, 0);
        return cal.getTime();
    }

    // ======================== OCI 费用统计专用工具 开始============================

    /**
     * 用于返回 OCI API 所需的 UTC 开始和结束时间
     */
    @Data
    public static class DateRange {
        private Date startUtc;
        private Date endUtc;

        public DateRange(Date start, Date end) {
            this.startUtc = start;
            this.endUtc = end;
        }
    }

    /**
     * 将 LocalDate 转为该天的 UTC 开始时间 (00:00:00)
     */
    public static Date toUtcStart(LocalDate date) {
        return Date.from(
                date.atStartOfDay(ZoneOffset.UTC).toInstant()
        );
    }

    /**
     * 将 LocalDate 转为该天的 UTC 结束时间 (23:59:59.999)
     */
    public static Date toUtcEnd(LocalDate date) {
        LocalDate next = date.plusDays(1);
        return Date.from(
                next.atStartOfDay(ZoneOffset.UTC).toInstant()
        );
    }

    /**
     * 自动解析日期字符串 → LocalDate
     */
    public static LocalDate parseToLocalDateSmart(String input) {
        String[] patterns = {
                "yyyy-MM-dd",
                "yyyy/MM/dd",
                "yyyy.MM.dd",
                "yyyy-MM-dd HH:mm:ss",
                "yyyy/MM/dd HH:mm:ss",
                "yyyy.MM.dd HH:mm:ss",
                "yyyy-MM-dd'T'HH:mm:ss"
        };

        for (String p : patterns) {
            try {
                DateTimeFormatter f = DateTimeFormatter.ofPattern(p);
                if (p.contains("HH")) {
                    return LocalDateTime.parse(input, f).toLocalDate();
                } else {
                    return LocalDate.parse(input, f);
                }
            } catch (Exception ignored) {}
        }

        throw new IllegalArgumentException("无法解析日期: " + input);
    }

    /**
     * 昨日（UTC）
     */
    public static DateRange getYesterdayUtcRange() {
        LocalDate yesterday = LocalDate.now().minusDays(1);
        return new DateRange(
                toUtcStart(yesterday),
                toUtcEnd(yesterday)
        );
    }

    /**
     * 今日（UTC）
     */
    public static DateRange getTodayUtcRange() {
        LocalDate today = LocalDate.now();
        return new DateRange(
                toUtcStart(today),
                toUtcEnd(today)
        );
    }

    /**
     * 上月整个时间范围（UTC）
     */
    public static DateRange getLastMonthUtcRange() {
        LocalDate now = LocalDate.now();

        LocalDate first = now.minusMonths(1).withDayOfMonth(1);
        LocalDate last = now.minusMonths(1).withDayOfMonth(now.minusMonths(1).lengthOfMonth());

        return new DateRange(
                toUtcStart(first),
                toUtcEnd(last)
        );
    }

    /**
     * 本月截至今天的范围（UTC）
     */
    public static DateRange getCurrentMonthUtcRange() {
        LocalDate now = LocalDate.now();

        LocalDate first = now.withDayOfMonth(1);
        LocalDate last = now; // 截止今天

        return new DateRange(
                toUtcStart(first),
                toUtcEnd(last)
        );
    }

    /**
     * 自定义日期范围（UTC）
     */
    public static DateRange getCustomUtcRange(String startStr, String endStr) {
        LocalDate s = parseToLocalDateSmart(startStr);
        LocalDate e = parseToLocalDateSmart(endStr);
        return new DateRange(
                toUtcStart(s),
                toUtcEnd(e)
        );
    }
    // ======================== OCI 费用统计专用工具 开始============================

    public static String calculateDaysFromNow(Date date) {
        if (date == null) {
            return "0";
        }
        LocalDateTime startDateTime = date.toInstant()
                .atZone(ZoneId.systemDefault())
                .toLocalDateTime();

        LocalDateTime now = LocalDateTime.now();
        Duration duration = Duration.between(startDateTime, now);
        long seconds = duration.getSeconds();
        if (seconds <= 0) {
            return "0";
        }
        final long SECONDS_PER_DAY = 24 * 60 * 60;
        return ((seconds + SECONDS_PER_DAY - 1) / SECONDS_PER_DAY) +"";
    }


    public static void main(String[] args) {
        final boolean withinTimeRangeSimple = isWithinTimeRangeSimple(5);
        System.out.println("是否在9点前5分钟内："+withinTimeRangeSimple);
    }



}
