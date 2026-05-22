package com.doubledimple.ociserver.service.message.factory;

import com.doubledimple.ociserver.pojo.enums.MessageEnum;
import com.doubledimple.ociserver.service.message.MessageService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.context.annotation.Configuration;

import java.util.List;
import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

/**
 * @author doubleDimple
 * @date 2024:09:22日 17:13
 */
@Configuration
public class MessageFactory {


    private final Map<MessageEnum, MessageService> MAP = new ConcurrentHashMap<>();

    @Autowired
    public MessageFactory(List<MessageService> serviceList){
        serviceList.forEach(service ->MAP.put(service.getMessageType(),service));
    }


    public MessageService getType(MessageEnum type){
        return MAP.get(type);
    }

}
