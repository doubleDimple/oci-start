package com.doubledimple.ociserver.pojo.request;

import com.doubledimple.dao.entity.Message;
import lombok.Data;

import javax.persistence.Column;
import javax.persistence.EnumType;
import javax.persistence.Enumerated;
import javax.persistence.GeneratedValue;
import javax.persistence.GenerationType;
import javax.persistence.Id;
import java.time.LocalDateTime;

/**
 * @version 1.0.0
 * @ClassName EmailReceiveRequsrt
 * @Description TODO
 * @Author doubleDimpl
 * @Date 2025-09-27 09:47
 */
@Data
public class SystemMessageRequest extends BaseRequest{

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    //业务id
    private String businessId;

    //消息类型
    private Message.MessageType messageType;

    //消息读取状态,1:已读,0:未读
    private Integer readStatus;

    //消息主题
    private String subject;

    //消息内容
    private String content;

    private LocalDateTime updateTime;

    private LocalDateTime createTime;
}
