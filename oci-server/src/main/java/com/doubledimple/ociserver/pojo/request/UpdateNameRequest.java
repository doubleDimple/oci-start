package com.doubledimple.ociserver.pojo.request;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;

/**
 * @version 1.0.0
 * @ClassName UpdateNameRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-11-25 17:27
 */
@Data
@NoArgsConstructor
@AllArgsConstructor
public class UpdateNameRequest {
    private String instanceId;
    private String newName;
}
