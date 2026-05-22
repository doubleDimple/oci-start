package com.doubledimple.ociserver.service.message;

import com.doubledimple.dao.entity.SystemConfig;
import com.doubledimple.dao.repository.SystemConfigRepository;
import com.doubledimple.ocicommon.bark.BarkPush;
import com.doubledimple.ociserver.pojo.domain.dto.OracleInstanceDetail;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.pojo.request.BarkConfig;
import lombok.extern.slf4j.Slf4j;
import org.springframework.stereotype.Service;

import javax.annotation.Resource;
import java.util.Optional;

/**
 * @version 1.0.0
 * @ClassName BarkMessageService
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-05-04 22:47
 */
@Service
@Slf4j
public class BarkMessageService implements MessageService {

    @Resource
    SystemConfigRepository systemConfigRepository;

    @Override
    public void sendMessage(OracleInstanceDetail instanceData) {

    }

    @Override
    public void sendMessageTemplate(String message) {

    }

    @Override
    public void sendMessageTemplateText(String message) {

    }

    @Override
    public void sendMessageTemplateText(String message, Boolean consoleFlag) {

    }

    @Override
    public void sendMessageTemplateTest(String message) {
        BarkConfig barkConfig = getBarkConfig();
        if (barkConfig == null){
            log.warn("BARK 无法推送消息,消息未配置");
            return;
        }

        final String url = barkConfig.getUrl();
        final String deviceKey = barkConfig.getDeviceKey();

        try {
            BarkPush pusher = new BarkPush(url, deviceKey);
            pusher.simpleWithResp("Oci-Start BARK通知测试消息");
        } catch (Exception e) {
            log.debug("bark消息发送失败");
        }
    }

    @Override
    public MessageEnum getMessageType() {
        return MessageEnum.BARK;
    }

    @Override
    public void sendErrorMessage(String s) {

    }

    @Override
    public void sendMyChannel(String message) {

    }

    @Override
    public void sendVerificationCodeMessage(String userName, String verificationCode) {

    }

    public BarkConfig getBarkConfig() {
        BarkConfig config = new BarkConfig();

        Optional<SystemConfig> url = systemConfigRepository.findByKey("bark.url");
        Optional<SystemConfig> deviceKey = systemConfigRepository.findByKey("bark.device.key");
        Optional<SystemConfig> enabled = systemConfigRepository.findByKey("bark.enabled");

        config.setUrl(url.map(SystemConfig::getValue).orElse(""));
        config.setDeviceKey(deviceKey.map(SystemConfig::getValue).orElse(""));
        config.setEnabled(enabled.map(SystemConfig::isEnabled).orElse(false));

        return config;
    }
}
