package com.doubledimple.ocicommon.cache;

/**
 * @version 1.0.0
 * @ClassName CacheConstants
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-03-18 14:56
 */
public class CacheConstants {

    public static final String OCI_IP_RANGES_CACHE = "ociIpRangesCache";

    public static final String ALL_IP_RANGES_KEY = "allIpRanges";
    /**
    * oci 用户信息的缓存,缓存5min
    */
    public static final String OCI_USER_LIST_KEY = "ociUserList";

    /**
    * 活跃用户数量
    */
    public static final String APP_INSTALL_ACTIVE_KEY = "appInstallActive";
    public static final String OCI_USER_LIST_CACHE = "ociUserListCache_";

    /**
    * OCI network
    */
    public static final String OCI_NET_WORK_KEY = "ociNetWork";
    public static final String OCI_NET_WORK_CACHE = "ociNetWorkCache_";

    /**
    * 救援缓存
    */
    private final static String HELP_CACHE = "HELP_CACHE_KEY";

    private final static String HELP_CACHE_KEY = "HELP_CACHE_";

    //开机数量缓存
    public static final String BOOT_COUNT_KEY = "BOOT_COUNT_KEY";

    //github stars 缓存key
    public static final String GITHUB_STARS_KEY = "GITHUB_STARS_KEY";


    // 缓存集合，方便批量配置
    public static final String[] CACHE_NAMES = {
           OCI_IP_RANGES_CACHE,HELP_CACHE,OCI_USER_LIST_KEY,APP_INSTALL_ACTIVE_KEY,BOOT_COUNT_KEY,GITHUB_STARS_KEY
    };
}
