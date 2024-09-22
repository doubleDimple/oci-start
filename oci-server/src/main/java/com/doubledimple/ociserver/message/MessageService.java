package com.doubledimple.ociserver.message;

import com.doubledimple.ociserver.enums.MessageEnum;

public interface MessageService {

    void sendMessage(String message);


    MessageEnum getMessageType();
}
