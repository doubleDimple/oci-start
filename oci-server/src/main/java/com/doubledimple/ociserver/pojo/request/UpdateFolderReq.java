package com.doubledimple.ociserver.pojo.request;

import lombok.Data;

@Data
public class UpdateFolderReq {
    private String name;            // 可选：不传则不改名
    private Long parentId;          // 可选：不传则不移动
    private Integer sortOrder;      // 可选
}
