package com.doubledimple.ociserver.utils;

import javax.servlet.http.HttpServletRequest;

/**
 * @version 1.0.0
 * @ClassName DesktopUtils
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-07-05 11:16
 */
public class DesktopUtils {


    public static boolean isMobileRequest(HttpServletRequest request) {
        String userAgent = request.getHeader("User-Agent");

        if (userAgent == null) {
            return false;
        }

        userAgent = userAgent.toLowerCase();

        // 检查移动端标识
        String[] mobileKeywords = {
                "mobile", "android", "iphone", "ipad", "ipod", "blackberry",
                "windows phone", "opera mini", "webos", "palm", "symbian"
        };

        for (String keyword : mobileKeywords) {
            if (userAgent.contains(keyword)) {
                return true;
            }
        }

        // 检查请求参数中是否明确指定移动端
        String mobileParam = request.getParameter("mobile");
        if ("true".equals(mobileParam) || "1".equals(mobileParam)) {
            return true;
        }

        // 检查请求路径中是否包含mobile标识
        String requestURI = request.getRequestURI();
        if (requestURI != null && requestURI.contains("/mobile/")) {
            return true;
        }

        return false;
    }
}
