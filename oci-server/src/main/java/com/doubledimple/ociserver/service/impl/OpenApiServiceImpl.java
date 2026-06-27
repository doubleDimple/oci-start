package com.doubledimple.ociserver.service.impl;

import cn.hutool.http.HttpRequest;
import cn.hutool.json.JSONUtil;
import com.alibaba.fastjson2.JSON;
import com.doubledimple.dao.entity.InstallApp;
import com.doubledimple.ocicommon.param.InstallAppNotify;
import com.doubledimple.ocicommon.param.InstanceHelpNotify;
import com.doubledimple.ocicommon.param.OpenInstanceNotify;
import com.doubledimple.ocicommon.param.OpenRegionNotify;
import com.doubledimple.ocicommon.param.ThirdApiParam;
import com.doubledimple.ociserver.service.OpenApiService;
import com.doubledimple.ociserver.service.SystemKVStoreService;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import com.doubledimple.ociserver.utils.SignatureUtil;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Lazy;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.util.CollectionUtils;

import javax.annotation.Resource;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static com.doubledimple.ociserver.service.SystemKVStoreService.SYSTEM_KV_STORE_ARM_RECORDS;

/**
 * @version 2.0.0 (Serverless)
 * @ClassName OpenApiServiceImpl
 * @Description  Cloudflare Worker
 * @Author doubleDimple
 */
@Service
@Slf4j
public class OpenApiServiceImpl implements OpenApiService {

    @Value("${cf.worker.domain:cf.worker.domain:https://oci-api-worker.lovele-cn.workers.dev}")
    private String cfDomain;

    @Resource
    private SystemKVStoreService systemKVStoreService;

    @Resource
    @Lazy
    private SystemConfigService systemConfigService;

    private static final String DEVICE_TOKEN_KEY = "SYSTEM_DEVICE_API_TOKEN";
    // 用于记录增量拉取的时间戳
    private static final String LAST_SYNC_TIME_KEY = "SYSTEM_KV_STORE_LAST_SYNC_TIME";

    /**
     * 每次请求前动态获取当前设备的唯一 Token
     */
    private String getDeviceToken() {
        String token = systemKVStoreService.getValue(DEVICE_TOKEN_KEY);
        if (StringUtils.isEmpty(token)) {
            log.warn("未找到设备注册 Token");
            return "";
        }
        return token;
    }

    @Override
    @Async
    public void notify(OpenInstanceNotify openInstanceNotify) {
        if (!systemConfigService.getChannelNotifyEnabled()) {
            log.debug("频道通知已关闭，跳过开机通知上报");
            return;
        }
        try {
            HttpRequest.post(cfDomain + "/api/notify")
                    .header("Authorization", "Bearer " + getDeviceToken())
                    .header("Content-Type", "application/json")
                    .body(JSONUtil.toJsonStr(openInstanceNotify))
                    .execute();
        } catch (Exception e) {
            log.debug("向 CF 发送开机通知失败, 原因为: {}", e.getMessage());
        }
    }

    @Override
    @Async
    public void help(InstanceHelpNotify instanceHelpNotify) {
        try {
            HttpRequest.post(cfDomain + "/api/help")
                    .header("Authorization", "Bearer " + getDeviceToken())
                    .header("Content-Type", "application/json")
                    .body(JSONUtil.toJsonStr(instanceHelpNotify))
                    .execute();
        } catch (Exception e) {
            log.error("向 CF 发送帮助通知失败", e);
        }
    }

    @Override
    public List<OpenRegionNotify> armRecords(OpenRegionNotify openRegionNotify) {
        List<OpenRegionNotify> openRegionNotifies = new ArrayList<>();
        try {
            String body = HttpRequest.post(cfDomain + "/api/armRecords")
                    .header("Authorization", "Bearer " + getDeviceToken())
                    .header("Content-Type", "application/json")
                    .body(JSONUtil.toJsonStr(openRegionNotify))
                    .execute()
                    .body();
            openRegionNotifies = JSON.parseArray(body, OpenRegionNotify.class);
        } catch (Exception e) {
            log.debug("请求远端增量 armRecords 失败: {}", e.getMessage());
        }
        return openRegionNotifies;
    }

    @Override
    @Transactional
    public List<OpenRegionNotify> armRecordsLocal(OpenRegionNotify openRegionNotify) {
        List<OpenRegionNotify> allRecords = new ArrayList<>();
        try {
            openRegionNotify.setLastNotifyTime(null);

            allRecords = armRecords(openRegionNotify);

            if (!CollectionUtils.isEmpty(allRecords)) {
                systemKVStoreService.saveOrUpdate(SYSTEM_KV_STORE_ARM_RECORDS, JSON.toJSONString(allRecords), "armRecords");
            } else {
                String existingValue = systemKVStoreService.getValue(SYSTEM_KV_STORE_ARM_RECORDS);
                if (StringUtils.isNotEmpty(existingValue)) {
                    allRecords = JSON.parseArray(existingValue, OpenRegionNotify.class);
                    log.warn("远端全量拉取为空，已降级使用本地缓存数据！");
                }
            }
        } catch (Exception e) {
            log.error("全量同步开机数据失败", e);
        }
        return allRecords;
    }

    @Override
    public InstallAppNotify installApp(InstallApp installApp) {
        InstallAppNotify installAppNotifyResult = new InstallAppNotify();
        try {
            String body = HttpRequest.post(cfDomain + "/api/installApp")
                    .header("Authorization", "Bearer " + getDeviceToken())
                    .header("Content-Type", "application/json")
                    .body(JSONUtil.toJsonStr(installApp))
                    .execute()
                    .body();
            installAppNotifyResult = JSON.parseObject(body, InstallAppNotify.class);
            log.debug("installApp 返回结果: {}", installAppNotifyResult);
        } catch (Exception e) {
            log.warn("installApp 打点发送至 CF 失败: {}", e.getMessage());
        }
        return installAppNotifyResult;
    }
}
