package com.doubledimple.ociserver.config.context;


/**
 * @version 1.0.0
 * @ClassName UserContext
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-12-21 16:53
 */
public class UserContext {
    private static final ThreadLocal<String> USER_HOLDER = new ThreadLocal<>();

    public static void setUsername(String username) {
        USER_HOLDER.set(username);
    }

    public static String getUsername() {
        return USER_HOLDER.get();
    }

    public static void clear() {
        USER_HOLDER.remove();
    }
}
