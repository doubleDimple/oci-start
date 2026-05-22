package com.doubledimple.ociserver.service.message;

import com.doubledimple.ociserver.pojo.domain.dto.OracleInstanceDetail;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.pojo.request.DingTalkConfig;
import com.doubledimple.ociserver.service.impl.system.SystemConfigService;
import lombok.extern.slf4j.Slf4j;
import org.springframework.context.annotation.Lazy;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Service;
import org.springframework.util.StringUtils;
import org.springframework.web.client.RestTemplate;

import javax.annotation.Resource;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.Base64;
import java.util.HashMap;
import java.util.Map;

import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_LOGIN_TEMPLATE;

/**
 * @author doubleDimple
 * @date 2024:09:22日 16:01
 */
@Service
@Slf4j
public class DingDingMessageService implements MessageService {

    @Resource
    private RestTemplate restTemplate;

    @Resource
    @Lazy
    private SystemConfigService systemConfigService;

    @Override
    public void sendMessage(OracleInstanceDetail instanceData) {
       log.info("推送钉钉消息开始.....");
    }

    @Override
    public void sendMessageTemplate(String message) {
        DingTalkConfig dingTalkConfig = systemConfigService.getDingTalkConfig();
        String webhook = dingTalkConfig.getWebhook();
        boolean enabled = dingTalkConfig.isEnabled();
        String secret = dingTalkConfig.getSecret();

        if (!enabled || StringUtils.isEmpty(webhook)) {
            log.debug("DINGDING 未配置 无法发送消息");
            return;
        }

        try {
            // 计算签名
            Long timestamp = System.currentTimeMillis();
            String stringToSign = timestamp + "\n" + secret;
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            byte[] signData = mac.doFinal(stringToSign.getBytes(StandardCharsets.UTF_8));
            String sign = URLEncoder.encode(Base64.getEncoder().encodeToString(signData), "UTF-8");

            // 拼接签名后的URL
            String signedUrl = webhook + "&timestamp=" + timestamp + "&sign=" + sign;

            // 判断是否为markdown格式
            boolean isMarkdown = isMarkdownFormat(message);

            // 构造消息内容
            Map<String, Object> content = new HashMap<>();

            if (isMarkdown) {
                // Markdown消息
                content.put("msgtype", "markdown");

                Map<String, String> markdownContent = new HashMap<>();
                markdownContent.put("title", "通知");
                markdownContent.put("text", message);
                content.put("markdown", markdownContent);
            } else {
                // 普通文本消息
                content.put("msgtype", "text");

                Map<String, String> textContent = new HashMap<>();
                textContent.put("content", message);
                content.put("text", textContent);
            }

            // 可选：@所有人或特定人员
            Map<String, Object> at = new HashMap<>();
            at.put("isAtAll", false);
            content.put("at", at);

            // 发送请求
            ResponseEntity<String> response = restTemplate.postForEntity(
                    signedUrl,
                    content,
                    String.class
            );

            if (!response.getStatusCode().is2xxSuccessful()) {
                log.error("钉钉消息发送失败: {}", response.getBody());
            }
        } catch (Exception e) {
            log.error("钉钉消息发送异常", e);
        }
    }

    @Override
    public void sendMessageTemplateText(String message) {
        log.info("推送钉钉消息开始.....");
    }

    @Override
    public void sendMessageTemplateText(String message, Boolean consoleFlag) {

    }

    private boolean isMarkdownFormat(String message) {
        if (StringUtils.isEmpty(message)) {
            return false;
        }

        // 方式1: 检查常见的markdown语法
        return message.contains("**") ||     // 粗体
                message.contains("*") ||      // 斜体
                message.contains("#") ||      // 标题
                message.contains("```") ||    // 代码块
                message.contains("`") ||      // 行内代码
                message.contains("[") ||      // 链接
                message.contains("- ") ||     // 列表
                message.contains("1. ") ||    // 有序列表
                message.contains("> ") ||     // 引用
                message.contains("---") ||    // 分割线
                message.contains("~~");       // 删除线
    }

    @Override
    public void sendMessageTemplateTest(String message) {
        DingTalkConfig dingTalkConfig = systemConfigService.getDingTalkConfig();
        String webhook = dingTalkConfig.getWebhook();
        String secret = dingTalkConfig.getSecret();

        if (StringUtils.isEmpty(webhook)) {
            log.debug("DINGDING 未配置 无法发送消息");
            return;
        }

        try {
            // 计算签名
            Long timestamp = System.currentTimeMillis();
            String stringToSign = timestamp + "\n" + secret;
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(secret.getBytes(StandardCharsets.UTF_8), "HmacSHA256"));
            byte[] signData = mac.doFinal(stringToSign.getBytes(StandardCharsets.UTF_8));
            String sign = URLEncoder.encode(Base64.getEncoder().encodeToString(signData), "UTF-8");

            // 拼接签名后的URL
            String signedUrl = webhook + "&timestamp=" + timestamp + "&sign=" + sign;

            // 构造消息内容
            Map<String, Object> content = new HashMap<>();
            content.put("msgtype", "text");

            Map<String, String> textContent = new HashMap<>();
            textContent.put("content", message);
            content.put("text", textContent);

            // 发送请求
            ResponseEntity<String> response = restTemplate.postForEntity(
                    signedUrl,
                    content,
                    String.class
            );

            if (!response.getStatusCode().is2xxSuccessful()) {
                log.error("钉钉消息发送失败: {}", response.getBody());
            }
        } catch (Exception e) {
            log.error("钉钉消息发送异常", e);
        }
    }

    @Override
    public MessageEnum getMessageType() {
        return MessageEnum.DING_DING;
    }

    @Override
    public void sendErrorMessage(String s) {
        sendMessageTemplate(s);
    }

    @Override
    public void sendMyChannel(String message) {
        log.info("..........");
    }

    @Override
    public void sendVerificationCodeMessage(String userName, String verificationCode) {
        sendMessageTemplate(String.format(MESSAGE_LOGIN_TEMPLATE,userName,verificationCode));
    }
}
