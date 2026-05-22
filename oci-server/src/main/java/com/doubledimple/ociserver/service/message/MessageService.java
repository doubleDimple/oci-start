package com.doubledimple.ociserver.service.message;

import com.doubledimple.ociserver.pojo.domain.dto.OracleInstanceDetail;
import com.doubledimple.ociserver.pojo.enums.MessageEnum;

public interface MessageService {

    void sendMessage(OracleInstanceDetail instanceData);


    void sendMessageTemplate(String message);
    void sendMessageTemplateText(String message);

    void sendMessageTemplateText(String message,Boolean consoleFlag);

    void sendMessageTemplateTest(String message);


    MessageEnum getMessageType();

    void sendErrorMessage(String s);


    /**
    * @Description: 发送自己的频道,只发送抢机的区域
    * @Param: [java.lang.String]
    * @return: void
    * @Author doubleDimple
    * @Date: 12/28/24 11:00 AM
    */
    void sendMyChannel(String message);

    /**
     * 发送带 Markdown 格式的验证码消息
     * @param userName 用户名
     * @param verificationCode 验证码
     */
    void sendVerificationCodeMessage(String userName, String verificationCode);
}
