package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

/**
 * @version 1.0.0
 * @ClassName BaseRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-09-27 09:47
 */
@Data
public class BaseRequest {

    private int pageNum = 1;
    private int pageSize = 10;
    private String sort;
    private String order = "desc";

}
