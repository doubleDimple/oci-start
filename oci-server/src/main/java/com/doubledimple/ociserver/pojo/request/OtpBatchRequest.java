package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

import java.util.List;

/**
 * @author doubleDimple
 * @date 2024:11:01日 23:18
 */
@Data
public class OtpBatchRequest {

    private List<String> secretKeys;
}
