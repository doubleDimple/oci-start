package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

import javax.validation.constraints.NotBlank;

@Data
public class CreateFolderReq {
    @NotBlank(message = "名称不能为空")
    private String name;
    private Long parentId;          // 顶层可为 null
    private Integer sortOrder;      // 可空，默认 0
}
