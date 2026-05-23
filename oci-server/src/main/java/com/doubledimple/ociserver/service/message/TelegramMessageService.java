package com.doubledimple.ociserver.service.message;

import com.doubledimple.dao.entity.Message;
import com.doubledimple.dao.entity.SystemConfig;
import com.doubledimple.dao.repository.SystemConfigRepository;
import com.doubledimple.ocicommon.bark.BarkPush;
import com.doubledimple.ocicommon.enums.RegionEnum;
import com.doubledimple.ociserver.pojo.domain.dto.OracleInstanceDetail;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.pojo.request.BarkConfig;
import com.doubledimple.ociserver.pojo.request.SystemMessageRequest;
import com.doubledimple.ociserver.pojo.request.TelegramConfig;
import com.doubledimple.ociserver.service.SystemMessageService;
import lombok.extern.slf4j.Slf4j;
import org.apache.commons.lang3.StringUtils;
import org.springframework.stereotype.Service;
import org.springframework.web.context.request.RequestContextHolder;
import org.springframework.web.context.request.ServletRequestAttributes;

import javax.annotation.Resource;
import javax.servlet.http.HttpServletRequest;
import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.util.Optional;

import static com.doubledimple.ocicommon.template.MessageTemplate.LEGACY_MESSAGE_TEMPLATE;
import static com.doubledimple.ocicommon.template.MessageTemplate.LEGACY_MESSAGE_TEMPLATE_SUBJECT;
import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_CONFIG_DEAD_ACCOUNT_TEMPLATE_SUBJECT;
import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_CONFIG_STOP_INSTANCE_TEMPLATE_SUBJECT;
import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_CONFIG_STOP_NO_AUTH_TEMPLATE_SUBJECT;
import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_CONSOLE_PASSWORD_RESET_WITH_PASSWORD_TEMPLATE_SUBJECT;
import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_LOGIN_TEMPLATE_V_2;
import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_LOGIN_TEMPLATE_V_2_SUBJECT;
import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_MALICIOUS_LOGIN_TEMPLATE_V_2_SUBJECT;
import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_RESCUE_SUCCESS_TEMPLATE_SUBJECT;
import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_TRAFFIC_EXCEED_ALERT_TEMPLATE_SUBJECT;
import static com.doubledimple.ocicommon.template.MessageTemplate.MESSAGE_VERSION_UPDATE_TEMPLATE_SUBJECT;
import static com.doubledimple.ocicommon.template.MessageTemplate.MYSQL_AUTH_RESET_SUCCESS_TEMPLATE_SUBJECT;
import static com.doubledimple.ocicommon.template.MessageTemplate.MYSQL_CREATE_SUCCESS_TEMPLATE_SUBJECT;
import static com.doubledimple.ocicommon.utils.DateTimeUtils.genAsiaTime;
import static com.doubledimple.ociserver.utils.PingUtil.getCurrentPublicIpAndAddress;

/**
 * 消息
 * @author doubleDimple
 * @date 2024:09:22日 16:01
 */
@Service
@Slf4j
public class TelegramMessageService implements MessageService {

    //需要记录站内信的消息主题集合
    private static final String[] MESSAGE_SUBJECT_ARRAY = new String[]{
            LEGACY_MESSAGE_TEMPLATE_SUBJECT, //开机成功提醒
            MESSAGE_LOGIN_TEMPLATE_V_2_SUBJECT,//系统登录
            MESSAGE_CONFIG_STOP_NO_AUTH_TEMPLATE_SUBJECT,//抢机停止
            MESSAGE_CONFIG_STOP_INSTANCE_TEMPLATE_SUBJECT,//实例终止提醒
            MESSAGE_MALICIOUS_LOGIN_TEMPLATE_V_2_SUBJECT,//异常登录警告
            MESSAGE_CONFIG_DEAD_ACCOUNT_TEMPLATE_SUBJECT,//账号状态提醒
            MESSAGE_TRAFFIC_EXCEED_ALERT_TEMPLATE_SUBJECT,//流量超出预警
            MESSAGE_RESCUE_SUCCESS_TEMPLATE_SUBJECT,//实例救援成功
            MESSAGE_CONSOLE_PASSWORD_RESET_WITH_PASSWORD_TEMPLATE_SUBJECT,//OCI控制台密码重置成功
            MESSAGE_VERSION_UPDATE_TEMPLATE_SUBJECT,//系统更新
            MYSQL_CREATE_SUCCESS_TEMPLATE_SUBJECT,//创建MySQL成功
            MYSQL_AUTH_RESET_SUCCESS_TEMPLATE_SUBJECT //mysql账密
    };
    private static final String TG_URL="https://api.telegram.org/bot%s/sendMessage?chat_id=%s&text=%s";

    @Resource
    SystemMessageService systemMessageService;
    @Resource
    private DingDingMessageService dingDingMessageService;

    @Resource
    private FeishuService feishuService;


    @Resource
    SystemConfigRepository systemConfigRepository;

    /**
    * @Description: 开机成功消息
    * @Param: [com.doubledimple.ociserver.domain.dto.OracleInstanceDetail]
    * @return: void
    * @Author doubleDimple
    * @Date: 12/28/24 11:10 AM
    */
    @Override
    public void sendMessage(OracleInstanceDetail instanceData) {
        log.debug("推送开机成功消息开始...");
        doSendPlainText(formatMessage(instanceData));
    }

    @Override
    public void sendMessageTemplate(String message) {
        log.info("发送消息的内容为:{}",message);
        doSend(message);
    }

    @Override
    public void sendMessageTemplateText(String message) {
        log.info("发送消息的内容为:{}",message);
        doSendHtml(message);
    }

    @Override
    public void sendMessageTemplateText(String message, Boolean consoleFlag) {
        if (consoleFlag){
            log.info("发送消息的内容为:{}",message);
        }
        doSendHtml(message);
    }

    @Override
    public void sendMessageTemplateTest(String message) {
        TelegramConfig telegramConfig = getTelegramConfig();
        if (telegramConfig == null || StringUtils.isEmpty(telegramConfig.getBotToken()) || StringUtils.isEmpty(telegramConfig.getChatId())){
            log.warn("TG 无法推送消息,消息未配置");
            return;
        }

        String chatId = telegramConfig.getChatId();
        String botToken = telegramConfig.getBotToken();
        try {
            String encodedMessage = URLEncoder.encode(message, "UTF-8");
            String urlString = String.format(TG_URL,
                    botToken, chatId, encodedMessage);

            URL url = new URL(urlString);
            HttpURLConnection connection = (HttpURLConnection) url.openConnection();
            connection.setRequestMethod("GET");
            connection.connect();

            int responseCode = connection.getResponseCode();
        }  catch (Exception e) {
            log.error("消息发送失败:{}",e.getMessage(),e);
        }
    }

    @Override
    public MessageEnum getMessageType() {
        return MessageEnum.TELEGRAM;
    }

    @Override
    public void sendErrorMessage(String s) {
        doSend(s);
    }


    @Override
    public void sendMyChannel(String message) {

    }


    public String formatMessage(OracleInstanceDetail instanceData){

        return String.format(LEGACY_MESSAGE_TEMPLATE,
                genAsiaTime(),
                instanceData.getUserName(),
                instanceData.getArchitecture(),
                RegionEnum.getNameByCode(instanceData.getRegion()),
                instanceData.getPublicIp(),
                instanceData.getRootPasswd(),
                instanceData.getAddCount());
    }


    /**
    * @Description: doSend (DINGDING AND tg)
    * @Param: [java.lang.String]
    * @return: void
    * @Author doubleDimple
    * @Date: 12/22/24 9:10 AM
    */
    private void doSend(String message){
        doCheckMessage( message);
        TelegramConfig telegramConfig = getTelegramConfig();
        if (!isTelegramAvailable(telegramConfig)){
            log.warn("TG 无法推送消息,消息未配置");
        } else if (!telegramConfig.isEnabled()){
            log.debug("TG 无法推送消息,消息推送已被禁用");
        } else {
            try {
                String encodedMessage = URLEncoder.encode(message, "UTF-8");
                String urlString = String.format(
                        TG_URL + "&parse_mode=Markdown",
                        telegramConfig.getBotToken(), telegramConfig.getChatId(), encodedMessage);
                sendTelegramRequest(urlString, "Markdown");
            }  catch (Exception e) {
                log.warn("send message error,reason:{}",e.getMessage());
            }
        }

        sendOtherChannels(message);
    }

    /**
     * @Description: doSend (DINGDING AND tg)
     * @Param: [java.lang.String]
     * @return: void
     * @Author doubleDimple
     * @Date: 12/22/24 9:10 AM
     */
    private void doSendHtml(String message){
        TelegramConfig telegramConfig = getTelegramConfig();
        if (!isTelegramAvailable(telegramConfig)){
            log.warn("TG 无法推送消息,消息未配置");
        } else if (!telegramConfig.isEnabled()){
            log.debug("TG 无法推送消息,消息推送已被禁用");
        } else {
            try {
                String encodedMessage = URLEncoder.encode(message, "UTF-8");
                String urlString = String.format(
                        TG_URL + "&parse_mode=HTML",
                        telegramConfig.getBotToken(), telegramConfig.getChatId(), encodedMessage);
                sendTelegramRequest(urlString, "HTML");
            }  catch (Exception e) {
                log.warn("send message error,reason:{}",e.getMessage());
            }
        }

        sendOtherChannels(message);
    }

    /**
     * 开机成功消息包含 IP、密码等原始文本。密码中的 Markdown 特殊字符会让 Telegram
     * 拒收整条消息，所以这里不设置 parse_mode，确保机器信息一定能送达。
     */
    private void doSendPlainText(String message) {
        doCheckMessage(message);
        TelegramConfig telegramConfig = getTelegramConfig();
        if (!isTelegramAvailable(telegramConfig)){
            log.warn("TG 无法推送消息,消息未配置");
        } else if (!telegramConfig.isEnabled()){
            log.debug("TG 无法推送消息,消息推送已被禁用");
        } else {
            try {
                String encodedMessage = URLEncoder.encode(message, "UTF-8");
                String urlString = String.format(TG_URL,
                        telegramConfig.getBotToken(), telegramConfig.getChatId(), encodedMessage);
                sendTelegramRequest(urlString, "plain text");
            } catch (Exception e) {
                log.warn("send message error,reason:{}", e.getMessage());
            }
        }

        sendOtherChannels(message);
    }

    private void sendOtherChannels(String message) {
        try {
            dingDingMessageService.sendMessageTemplate(message);
        } catch (Exception e) {
            log.error("钉钉消息发送失败");
        }

        sendBark(message);
        feishuService.sendMessageTemplate(message);
    }

    private boolean isTelegramAvailable(TelegramConfig telegramConfig) {
        return telegramConfig != null
                && StringUtils.isNotBlank(telegramConfig.getBotToken())
                && StringUtils.isNotBlank(telegramConfig.getChatId());
    }

    private void sendTelegramRequest(String urlString, String mode) throws Exception {
        URL url = new URL(urlString);
        HttpURLConnection connection = (HttpURLConnection) url.openConnection();
        connection.setRequestMethod("GET");
        connection.setConnectTimeout(5000);
        connection.setReadTimeout(5000);
        connection.connect();

        int responseCode = connection.getResponseCode();
        if (responseCode < 200 || responseCode >= 300) {
            log.warn("TG 消息发送失败, mode:{}, responseCode:{}, response:{}",
                    mode, responseCode, readResponseBody(connection));
        }
    }

    private String readResponseBody(HttpURLConnection connection) {
        try {
            InputStream inputStream = connection.getErrorStream();
            if (inputStream == null) {
                inputStream = connection.getInputStream();
            }
            if (inputStream == null) {
                return "";
            }
            try (BufferedReader reader = new BufferedReader(new InputStreamReader(inputStream, StandardCharsets.UTF_8))) {
                StringBuilder body = new StringBuilder();
                String line;
                while ((line = reader.readLine()) != null) {
                    body.append(line);
                }
                return body.toString();
            }
        } catch (Exception e) {
            return "读取 TG 响应失败: " + e.getMessage();
        }
    }

    /**
    * @Description: 发送bark消息
    * @Param: [java.lang.String]
    * @return: void
    * @Author doubleDimple
    * @Date: 5/4/25 10:39 PM
    */
    private void sendBark(String message) {
        final BarkConfig barkConfig = getBarkConfig();
        if (barkConfig == null){
            log.warn("BARK 无法推送消息,消息未配置");
            return;
        }

        final String url = barkConfig.getUrl();
        final String deviceKey = barkConfig.getDeviceKey();
        boolean enabled = barkConfig.isEnabled();
        if (!enabled){
            log.debug("BARK 无法推送消息,消息推送已被禁用");
        }

        try {
            BarkPush pusher = new BarkPush(url, deviceKey);
            pusher.simpleWithResp(message);
        } catch (Exception e) {
            log.debug("bark消息发送失败");
        }
    }


    public TelegramConfig getTelegramConfig() {
        TelegramConfig config = new TelegramConfig();

        Optional<SystemConfig> botToken = systemConfigRepository.findByKey("telegram.bot.token");
        Optional<SystemConfig> chatId = systemConfigRepository.findByKey("telegram.chat.id");
        Optional<SystemConfig> enabled = systemConfigRepository.findByKey("telegram.enabled");

        config.setBotToken(botToken.map(SystemConfig::getValue).orElse(""));
        config.setChatId(chatId.map(SystemConfig::getValue).orElse(""));
        config.setEnabled(enabled.map(SystemConfig::isEnabled).orElse(false));

        return config;
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

    /**
     * 格式化带 Markdown 的验证码消息
     * @param userName 用户名
     * @param verificationCode 验证码
     * @return 格式化后的消息
     */
    public String formatVerificationCodeMessage(String userName, String verificationCode) {
        return String.format(MESSAGE_LOGIN_TEMPLATE_V_2,
                getCurrentPublicIpAndAddress(getCurrentRequest()),userName, verificationCode
        );
    }

    /**
     * 发送带 Markdown 格式的验证码消息
     * @param userName 用户名
     * @param verificationCode 验证码
     */
    public void sendVerificationCodeMessage(String userName, String verificationCode) {
        String message = formatVerificationCodeMessage(userName, verificationCode);
        log.info("发送验证码消息: {}", message);
        //doSend(message);  // 调用原来的消息发送方法
        doSendHtml(message);  // 调用原来的消息发送方法
    }


    private HttpServletRequest getCurrentRequest() {
        try {
            ServletRequestAttributes attributes =
                    (ServletRequestAttributes) RequestContextHolder.getRequestAttributes();
            return attributes != null ? attributes.getRequest() : null;
        } catch (Exception e) {
            log.warn("获取当前请求失败", e);
            return null;
        }
    }


    private String doInnerMessage(String subject, String content) {
        SystemMessageRequest messageRequest = new SystemMessageRequest();
        messageRequest.setSubject(subject);
        messageRequest.setContent(content);
        messageRequest.setMessageType(Message.MessageType.INNER);
        systemMessageService.saveMessage(messageRequest);
        return content;
    }


    private void doCheckMessage(String message) {
        for (String s : MESSAGE_SUBJECT_ARRAY) {
            if (message.contains(s)){
                doInnerMessage(s,message);
            }
        }
    }

}
