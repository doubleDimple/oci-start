package com.doubledimple.ociserver.pojo.request;

import lombok.AllArgsConstructor;
import lombok.Data;
import lombok.NoArgsConstructor;
import lombok.ToString;

/**
 * @version 1.0.0
 * @ClassName UpdateBootVolumeRequest
 * @Description TODO
 * @Author doubleDimple
 * @Date 2024-11-26 18:50
 */
@Data
@AllArgsConstructor
@NoArgsConstructor
@ToString
public class UpdateVolumeDefRequest {
    private String instanceId;
    private Long bootVolumeSize;
    private boolean expand;
}
