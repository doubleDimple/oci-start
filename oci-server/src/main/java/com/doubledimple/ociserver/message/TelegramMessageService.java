package com.doubledimple.ociserver.message;

import com.doubledimple.ociserver.enums.MessageEnum;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.UnsupportedEncodingException;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;

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
    public void sendMessage(String message) {
        log.info("推送TG消息开始...");
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

    @Override
    public MessageEnum getMessageType() {
        return MessageEnum.TELEGRAM;
    }
}
