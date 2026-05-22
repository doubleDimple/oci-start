package com.doubledimple.ocicommon.constant;

public interface TaskService {

    public static final String DAILY_TASK = "dailyTask";

    public static final String IP_CHECK_TASK = "ipCheckTask";

    public static final String INSTANCE_SYNC_TASK = "instanceSync";

    public static final String INSTANCE_TRAFFIC_TASK = "instanceTraffic";

    public static final String LOAD_REGION_TASK = "loadRegion";

    public static final String CREATE_INSTANCE_TASK = "memoryTask";

    public static final String VERSION_CHECK_TASK = "versionCheck";

    public static final String ACCOUNT_LIVE_CHECK_TASK = "accountLiveCheck";

    public static final String PING_CON_TIME_TASK = "pingConnTimeJob";
    public static final String SSL_CERT_TASK = "sslCertJob";
    public static final String BOOT_INSTANCE_REFRESH_TASK = "bootInstanceRefreshJob";
    public static final String MONITOR_FLASH_HEARTBEAT_TASK = "monitorFlashHeartbeatJob";
    public static final String MONITOR_CHECK_OFFLINE_INSTANCE_TASK = "checkOfflineInstanceJob";

    public static final String MULTIPART_UPLOAD_CLEANUP_TASK = "multipartUploadCleanupJob";

    public static final String AI_CHAT_HISTORY_CLEANUP_TASK = "aiChatHistoryCleanupJob";
}
