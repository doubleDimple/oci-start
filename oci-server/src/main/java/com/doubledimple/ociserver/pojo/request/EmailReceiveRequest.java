package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName EmailReceiveRequsrt
 * @Description TODO
 * @Author renyx
 * @Date 2025-09-27 09:47
 */
@Data
public class EmailReceiveRequest extends BaseRequest{

    private String email;
    private String name;
}
