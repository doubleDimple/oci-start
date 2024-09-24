package com.doubledimple.ociserver.message;

import com.doubledimple.ociserver.domain.OracleInstanceDetail;
import com.doubledimple.ociserver.enums.MessageEnum;

public interface MessageService {

    void sendMessage(OracleInstanceDetail instanceData);


    MessageEnum getMessageType();

    void sendErrorMessage(String s);
}
