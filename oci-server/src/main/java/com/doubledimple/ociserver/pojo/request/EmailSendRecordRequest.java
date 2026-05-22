package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName EmailSendRecordRequest
 * @Description TODO
 * @Author renyx
 * @Date 2025-09-28 12:39
 */
@Data
public class EmailSendRecordRequest extends BaseRequest{

    private String emailBodyId;
}
