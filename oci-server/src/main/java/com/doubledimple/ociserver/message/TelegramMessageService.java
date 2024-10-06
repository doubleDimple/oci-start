package com.doubledimple.ociserver.message;

import com.doubledimple.ociserver.domain.OracleInstanceDetail;
import com.doubledimple.ociserver.enums.MessageEnum;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.UnsupportedEncodingException;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;

/**
 * @author doubleDimple
 * @date 2024:09:22日 16:01
 */
@Service
@Slf4j
public class TelegramMessageService implements MessageService {

    private static final String TG_URL="https://api.telegram.org/bot%s/sendMessage?chat_id=%s&text=%s";
    @Value("${telegram.chatId}")
    private String chatId;

    @Value("${telegram.token}")
    private String botToken;

    @Override
    public void sendMessage(OracleInstanceDetail instanceData) {
        log.info("推送TG消息开始...");
        String message = formatMessage(instanceData);
        doSend(message);
    }

    @Override
    public MessageEnum getMessageType() {
        return MessageEnum.TELEGRAM;
    }

    @Override
    public void sendErrorMessage(String s) {
        doSend(s);
    }


    public String formatMessage(OracleInstanceDetail instanceData){
        String currentTime = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyy-MM-dd HH:mm:ss"));

        return String.format(LEGACY_MESSAGE_TEMPLATE,
                currentTime,
                instanceData.getPublicIp(),
                instanceData.getUserName());
    }


    private void doSend(String message){
        try {
            String encodedMessage = URLEncoder.encode(message, "UTF-8");
            String urlString = String.format(TG_URL,
                    botToken, chatId, encodedMessage);

            URL url = new URL(urlString);
            HttpURLConnection connection = (HttpURLConnection) url.openConnection();
            connection.setRequestMethod("GET");
            connection.connect();

            int responseCode = connection.getResponseCode();
            if (responseCode == HttpURLConnection.HTTP_OK) {
                log.info("Message sent successfully!");
            } else {
                log.info("Failed to send message, response code: [{}]",responseCode);
            }
        } catch (UnsupportedEncodingException e) {
            e.printStackTrace();
        } catch (Exception e) {
            e.printStackTrace();
        }
    }


    private static final String LEGACY_MESSAGE_TEMPLATE =
            "🚀 *New Instance Deployed Successfully*\n\n" +
                    "Timestamp: %s\n\n" +
                    "Instance Details:*\n" +
                    "   IP: %s\n" +
                    "   USER: %s\n\n" +
                    "The source code address is:(https://github.com/doubleDimple)\n\n" +
                    "Powered by oci-start";
}
