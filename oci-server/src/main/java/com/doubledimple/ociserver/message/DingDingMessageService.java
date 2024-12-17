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

/**
 * @author doubleDimple
 * @date 2024:09:22日 16:01
 */
@Service
@Slf4j
public class DingDingMessageService implements MessageService {


    @Override
    public void sendMessage(OracleInstanceDetail instanceData) {
       log.info("推送钉钉消息开始.....");
    }

    @Override
    public MessageEnum getMessageType() {
        return MessageEnum.DING_DING;
    }

    @Override
    public void sendErrorMessage(String s) {
        log.info("开始发送错误消息,发送的错误信息是:{}",s);
    }
}
