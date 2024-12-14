package com.doubledimple.ociserver.message;

import com.doubledimple.ociserver.domain.OracleInstanceDetail;
import com.doubledimple.ociserver.enums.MessageEnum;

/**
* @Description:  这是发送消息的类
* @Param:
* @return:
* @Author: doubleDimple
* @Date: 12/14/24 4:04 PM
*/
public interface MessageService {

    void sendMessage(OracleInstanceDetail instanceData);


    MessageEnum getMessageType();

    void sendErrorMessage(String s);
}
