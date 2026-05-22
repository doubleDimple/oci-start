package com.doubledimple.ociserver.pojo.request;

import com.doubledimple.dao.entity.Tenant;
import lombok.Data;

import javax.validation.constraints.NotBlank;

/**
 * @version 1.0.0
 * @ClassName ImageInfoReq
 * @Description TODO
 * @Author doubleDimple
 * @Date 2025-10-29 09:28
 */
@Data
public class ImageInfoReq {
    //租户id,实例类型
    @NotBlank(message = "租户id不能为空")
    String tenantId;
    @NotBlank(message = "实例类型不能为空")
    String shapeType;
}
