package com.doubledimple.ociserver.service.impl;

import com.doubledimple.dao.entity.CloudSshConn;
import com.doubledimple.dao.entity.InstanceDetails;
import com.doubledimple.dao.entity.Tenant;
import com.doubledimple.dao.repository.CloudSshConnRepository;
import com.doubledimple.dao.repository.TenantRepository;
import com.doubledimple.ocicommon.param.ScriptResult;
import com.doubledimple.ocicommon.template.MessageTemplate;
import com.doubledimple.ocicommon.utils.JschUtils;
import com.doubledimple.ociserver.pojo.enums.ArchitectureEnum;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.pojo.request.DDRequest;
import com.doubledimple.ocicommon.param.ApiResponse;
import com.doubledimple.ociserver.service.QuickDdService;
import com.doubledimple.ociserver.service.message.factory.MessageFactory;
import com.doubledimple.ociserver.service.oracle.OracleInstanceService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;
import org.springframework.web.servlet.mvc.method.annotation.SseEmitter;

import javax.annotation.Resource;
import java.util.Optional;
import java.util.concurrent.Executors;

import static com.doubledimple.ocicommon.utils.JschUtils.AMD_DD_SCRIPT;
import static com.doubledimple.ocicommon.utils.JschUtils.DD_SCRIPT_PARAM;
import static com.doubledimple.ocicommon.utils.JschUtils.DEBIAN_INSTALL_SCRIPT;

/**
 * @version 1.0.0
 * @ClassName QuickDdServiceImpl
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-10-25 10:50
 */
@Service
@Slf4j
public class QuickDdServiceImpl implements QuickDdService {

    @Resource
    CloudSshConnRepository cloudSshConnRepository;

    @Resource
    OracleInstanceService oracleInstanceService;

    @Resource
    TenantRepository tenantRepository;

    @Resource
    MessageFactory messageFactory;

    @Override
    @Transactional
    public ApiResponse quickDd(DDRequest request) {
        String instanceId = request.getInstanceId();
        String osType = request.getOsType();
        String osVersion = request.getOsVersion();
        String ddPassword = request.getDdPassword();

        InstanceDetails instance = oracleInstanceService.getInstanceById(Long.valueOf(instanceId));
        if (instance == null) {
            return ApiResponse.error("未找到实例配置");
        }

        Optional<CloudSshConn> byInstanceId = cloudSshConnRepository.findByInstanceId(instance.getInstanceId());
        if (!byInstanceId.isPresent()) {
            return ApiResponse.error("获取SSH配置失败：请重新设置密码");
        }
        Optional<Tenant> byId = tenantRepository.findById(instance.getTenantId());
        Tenant tenant = byId.get();
        CloudSshConn cloudSshConn = byInstanceId.get();
        String publicIps = instance.getPublicIps();
        String username = cloudSshConn.getUsername();
        Integer port = cloudSshConn.getPort();
        String password = cloudSshConn.getPassword();

        try {
            // 发送安装中通知
            String installingMsg = String.format(MessageTemplate.MESSAGE_DD_INSTALLING_TEMPLATE,
                    tenant.getUserName(),
                    instance.getDisplayName(),
                    publicIps,
                    osType,
                    osVersion);
            messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(installingMsg);

            // 构建DD脚本命令
            String command;
            if ("debian".equalsIgnoreCase(osType)) {
                // osVersion 即 Debian 版本号，例如 "12"、"11"
                command = String.format(DEBIAN_INSTALL_SCRIPT, osVersion, ddPassword);
            } else {
                command = String.format(DD_SCRIPT_PARAM, ddPassword, ddPassword, osType, osVersion);
            }

            // 执行DD脚本
            ScriptResult ddScript = JschUtils.executeDDScript(publicIps, username, password, port, command);

            if (!ddScript.isSuccess()) {
                // 发送失败通知
                String failedMsg = String.format(MessageTemplate.MESSAGE_DD_FAILED_TEMPLATE,
                        tenant.getUserName(),
                        instance.getDisplayName(),
                        publicIps,
                        osType,
                        osVersion,
                        "脚本执行异常");
                messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(failedMsg);

                return ApiResponse.error("执行DD脚本失败：");
            }

            // 更新SSH连接密码
            cloudSshConn.setPassword(ddPassword);
            cloudSshConnRepository.save(cloudSshConn);

            // 发送成功通知
            String successMsg = String.format(MessageTemplate.MESSAGE_DD_SUCCESS_TEMPLATE,
                    tenant.getUserName(),
                    instance.getDisplayName(),
                    publicIps,
                    osType,
                    osVersion,
                    ddPassword);
            messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(successMsg);

            return ApiResponse.success("DD系统安装命令已下发");

        } catch (Exception e) {
            // 发送异常通知
            try {
                String exceptionMsg = String.format(MessageTemplate.MESSAGE_DD_FAILED_TEMPLATE,
                        tenant.getUserName(),
                        instance.getDisplayName(),
                        instance.getPublicIps(),
                        osType,
                        osVersion,
                        e.getMessage() != null ? e.getMessage() : "系统异常");
                messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(exceptionMsg);
            } catch (Exception ex) {
                log.error("发送DD异常通知失败", ex);
            }

            log.error("执行DD脚本异常", e);
            return ApiResponse.error("执行DD脚本异常：" + e.getMessage());
        }
    }

    @Override
    public SseEmitter quickDdSse(DDRequest request) {
        SseEmitter emitter = new SseEmitter(60 * 60 * 1000L); // 1 小时

        Executors.newSingleThreadExecutor().submit(() -> {

            String instanceId = request.getInstanceId();
            String osType = request.getOsType();
            String osVersion = request.getOsVersion();
            String ddPassword = request.getDdPassword();

            InstanceDetails instance = oracleInstanceService.getInstanceById(Long.valueOf(instanceId));
            if (instance == null) {
                sendAndClose(emitter, "error", "未找到实例配置");
                return;
            }

            Optional<CloudSshConn> byInstanceId = cloudSshConnRepository.findByInstanceId(instance.getInstanceId());
            if (!byInstanceId.isPresent()) {
                sendAndClose(emitter, "error", "获取SSH配置失败：请重新设置密码");
                return;
            }

            Tenant tenant = tenantRepository.findById(instance.getTenantId()).get();
            CloudSshConn cloudSshConn = byInstanceId.get();
            String publicIp = instance.getPublicIps();
            String username = cloudSshConn.getUsername();
            Integer port = cloudSshConn.getPort();
            String password = cloudSshConn.getPassword();

            String architecture = instance.getArchitecture();

            try {
                // 发送开始消息（Telegram）
                messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(
                        String.format(MessageTemplate.MESSAGE_DD_INSTALLING_TEMPLATE,
                                tenant.getUserName(), instance.getDisplayName(), publicIp, osType, osVersion)
                );

                // 构建脚本命令
                String command;

                if (architecture.equals(ArchitectureEnum.AMD.getType())){
                    command = String.format(AMD_DD_SCRIPT, ddPassword, ddPassword, osType, osVersion);
                }else {
                    command = String.format(DD_SCRIPT_PARAM, ddPassword, ddPassword, osType, osVersion);
                }

                //使用支持实时输出推送的 DD 执行函数
                JschUtils.executeDDScriptWithSse(publicIp, username, password, port, command, emitter);

                // 重装成功（SSH 断线前执行）
                //cloudSshConn.setPassword(ddPassword);
                //cloudSshConnRepository.save(cloudSshConn);

                messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(
                        String.format(MessageTemplate.MESSAGE_DD_SUCCESS_TEMPLATE,
                                tenant.getUserName(), instance.getDisplayName(), publicIp, osType, osVersion, ddPassword,password)
                );

                sendAndClose(emitter, "success", "✅ DD系统安装命令执行完成，如果未自动重启,请手动重启后,等待15分钟左右尝试登录");

            } catch (Exception e) {
                log.error("执行DD脚本异常", e.getMessage(),e);

                messageFactory.getType(MessageEnum.TELEGRAM).sendMessageTemplate(
                        String.format(MessageTemplate.MESSAGE_DD_FAILED_TEMPLATE,
                                tenant.getUserName(), instance.getDisplayName(), publicIp, osType, osVersion, e.getMessage())
                );

                sendAndClose(emitter, "error", "❌ 执行异常：" + e.getMessage());
            }
        });

        return emitter;
    }

    private void sendEvent(SseEmitter emitter, String event, String msg) {
        try {
            emitter.send(SseEmitter.event().name(event).data(msg));
        } catch (Exception ignored) {

        }
    }

    private void sendAndClose(SseEmitter emitter, String event, String msg) {
        sendEvent(emitter, event, msg);
        try {emitter.complete();} catch (Exception ignored) {}
    }

}
