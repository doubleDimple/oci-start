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
public class DingDingMessageService implements MessageService {

    private static final String DING_DING_URL="https://api.telegram.org/bot%s/sendMessage?chat_id=%s&text=%s";

    @Override
    public void sendMessage(String message) {
       log.info("推送钉钉消息开始.....");
    }

    @Override
    public MessageEnum getMessageType() {
        return MessageEnum.DING_DING;
    }
}
